import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../design_trials/tumi_2d_motion/rig/main.dart';
import '../design_trials/tumi_2d_motion/rig/motion.dart';

Future<Map<String, ui.Image>> loadLayers() async {
  final layers = <String, ui.Image>{};
  for (final name in ['body', 'arm', 'vest']) {
    final data = await File(
      'design_trials/tumi_2d_motion/rig/layers/$name.png',
    ).readAsBytes();
    final codec = await ui.instantiateImageCodec(data);
    layers[name] = (await codec.getNextFrame()).image;
    codec.dispose();
  }
  return layers;
}

Future<ui.Image> render(
  Map<String, ui.Image> layers,
  double ms,
  bool vest,
) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawColor(const Color(0xFF344148), BlendMode.src);
  RigPainter(
    layers: layers,
    angle: armAngle(ms),
    vest: vest,
  ).paint(canvas, const Size.square(512));
  final picture = recorder.endRecording();
  final result = await picture.toImage(512, 512);
  picture.dispose();
  return result;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'arm stays attached and triangles never fold during the full motion',
    () {
      for (var ms = 0; ms <= 2800; ms += 10) {
        final angle = armAngle(ms.toDouble());
        expect(
          deformArm(const Offset(388, 540), angle),
          const Offset(388, 540),
        );
        final mesh = armMesh(angle);
        for (var i = 0; i < mesh.indices.length; i += 3) {
          final a = mesh.posed[mesh.indices[i]];
          final b = mesh.posed[mesh.indices[i + 1]];
          final c = mesh.posed[mesh.indices[i + 2]];
          final area =
              (b.dx - a.dx) * (c.dy - a.dy) - (b.dy - a.dy) * (c.dx - a.dx);
          expect(
            area,
            greaterThan(0),
            reason: 'fold at $ms ms, triangle ${i ~/ 3}',
          );
        }
      }
    },
  );

  test('rendered rest returns exactly; outfit never changes the face', () async {
    final layers = await loadLayers();
    try {
      for (final vest in [false, true]) {
        final first = await render(layers, 0, vest);
        final last = await render(layers, 2800, vest);
        expect(
          (await first.toByteData())!.buffer.asUint8List(),
          (await last.toByteData())!.buffer.asUint8List(),
        );
        first.dispose();
        last.dispose();
      }
      final original = await render(layers, 1300, false);
      final dressed = await render(layers, 1300, true);
      final a = (await original.toByteData())!.buffer.asUint8List();
      final b = (await dressed.toByteData())!.buffer.asUint8List();
      // Head region lies above both the repair region and all moving vertices.
      expect(a.sublist(0, 250 * 512 * 4), b.sublist(0, 250 * 512 * 4));
      original.dispose();
      dressed.dispose();
    } finally {
      for (final image in layers.values) {
        image.dispose();
      }
    }
  });

  testWidgets(
    'trial keeps time when dressing, pauses in background and respects reduced motion',
    (tester) async {
      final layers = await tester.runAsync(loadLayers);
      addTearDown(() {
        for (final image in layers!.values) {
          image.dispose();
        }
      });
      tester.view.physicalSize = const Size(402, 874);
      tester.view.devicePixelRatio = 1;
      tester.view.padding = const FakeViewPadding(top: 62, bottom: 34);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPadding);
      await tester.pumpWidget(MaterialApp(home: RigTrialPage(layers: layers!)));
      expect(find.textContaining('PNG 顯示 213.0 pt'), findsOneWidget);
      await tester.tap(find.text('播放一次'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 800));
      RigPainter painter() =>
          tester
                  .widget<CustomPaint>(find.byKey(const ValueKey('rig-stage')))
                  .painter!
              as RigPainter;
      final before = painter().angle;
      await tester.tap(find.text('小背心'));
      await tester.pump();
      expect(painter().angle, before);
      expect(painter().vest, isTrue);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump(const Duration(seconds: 2));
      expect(painter().angle, before);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      await tester.ensureVisible(find.text('降低動態'));
      await tester.tap(find.text('降低動態'));
      await tester.pump();
      expect(painter().angle, armAngle(1200));
      await tester.pump(const Duration(seconds: 2));
      expect(painter().angle, armAngle(1200));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  test('optional contact sheet uses the actual Flutter painter', () async {
    if (Platform.environment['TUMI_RIG_CONTACT'] != '1') return;
    final font = FontLoader('RigReview')
      ..addFont(
        File(
          'assets/fonts/Nunito-Regular.ttf',
        ).readAsBytes().then(ByteData.sublistView),
      );
    await font.load();
    final layers = await loadLayers();
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawColor(const Color(0xFFFFFDF9), BlendMode.src);
    for (var row = 0; row < 2; row++) {
      for (var col = 0; col < 4; col++) {
        final ms = [0.0, 700.0, 1300.0, 2300.0][col];
        final frame = await render(layers, ms, row == 1);
        canvas.drawImage(frame, Offset(col * 512.0, row * 540.0), Paint());
        final label = TextPainter(
          text: TextSpan(
            text: '${row == 0 ? 'core' : 'vest'} / ${ms.round()} ms',
            style: const TextStyle(
              color: Colors.black,
              fontSize: 20,
              fontFamily: 'RigReview',
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        label.paint(canvas, Offset(col * 512.0 + 12, row * 540.0 + 512));
        frame.dispose();
      }
    }
    final picture = recorder.endRecording();
    final image = await picture.toImage(2048, 1080);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await Directory('tmp').create(recursive: true);
    await File(
      'tmp/tumi-rig-contact.png',
    ).writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
    picture.dispose();
    for (final image in layers.values) {
      image.dispose();
    }
  });
}
