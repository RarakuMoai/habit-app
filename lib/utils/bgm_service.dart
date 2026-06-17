// 背景音樂服務（gapless 單曲循環 + 淡入淡出 + 靜音持久化 + lifecycle 暫停）。
//
// 底層改用 just_audio，因為它對 AAC priming samples 有補正，LoopMode.one 是真正
// 無縫的；audioplayers 之前在 m4a 循環會有明顯接點。
//
// 對外 API 維持不變：
//   - [BgmService.instance.init]
//   - [BgmService.instance.play]
//   - [BgmService.instance.setMuted]
//
// 行為：
//   - 單曲循環（LoopMode.one）→ 真正 gapless
//   - 切換歌會 fade-out 舊歌 + 切 source + fade-in 新歌
//   - app 切到背景自動暫停，回前景續播

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:just_audio/just_audio.dart';

import 'app_audio_session.dart';
import 'audio_settings_service.dart';

class BgmService with WidgetsBindingObserver {
  BgmService._();
  static final BgmService instance = BgmService._();

  static const double _targetVolume = 0.25;
  static const Duration _fadeDuration = Duration(milliseconds: 1200);
  // 冷啟動 AOT（profile/release）下，just_audio 的 play() 常常「回傳了但 playing
  // 一直是 false」＝沒真的開始播。在「音量 0」下依這些時間點反覆重踢，直到確認
  // playing=true 才淡入；全程靜音聽不到，所以既保證有聲又不破音。
  static const List<Duration> _engageCheckDelays = [
    Duration(milliseconds: 300),
    Duration(milliseconds: 700),
    Duration(milliseconds: 1300),
    Duration(milliseconds: 2200),
    Duration(seconds: 4),
    Duration(seconds: 6),
    Duration(seconds: 9),
  ];
  static const Duration _fadeStep = Duration(milliseconds: 50);

  // 入場淡入：刻意長 + ease-in 曲線（前段幾乎聽不到、再慢慢膨脹），
  // 比線性淡入更有「漸漸進來」的感覺，避免音樂一下就明顯出現。
  static const Duration _entranceFadeDuration = Duration(milliseconds: 3200);
  static const Curve _entranceCurve = Curves.easeInQuad;
  static const int _playStartRetries = 3;

  // 跳過 AAC encoder 在開頭塞的暖機靜音（~48ms），讓 LoopMode.one 接得更緊
  static const Duration _aacPrimingTrim = Duration(milliseconds: 50);

  final AudioPlayer _player = AudioPlayer();
  // "app 想要現在播這首" 的同步旗標，play()/ensurePlaying() 進來第一件事就設。
  // 跟 _currentAsset 不同：_currentAsset 是「目前 native player 實際載入的」，
  // 會在 fadeTo + stop 後才更新；_intendedAsset 立刻反映呼叫端的意圖，
  // 解 race（例：_finish 呼 play('bgm_main') 後，舊的 ensurePlaying('bgm_onboarding')
  // 看到 intent 已改就 bail，不會把曲目切回去）。
  String? _intendedAsset;
  String? _currentAsset;
  String? _deferredFadeAsset;
  // 目前有哪一首正在 play() 執行流程中（同步段尚未跑完）。用來讓並發的
  // no-op play 知道「已有同首 play 在進行」而直接 bail，不去 bump requestId。
  String? _playInFlightAsset;
  int _playRequestId = 0;
  double _currentVolume = 0;
  Timer? _fadeTimer;
  // 冷啟動「靜音重試直到 play engage」的計時器們。
  final List<Timer> _engageTimers = [];
  // 當前 fade 的 completer。下一個 fade 啟動時會把這個 complete 掉，
  // 避免「舊的 await _fadeTo」永遠 hang 在那裡。
  Completer<void>? _activeFadeCompleter;
  bool _initialized = false;
  bool _wasPlayingBeforeBackground = false;

  // ── 播放進度（衣櫃試聽進度條用）──
  // 唯讀 + seek，不影響 engage/fade/淡入救援核心。注意 source 是
  // ClippingAudioSource（跳開頭 _aacPrimingTrim），所以 position/duration
  // 都是相對裁切後的時間，seek 也落在裁切範圍內。
  /// 目前 native player 實際載入的 asset（相對 `assets/`）。
  String? get loadedAsset => _currentAsset;
  Stream<Duration> get positionStream => _player.positionStream;
  Stream<Duration?> get durationStream => _player.durationStream;
  Duration get position => _player.position;
  Duration? get duration => _player.duration;
  Future<void> seek(Duration position) => _player.seek(position);

