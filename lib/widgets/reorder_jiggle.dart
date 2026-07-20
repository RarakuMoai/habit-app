// 「拖曳排序模式」的共用零件：整列 Q 版抖動＋長按/即按雙態拖曳辨識器。
//
// 這套互動語言（長按 1 秒整列拖曳、⋯ > 移動 明示入口、抖動＝排序中）
// 最早在習慣頁建立；衣櫃播放清單與遊戲桌設定頁共用本零件，確保排序模式
// 不會因各自複製而出現尺寸、圖示或手感差異。習慣頁既有私有版另行遷移。
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// 長按啟動拖曳的門檻。預設 kLongPressTimeout(500ms) 太靈敏，
/// 滑一下容易誤觸進排序；拉長到 1 秒（與習慣頁同一手感）。
const Duration kReorderHoldDelay = Duration(seconds: 1);

/// 排序模式中每列的「Q 版抖動」：監聽外部共用的 jiggle controller
/// （無自己的 ticker），依 seed 給不同相位/方向，看起來像 iOS 主畫面
/// 長按 App 那樣整列在輕輕晃。enabled=false 時零成本直通。
/// 共用 ticker 讓被拖曳的列 reparent 時不會帶著正在跑的 ticker，
/// 避開 element 生命週期崩潰。
class ReorderJiggle extends StatelessWidget {
  final Animation<double> animation;
  final bool enabled;
  final int seed;
  final Widget child;

  const ReorderJiggle({
    super.key,
    required this.animation,
    required this.enabled,
    required this.seed,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final direction = seed.isEven ? 1.0 : -1.0;
    final phaseOffset = (seed.abs() % 100) / 100 * math.pi * 2;
    // AnimatedBuilder 永遠存在（結構穩定）：停用時 builder 直接回傳 child、
    // controller 停在 0 不重繪；啟用時才套抖動 transform。
    return AnimatedBuilder(
      animation: animation,
      child: child,
      builder: (_, child) {
        if (!enabled) return child!;
        final phase = animation.value * math.pi * 2 + phaseOffset;
        final sway = math.sin(phase);
        final bounce = math.sin(phase + math.pi / 2);
        final squash = math.sin(phase + math.pi);
        // 抖動幅度：旋轉是主要訊號（~0.8°），位移/擠壓小幅跟上
        return Transform.translate(
          offset: Offset(direction * sway * 0.5, bounce * 0.9),
          child: Transform.rotate(
            angle: direction * sway * 0.014,
            child: Transform.scale(
              scaleX: 1 + squash * 0.005,
              scaleY: 1 - squash * 0.0035,
              child: child,
            ),
          ),
        );
      },
    );
  }
}

/// 拖曳啟動辨識器：未進排序模式用 Delayed（長按啟動，同一手勢長按完
/// 直接滑、不必放手重抓）；進模式後用 Immediate（觸碰即拖）。
/// 同一 widget 型別、只換 recognizer，不會在拖曳途中替換 element
/// 破壞 Reorderable 清單的 GlobalKey reparent。
class ReorderHoldDragListener extends ReorderableDragStartListener {
  final bool immediate;

  const ReorderHoldDragListener({
    super.key,
    required super.child,
    required super.index,
    required this.immediate,
  });

  @override
  MultiDragGestureRecognizer createRecognizer() {
    return immediate
        ? ImmediateMultiDragGestureRecognizer(debugOwner: this)
        : DelayedMultiDragGestureRecognizer(
            delay: kReorderHoldDelay,
            debugOwner: this,
          );
  }
}
