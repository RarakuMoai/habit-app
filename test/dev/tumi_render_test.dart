import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:habit_app/dev/tumi/tumi_painter.dart';

/// 開發工具：把 TumiPainter 渲染成 PNG 供視覺比對（非行為測試）。
/// 跑 `flutter test test/dev/tumi_render_test.dart` 後輸出 /tmp/tumi_painted.png。
void main() {
  test('render TumiPainter to PNG', () async {
    const size = 1024.0;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawRect(
      const Rect.fromLTWH(0, 0, size, size),
      Paint()..color = Colors.white,
    );
    const TumiPainter().paint(canvas, const Size(size, size));
    final image = await recorder.endRecording().toImage(1024, 1024);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    File('/tmp/tumi_painted.png').writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}