  Future<void> init() async {
    if (_initialized) return;

    await AudioSettingsService.instance.init();

    // 全 app 只在這裡 configure 一次 audio session（ambient = 跟其他 app 共存、
    // 響應實體靜音鈕）。重複 configure 會讓 iOS 重設輸出路由 → 冷啟動沒聲音，
    // 所以之後所有「確保 active」的場合都只呼叫 AppAudioSession.activate()。
    await AppAudioSession.ensureConfigured();

    await _player.setLoopMode(LoopMode.one); // gapless 單曲循環
    await _player.setVolume(0);
    _currentVolume = 0;

    WidgetsBinding.instance.addObserver(this);
    _initialized = true;
  }

  /// 切換到指定 BGM 資產（路徑相對 `assets/`，例如 `sounds/bgm_main.m4a`）。
  /// 重複呼叫同一首會無操作；切換到不同首會 cross-fade。
  Future<void> play(String asset, {bool deferFade = false}) async {
    // 同步聲明意圖，必須在任何 await 之前 — 解 race（見 _intendedAsset 註解）
    _intendedAsset = asset;
    if (!_initialized) await init();
    if (_intendedAsset != asset) return;
    // 已經在播同一首、或已有另一個 play(同首) 在執行中：直接 return，
    // 且「不要」bump requestId。否則並發的 no-op play（例：既有用戶 main() 與
    // MainPage 同時起播 bgm_main）會作廢另一個 play 排定的延遲淡入，
    // 導致永遠停在音量 0 沒聲音。
    if (_currentAsset == asset &&
        (_player.playing || _playInFlightAsset == asset)) {
      return;
    }
    final requestId = ++_playRequestId;
    _playInFlightAsset = asset;
    try {
      // iOS / release 下，不只冷啟動，切換到新的 AudioSource 後也可能出現
      // player 狀態正常但沒有實際聲音輸出的情況。
      final sourceWillChange = _currentAsset != asset;

      // 只在「已有先前曲目」時才 stop（asset 切換要乾淨清掉舊 source）。
      // 首次呼叫對 fresh player 做 stop+setAudioSource+play 在 iOS 上會 silently fail。
      await _fadeTo(0);
      if (!_isPlayRequestCurrent(requestId, asset)) return;
      if (_currentAsset != null) {
        await _player.stop();
      }
      _currentAsset = asset;

      if (AudioSettingsService.musicMuted.value) {
        return; // 靜音中只記錄當前曲目，不實際播放
      }

      await _loadAsset(asset);
      if (!_isPlayRequestCurrent(requestId, asset)) return;

      if (sourceWillChange) {
        await _primePlaybackOutput(asset, requestId: requestId);
      }

      await _startPlaybackWithRecovery(asset, requestId: requestId);
      if (!_isPlayRequestCurrent(requestId, asset)) return;

      if (deferFade) {
        // 冷啟動：保持靜音，靜音重試直到 play 真的 engage 才淡入（gap-free 入場）
        _deferredFadeAsset = asset;
        await _player.setVolume(0);
        _currentVolume = 0;
        _scheduleEngageChecks(asset, requestId);
        return;
      }

      // app 內切歌（route 已建立）：直接柔和淡入
      _deferredFadeAsset = null;
      _cancelEngageChecks();
      await _fadeInEntrance();
    } finally {
      // 只有「最後一個」play 負責清旗標（被新的 play 接手就不清，交給它）
      if (_playRequestId == requestId) _playInFlightAsset = null;
    }
  }

