import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'tumi_rig.dart';

/// 兔咪動畫演示（開發用，不進正式 app）。
/// 跑法：flutter run -t lib/dev/tumi/tumi_preview_main.dart
/// 上：參考圖　下：向量版（呼吸＋耳朵擺動＋隨機眨眼，點她會彈跳）
void main() => runApp(const _TumiPreviewApp());

const _refAsset = 'assets/mascot/ref/tumi_neutral_front.JPG';

class _TumiPreviewApp extends StatelessWidget {
  const _TumiPreviewApp();

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(child: _PreviewBody()),
      ),
    );
  }
}

class _PreviewBody extends StatefulWidget {
  const _PreviewBody();

  @override
  State<_PreviewBody> createState() => _PreviewBodyState();
}

class _PreviewBodyState extends State<_PreviewBody>
    with TickerProviderStateMixin {
  late final AnimationController _breath;
  late final AnimationController _sway;
  late final AnimationController _blink;
  late final AnimationController _bounce;
  Timer? _blinkTimer;
  final _rand = math.Random();

  @override
  void initState() {
    super.initState();
    _breath = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat(reverse: true);
    _sway = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3600),
    )..repeat();
    _blink = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 130),
    );
    _bounce = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 520),
    );
    _scheduleBlink();
  }

  void _scheduleBlink() {
    _blinkTimer = Timer(
      Duration(milliseconds: 1800 + _rand.nextInt(2600)),
      () async {
        if (!mounted) return;
        await _blink.forward();
        await _blink.reverse();
        // 偶爾連眨兩下
        if (_rand.nextInt(4) == 0 && mounted) {
          await _blink.forward();
          await _blink.reverse();
        }
        _scheduleBlink();
      },
    );
  }

  @override
  void dispose() {
    _blinkTimer?.cancel();
    _breath.dispose();
    _sway.dispose();
    _blink.dispose();
    _bounce.dispose();
    super.dispose();
  }

  void _onTap() {
    _bounce.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Padding(
          padding: EdgeInsets.all(8),
          child: Text('上：參考圖　下：向量版（點她看看）'),
        ),
        Expanded(child: Image.asset(_refAsset)),
        Expanded(
          child: GestureDetector(
            onTap: _onTap,
            child: AnimatedBuilder(
              animation: Listenable.merge([_breath, _sway, _blink, _bounce]),
              builder: (context, _) {
                final breath = Curves.easeInOut.transform(_breath.value);
                final phase = _sway.value * 2 * math.pi;
                // 點擊彈跳：快速壓扁再回彈（squash & stretch）
                final b = _bounce.isAnimating || _bounce.value > 0
                    ? _bounce.value
                    : 1.0;
                final squash = _bounce.isAnimating
                    ? 1.0 -
                          0.10 *
                              math.sin(b * math.pi) *
                              math.cos(b * math.pi * 2.5)
                    : 1.0;
                return Transform.scale(
                  scaleY: (1.0 + 0.012 * breath) * squash,
                  scaleX: (1.0 - 0.006 * breath) * (2 - squash),
                  alignment: Alignment.bottomCenter,
                  child: CustomPaint(
                    painter: TumiRigPainter(
                      earL: math.sin(phase),
                      earR: math.sin(phase + 0.9),
                      blink: Curves.easeIn.transform(_blink.value),
                    ),
                    size: const Size.square(380),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}
