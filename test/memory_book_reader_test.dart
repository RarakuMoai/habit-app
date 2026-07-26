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
}