  /// 確認指定 BGM 已載入並正在前進。
  ///
  /// 用在使用者互動後補救「player 顯示 playing 但沒有實際出聲」的裝置狀態。
  /// 若 [unmute] 為 false，會尊重使用者已保存的靜音偏好。
  ///
  /// 重要：如果 app 同時間已透過 [play] 切到別的曲目（例如 onboarding 結束
  /// 切 bgm_main），這裡會直接 bail，不會把曲目硬切回去。
  Future<void> ensurePlaying(String asset, {bool unmute = false}) async {
    if (!_initialized) await init();
    // 別人已聲明不同 intent → 不要搶回去
    if (_intendedAsset != null && _intendedAsset != asset) return;
    _intendedAsset = asset;

    if (unmute && AudioSettingsService.musicMuted.value) {
      await setMuted(false);
    }
    if (_intendedAsset != asset) return;
    if (AudioSettingsService.musicMuted.value) return;

    // 同一首的 play() 流程還在執行中（冷啟動 asset 載入慢時會撞到）：
    // 別插手。否則下面的救援 stop()/load 會把對方還掛著的 setAudioSource
    // 打斷成 Loading interrupted，兩條流程雙雙失敗、音量卡在 0。
    // 該 play() 自己的 engage 重試 + 延遲淡入會把聲音帶起來。
    if (_playInFlightAsset == asset) return;

    if (_currentAsset != asset) {
      // 全新起播也走 deferFade（靜音喚醒路由 + 延遲柔和淡入），
      // 確保不管是 main() 還是 MainPage 的 ensurePlaying 先搶到，入場都一致柔和。
      await play(asset, deferFade: true);
      return;
    }

    if (_player.processingState == ProcessingState.idle) {
      await _loadAsset(asset);
    }
    if (_intendedAsset != asset) return;
    final deferredFade = _deferredFadeAsset == asset;
    if (deferredFade) {
      await _player.setVolume(0);
      _currentVolume = 0;
      if (!_engageActive) _scheduleEngageChecks(asset, _playRequestId);
    }
    await _startPlaybackWithRecovery(asset);
    if (AudioSettingsService.musicMuted.value || _intendedAsset != asset) {
      return;
    }
    if (_currentVolume < _targetVolume * 0.75) {
      if (deferredFade) {
        if (!_engageActive) _scheduleEngageChecks(asset, _playRequestId);
      } else {
        await _fadeInEntrance();
      }
    }
  }

  // 確保 session active（不 reconfigure）。播放 / 救援前用，避免重設輸出路由。
  Future<void> _activateSession() => AppAudioSession.activate();

  bool _isPlayRequestCurrent(int requestId, String asset) {
    return _playRequestId == requestId && _intendedAsset == asset;
  }

  // 載入 asset 並包進 ClippingAudioSource 跳過開頭 priming，循環會更緊密
  Future<void> _loadAsset(String asset) async {
    await _player.setAudioSource(
      ClippingAudioSource(
        start: _aacPrimingTrim,
        child: AudioSource.asset('assets/$asset'),
      ),
    );
    await _player.setLoopMode(LoopMode.one);
  }

  // iOS/just_audio workaround：新的 AudioSource 第一次 play() 有機率 silent fail。
  // 手動「靜音→開啟」會修好，是因為它走了 pause→play；這裡在音量 0 時先做
  // 一次 play→pause→seek(0)，讓真正播放時已經是同一個 source 的第二次 play。
  Future<void> _primePlaybackOutput(
    String asset, {
    required int requestId,
  }) async {
    try {
      await _activateSession();
      if (!_isPlayRequestCurrent(requestId, asset)) return;
      await _player.setVolume(0);
      _currentVolume = 0;
      // 注意：just_audio 的 play() future「播到停止才完成」，不可 await，否則會卡住
      unawaited(_player.play());
      await Future<void>.delayed(const Duration(milliseconds: 80));
      if (!_isPlayRequestCurrent(requestId, asset)) return;
      await _player.pause();
      await _player.seek(Duration.zero);
    } catch (e) {
      debugPrint('BGM: playback output prime failed: $e');
    }
  }

  bool get _engageActive => _engageTimers.any((t) => t.isActive);

  void _cancelEngageChecks() {
    for (final t in _engageTimers) {
      t.cancel();
    }
    _engageTimers.clear();
  }

  // 排一串「靜音重試」檢查點：每個時間點檢查 play 有沒有真的 engage（playing=true）。
  // 沒 engage 就在音量 0 下重踢；engage 了就淡入一次並結束。全程靜音、不破音。
  void _scheduleEngageChecks(String asset, int requestId) {
    _cancelEngageChecks();
    for (final delay in _engageCheckDelays) {
      final isLast = delay == _engageCheckDelays.last;
      _engageTimers.add(
        Timer(delay, () {
          unawaited(_engageCheck(asset, requestId, isLast: isLast));
        }),
      );
    }
  }

