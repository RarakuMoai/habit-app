// Offline pose atlas review only. No production imports reference this entry.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:habit_app/pages/home/room_metrics.dart';

const previewDuration = Duration(milliseconds: 4200);

double poseProgress(double ms) {
  double ease(double value) {
    final t = value.clamp(0.0, 1.0);
    return t * t * (3 - 2 * t);
  }

  if (ms < 600) return 0;
  if (ms < 1800) return ease((ms - 600) / 1200);
  if (ms < 2400) return 1;
  if (ms < 3600) return 1 - ease((ms - 2400) / 1200);
  return 0;
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!kDebugMode) throw StateError('Art preview is debug-only.');
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
  late ui.Image atlas;
  try {
    final request = await client.getUrl(
      Uri.parse('http://127.0.0.1:8767/pose-atlas.png'),
    );
    final response = await request.close();
    if (response.statusCode != 200) throw StateError('Missing pose atlas');
    final codec = await ui.instantiateImageCodec(
      await consolidateHttpClientResponseBytes(response),
    );
    atlas = (await codec.getNextFrame()).image;
    codec.dispose();
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
      home: InvitePreview(atlas: atlas),
    ),
  );
}

class InvitePreview extends StatefulWidget {
  const InvitePreview({super.key, required this.atlas});
  final ui.Image atlas;

  @override
  State<InvitePreview> createState() => _InvitePreviewState();
}

class _InvitePreviewState extends State<InvitePreview>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _clock;
  bool _zoom = false;
  bool _reduced = false;
  bool _systemReduced = false;
  bool _visible = true;
  bool _foreground = true;
  bool get _allowed => !_reduced && !_systemReduced && _visible && _foreground;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _clock = AnimationController(vsync: this, duration: previewDuration);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _systemReduced = MediaQuery.disableAnimationsOf(context);
    _visible = TickerMode.valuesOf(context).enabled;
    if (!_allowed) _clock.stop();
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

  @override
  Widget build(BuildContext context) {
    // Read top inset outside Scaffold, matching production HomePage.
    final viewport = MediaQuery.of(context);
    final region = sceneRegionHeightAnchored(
      viewport.size.width,
      viewport.padding.top,
    );
    final scale = mascotStageScale(
      maxWidth: viewport.size.width,
      maxHeight: region,
    );
    return Scaffold(
      appBar: AppBar(title: const Text('中性 → 邀請 · 動作樣品')),
      body: AnimatedBuilder(
        animation: _clock,
        builder: (context, _) {
          final ms = _clock.value * previewDuration.inMilliseconds;
          final progress = _reduced || _systemReduced ? 1.0 : poseProgress(ms);
          return ListView(
            children: [
              ColoredBox(
                color: const Color(0xFF39464B),
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
                              key: const ValueKey('invite-stage'),
                              painter: PoseAtlasPainter(
                                widget.atlas,
                                (progress * 30).round(),
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
                    Text('${ms.round()} ms · 姿勢 ${(progress * 100).round()}%'),
                    Text(
                      _zoom
                          ? '放大檢查接縫'
                          : '正式尺寸基準：PNG 顯示 ${(236 * scale).toStringAsFixed(1)} pt',
                    ),
                    const SizedBox(height: 8),
                    const Text('這是離線動作樣品。檢查手臂路徑與接縫，尚未加入換裝、語音或正式場景。'),
                    Slider(
                      value: ms,
                      max: 4200,
                      onChanged: !_allowed
                          ? null
                          : (value) {
                              _clock.stop();
                              _clock.value = value / 4200;
                              setState(() {});
                            },
                    ),
                    Wrap(
                      spacing: 8,
                      children: [
                        FilledButton(
                          onPressed: !_allowed
                              ? null
                              : () {
                                  if (_clock.isAnimating) {
                                    _clock.stop();
                                  } else {
                                    _clock.forward(
                                      from: _clock.value >= 1
                                          ? 0
                                          : _clock.value,
                                    );
                                  }
                                  setState(() {});
                                },
                          child: Text(_clock.isAnimating ? '暫停' : '播放一次'),
                        ),
                        TextButton(
                          onPressed: !_allowed
                              ? null
                              : () {
                                  _clock.stop();
                                  _clock.value = 0;
                                  setState(() {});
                                },
                          child: const Text('回到起點'),
                        ),
                        TextButton(
                          onPressed: !_allowed
                              ? null
                              : () {
                                  _clock.stop();
                                  _clock.value = 2000 / 4200;
                                  setState(() {});
                                },
                          child: const Text('核准邀請姿勢'),
                        ),
                      ],
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('放大檢查'),
                      value: _zoom,
                      onChanged: (value) => setState(() => _zoom = value),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('降低動態效果'),
                      value: _reduced || _systemReduced,
                      onChanged: _systemReduced
                          ? null
                          : (value) => setState(() {
                              _reduced = value;
                              if (value) _clock.stop();
                            }),
                    ),
                    const Text(
                      '預覽含 31 個取樣姿勢；不代表 App 鎖定 31 FPS，也不能用 debug 模擬器判斷上架幀率。',
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

class PoseAtlasPainter extends CustomPainter {
  PoseAtlasPainter(this.atlas, this.index);
  final ui.Image atlas;
  final int index;
  @override
  void paint(Canvas canvas, Size size) {
    final i = index.clamp(0, 30);
    canvas.drawImageRect(
      atlas,
      Rect.fromLTWH((i % 8) * 384.0, (i ~/ 8) * 384.0, 384, 384),
      Offset.zero & size,
      Paint()..filterQuality = FilterQuality.medium,
    );
  }

  @override
  bool shouldRepaint(covariant PoseAtlasPainter oldDelegate) =>
      oldDelegate.atlas != atlas || oldDelegate.index != index;
}
