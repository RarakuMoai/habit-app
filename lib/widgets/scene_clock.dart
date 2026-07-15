// 場景動畫時鐘（從 room_ambient_overlay.dart 抽出；舊程序化光影退場後
// 這是唯一留下的動態基礎設施）。
//
// [SceneAnimationClock]：單一 Ticker 驅動同場景所有動態層（空氣層／
// 完成星光等共享相位），完整模式節流 20fps。由頁面 State 持有並負責
// start/stop/dispose：閒置凍結呼叫 [SceneAnimationClock.stop]（0fps），
// 互動喚醒呼叫 [SceneAnimationClock.start]；切分頁/退背景由
// TickerProvider 的 TickerMode 靜音。
//
// [ThrottledSceneTicker]：Ticker + ValueNotifier 的共用底座（動態層
// 自有時鐘用，30fps 節流）。覆寫 [ThrottledSceneTicker.externalClock]
// 提供共享時鐘時，不建立自己的 Ticker。
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

class SceneAnimationClock {
  SceneAnimationClock({required TickerProvider vsync, double maxFps = 20})
    : _minInterval = 1 / maxFps {
    _ticker = vsync.createTicker(_onTick);
  }

  late final Ticker _ticker;
  final double _minInterval;

  /// painter 的 repaint listenable：值 = 時鐘啟動至今秒數（無界）。
  final ValueNotifier<double> time = ValueNotifier<double>(0);
  double _lastNotified = 0;

  void _onTick(Duration elapsed) {
    final t = elapsed.inMicroseconds / 1e6;
    if (t - _lastNotified < _minInterval) return;
    _lastNotified = t;
    time.value = t;
  }

  void start() {
    if (!_ticker.isActive) _ticker.start();
  }

  /// 完全停止（0fps）。之後的時段配色更新走 SceneTimeController 的
  /// 分鐘級單次 repaint，不需要動畫幀。
  void stop() => _ticker.stop();

  void dispose() {
    _ticker.dispose();
    time.dispose();
  }
}

mixin ThrottledSceneTicker<T extends StatefulWidget>
    on State<T>, SingleTickerProviderStateMixin<T> {
  Ticker? _ticker;
  // painter 的 repaint listenable：值 = 開場至今秒數（無界）
  final ValueNotifier<double> _time = ValueNotifier<double>(0);
  double _lastNotified = 0;

  /// 外部共享時鐘（例：首頁的 [SceneAnimationClock.time]）；null = 自建。
  ValueNotifier<double>? get externalClock => null;

  /// painter 的 repaint listenable。
  ValueNotifier<double> get sceneTime => externalClock ?? _time;

  @override
  void initState() {
    super.initState();
    if (externalClock == null) {
      _ticker = createTicker((elapsed) {
        final t = elapsed.inMicroseconds / 1e6;
        if (t - _lastNotified < 1 / 30) return; // 節流 ~30fps
        _lastNotified = t;
        _time.value = t;
      })..start();
    }
  }

  @override
  void dispose() {
    _ticker?.dispose();
    _time.dispose();
    super.dispose();
  }
}