  Future<void> _engageCheck(
    String asset,
    int requestId, {
    required bool isLast,
  }) async {
    // 已被別的 play 接手 / 已淡入過 / 該靜音 → 放手
    if (_bailDeferred(requestId, asset) || _deferredFadeAsset != asset) return;

    // play 真的 engage 了（有在播且 buffer ready）→ 柔和淡入一次，結束重試
    if (_player.playing && _player.processingState == ProcessingState.ready) {
      _cancelEngageChecks();
      _deferredFadeAsset = null;
      await _fadeInEntrance();
      return;
    }

    // 還沒 engage → 在「音量 0」下重踢 pause→play（聽不到），等下個檢查點再驗證。
    try {
      await _activateSession();
      if (_bailDeferred(requestId, asset)) return;
      await _player.setVolume(0);
      _currentVolume = 0;
      await _player.pause();
      await Future<void>.delayed(const Duration(milliseconds: 40));
      if (_bailDeferred(requestId, asset)) return;
      // 注意：play() 不可 await（其 future 播到停止才完成）。fire-and-forget。
      unawaited(_player.play());
    } catch (e) {
      debugPrint('BGM: engage retry failed: $e');
    }

    // 最後一次：不論有沒有 engage 都淡入，至少不要永遠靜音卡在音量 0
    if (isLast) {
      if (_bailDeferred(requestId, asset) || _deferredFadeAsset != asset) {
        return;
      }
      _deferredFadeAsset = null;
      await _fadeInEntrance();
    }
  }

  bool _bailDeferred(int requestId, String asset) {
    return AudioSettingsService.musicMuted.value ||
        !_isPlayRequestCurrent(requestId, asset) ||
        _currentAsset != asset;
  }

  // iOS/just_audio 偶爾會出現 play() 已回傳、甚至 playing=true，但音源還沒真正
  // 前進的狀態。用 processingState + position 是否前進確認，比只看 playing 穩。
  Future<void> _startPlaybackWithRecovery(
    String asset, {
    int? requestId,
  }) async {
    bool isCurrentRequest() {
      return requestId == null
          ? _intendedAsset == asset
          : _isPlayRequestCurrent(requestId, asset);
    }

    for (var attempt = 0; attempt < _playStartRetries; attempt++) {
      if (AudioSettingsService.musicMuted.value || !isCurrentRequest()) {
        return;
      }

      await _activateSession();
      if (!isCurrentRequest()) return;
      // play() 不可 await（其 future 播到停止才完成）。fire-and-forget 再驗證。
      unawaited(_player.play());

      if (await _isPlaybackAdvancing()) return;

      debugPrint('BGM: playback did not advance, retry ${attempt + 1}');
      if (attempt == _playStartRetries - 1) {
        // 驗證在某些裝置上可能誤判；最後一次不要 stop 掉，避免救援流程
        // 反而讓 BGM 留在停止狀態。
        unawaited(_player.play());
        return;
      }
      await _player.stop();
      if (AudioSettingsService.musicMuted.value || !isCurrentRequest()) {
        return;
      }
      await _loadAsset(asset);
    }
  }

  Future<bool> _isPlaybackAdvancing() async {
    try {
      final ready = await _player.processingStateStream
          .firstWhere(
            (state) =>
                state == ProcessingState.ready ||
                state == ProcessingState.completed,
          )
          .timeout(
            const Duration(milliseconds: 900),
            onTimeout: () {
              return _player.processingState;
            },
          );
      if (ready != ProcessingState.ready &&
          ready != ProcessingState.completed) {
        return false;
      }

      final before = _player.position;
      await Future<void>.delayed(const Duration(milliseconds: 450));
      final after = _player.position;
      return _player.playing &&
          after.inMilliseconds > before.inMilliseconds + 80;
    } catch (e) {
      debugPrint('BGM: playback verification failed: $e');
      return false;
    }
  }

