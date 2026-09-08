import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../design_trials/tumi_2d_motion/invite_transition/main.dart';

void main() {
  testWidgets(
    'pose review preserves stage size, stops in background and reduces motion',
    (tester) async {
      final atlas = await tester.runAsync(() async {
        final codec = await ui.instantiateImageCodec(
          await File(
            'design_trials/tumi_2d_motion/invite_transition/pose-atlas.png',
          ).readAsBytes(),
        );
        final image = (await codec.getNextFrame()).image;
        codec.dispose();
        return image;
      });
      addTearDown(atlas!.dispose);
      tester.view.physicalSize = const Size(402, 874);
      tester.view.devicePixelRatio = 1;
      tester.view.padding = const FakeViewPadding(top: 62, bottom: 34);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPadding);
      await tester.pumpWidget(MaterialApp(home: InvitePreview(atlas: atlas)));
      expect(find.textContaining('PNG 顯示 213.0 pt'), findsOneWidget);
      PoseAtlasPainter painter() =>
          tester
                  .widget<CustomPaint>(
                    find.byKey(const ValueKey('invite-stage')),
                  )
                  .painter!
              as PoseAtlasPainter;
      expect(painter().index, 0);
      await tester.tap(find.text('播放一次'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1000));
      expect(painter().index, inExclusiveRange(0, 30));
      final atPause = painter().index;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump(const Duration(seconds: 2));
      expect(painter().index, atPause);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      await tester.ensureVisible(find.text('降低動態效果'));
      await tester.tap(find.text('降低動態效果'));
      await tester.pumpAndSettle();
      expect(painter().index, 30);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      await tester.pump(const Duration(seconds: 5));
      expect(painter().index, 30);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
