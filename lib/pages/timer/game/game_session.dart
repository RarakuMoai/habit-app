import 'dart:async';

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../../../utils/app_feedback.dart';
import '../../../utils/audio_settings_service.dart';
import '../../../utils/bgm_service.dart';
import '../../../utils/sfx_service.dart';
import '../../../utils/timer_mutex.dart';
import '../../../utils/wake_guard.dart';
import 'game_clock.dart';

/// [GameSession.start] 的結果：呼叫端據此決定後續 UI 動作
/// （新開局→卡片自動進全螢幕；搶鎖暫停了別的計時器→在自己的畫面跳提示）。
class GameStartResult {
  /// 是否為新開局（而非暫停後繼續）。
  final bool freshStart;

  /// 搶鎖時被自動暫停的另一個計時器提示字；沒有就 null。
  final String? pausedOtherMessage;

  const GameStartResult({required this.freshStart, this.pausedOtherMessage});
}

/// 遊戲計時器的副作用接線層：Ticker、TimerMutex、WakeGuard、音效/觸覺、
/// 進出全螢幕的 BGM 靜音，全部集中在這裡。
///
/// 卡片與全螢幕頁都只呼叫這裡的意圖方法、監聽 [controller] 重繪，
/// 誰都碰不到對方的私有狀態——舊版「全螢幕頁偷讀卡片 State + 手動世代
/// 計數器同步」的整類 bug 從結構上消失。
///
/// 副作用跟著狀態走：controller 每次通知都經過 [_syncSideEffects]，
/// ticker/鎖屏/互斥鎖永遠跟 running 對齊，不存在「忘記 release」的路徑。
class GameSession with WidgetsBindingObserver {
  final GameClockController controller = GameClockController();
  late final Ticker _ticker;
  Duration _lastElapsed = Duration.zero;
  bool _bgmMutedByUs = false;
  bool _disposed = false;

  /// 全螢幕頁掛上的「關閉自己」回呼：session 被 dispose 時（宿主卡片被移出
  /// widget 樹）先請它退場，不留持有殭屍參照的 route。
  final List<VoidCallback> _fullscreenClosers = [];

  GameSession({required TickerProvider vsync}) {
    _ticker = vsync.createTicker(_onTick);
    controller.onEvent = _onClockEvent;
    controller.addListener(_syncSideEffects);
    TimerMutex.register(ActiveTimer.game, pauseForOther);
    WidgetsBinding.instance.addObserver(this);
    unawaited(controller.loadPrefs());
  }

  bool get disposed => _disposed;

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final close in List.of(_fullscreenClosers)) {
      close();
    }
    _fullscreenClosers.clear();
    onFullscreenExited(); // 還掛著我們設的 BGM 靜音就還原
    WidgetsBinding.instance.removeObserver(this);
    controller.removeListener(_syncSideEffects);
    _ticker.dispose();
    WakeGuard.release('game');
    TimerMutex.unregister(ActiveTimer.game);
    controller.dispose();
  }

  // ── 意圖（卡片/全螢幕共用，回饋音在這裡發，狀態變化交給 controller）──

  /// 開始或繼續。決出勝負／已在跑時回 null（呼叫端不用做事）。
  GameStartResult? start() {
    if (controller.running || controller.finished) return null;
    final fresh = !controller.started;
    final pausedOther = TimerMutex.acquire(ActiveTimer.game);
    controller.start();
    playFeedback(SfxCue.tap, haptic: HapticLevel.medium);
    return GameStartResult(
      freshStart: fresh,
      pausedOtherMessage: pausedOther?.pausedMessage,
    );
  }

  void pause() {
    if (controller.pause()) {
      playFeedback(SfxCue.tap, haptic: HapticLevel.selection);
    }
  }

  /// 換手：醒目的 gameTurn 鈴聲提醒下一位可以動了（不是普通 tap 音）。
  void pass() {
    if (controller.pass()) {
      playFeedback(SfxCue.gameTurn, haptic: HapticLevel.medium);
    }
  }

  /// 上一位：沒有歷史可還原時輕震提示，不報錯不出聲。
  void undo() {
    if (controller.undo()) {
      playFeedback(SfxCue.cancel, haptic: HapticLevel.selection);
    } else {
      playHaptic(HapticLevel.light);
    }
  }

  void reset() {
    if (controller.reset()) {
      playFeedback(SfxCue.cancel, haptic: HapticLevel.light);
    }
  }

  /// 圓環／全螢幕整頁共用同一套點擊規則：進行中＝換手、決出勝負＝再來一局、
  /// 待機或暫停＝開始/繼續（此時回傳結果給呼叫端跳提示、進全螢幕）。
  GameStartResult? tapAnywhere() {
    if (controller.running) {
      pass();
      return null;
    }
    if (controller.finished) {
      reset();
      return null;
    }
    return start();
  }

  /// 被別的計時器搶鎖：暫停保留戰局，不發音效。
  void pauseForOther() => controller.pause();

  // ── 全螢幕期間的 BGM 靜音（大家在看棋盤，音樂較干擾）──

  void onFullscreenEntered() {
    if (!AudioSettingsService.musicMuted.value) {
      _bgmMutedByUs = true;
      unawaited(BgmService.instance.setMuted(true));
    }
  }

  void onFullscreenExited() {
    // 只有「目前仍是我們設的靜音」才還原；使用者中途自己改過音樂設定
    // 就尊重他的選擇，不硬蓋回去。
    if (_bgmMutedByUs && AudioSettingsService.musicMuted.value) {
      unawaited(BgmService.instance.setMuted(false));
    }
    _bgmMutedByUs = false;
  }

  void addFullscreenCloser(VoidCallback close) => _fullscreenClosers.add(close);

  void removeFullscreenCloser(VoidCallback close) =>
      _fullscreenClosers.remove(close);

  // ── 內部接線 ──

  void _onTick(Duration elapsed) {
    final dt = (elapsed - _lastElapsed).inMicroseconds / 1e6;
    _lastElapsed = elapsed;
    controller.tick(dt);
  }

  // controller 每次通知都把副作用對齊狀態：running 才轉 ticker、held 鎖屏。
  void _syncSideEffects() {
    if (controller.running) {
      if (!_ticker.isActive) {
        _lastElapsed = Duration.zero; // Ticker.start() 的 elapsed 從零起算
        _ticker.start();
      }
      WakeGuard.acquire('game');
    } else {
      _ticker.stop();
      WakeGuard.release('game');
      // 只有持有者能真的釋放；被別人搶走時這行是安全的 no-op。
      TimerMutex.release(ActiveTimer.game);
    }
  }

  void _onClockEvent(GameClockEvent event) {
    switch (event) {
      case GameClockEvent.warnTick:
        playFeedback(SfxCue.tap, haptic: HapticLevel.light);
      case GameClockEvent.turnTimeUp:
      case GameClockEvent.playerFlagged:
        playFeedback(SfxCue.complete, haptic: HapticLevel.medium);
      case GameClockEvent.finished:
        playFeedback(SfxCue.success);
    }
  }

  // 前景工具：切到背景就暫停（保留戰局），不在背景空轉 ticker。
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      controller.pause();
    }
  }
}
