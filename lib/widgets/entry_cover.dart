import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/app_localizations.dart';
import 'app_pressable.dart';

const kEntryCleanPlateAsset =
    'assets/scenes/onboarding/entry_living_room_v6_clean_fur.png';
const kEntryLeavesAsset = 'assets/scenes/onboarding/entry_leaves_v4.png';
const kEntryLogoAsset = 'assets/scenes/onboarding/entry_logo_zh_v4.png';

/// The cutout touches the left and bottom image edges. Both pose components are
/// positive-only, so the layer moves into the viewport instead of exposing its
/// cropped edges. Translation makes the low-right leaf visibly move while the
/// rigid rotation preserves every leaf's shape (unlike the former UV warp).
@visibleForTesting
double entryFoliagePhase(double seconds) {
  const primaryPeriod = 4.8;
  const secondaryPeriod = 7.6;
  final primary = (1 - math.cos(seconds * math.pi * 2 / primaryPeriod)) / 2;
  final secondary = (1 - math.cos(seconds * math.pi * 2 / secondaryPeriod)) / 2;
  return .75 * primary + .25 * secondary;
}

@visibleForTesting
double entryFoliageInset(double seconds) => 14 * entryFoliagePhase(seconds);

@visibleForTesting
double entryFoliageAngle(double seconds) => .011 * entryFoliagePhase(seconds);

/// The approved HTML composition, in full-viewport logical pixels. Safe areas
/// constrain controls, never the background's BoxFit.cover camera.
@immutable
class EntryCoverLayout {
  EntryCoverLayout(this.size, this.safe) {
    scale = math.max(size.width / 941, size.height / 1672);
    art = Rect.fromLTWH(
      (size.width - 941 * scale) / 2,
      (size.height - 1672 * scale) / 2,
      941 * scale,
      1672 * scale,
    );
    heroTop = art.top + 520 * scale; // Above the highest tuft, not the face.
    final top = math.max(size.height * .045, safe.top + 16);
    final width = math.max(
      0.0,
      math.min(size.width * .58, (heroTop - 20 - top) * 1233 / 963),
    );
    logo = Rect.fromLTWH(
      math.max(size.width * .075, safe.left + 8),
      top,
      width,
      width * 963 / 1233,
    );
  }
  final Size size;
  final EdgeInsets safe;
  late final double scale, heroTop;
  late final Rect art, logo;
  double get controlsBottom => math.max(24, safe.bottom + 12);
}

class EntryCover extends StatefulWidget {
  const EntryCover({
    super.key,
    required this.prompt,
    required this.onStart,
    required this.onLanguage,
    required this.onSettings,
    this.notice,
    this.onRetry,
    this.active = true,
  });
  final String prompt;
  final VoidCallback? onStart;
  final VoidCallback onLanguage, onSettings;
  final String? notice;
  final VoidCallback? onRetry;
  final bool active;
  @override
  State<EntryCover> createState() => EntryCoverState();
}

