import 'dart:async';

import 'package:flutter/widgets.dart';

import '../utils/app_feedback.dart';

// 長按連發按鈕：點一下觸發一次；按住先停頓再連續觸發（步進器加減用）。
// 只負責手勢，外觀由 child 決定。onTrigger 為 null 時停用（不觸發、不連發）。
class HoldRepeatButton extends StatefulWidget {
  final VoidCallback? onTrigger;
  final Widget child;

  const HoldRepeatButton({
    super.key,
    required this.onTrigger,
    required this.child,
  });

  @override
  State<HoldRepeatButton> createState() => _HoldRepeatButtonState();
}

class _HoldRepeatButtonState extends State<HoldRepeatButton> {
  Timer? _delay;
  Timer? _repeat;
  int _fires = 0;

  void _start() {
    if (widget.onTrigger == null) return;
    _fire(haptic: true);
    // 按住 ~360ms 後開始連發，連發到一定次數再加速
    _delay = Timer(const Duration(milliseconds: 360), () {
      _repeat = Timer.periodic(
        const Duration(milliseconds: 110),
        (_) => _fire(haptic: false),
      );
    });
  }

  void _fire({required bool haptic}) {
    if (widget.onTrigger == null) {
      _stop();
      return;
    }
    _fires++;
    if (haptic) playHaptic(HapticLevel.selection);
    widget.onTrigger!.call();
    // 連發超過一段時間後加速一次
    if (_fires == 14) {
      _repeat?.cancel();
      _repeat = Timer.periodic(
        const Duration(milliseconds: 55),
        (_) => _fire(haptic: false),
      );
    }
  }

  void _stop() {
    _delay?.cancel();
    _repeat?.cancel();
    _delay = null;
    _repeat = null;
    _fires = 0;
  }

  @override
  void dispose() {
    _stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) => _start(),
      onPointerUp: (_) => _stop(),
      onPointerCancel: (_) => _stop(),
      child: widget.child,
    );
  }
}