  /// 切換靜音狀態，存到偏好。
  /// 瘋狂連按時：舊 fade 會被中止，每個 await 後重檢查 muted.value，
  /// 中途改變心意就放棄該分支，避免「該播時暫停」這種亂跳。
  Future<void> setMuted(bool value) async {
    if (AudioSettingsService.musicMuted.value == value) return;
    await AudioSettingsService.instance.setMusicMuted(value);

    if (value) {
      await _fadeTo(0);
      if (!AudioSettingsService.musicMuted.value) return; // 使用者已改回不靜音
      await _player.pause();
    } else if (_currentAsset != null) {
      // 之前因靜音而沒實際播放 → 啟動；之前在播但被暫停 → 復原
      if (_player.processingState == ProcessingState.idle) {
        await _loadAsset(_currentAsset!);
      }
      if (AudioSettingsService.musicMuted.value) return; // 使用者已改回靜音
      await _startPlaybackWithRecovery(_currentAsset!);
      await _fadeTo(_targetVolume);
      // 淡入過程中又被靜音
      if (AudioSettingsService.musicMuted.value) {
        await _player.pause();
      }
    }
  }

  // 線性淡到目標音量。新的 fade 會把舊的 fade 的 Future 直接 complete 掉，
  // 防止「await _fadeTo」永遠卡住。
  // 入場 / 救援統一走的柔和淡入：長時間 + ease-in 曲線。
  Future<void> _fadeInEntrance() => _fadeTo(
    _targetVolume,
    duration: _entranceFadeDuration,
    curve: _entranceCurve,
  );

  Future<void> _fadeTo(
    double to, {
    Duration duration = _fadeDuration,
    Curve curve = Curves.linear,
  }) async {
    // 取消舊 timer + complete 舊 future
    _fadeTimer?.cancel();
    if (_activeFadeCompleter != null && !_activeFadeCompleter!.isCompleted) {
      _activeFadeCompleter!.complete();
    }

    final from = _currentVolume;
    if ((from - to).abs() < 0.01) {
      _currentVolume = to;
      await _player.setVolume(to);
      return;
    }

    final completer = Completer<void>();
    _activeFadeCompleter = completer;
    final totalSteps = duration.inMilliseconds ~/ _fadeStep.inMilliseconds;
    var step = 0;

    _fadeTimer = Timer.periodic(_fadeStep, (timer) async {
      // 換到新的 fade 了，這個 timer 就放生
      if (_activeFadeCompleter != completer) {
        timer.cancel();
        return;
      }
      step++;
      final progress = (step / totalSteps).clamp(0.0, 1.0);
      final eased = curve.transform(progress);
      final vol = from + (to - from) * eased;
      _currentVolume = vol;
      await _player.setVolume(vol);
      if (step >= totalSteps) {
        timer.cancel();
        _currentVolume = to;
        await _player.setVolume(to);
        if (!completer.isCompleted) completer.complete();
      }
    });

    return completer.future;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
        _wasPlayingBeforeBackground = _player.playing;
        if (_wasPlayingBeforeBackground) {
          _player.pause();
        }
      case AppLifecycleState.resumed:
        // app 真正回到前景（含冷啟動後第一次 active）才是 iOS 願意建立輸出
        // 路由的可靠時機。這裡 re-activate session 並把該播的曲目踢起來，
        // 救冷啟動「狀態在播但沒聲」而不必使用者手動切靜音。
        final shouldResume =
            _wasPlayingBeforeBackground || _currentAsset != null;
        _wasPlayingBeforeBackground = false;
        if (shouldResume && !AudioSettingsService.musicMuted.value) {
          unawaited(_resumeOutput());
        }
      case AppLifecycleState.detached:
        break;
    }
  }

  // 回前景 / 冷啟動後第一次 active 的播放救援。
  // re-activate session（不 reconfigure）後做一次 play，並在不是 deferred-fade
  // 期間時把音量補到目標值。intent 已被別人改掉就放手。
  Future<void> _resumeOutput() async {
    final asset = _currentAsset;
    if (asset == null) return;
    await AppAudioSession.activate();
    if (AudioSettingsService.musicMuted.value || _currentAsset != asset) {
      return;
    }
    // play() 不可 await（其 future 播到停止才完成）。fire-and-forget。
    unawaited(_player.play());
    if (AudioSettingsService.musicMuted.value || _currentAsset != asset) {
      return;
    }
    // onboarding 的 deferred fade 還在排程時不要硬拉音量，交給它自己淡入
    if (_deferredFadeAsset == null && _currentVolume < _targetVolume * 0.75) {
      await _fadeInEntrance();
    }
  }
}
