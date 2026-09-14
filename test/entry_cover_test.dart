import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:habit_app/widgets/entry_cover.dart';
import 'package:habit_app/widgets/entry_scenery.dart';

import 'l10n_test_app.dart';

void main() {
  test('cover and first meeting share the selected clean-fur base', () {
    expect(kEntryCoverAsset, kEntryCleanPlateAsset);
    expect(kEntryCoverAsset, contains('entry_living_room_v5_clean_fur.png'));
  });

  test('foliage uses a subtle inward-only rigid sway', () {
    final samples = [
      for (var milliseconds = 0; milliseconds <= 26000; milliseconds += 100)
        entryFoliageAngle(milliseconds / 1000),
    ];
    expect(samples.reduce((a, b) => a < b ? a : b), greaterThan(0));
    expect(samples.reduce((a, b) => a > b ? a : b), lessThan(.008));
    expect(samples.toSet().length, greaterThan(100));
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
