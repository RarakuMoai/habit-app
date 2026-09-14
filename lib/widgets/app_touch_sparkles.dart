import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../utils/app_style.dart';
import 'entry_loading_scene.dart';

/// Passive pointer observation: never competes with buttons, scrolling or Back.
class AppTouchSparkles extends StatefulWidget {
  const AppTouchSparkles({super.key, required this.child});
  final Widget child;
  @override
  State<AppTouchSparkles> createState() => AppTouchSparklesState();
}

class _TouchDown {
  _TouchDown(this.position, this.time);
  final Offset position;
  final Duration time;
  bool moved = false;
}

class _TouchBurst {
  _TouchBurst(this.position, this.born, this.reduced);
  final Offset position;
  final Duration born;
  final bool reduced;
  Duration get duration => Duration(milliseconds: reduced ? 180 : 720);
}

class _TouchFrame extends ChangeNotifier {
  Duration elapsed = Duration.zero;
  void tick(Duration time) {
    elapsed = time;
    notifyListeners();
  }
}

class AppTouchSparklesState extends State<AppTouchSparkles>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final _downs = <int, _TouchDown>{};
  final _bursts = <_TouchBurst>[];
  final _frame = _TouchFrame();
  late final Ticker _ticker;

  @visibleForTesting
  int get activeBurstCount => _bursts.length;
  @visibleForTesting
  bool get motionRunning => _ticker.isActive;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_tick);
    WidgetsBinding.instance.addObserver(this);
  }

  void _tick(Duration elapsed) {
    _bursts.removeWhere((b) => elapsed - b.born >= b.duration);
    _frame.tick(elapsed);
    if (_bursts.isEmpty) _ticker.stop();
  }

  void _down(PointerDownEvent e) {
    if (e.buttons != kPrimaryButton) return;
    _downs[e.pointer] = _TouchDown(e.localPosition, e.timeStamp);
  }

  void _up(PointerUpEvent e) {
    final down = _downs.remove(e.pointer);
    if (down == null ||
        down.moved ||
        (e.localPosition - down.position).distance > 12 ||
        e.timeStamp - down.time > const Duration(milliseconds: 650)) {
      return;
    }
    if (!_ticker.isActive) {
      _frame.elapsed = Duration.zero;
      _ticker.start();
    }
    if (_bursts.length >= 8) _bursts.removeAt(0);
    _bursts.add(
      _TouchBurst(
        e.localPosition,
        _frame.elapsed,
        MediaQuery.disableAnimationsOf(context) ||
            MediaQuery.accessibleNavigationOf(context),
      ),
    );
    _frame.tick(_frame.elapsed);
  }

  void _clear() {
    _downs.clear();
    _bursts.clear();
    _ticker.stop();
    _frame.tick(Duration.zero);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _clear();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker.dispose();
    _frame.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Listener(
    behavior: HitTestBehavior.translucent,
    onPointerDown: _down,
    onPointerMove: (e) {
      final down = _downs[e.pointer];
      if (down != null && (e.localPosition - down.position).distance > 12) {
        down.moved = true;
      }
    },
    onPointerUp: _up,
    onPointerCancel: (e) => _downs.remove(e.pointer),
    child: Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        Positioned.fill(
          child: IgnorePointer(
            child: ExcludeSemantics(
              child: RepaintBoundary(
                child: CustomPaint(
                  key: const ValueKey('app-touch-sparkles'),
                  painter: _TouchPainter(_frame, _bursts),
                ),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

class _TouchPainter extends CustomPainter {
  _TouchPainter(this.frame, this.bursts) : super(repaint: frame);
  final _TouchFrame frame;
  final List<_TouchBurst> bursts;
  @override
  void paint(Canvas canvas, Size size) {
    for (final b in bursts) {
      final p =
          ((frame.elapsed - b.born).inMicroseconds / b.duration.inMicroseconds)
              .clamp(0.0, 1.0);
      final fade = 1 - Curves.easeIn.transform(p);
      canvas.save();
      canvas.translate(b.position.dx, b.position.dy);
      if (b.reduced) {
        canvas.drawCircle(
          Offset.zero,
          8,
          Paint()..color = AppPalette.habit.withValues(alpha: .22 * fade),
        );
        canvas.restore();
        continue;
      }
      final out = Curves.easeOutCubic.transform(p);
      canvas.drawCircle(
        Offset.zero,
        10 + out * 37,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.8 - p
          ..color = const Color(0xffefa39a).withValues(alpha: .8 * fade),
      );
      canvas.drawCircle(
        Offset.zero,
        6 + out * 30,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..color = const Color(0xfffffff2).withValues(alpha: .9 * fade),
      );
      for (var i = 0; i < 7; i++) {
        final angle = i * math.pi * 2 / 7 - .7;
        final travel = 12 + out * (i.isEven ? 52 : 41);
        canvas.save();
        canvas.translate(
          math.cos(angle) * travel,
          math.sin(angle) * travel + p * p * 10,
        );
        canvas.rotate(angle * .2 + p * (i.isEven ? .8 : -.8));
        canvas.scale((i == 0 ? .52 : .34) * (1 - p * .4));
        final motif = EntryMotif.values[i % 4];
        final color = [
          const Color(0xffd5aa67),
          const Color(0xff98b897),
          const Color(0xffe69c91),
          const Color(0xffe9c36f),
        ][i % 4];
        paintEntryMotif(
          canvas,
          motif,
          Paint()
            ..style = i == 0 || motif == EntryMotif.bunny
                ? PaintingStyle.stroke
                : PaintingStyle.fill
            ..strokeWidth = 2.5
            ..strokeCap = StrokeCap.round
            ..color = color.withValues(alpha: fade),
        );
        canvas.restore();
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _TouchPainter old) => old.frame != frame;
}
