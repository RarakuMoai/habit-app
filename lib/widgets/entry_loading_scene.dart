import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../utils/app_style.dart';

/// Deliberate presentation timings, independent of actual asset progress.
abstract final class EntrySceneMotion {
  /// One complete opening beat: wallpaper arrival, one bunny hop, then rest.
  static const entrance = Duration(milliseconds: 1320);

  /// Avoid flashing a loading label when startup work finishes quickly.
  static const loadingStatusDelay = Duration(milliseconds: 700);
  static const reveal = Duration(milliseconds: 560);
  static const route = Duration(milliseconds: 620);

  /// A pale apricot paper, darker than the app's cards but still quiet enough
  /// to hand off to the bright cover without a color flash.
  static const paper = Color(0xFFFFF1E5);
  static const motifOpacity = .32;
  static const strongMotifOpacity = .40;
}

/// Shared original line art for loading wallpaper and touch confetti.
enum EntryMotif { bunny, leaf, flower, sparkle }

void paintEntryMotif(Canvas canvas, EntryMotif motif, Paint paint) {
  switch (motif) {
    case EntryMotif.bunny:
      canvas.drawPath(
        Path()
          ..moveTo(-6, -1)
          ..cubicTo(-13, -20, -2, -24, -1, -5)
          ..cubicTo(1, -24, 13, -21, 6, -1)
          ..cubicTo(15, 12, -15, 12, -6, -1)
          ..close(),
        paint,
      );
    case EntryMotif.leaf:
      canvas.drawPath(
        Path()
          ..moveTo(-8, 10)
          ..quadraticBezierTo(-14, -8, 11, -13)
          ..quadraticBezierTo(18, 6, -8, 10)
          ..close(),
        paint,
      );
      if (paint.style == PaintingStyle.stroke) {
        canvas.drawLine(const Offset(-9, 12), const Offset(5, -5), paint);
      }
    case EntryMotif.flower:
      final path = Path();
      for (var i = 0; i <= 80; i++) {
        final angle = i * math.pi * 2 / 80;
        final radius = 9 + 2.6 * math.cos(angle * 5);
        final x = math.cos(angle) * radius, y = math.sin(angle) * radius;
        if (i == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      canvas.drawPath(path..close(), paint);
      if (paint.style == PaintingStyle.stroke) {
        canvas.drawCircle(Offset.zero, 2.2, paint);
      }
    case EntryMotif.sparkle:
      canvas.drawPath(
        Path()
          ..moveTo(0, -11)
          ..quadraticBezierTo(2, -2, 10, 0)
          ..quadraticBezierTo(2, 2, 0, 11)
          ..quadraticBezierTo(-2, 2, -10, 0)
          ..quadraticBezierTo(-2, -2, 0, -11)
          ..close(),
        paint,
      );
  }
}

/// Native warm-paper interstitial. Progress is decoded asset count, never time.
class EntryLoadingScene extends StatefulWidget {
  const EntryLoadingScene({
    super.key,
    required this.label,
    this.detail,
    this.progress,
    this.preparingRoom = false,
    this.showStatus = true,
    this.statusDelay = Duration.zero,
    this.active = true,
  });

  final String label;
  final String? detail;
  final double? progress;
  final bool preparingRoom, showStatus, active;
  final Duration statusDelay;

  @override
  State<EntryLoadingScene> createState() => EntryLoadingSceneState();
}

class EntryLoadingSceneState extends State<EntryLoadingScene>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final _clock = AnimationController.unbounded(vsync: this);
  bool _reduce = false, _foreground = true;
  Timer? _statusTimer;
  bool _statusDelayElapsed = false;

  @visibleForTesting
  double get motionSeconds => _clock.value;
  @visibleForTesting
  bool get motionRunning => _clock.isAnimating;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _statusDelayElapsed = widget.statusDelay == Duration.zero;
    if (!_statusDelayElapsed) {
      _statusTimer = Timer(widget.statusDelay, () {
        if (mounted) setState(() => _statusDelayElapsed = true);
      });
    }
  }

  void _sync() {
    final run =
        widget.active &&
        _foreground &&
        !_reduce &&
        TickerMode.valuesOf(context).enabled;
    if (run && !_clock.isAnimating) {
      _clock.repeat(min: 0, max: 3600, period: const Duration(hours: 1));
    } else if (!run) {
      _clock.stop();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduce =
        MediaQuery.disableAnimationsOf(context) ||
        MediaQuery.accessibleNavigationOf(context);
    _sync();
  }

  @override
  void didUpdateWidget(covariant EntryLoadingScene oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _sync();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _statusTimer?.cancel();
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return ColoredBox(
      color: EntrySceneMotion.paper,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ExcludeSemantics(
            child: RepaintBoundary(
              child: CustomPaint(
                painter: _WallpaperPainter(
                  _clock,
                  reduced: _reduce,
                  strong: widget.preparingRoom,
                ),
              ),
            ),
          ),
          if (widget.preparingRoom && widget.showStatus)
            SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 32,
                    vertical: 24,
                  ),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 320),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ExcludeSemantics(
                          child: SizedBox(
                            width: 112,
                            height: 112,
                            child: RepaintBoundary(
                              child: CustomPaint(
                                painter: _RoomSealPainter(_clock, _reduce),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          widget.label,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        if (widget.detail != null) ...[
                          const SizedBox(height: 10),
                          Text(
                            widget.detail!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: AppInk.soft,
                              fontSize: 13,
                              height: 1.6,
                            ),
                          ),
                        ],
                        const SizedBox(height: 24),
                        SizedBox(
                          width: 184,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: LinearProgressIndicator(
                              value: widget.progress ?? (_reduce ? 0 : null),
                              minHeight: 5,
                              color: AppPalette.habit,
                              backgroundColor: AppPalette.habit.withValues(
                                alpha: .12,
                              ),
                              semanticsLabel: l.entryPreparingAssets,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          if (widget.showStatus && _statusDelayElapsed)
            Positioned.fill(
              child: SafeArea(
                child: Align(
                  alignment: Alignment.bottomRight,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
                    child: Semantics(
                      label: widget.label,
                      child: ExcludeSemantics(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              width: 30,
                              height: 38,
                              child: RepaintBoundary(
                                child: CustomPaint(
                                  painter: _LoadingBunnyPainter(
                                    _clock,
                                    _reduce,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 7),
                            Text(
                              l.commonLoading,
                              style: const TextStyle(
                                color: AppPalette.habitInk,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                letterSpacing: .8,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _WallpaperPainter extends CustomPainter {
  _WallpaperPainter(this.clock, {required this.reduced, required this.strong})
    : super(repaint: clock);
  final Animation<double> clock;
  final bool reduced, strong;

  @override
  void paint(Canvas canvas, Size size) {
    final t = reduced ? 0.0 : clock.value;
    // The source reference uses regular diagonal drift, not random confetti.
    const pitch = 86.0;
    final drift = reduced ? 0.0 : t * 9 % (pitch * 4);
    final appear = reduced ? 1.0 : ((t - .12) / .42).clamp(0.0, 1.0);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.65
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    for (var row = -5; row < size.height / pitch + 6; row++) {
      for (var col = -5; col < size.width / pitch + 6; col++) {
        final motif = EntryMotif.values[(row + col * 3) % 4];
        final x = col * pitch + (row.isOdd ? pitch / 2 : 0) + drift;
        final y = row * pitch - drift;
        if (x < -30 || y < -30 || x > size.width + 30 || y > size.height + 30) {
          continue;
        }
        canvas.save();
        canvas.translate(x, y);
        canvas.rotate((row + col) % 2 == 0 ? -.16 : .18);
        canvas.scale(1.04);
        paint.color =
            (motif == EntryMotif.leaf
                    ? AppPalette.habitDone
                    : motif == EntryMotif.flower
                    ? AppPalette.habit
                    : const Color(0xffcbb075))
                .withValues(
                  alpha:
                      (strong
                          ? EntrySceneMotion.strongMotifOpacity
                          : EntrySceneMotion.motifOpacity) *
                      appear,
                );
        paintEntryMotif(canvas, motif, paint);
        canvas.restore();
      }
    }
    // Quiet center, legible text; no extra artwork or large brand mark.
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = RadialGradient(
          radius: .75,
          colors: [
            EntrySceneMotion.paper.withValues(alpha: strong ? .85 : .48),
            EntrySceneMotion.paper.withValues(alpha: 0),
          ],
        ).createShader(Offset.zero & size),
    );
  }

  @override
  bool shouldRepaint(covariant _WallpaperPainter old) =>
      old.reduced != reduced || old.strong != strong;
}

class _LoadingBunnyPainter extends CustomPainter {
  _LoadingBunnyPainter(this.clock, this.reduced) : super(repaint: clock);
  final Animation<double> clock;
  final bool reduced;
  @override
  void paint(Canvas canvas, Size size) {
    final hop = reduced
        ? 0.0
        : math.pow(math.max(0, math.sin(clock.value * 4.4)), 2).toDouble();
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(size.width / 2, 32),
        width: 16 - hop * 5,
        height: 3,
      ),
      Paint()..color = AppPalette.habitInk.withValues(alpha: .12 - hop * .04),
    );
    canvas.save();
    canvas.translate(size.width / 2, 24 - hop * 5);
    canvas.scale(.67);
    paintEntryMotif(
      canvas,
      EntryMotif.bunny,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8
        ..strokeCap = StrokeCap.round
        ..color = AppPalette.habitInk,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _LoadingBunnyPainter old) =>
      old.reduced != reduced;
}

class _RoomSealPainter extends CustomPainter {
  _RoomSealPainter(this.clock, this.reduced) : super(repaint: clock);
  final Animation<double> clock;
  final bool reduced;
  @override
  void paint(Canvas canvas, Size size) {
    final t = reduced ? 0.0 : clock.value;
    canvas.translate(size.width / 2, size.height / 2);
    canvas.drawCircle(
      Offset.zero,
      44,
      Paint()..color = const Color(0xffffecd6),
    );
    canvas.drawCircle(
      Offset.zero,
      50,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = const Color(0xffead3ac),
    );
    canvas.save();
    canvas.translate(0, 7 + (reduced ? 0 : math.sin(t * 2.8) * 2));
    canvas.scale(1.8);
    paintEntryMotif(
      canvas,
      EntryMotif.bunny,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.55
        ..strokeCap = StrokeCap.round
        ..color = AppPalette.habitInk,
    );
    canvas.restore();
    for (var i = 0; i < 3; i++) {
      final angle = i * math.pi * 2 / 3 + t * .22;
      canvas.save();
      canvas.translate(math.cos(angle) * 49, math.sin(angle) * 49);
      canvas.scale(.44);
      paintEntryMotif(
        canvas,
        EntryMotif.values[i + 1],
        Paint()
          ..style = PaintingStyle.fill
          ..color = [
            AppPalette.habitDone,
            AppPalette.habitLight,
            AppPalette.habit,
          ][i],
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _RoomSealPainter old) => old.reduced != reduced;
}

/// Reveal the destination through the paper; both screen sizes use real bounds.
class EntryPaperRevealClipper extends CustomClipper<Path> {
  EntryPaperRevealClipper(this.progress);
  final double progress;
  @override
  Path getClip(Size size) {
    final path = Path()..fillType = PathFillType.evenOdd;
    path.addRect(Offset.zero & size);
    if (progress > 0) {
      final center = Offset(size.width * .52, size.height * .56);
      final far = Offset(size.width * .52, size.height * .56).distance + 2;
      path.addOval(Rect.fromCircle(center: center, radius: far * progress));
    }
    return path;
  }

  @override
  bool shouldReclip(covariant EntryPaperRevealClipper old) =>
      old.progress != progress;
}