class EntryCoverState extends State<EntryCover>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final _clock = AnimationController.unbounded(vsync: this);
  ui.Image? _leaves;
  bool _reduce = false;
  bool _foreground = true;
  bool _tickerEnabled = true;

  @visibleForTesting
  bool get hasAnimatedFoliage => _leaves != null;
  @visibleForTesting
  double get motionSeconds => _clock.value;
  @visibleForTesting
  bool get motionRunning => _clock.isAnimating;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_loadLeaves());
  }

  Future<void> _loadLeaves() async {
    ui.Image? image;
    try {
      final data = await rootBundle.load(kEntryLeavesAsset);
      final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
      try {
        image = (await codec.getNextFrame()).image;
      } finally {
        codec.dispose();
      }
      if (!mounted) {
        image.dispose();
        return;
      }
      setState(() => _leaves = image);
    } catch (error) {
      image?.dispose();
      debugPrint('Entry foliage could not load: $error');
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduce =
        MediaQuery.disableAnimationsOf(context) ||
        MediaQuery.accessibleNavigationOf(context);
    _tickerEnabled = TickerMode.valuesOf(context).enabled;
    _sync();
  }

  @override
  void didUpdateWidget(covariant EntryCover oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _sync();
  }

  void _sync() {
    final run = widget.active && _foreground && _tickerEnabled && !_reduce;
    if (run && !_clock.isAnimating) {
      _clock.repeat(min: 0, max: 3600, period: const Duration(hours: 1));
    } else if (!run) {
      _clock.stop();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _clock.dispose();
    _leaves?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final layout = EntryCoverLayout(
          constraints.biggest,
          MediaQuery.paddingOf(context),
        );
        return ClipRect(
          child: Stack(
            fit: StackFit.expand,
            children: [
              ExcludeSemantics(
                child: RepaintBoundary(
                  child: Image.asset(kEntryCleanPlateAsset, fit: BoxFit.cover),
                ),
              ),
              IgnorePointer(
                child: RepaintBoundary(
                  child: CustomPaint(
                    key: const ValueKey('entry-environment'),
                    painter: _EnvironmentPainter(_clock, layout, _reduce),
                  ),
                ),
              ),
              IgnorePointer(
                child: RepaintBoundary(
                  child: _leaves == null
                      ? Image.asset(kEntryLeavesAsset, fit: BoxFit.cover)
                      : CustomPaint(
                          painter: _FoliagePainter(
                            _clock,
                            layout,
                            _leaves!,
                            _reduce,
                          ),
                        ),
                ),
              ),
              const IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      stops: [.7, 1],
                      colors: [Color(0x004b2f1c), Color(0x2a4b2f1c)],
                    ),
                  ),
                ),
              ),
              AppPressable(
                key: const ValueKey('entry-primary'),
                onPressed: widget.onStart,
                semanticsLabel: widget.prompt,
                child: const SizedBox.expand(),
              ),
              Positioned.fromRect(
                key: const ValueKey('entry-cover-logo'),
                rect: layout.logo,
                child: IgnorePointer(
                  child: AnimatedBuilder(
                    animation: _clock,
                    child: Semantics(
                      label: l.appTitle,
                      image: true,
                      child: const _LogoImage(),
                    ),
                    builder: (context, child) {
                      final t = _reduce ? 0.0 : _clock.value;
                      final float = (1 - math.cos(t * math.pi * 2 / 6.4)) / 2;
                      final shine = (t % 9 / 9 - .15) / .23;
                      return Transform.translate(
                        offset: Offset(
                          0,
                          _reduce ? 0 : -layout.logo.height * .0105 * float,
                        ),
                        child: Transform.rotate(
                          angle: _reduce
                              ? 0
                              : (-.16 + .32 * float) * math.pi / 180,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              child!,
                              if (!_reduce && shine > 0 && shine < 1)
                                ExcludeSemantics(
                                  child: ShaderMask(
                                    blendMode: BlendMode.srcIn,
                                    shaderCallback: (rect) => LinearGradient(
                                      begin: Alignment(-3 + shine * 6, -.4),
                                      end: Alignment(-1.8 + shine * 6, .4),
                                      colors: [
                                        const Color(0x00fff9df),
                                        const Color(0x70fff9df),
                                        const Color(0x00fff9df),
                                      ],
                                    ).createShader(rect),
                                    child: const _LogoImage(),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
              Positioned(
                left: 24,
                right: 24,
                top: math.min(
                  layout.size.height * .835 - 24,
                  layout.size.height - layout.controlsBottom - 52 - 56,
                ),
                child: IgnorePointer(
                  child: ExcludeSemantics(
                    child: AnimatedBuilder(
                      animation: _clock,
                      builder: (context, _) => Opacity(
                        opacity: _reduce
                            ? .92
                            : .55 + .37 * math.cos(_clock.value * math.pi),
                        child: _CoverPrompt(
                          widget.prompt,
                          width: layout.size.width,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              if (widget.notice != null || widget.onRetry != null)
                Positioned(
                  left: 20,
                  right: 20,
                  bottom: layout.controlsBottom + 64,
                  child: Material(
                    color: const Color(0xf5fff9ef),
                    borderRadius: BorderRadius.circular(16),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: layout.size.height * .30,
                      ),
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (widget.notice != null)
                              Semantics(
                                liveRegion: true,
                                child: Text(
                                  widget.notice!,
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            if (widget.onRetry != null)
                              TextButton(
                                onPressed: widget.onRetry,
                                child: Text(l.csRetry),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              Positioned(
                left: math.max(16, layout.safe.left),
                bottom: layout.controlsBottom,
                child: _CoverUtility(
                  key: const ValueKey('app-language'),
                  icon: Icons.language,
                  label: l.appLanguageTitle,
                  onPressed: widget.onLanguage,
                ),
              ),
              Positioned(
                right: math.max(16, layout.safe.right),
                bottom: layout.controlsBottom,
                child: _CoverUtility(
                  key: const ValueKey('entry-settings'),
                  icon: Icons.settings,
                  label: l.settingsTitle,
                  onPressed: widget.onSettings,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _CoverUtility extends StatelessWidget {
  const _CoverUtility({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
  });
  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 52,
    height: 52,
    child: DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: const [
          BoxShadow(
            color: Color(0x3e3d2618),
            blurRadius: 7,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: IconButton.filled(
        style: IconButton.styleFrom(
          backgroundColor: const Color(0xf5fff9ef),
          foregroundColor: const Color(0xff63402a),
          padding: EdgeInsets.zero,
          side: const BorderSide(color: Color(0xdacd9060)),
        ),
        tooltip: label,
        onPressed: onPressed,
        icon: Icon(icon, size: 30),
      ),
    ),
  );
}

// The approved preview crops only transparent margins (13 px each side).
// Preserve the original PNG bytes and perform that same crop at render time.
class _LogoImage extends StatelessWidget {
  const _LogoImage();
  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: ClipRect(
      child: FittedBox(
        fit: BoxFit.fill,
        child: SizedBox(
          width: 1233,
          height: 963,
          child: Stack(
            children: [
              Positioned(
                left: -13,
                top: -13,
                width: 1259,
                height: 989,
                child: Image.asset(kEntryLogoAsset),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _CoverPrompt extends StatelessWidget {
  const _CoverPrompt(this.text, {required this.width});
  final String text;
  final double width;
  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontSize: (width * .04676).clamp(16, 22),
      fontWeight: FontWeight.w600,
      letterSpacing: width * .00425,
      height: 1.4,
    );
    return SizedBox(
      height: 48,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Stack(
          children: [
            RichText(
              textScaler: MediaQuery.textScalerOf(context),
              text: TextSpan(
                text: text,
                style: style.copyWith(
                  foreground: Paint()
                    ..style = PaintingStyle.stroke
                    ..strokeWidth = width * .00319
                    ..color = const Color(0xfffff9ed),
                ),
              ),
            ),
            Text(
              text,
              style: style.copyWith(
                color: const Color(0xff69452d),
                shadows: const [
                  Shadow(
                    color: Color(0x59362216),
                    offset: Offset(0, 1.2),
                    blurRadius: 2,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FoliagePainter extends CustomPainter {
  _FoliagePainter(this.clock, this.layout, this.image, this.reduced)
    : super(repaint: clock);
  final Animation<double> clock;
  final EntryCoverLayout layout;
  final ui.Image image;
  final bool reduced;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.translate(layout.art.left, layout.art.top);
    canvas.scale(layout.scale);
    if (!reduced) {
      const root = Offset(-18, 1690);
      canvas
        ..translate(entryFoliageInset(clock.value), 0)
        ..translate(root.dx, root.dy)
        ..rotate(entryFoliageAngle(clock.value))
        ..translate(-root.dx, -root.dy);
    }
    canvas.drawImage(
      image,
      Offset.zero,
      Paint()..filterQuality = FilterQuality.medium,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _FoliagePainter old) =>
      old.image != image || old.layout != layout || old.reduced != reduced;
}

/// Matches the approved preview's deterministic particles, authored in logical
/// pixels so the large foreground motes remain legible on phones.
class _EnvironmentPainter extends CustomPainter {
  _EnvironmentPainter(this.clock, this.layout, this.reduced)
    : super(repaint: clock);
  final Animation<double> clock;
  final EntryCoverLayout layout;
  final bool reduced;
  @override
  void paint(Canvas canvas, Size size) {
    if (reduced) return;
    final t = clock.value;
    final gust = math.sin(t * .65) * .65 + math.sin(t * .27) * .35;
    canvas.save();
    canvas.translate(layout.art.left, layout.art.top);
    canvas.scale(layout.scale);
    canvas.drawRect(
      const Rect.fromLTWH(0, 0, 941, 1672),
      Paint()
        ..shader = ui.Gradient.radial(
          Offset(200 + gust * 24, 700),
          860,
          [
            Color.fromRGBO(255, 236, 173, .055 + .03 * (gust + 1)),
            const Color(0x06fff2cb),
            const Color(0x00fff6da),
          ],
          [0, .6, 1],
        ),
    );
    for (var i = 0; i < 2; i++) {
      canvas.save();
      canvas.translate(90 + i * 100 + gust * 18, 0);
      canvas.rotate(-.20 + gust * .009);
      canvas.drawRect(
        const Rect.fromLTWH(-55, 0, 145, 1972),
        Paint()
          ..shader = ui.Gradient.linear(
            const Offset(-55, 0),
            const Offset(90, 0),
            [
              const Color(0x00fff5ca),
              Color.fromRGBO(255, 243, 195, .07 + .02 * math.sin(t * .55 + i)),
              const Color(0x00fff5ca),
            ],
            [0, .45, 1],
          ),
      );
      canvas.restore();
    }
    canvas.save();
    canvas.clipPath(
      Path()
        ..moveTo(0, 1390)
        ..lineTo(260, 1415)
        ..lineTo(880, 1470)
        ..lineTo(941, 1672)
        ..lineTo(0, 1672)
        ..close(),
    );
    canvas.translate(-35 + gust * 24, 1350 + math.sin(t * .57) * 12);
    canvas.rotate(gust * .017);
    final shadow = Paint()
      ..color = Color.fromRGBO(99, 67, 45, .16 + gust * .025)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 13);
    canvas.drawPath(
      Path()
        ..moveTo(-40, 390)
        ..cubicTo(250, 220, 480, 250, 850, 0),
      shadow
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5,
    );
    shadow.style = PaintingStyle.fill;
    for (var i = 0; i < 15; i++) {
      for (final side in [-1, 1]) {
        canvas.save();
        canvas.translate(20 + i * 55, 355 - i * 22);
        canvas.rotate(-.65 + side * .8);
        canvas.translate(side * 28, -20);
        canvas.rotate(-.3);
        canvas.drawOval(
          Rect.fromCenter(
            center: Offset.zero,
            width: (18 + i % 3 * 6) * 2,
            height: 88,
          ),
          shadow,
        );
        canvas.restore();
      }
    }
    canvas.restore();
    for (var i = 0; i < 28; i++) {
      final phase = i * 2.39996;
      final y = ((180 + i * 251 % 1230) - t * (20 + i % 7 * 2.4)) % 1430 + 100;
      final x = 80 + i * 173 % 740 + math.sin(t * .39 + phase) * 36 + gust * 14;
      final face = math.pow((x - 613) / 230, 2) + math.pow((y - 795) / 245, 2);
      final alpha =
          (.45 + .25 * math.sin(t * .8 + phase)) *
          ((face - .65) * 2).clamp(.06, 1) *
          math.min(1, math.min((y - 100) / 110, (1530 - y) / 110)).clamp(0, 1);
      final r = (i % 7 == 0 ? 3.3 : 1.3 + i % 4 * .3) / layout.scale;
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(phase);
      canvas.drawOval(
        Rect.fromCenter(center: Offset.zero, width: r * 2, height: r * 1.64),
        Paint()..color = Color.fromRGBO(255, 247, 206, alpha),
      );
      if (i % 7 == 0) {
        canvas.drawCircle(
          Offset.zero,
          r * 2.5,
          Paint()..color = Color.fromRGBO(255, 239, 177, alpha * .15),
        );
      }
      canvas.restore();
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _EnvironmentPainter old) =>
      old.layout != layout || old.reduced != reduced;
}
