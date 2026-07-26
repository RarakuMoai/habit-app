import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:habit_app/dev/tumi/tumi_rig.dart';

/// 開發工具：渲染兔咪動畫 16 幀到 /tmp/tumi_anim_XX.png（拼條/GIF 用）。
void main() {
  test('render TumiRig animation frames', () async {
    const size = 512.0;
    for (var i = 0; i < 16; i++) {
      final phase = i / 16 * 2 * math.pi;
      final blink = switch (i) {
        10 => 0.6,
        11 => 1.0,
        12 => 0.4,
        _ => 0.0,
      };
      final breath = math.sin(phase);

      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawRect(
        const Rect.fromLTWH(0, 0, size, size),
        Paint()..color = Colors.white,
      );
      // 呼吸：以底部中心為錨點的輕微縱向縮放
      canvas.translate(size / 2, size);
      canvas.scale(1.0 - 0.006 * breath, 1.0 + 0.012 * breath);
      canvas.translate(-size / 2, -size);
      TumiRigPainter(
        earL: math.sin(phase),
        earR: math.sin(phase + 0.9),
        blink: blink,
      ).paint(canvas, const Size.square(size));

      final image = await recorder.endRecording().toImage(512, 512);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      File(
        '/tmp/tumi_anim_${i.toString().padLeft(2, '0')}.png',
      ).writeAsBytesSync(bytes!.buffer.asUint8List());
    }
  });
}
