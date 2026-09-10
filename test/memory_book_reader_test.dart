import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:habit_app/pages/memory_book_reader.dart';
import 'package:habit_app/pages/story_reveal_page.dart';
import 'package:habit_app/utils/story_catalog.dart';
import 'package:habit_app/utils/story_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'l10n_test_app.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await StoryStore.load();
  });

  void useCompactPhone(WidgetTester tester) {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  testWidgets('memory reader keeps the full story readable on compact phones', (
    tester,
  ) async {
    useCompactPhone(tester);
    final event = storyEventById('comeback');

    await tester.pumpWidget(
      l10nTestApp(
        home: MemoryBookReader(
          entries: [StoryUnlock(event.id, DateTime(2026, 7, 12))],
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 3));

    expect(find.text('兔咪回憶本'), findsOneWidget);
    expect(find.text(event.label), findsOneWidget);
    expect(find.text(event.title), findsOneWidget);
    expect(find.text('嗯...我們就從今天，慢慢再走。'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('嗯...我們就從今天，慢慢再走。'),
      120,
      scrollable: find.byType(Scrollable).last,
    );
    expect(
      tester.getBottomRight(find.text('嗯...我們就從今天，慢慢再走。')).dy,
      lessThanOrEqualTo(568),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty memory reader has a readable first-page state', (
    tester,
  ) async {
    useCompactPhone(tester);
    await tester.pumpWidget(
      l10nTestApp(home: const MemoryBookReader(entries: [])),
    );
    await tester.pump();
    expect(find.byIcon(Icons.auto_stories_outlined), findsOneWidget);
    expect(find.text('1 / 0'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('story reveal presents its collection label without overflow', (
    tester,
  ) async {
    useCompactPhone(tester);
    final event = storyEventById('streak_7');

    await tester.pumpWidget(
      l10nTestApp(
        home: StoryRevealPage(event: event, date: DateTime(2026, 7, 12)),
      ),
    );
    await tester.pump(const Duration(seconds: 4));

    expect(find.text('新的回憶・${event.label}'), findsOneWidget);
    expect(find.text(event.title), findsOneWidget);
    expect(find.text('點一下，收進回憶本 ✧'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'changing reduced motion keeps the current story and visible captions',
    (tester) async {
      useCompactPhone(tester);
      final reduced = ValueNotifier(false);
      addTearDown(reduced.dispose);
      final event = storyEventById('comeback');
      await tester.pumpWidget(
        l10nTestApp(
          home: ValueListenableBuilder<bool>(
            valueListenable: reduced,
            builder: (context, value, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: value),
              child: child!,
            ),
            child: StoryRevealPage(event: event, date: DateTime(2026, 9, 10)),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      reduced.value = true;
      await tester.pump();
      for (final line in event.pages.first.captions) {
        final opacity = tester.widget<AnimatedOpacity>(
          find
              .ancestor(
                of: find.text(line),
                matching: find.byType(AnimatedOpacity),
              )
              .first,
        );
        expect(opacity.opacity, 1);
        expect(opacity.duration, Duration.zero);
      }
      reduced.value = false;
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text(event.title), findsOneWidget);
      for (final line in event.pages.first.captions) {
        expect(
          tester
              .widget<AnimatedOpacity>(
                find
                    .ancestor(
                      of: find.text(line),
                      matching: find.byType(AnimatedOpacity),
                    )
                    .first,
              )
              .opacity,
          1,
        );
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
