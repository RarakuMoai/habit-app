import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'original_bunny.dart';

/// 原創向量兔演示（一次性實驗）。
/// 跑法：flutter run -t lib/dev/tumi/original_preview_main.dart
/// 呼吸＋耳擺＋隨機眨眼；點她 → 開心彎月眼＋彈跳。
void main() => runApp(const _App());

class _App extends StatelessWidget {
  const _App();

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: Color(0xFFFFFDF9),
        body: SafeArea(child: Center(child: _Bunny())),
      ),
    );
  }
}

class _Bunny extends StatefulWidget {
  const _Bunny();

  @override
  State<_Bunny> createState() => _BunnyState();
}

class _BunnyState extends State<_Bunny> with TickerProviderStateMixin {
  late final AnimationController _breath;
  late final AnimationController _sway;
  late final AnimationController _blink;
  late final AnimationController _cheer;
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
      duration: const Duration(milliseconds: 3800),
    )..repeat();
    _blink = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 130),
    );
    _cheer = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
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
    _cheer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _cheer.forward(from: 0),
      child: AnimatedBuilder(
        animation: Listenable.merge([_breath, _sway, _blink, _cheer]),
        builder: (context, _) {
          final phase = _sway.value * 2 * math.pi;
          // 開心曲線：快速進入、停留、淡出
          final c = _cheer.isAnimating || _cheer.value > 0
              ? (1 - (_cheer.value - 0.5).abs() * 2).clamp(0.0, 1.0) * 1.6
              : 0.0;
          final cheer = c.clamp(0.0, 1.0);
          final hop = _cheer.isAnimating
              ? math.sin(_cheer.value * math.pi * 3).abs() *
                    (1 - _cheer.value) *
                    26
              : 0.0;
          return Transform.translate(
            offset: Offset(0, -hop),
            child: CustomPaint(
              painter: OriginalBunnyPainter(
                breath: Curves.easeInOut.transform(_breath.value) * 2 - 1,
                earL: math.sin(phase),
                earR: math.sin(phase + 0.7),
                blink: Curves.easeIn.transform(_blink.value),
                cheer: cheer,
              ),
              size: const Size.square(380),
            ),
          );
        },
      ),
    );
  }
}
