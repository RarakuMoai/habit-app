// Standalone debug entry. Production main.dart never imports this trial.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:habit_app/pages/home/room_metrics.dart';
import 'motion.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!kDebugMode) throw StateError('This art trial is debug-only.');
  final layers = <String, ui.Image>{};
  // Served locally for the simulator; trial PNGs never enter pubspec or the
  // production bundle. Binary data in dart-defines exceeds macOS ARG_MAX.
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
  try {
    for (final name in ['body', 'arm', 'vest']) {
      final request = await client.getUrl(
        Uri.parse('http://127.0.0.1:8766/$name.png'),
      );
      final response = await request.close();
      if (response.statusCode != 200) {
        throw StateError('Missing trial layer: $name');
      }
      final bytes = await consolidateHttpClientResponseBytes(response);
      final codec = await ui.instantiateImageCodec(bytes);
      layers[name] = (await codec.getNextFrame()).image;
      codec.dispose();
    }
  } finally {
    client.close(force: true);
  }
  runApp(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF6C7D59)),
        scaffoldBackgroundColor: const Color(0xFFFFFDF9),
        useMaterial3: true,
      ),
      home: RigTrialPage(layers: layers),
    ),
  );
}

class RigTrialPage extends StatefulWidget {
  const RigTrialPage({super.key, required this.layers});
  final Map<String, ui.Image> layers;

  @override
  State<RigTrialPage> createState() => _RigTrialPageState();
}

