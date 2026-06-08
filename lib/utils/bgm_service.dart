// 背景音樂服務（gapless 單曲循環 + 淡入淡出 + 靜音持久化 + lifecycle 暫停）。
//
// 底層改用 just_audio，因為它對 AAC priming samples 有補正，LoopMode.one 是真正
// 無縫的；audioplayers 之前在 m4a 循環會有明顯接點。
//
// 對外 API 維持不變：
//   - [BgmService.instance.init]
//   - [BgmService.instance.play]
//   - [BgmService.instance.setMuted]
//   - [BgmService.muted]（ValueListenable）
//
// 行為：
//   - 單曲循環（LoopMode.one）→ 真正 gapless
//   - 切換歌會 fade-out 舊歌 + 切 source + fade-in 新歌
//   - app 切到背景自動暫停，回前景續播

import 'dart:async';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/widgets.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';

class BgmService with WidgetsBindingObserver {
  BgmService._();
  static final BgmService instance = BgmService._();

  // 靜音狀態（給 AppBar ValueListenableBuilder 用）
  static final ValueNotifier<bool> muted = ValueNotifier(false);

  static const String _prefKey = 'bgm_muted';
  static const double _targetVolume = 0.6;
  static const Duration _fadeDuration = Duration(milliseconds: 1200);
  static const Duration _fadeStep = Duration(milliseconds: 50);
  static const int _playStartRetries = 3;

  // 跳過 AAC encoder 在開頭塞的暖機靜音（~48ms），讓 LoopMode.one 接得更緊
  static const Duration _aacPrimingTrim = Duration(milliseconds: 50);

  final AudioPlayer _player = AudioPlayer();
  String? _currentAsset;
  double _currentVolume = 0;
  Timer? _fadeTimer;
  // 當前 fade 的 completer。下一個 fade 啟動時會把這個 complete 掉，
  // 避免「舊的 await _fadeTo」永遠 hang 在那裡。
  Completer<void>? _activeFadeCompleter;
  bool _initialized = false;
  bool _wasPlayingBeforeBackground = false;

  Future<void> init() async {
    if (_initialized) return;

    final prefs = await SharedPreferences.getInstance();
    muted.value = prefs.getBool(_prefKey) ?? false;

    // 顯式 configure + activate audio session（ambient = 跟其他 app 共存、響應靜音鈕）。
    // 不顯式設的話，iOS 在第一次 play() 時才幫忙設，會 race condition：
    // 冷啟動時 onboarding 那次 play() 看似成功但沒輸出，要到第二次 play()
    // （onboarding 結束切 bgm_main）才實際發聲。
    // 注意：ambient 預設就 mixWithOthers，再寫 mixWithOthers flag 會 assert，
    // 所以這裡只給 category。setActive 強制 iOS 立刻把 session 真正 active 起來。
    await _activateSession();

    await _player.setLoopMode(LoopMode.one); // gapless 單曲循環
    await _player.setVolume(0);
    _currentVolume = 0;

    WidgetsBinding.instance.addObserver(this);
    _initialized = true;
  }

  /// 切換到指定 BGM 資產（路徑相對 `assets/`，例如 `sounds/bgm_main.m4a`）。
  /// 重複呼叫同一首會無操作；切換到不同首會 cross-fade。
  Future<void> play(String asset) async {
    if (!_initialized) await init();
    if (_currentAsset == asset && _player.playing) return;

    // 不管之前狀態如何，先 fade out + stop 拿到乾淨狀態。
    // 首次呼叫（_currentAsset == null）也要 stop，避免冷啟動時 native player
    // 處於 stale 狀態導致 play() 看似成功但沒輸出。
    await _fadeTo(0);
    await _player.stop();
    _currentAsset = asset;

    if (muted.value) return; // 靜音中只記錄當前曲目，不實際播放

    await _loadAsset(asset);
    await _startPlaybackWithRecovery(asset);

    await _fadeTo(_targetVolume);
  }

