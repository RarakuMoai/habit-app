import 'package:flutter/material.dart';

import 'tumi_painter.dart';

/// 兔咪向量重繪預覽（開發用，不進正式 app）。
/// 跑法：flutter run -t lib/dev/tumi/tumi_preview_main.dart
void main() => runApp(const _TumiPreviewApp());

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
    with SingleTickerProviderStateMixin {
  late final AnimationController _breath;

  @override
  void initState() {
    super.initState();
    _breath = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 2400))
      ..repeat(reverse: true);
  }

  @override
  void dispose() {
    _breath.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: AnimatedBuilder(
        animation: _breath,
        builder: (context, _) {
          final t = Curves.easeInOut.transform(_breath.value);
          return Transform.scale(
            scaleY: 1.0 + 0.012 * t,
            scaleX: 1.0 - 0.006 * t,
            alignment: Alignment.bottomCenter,
            child: const CustomPaint(
              painter: TumiPainter(),
              size: Size.square(380),
            ),
          );
        },
      ),
    );
  }
}