class _RigTrialPageState extends State<RigTrialPage>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _clock;
  bool _vest = false;
  bool _mesh = false;
  bool _dark = false;
  bool _zoom = false;
  bool _reduce = false;
  bool _systemReduce = false;
  bool _foreground = true;
  bool _tickers = true;

  bool get _motionAllowed =>
      !_reduce && !_systemReduce && _foreground && _tickers;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _clock = AnimationController(vsync: this, duration: trialDuration);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _systemReduce = MediaQuery.disableAnimationsOf(context);
    _tickers = TickerMode.valuesOf(context).enabled;
    if (!_motionAllowed) _clock.stop();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground) _clock.stop();
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _clock.dispose();
    super.dispose();
  }

  void _seek(double ms) {
    _clock.stop();
    _clock.value = (ms / trialDuration.inMilliseconds).clamp(0.0, 1.0);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    // HomePage measures the top inset outside Scaffold; body padding is zero.
    final viewport = MediaQuery.of(context);
    if (!widget.layers.keys.toSet().containsAll(['body', 'arm', 'vest'])) {
      return const Scaffold(
        body: SafeArea(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text('請先執行 rig/prepare.py，並在本機 8766 埠啟動圖層伺服器。'),
          ),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('兔咪動作驗證 · 試作')),
      body: AnimatedBuilder(
        animation: _clock,
        builder: (context, _) {
          final ms = _clock.value * trialDuration.inMilliseconds;
          final angle = (_reduce || _systemReduce)
              ? armAngle(1200)
              : armAngle(ms);
          final size = viewport.size;
          final region = sceneRegionHeightAnchored(
            size.width,
            viewport.padding.top,
          );
          final scale = mascotStageScale(
            maxWidth: size.width,
            maxHeight: region,
          );
          return ListView(
            children: [
              // Same 252 stage, 8 horizontal padding, width/height scaling and
              // bottom alignment as production MascotScene. No production
              // room/light/subtitle rendering is claimed by this art harness.
              ColoredBox(
                color: _dark
                    ? const Color(0xFF344148)
                    : const Color(0xFFECE6D9),
                child: SizedBox(
                  height: _zoom ? 400 : region,
                  child: Align(
                    alignment: const Alignment(0, .92),
                    child: Transform.scale(
                      scale: _zoom ? 1.55 : scale,
                      alignment: Alignment.bottomCenter,
                      child: SizedBox(
                        width: 252,
                        height: 252,
                        child: Center(
                          child: SizedBox(
                            width: 236,
                            height: 236,
                            child: CustomPaint(
                              key: const ValueKey('rig-stage'),
                              painter: RigPainter(
                                layers: widget.layers,
                                angle: angle,
                                vest: _vest,
                                mesh: _mesh,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      '${_vest ? '小背心' : '原造型'} · ${ms.round()} ms',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Text(
                      _zoom
                          ? '放大檢查接縫；不是正式顯示尺寸'
                          : '正式尺寸基準：PNG 顯示 ${(236 * scale).toStringAsFixed(1)} pt',
                    ),
                    const SizedBox(height: 12),
                    SegmentedButton<bool>(
                      segments: const [
                        ButtonSegment(value: false, label: Text('原造型')),
                        ButtonSegment(value: true, label: Text('小背心')),
                      ],
                      selected: {_vest},
                      onSelectionChanged: (value) =>
                          setState(() => _vest = value.single),
                    ),
                    Slider(
                      value: ms,
                      max: trialDuration.inMilliseconds.toDouble(),
                      label: '${ms.round()} ms',
                      onChanged: (_reduce || _systemReduce) ? null : _seek,
                    ),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FilledButton.icon(
                          onPressed: !_motionAllowed
                              ? null
                              : () {
                                  setState(() {
                                    if (_clock.isAnimating) {
                                      _clock.stop();
                                    } else {
                                      _clock.forward(
                                        from: _clock.value >= 1
                                            ? 0
                                            : _clock.value,
                                      );
                                    }
                                  });
                                },
                          icon: Icon(
                            _clock.isAnimating ? Icons.pause : Icons.play_arrow,
                          ),
                          label: Text(_clock.isAnimating ? '暫停' : '播放一次'),
                        ),
                        OutlinedButton(
                          onPressed: (_reduce || _systemReduce)
                              ? null
                              : () => _seek(ms - 100),
                          child: const Text('−100 ms'),
                        ),
                        OutlinedButton(
                          onPressed: (_reduce || _systemReduce)
                              ? null
                              : () => _seek(ms + 100),
                          child: const Text('+100 ms'),
                        ),
                      ],
                    ),
                    Wrap(
                      spacing: 8,
                      children: [
                        FilterChip(
                          label: const Text('放大'),
                          selected: _zoom,
                          onSelected: (v) => setState(() => _zoom = v),
                        ),
                        FilterChip(
                          label: const Text('深色底'),
                          selected: _dark,
                          onSelected: (v) => setState(() => _dark = v),
                        ),
                        FilterChip(
                          label: const Text('顯示網格'),
                          selected: _mesh,
                          onSelected: (v) => setState(() => _mesh = v),
                        ),
                        FilterChip(
                          label: const Text('降低動態'),
                          selected: _reduce || _systemReduce,
                          onSelected: (v) => setState(() {
                            _reduce = v;
                            _clock.stop();
                          }),
                        ),
                      ],
                    ),
                    const Text(
                      '同一身體、手臂與時間軸；切換造型只增減衣服圖層。這是素材與網格試驗，尚未採用 Spine，也未接入正式 App。',
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class RigPainter extends CustomPainter {
  RigPainter({
    required this.layers,
    required this.angle,
    required this.vest,
    this.mesh = false,
  });
  final Map<String, ui.Image> layers;
  final double angle;
  final bool vest;
  final bool mesh;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 1024, size.height / 1024);
    final paint = Paint()..filterQuality = FilterQuality.medium;
    canvas.drawImage(layers['body']!, Offset.zero, paint);
    if (vest) canvas.drawImage(layers['vest']!, Offset.zero, paint);
    final geometry = armMesh(angle);
    final vertices = ui.Vertices(
      ui.VertexMode.triangles,
      geometry.posed,
      textureCoordinates: geometry.rest,
      indices: geometry.indices,
    );
    paint.shader = ui.ImageShader(
      layers['arm']!,
      TileMode.clamp,
      TileMode.clamp,
      Float64List.fromList([1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]),
    );
    canvas.drawVertices(vertices, BlendMode.srcOver, paint);
    vertices.dispose();
    paint.shader?.dispose();
    if (mesh) {
      final pen = Paint()
        ..color = const Color(0xBBE56454)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;
      for (var i = 0; i < geometry.indices.length; i += 3) {
        final points = geometry.indices
            .sublist(i, i + 3)
            .map((index) => geometry.posed[index])
            .toList();
        canvas.drawPath(Path()..addPolygon(points, true), pen);
      }
      canvas.drawCircle(shoulder, 7, Paint()..color = const Color(0xFF316C92));
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant RigPainter oldDelegate) =>
      oldDelegate.angle != angle ||
      oldDelegate.vest != vest ||
      oldDelegate.mesh != mesh ||
      oldDelegate.layers != layers;
}
