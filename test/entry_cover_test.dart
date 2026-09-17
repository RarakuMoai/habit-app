import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:habit_app/widgets/entry_cover.dart';
import 'package:habit_app/widgets/entry_scenery.dart';

import 'l10n_test_app.dart';

void main() {
  testWidgets('selected logo decodes with measured transparent ink bounds', (
    tester,
  ) async {
    await tester.runAsync(() async {
      expect(kEntryLogoAsset, endsWith('entry_logo_zh_v28.png'));
      final data = await rootBundle.load(kEntryLogoAsset);
      final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
      final image = (await codec.getNextFrame()).image;
      try {
        expect(
          Size(image.width.toDouble(), image.height.toDouble()),
          kEntryLogoImageSize,
        );
        final rgba = (await image.toByteData())!;
        var left = image.width, top = image.height, right = 0, bottom = 0;
        var hasTransparentPixel = false;
        for (var y = 0; y < image.height; y++) {
          for (var x = 0; x < image.width; x++) {
            final alpha = rgba.getUint8((y * image.width + x) * 4 + 3);
            hasTransparentPixel |= alpha == 0;
            if (alpha < 128) continue;
            if (x < left) left = x;
            if (y < top) top = y;
            if (x + 1 > right) right = x + 1;
            if (y + 1 > bottom) bottom = y + 1;
          }
        }
        expect(hasTransparentPixel, isTrue);
        expect(
          Rect.fromLTRB(
            left.toDouble(),
            top.toDouble(),
            right.toDouble(),
            bottom.toDouble(),
          ),
          kEntryLogoInkBounds,
        );
      } finally {
        image.dispose();
        codec.dispose();
      }
    });
  });

  test('cover and first meeting share the selected clean-fur base', () {
    expect(kEntryCoverAsset, kEntryCleanPlateAsset);
    expect(kEntryCoverAsset, contains('entry_living_room_v6_clean_fur.png'));
  });

  test('foliage uses a perceptible inward-only rigid sway', () {
    final seconds = [
      for (var milliseconds = 0; milliseconds <= 15200; milliseconds += 100)
        milliseconds / 1000,
    ];
    final insets = seconds.map(entryFoliageInset).toList();
    final angles = seconds.map(entryFoliageAngle).toList();
    expect(insets.reduce((a, b) => a < b ? a : b), 0);
    expect(insets.reduce((a, b) => a > b ? a : b), greaterThan(12));
    expect(angles.every((angle) => angle >= 0), isTrue);
    expect(angles.reduce((a, b) => a > b ? a : b), greaterThan(.009));
    expect(insets.toSet().length, greaterThan(100));
  });

  for (final size in [
    const Size(320, 568),
    const Size(375, 667),
    const Size(390, 844),
    const Size(430, 932),
    const Size(512, 795),
  ]) {
    for (final top in [0.0, 59.0]) {
      test('logo clears hero at $size, safe top $top', () {
        final layout = EntryCoverLayout(
          size,
          EdgeInsets.only(top: top, bottom: 34),
        );
        expect(
          layout.logo.bottom,
          lessThanOrEqualTo(layout.heroTop - 20 + 1e-8),
        );
        expect(layout.logo.top, greaterThanOrEqualTo(top + 16));
        expect(layout.logo.width, greaterThan(0));
        expect(layout.controlsBottom, 46);
      });
    }
  }

  testWidgets(
    'full screen tap, independent 52pt utilities, true native safe area',
    (tester) async {
      tester.view.physicalSize = const Size(430, 932);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var start = 0, language = 0, settings = 0;
      await tester.pumpWidget(
        l10nTestApp(
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(430, 932),
              padding: EdgeInsets.only(top: 59, bottom: 34),
            ),
            child: Scaffold(
              body: EntryCover(
                prompt: '輕觸開始',
                onStart: () => start++,
                onLanguage: () => language++,
                onSettings: () => settings++,
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 200));
      for (final key in ['app-language', 'entry-settings']) {
        final control = find.byKey(ValueKey(key));
        expect(tester.getSize(control), const Size(52, 52));
        expect(tester.getRect(control).bottom, 886);
        await tester.tap(control);
      }
      expect(language, 1);
      expect(settings, 1);
      expect(start, 0);
      await tester.tapAt(const Offset(240, 460));
      await tester.pump();
      expect(start, 1);
      expect(
        tester.getRect(find.byKey(const ValueKey('entry-cover-logo'))).top,
        75,
      );
      final logo = find.byKey(const ValueKey('entry-cover-logo'));
      final slot = tester.getRect(logo);
      final image = find
          .descendant(of: logo, matching: find.byType(Image))
          .first;
      final png = tester.getRect(image);
      // Transparent padding must not shrink the lettering, and the 3:2 PNG
      // must retain its aspect ratio inside the unchanged V4 allocation.
      // Measure transformed edges, not the diagonal's bounding rectangle:
      // the production logo also has a small, intentional animated rotation.
      final width =
          (tester.getTopRight(image) - tester.getTopLeft(image)).distance;
      final height =
          (tester.getBottomLeft(image) - tester.getTopLeft(image)).distance;
      expect(width / height, closeTo(1.5, .0001));
      final scale = width / kEntryLogoImageSize.width;
      expect(
        png.left + kEntryLogoInkBounds.left * scale,
        closeTo(slot.left, 1),
      );
      expect(
        png.left + kEntryLogoInkBounds.right * scale,
        closeTo(slot.right, 1),
      );
      expect(png.top + kEntryLogoInkBounds.top * scale, greaterThan(slot.top));
      expect(
        png.top + kEntryLogoInkBounds.bottom * scale,
        lessThan(slot.bottom),
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'one timeline pauses for panels, background, and reduced motion',
    (tester) async {
      Future<void> mount({bool active = true, bool reduce = false}) async {
        await tester.pumpWidget(
          l10nTestApp(
            home: MediaQuery(
              data: MediaQueryData(
                size: const Size(390, 844),
                disableAnimations: reduce,
              ),
              child: Scaffold(
                body: EntryCover(
                  prompt: '輕觸開始',
                  active: active,
                  onStart: () {},
                  onLanguage: () {},
                  onSettings: () {},
                ),
              ),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 100));
      }

      await mount();
      EntryCoverState state() =>
          tester.state<EntryCoverState>(find.byType(EntryCover));
      expect(state().motionRunning, isTrue);
      await tester.pump(const Duration(seconds: 1));
      final running = state().motionSeconds;
      expect(running, greaterThan(0));
      await mount(active: false);
      final stopped = state().motionSeconds;
      await tester.pump(const Duration(seconds: 2));
      expect(state().motionSeconds, stopped);
      await mount();
      expect(state().motionRunning, isTrue);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      expect(state().motionRunning, isFalse);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      expect(state().motionRunning, isTrue);
      await mount(reduce: true);
      expect(state().motionRunning, isFalse);
      expect(
        find.byKey(const ValueKey('entry-primary')).hitTestable(),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    },
  );
}
