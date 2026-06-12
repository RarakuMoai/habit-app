import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:habit_app/dev/tumi/original_bunny.dart';

/// 開發工具：渲染原創向量兔 — 靜態圖 + 動畫 12 幀。
void main() {
  Future<void> render(String name, OriginalBunnyPainter p) async {
    const size = 512.0;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawRect(const Rect.fromLTWH(0, 0, size, size),
        Paint()..color = Colors.white);
    p.paint(canvas, const Size.square(size));
    final image = await recorder.endRecording().toImage(512, 512);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    File('/tmp/obunny_$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
  }

  test('render original bunny static + frames', () async {
    await render('static', const OriginalBunnyPainter());
    await render('cheer', const OriginalBunnyPainter(cheer: 1));
    for (var i = 0; i < 12; i++) {
      final ph = i / 12 * 2 * math.pi;
      final blink = switch (i) { 7 => 0.7, 8 => 1.0, _ => 0.0 };
      await render(
          'f${i.toString().padLeft(2, '0')}',
          OriginalBunnyPainter(
            breath: math.sin(ph),
            earL: math.sin(ph),
            earR: math.sin(ph + 0.7),
            blink: blink,
            cheer: i >= 10 ? 1 : 0,
          ));
    }
  });
}
