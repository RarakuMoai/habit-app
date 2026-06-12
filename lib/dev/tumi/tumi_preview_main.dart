import 'dart:io';

import 'package:flutter/material.dart';

import 'tumi_painter.dart';

/// 兔咪向量重繪預覽（開發用，不進正式 app）。
/// 跑法：flutter run -t lib/dev/tumi/tumi_preview_main.dart
/// 上：參考圖（直接讀專案檔案，模擬器可讀 Mac 路徑；實機不行）
/// 下：程式向量版（會呼吸）
void main() => runApp(const _TumiPreviewApp());

const _refPath =
    '/Users/yayoi991331/habit-app/assets/mascot/ref/tumi_neutral_front.JPG';

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
    return Column(
      children: [
        const Padding(
          padding: EdgeInsets.all(8),
          child: Text('上：參考圖　下：程式向量版（呼吸中）'),
        ),
        Expanded(child: Image.file(File(_refPath))),
        Expanded(
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
                  size: Size.square(360),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
