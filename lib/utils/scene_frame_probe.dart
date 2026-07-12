// 場景效能探針：以 10 秒為一個視窗，統計 UI(build) / raster 幀時間的
// 平均、P95、最大值與超出 16.7ms 預算的幀數，印成 [SCENE_PERF] log。
//
// 用途：四時段場景系統（docs/fable5_day_cycle_scene_plan.md）的 Phase 0
// 效能基準與後續各 Phase 的前後對照。沒有幀時（例如閒置凍結、切到別的
// 分頁、App 退背景）也會印「0 frames」視窗，用來證明場景真的停在 0fps。
//
// 啟用方式（預設完全不編入行為，正式版零成本）：
//   flutter run --profile --dart-define=SCENE_PERF=1
//
// 注意：debug 模式數據只能做相對比較，上線判斷一律以 profile/release
// 實機數據為準（見計劃書 §7／§9）。
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

/// 是否啟用探針（compile-time；預設 false，release 不帶任何程式碼路徑）。
/// 接受 SCENE_PERF=1 或 SCENE_PERF=true。
const bool kScenePerfProbe =
    String.fromEnvironment('SCENE_PERF') == '1' ||
    bool.fromEnvironment('SCENE_PERF');

abstract final class SceneFrameProbe {
  static bool _attached = false;
  static final List<double> _buildMs = <double>[];
  static final List<double> _rasterMs = <double>[];
  static int _windowIndex = 0;

  /// 掛上 timings callback ＋ 10 秒視窗計時器。可重複呼叫（冪等）。
  /// 探針掛上後跟 App 同生共死，計時器不需回收。
  static void ensureAttached() {
    if (!kScenePerfProbe || _attached) return;
    _attached = true;
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
    Timer.periodic(const Duration(seconds: 10), (_) => _flush());
    debugPrint('[SCENE_PERF] probe attached (mode: $_modeLabel)');
  }

  static String get _modeLabel => kReleaseMode
      ? 'release'
      : kProfileMode
      ? 'profile'
      : 'debug';

  static void _onTimings(List<FrameTiming> timings) {
    for (final t in timings) {
      _buildMs.add(t.buildDuration.inMicroseconds / 1000);
      _rasterMs.add(t.rasterDuration.inMicroseconds / 1000);
    }
  }

  static void _flush() {
    final n = _buildMs.length;
    final i = _windowIndex++;
    if (n == 0) {
      debugPrint('[SCENE_PERF] w$i 10s: 0 frames (scene idle / 0fps)');
      return;
    }
    final build = _stats(_buildMs);
    final raster = _stats(_rasterMs);
    final over = _rasterMs.where((ms) => ms > 16.7).length;
    debugPrint(
      '[SCENE_PERF] w$i 10s: $n frames (~${(n / 10).toStringAsFixed(1)}fps) '
      'ui avg ${build.avg}/p95 ${build.p95}/max ${build.max}ms | '
      'raster avg ${raster.avg}/p95 ${raster.p95}/max ${raster.max}ms | '
      '>budget $over',
    );
    _buildMs.clear();
    _rasterMs.clear();
  }

  static ({String avg, String p95, String max}) _stats(List<double> xs) {
    final sorted = List<double>.of(xs)..sort();
    final avg = sorted.reduce((a, b) => a + b) / sorted.length;
    final p95 = sorted[((sorted.length - 1) * 0.95).round()];
    return (
      avg: avg.toStringAsFixed(1),
      p95: p95.toStringAsFixed(1),
      max: sorted.last.toStringAsFixed(1),
    );
  }
}