  /// 確認指定 BGM 已載入並正在前進。
  ///
  /// 用在使用者互動後補救「player 顯示 playing 但沒有實際出聲」的裝置狀態。
  /// 若 [unmute] 為 false，會尊重使用者已保存的靜音偏好。
  Future<void> ensurePlaying(String asset, {bool unmute = false}) async {
    if (!_initialized) await init();
    if (unmute && muted.value) {
      await setMuted(false);
    }
    if (muted.value) return;

    if (_currentAsset != asset) {
      await play(asset);
      return;
    }

    if (_player.processingState == ProcessingState.idle) {
      await _loadAsset(asset);
    }
    await _startPlaybackWithRecovery(asset);
    if (muted.value || _currentAsset != asset) return;
    if (_currentVolume < _targetVolume * 0.75) {
      await _fadeTo(_targetVolume);
    }
  }

  Future<void> _activateSession() async {
    try {
      final session = await AudioSession.instance;
      await session.configure(
        const AudioSessionConfiguration(
          avAudioSessionCategory: AVAudioSessionCategory.ambient,
        ),
      );
      await session.setActive(true);
    } catch (e) {
      debugPrint('BGM: audio session configure/activate failed: $e');
    }
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

  // iOS/just_audio 偶爾會出現 play() 已回傳、甚至 playing=true，但音源還沒真正
  // 前進的狀態。用 processingState + position 是否前進確認，比只看 playing 穩。
  Future<void> _startPlaybackWithRecovery(String asset) async {
    for (int attempt = 0; attempt < _playStartRetries; attempt++) {
      if (muted.value || _currentAsset != asset) return;

      await _activateSession();
      await _player.play();

      if (await _isPlaybackAdvancing()) return;

      debugPrint('BGM: playback did not advance, retry ${attempt + 1}');
      if (attempt == _playStartRetries - 1) {
        // 驗證在某些裝置上可能誤判；最後一次不要 stop 掉，避免救援流程
        // 反而讓 BGM 留在停止狀態。
        await _player.play();
        return;
      }
      await _player.stop();
      if (muted.value || _currentAsset != asset) return;
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
      await Future.delayed(const Duration(milliseconds: 450));
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
    if (muted.value == value) return;
    muted.value = value;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefKey, value);

    if (value) {
      await _fadeTo(0);
      if (!muted.value) return; // 使用者已改回不靜音
      await _player.pause();
    } else if (_currentAsset != null) {
      // 之前因靜音而沒實際播放 → 啟動；之前在播但被暫停 → 復原
      if (_player.processingState == ProcessingState.idle) {
        await _loadAsset(_currentAsset!);
      }
      if (muted.value) return; // 使用者已改回靜音
      await _startPlaybackWithRecovery(_currentAsset!);
      await _fadeTo(_targetVolume);
      // 淡入過程中又被靜音
      if (muted.value) {
        await _player.pause();
      }
    }
  }

  // 線性淡到目標音量。新的 fade 會把舊的 fade 的 Future 直接 complete 掉，
  // 防止「await _fadeTo」永遠卡住。
  Future<void> _fadeTo(double to) async {
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
    final totalSteps = _fadeDuration.inMilliseconds ~/ _fadeStep.inMilliseconds;
    var step = 0;

    _fadeTimer = Timer.periodic(_fadeStep, (timer) async {
      // 換到新的 fade 了，這個 timer 就放生
      if (_activeFadeCompleter != completer) {
        timer.cancel();
        return;
      }
      step++;
      final progress = (step / totalSteps).clamp(0.0, 1.0);
      final vol = from + (to - from) * progress;
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
        break;
      case AppLifecycleState.resumed:
        if (_wasPlayingBeforeBackground && !muted.value) {
          _player.play();
          _fadeTo(_targetVolume);
        }
        break;
      case AppLifecycleState.detached:
        break;
    }
  }
}
