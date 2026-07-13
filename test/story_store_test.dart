import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:habit_app/utils/prefs_keys.dart';
import 'package:habit_app/utils/story_catalog.dart';
import 'package:habit_app/utils/story_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    StoryEvents.debugCatalog = null;
    await StoryStore.load();
  });

  test('unlock stores a catalog event once and tracks unread state', () async {
    expect(await StoryStore.unlock('first_habit'), true);
    expect(await StoryStore.unlock('first_habit'), false);

    expect(StoryStore.unlocked.value.map((e) => e.id), ['first_habit']);
    expect(StoryStore.unread.value, contains('first_habit'));

    await StoryStore.markRead('first_habit');

    expect(StoryStore.unread.value, isNot(contains('first_habit')));
  });

  test('unlock enqueues a pending reveal; consumeReveal drains it', () async {
    await StoryStore.unlock('first_habit');
    await StoryStore.unlock('comeback');

    // 先進先出：解鎖順序就是播放順序
    expect(StoryStore.pendingReveal.value, ['first_habit', 'comeback']);

    await StoryStore.consumeReveal('first_habit');
    expect(StoryStore.pendingReveal.value, ['comeback']);
    // 看完揭曉＝已讀（衣櫃的書不用再發亮）
    expect(StoryStore.unread.value, isNot(contains('first_habit')));

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList(PrefsKeys.storyPendingReveal), ['comeback']);
  });

  test('load restores pending reveals and filters stale ids', () async {
    SharedPreferences.setMockInitialValues({
      PrefsKeys.storyUnlocked:
          '[{"id":"first_habit","date":"2026-06-30T00:00:00.000"}]',
      PrefsKeys.storyUnread: ['first_habit', 'comeback', 'ghost_event'],
      PrefsKeys.storyPendingReveal: ['first_habit', 'ghost_event', 'comeback'],
    });

    await StoryStore.load();

    expect(StoryStore.unlocked.value.map((e) => e.id), ['first_habit']);
    expect(StoryStore.unread.value, {'first_habit'});
    // 沒解鎖的 id（含幽靈事件）不會留在待揭曉佇列
    expect(StoryStore.pendingReveal.value, ['first_habit']);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList(PrefsKeys.storyUnread), ['first_habit']);
    expect(prefs.getStringList(PrefsKeys.storyPendingReveal), ['first_habit']);
  });

  test('clear wipes unlocked, unread, and pending reveal state', () async {
    await StoryStore.unlock('first_habit');
    await StoryStore.clear();

    expect(StoryStore.unlocked.value, isEmpty);
    expect(StoryStore.unread.value, isEmpty);
    expect(StoryStore.pendingReveal.value, isEmpty);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(PrefsKeys.storyUnlocked), isNull);
    expect(prefs.getStringList(PrefsKeys.storyPendingReveal), isNull);
  });

  test('StoryEvents exposes production trigger helpers', () async {
    expect(await StoryEvents.onFirstHabitCreated(), 'first_habit');
    expect(await StoryEvents.onFirstHabitCreated(), isNull);

    expect(await StoryEvents.onFirstAllDone(), 'first_all_done');

    expect(await StoryEvents.onHabitStreak(6), isNull);
    expect(await StoryEvents.onHabitStreak(7), 'streak_7');

    expect(await StoryEvents.onComeback(6), isNull);
    expect(await StoryEvents.onComeback(7), 'comeback');
  });

  group('SeasonWindow', () {
    test('contains dates inside the yearly window', () {
      const xmas = SeasonWindow(month: 12, day: 24, days: 3); // 12/24–12/26
      expect(xmas.contains(DateTime(2026, 12, 23)), false);
      expect(xmas.contains(DateTime(2026, 12, 24)), true);
      expect(xmas.contains(DateTime(2026, 12, 26)), true);
      expect(xmas.contains(DateTime(2026, 12, 27)), false);
      // 每年都適用
      expect(xmas.contains(DateTime(2030, 12, 25)), true);
    });

    test('supports windows that wrap across new year', () {
      const newYear = SeasonWindow(month: 12, day: 30, days: 5); // 12/30–1/3
      expect(newYear.contains(DateTime(2026, 12, 29)), false);
      expect(newYear.contains(DateTime(2026, 12, 31)), true);
      expect(newYear.contains(DateTime(2027, 1, 2)), true);
      expect(newYear.contains(DateTime(2027, 1, 3)), true);
      expect(newYear.contains(DateTime(2027, 1, 4)), false);
    });
  });

  group('season / login streak triggers', () {
    // 目錄裡還沒有正式的節日／登入事件，用測試目錄驗證引擎行為；
    // id 沿用既有事件（unlock 會驗證 storyEventExists）。
    const testCatalog = [
      StoryEventSpec(
        id: 'first_habit',
        title: '測試節日 A',
        trigger: StoryTrigger.season,
        season: SeasonWindow(month: 12, day: 24, days: 3),
        pages: [
          StoryPage('assets/story/first_habit.png', ['台詞']),
        ],
      ),
      StoryEventSpec(
        id: 'comeback',
        title: '測試節日 B（重疊視窗）',
        trigger: StoryTrigger.season,
        season: SeasonWindow(month: 12, day: 25, days: 2),
        pages: [
          StoryPage('assets/story/comeback.png', ['台詞']),
        ],
      ),
      StoryEventSpec(
        id: 'streak_7',
        title: '測試登入 30 天',
        trigger: StoryTrigger.loginStreak,
        threshold: 30,
        pages: [
          StoryPage('assets/story/streak_7.png', ['台詞']),
        ],
      ),
    ];

    tearDown(() => StoryEvents.debugCatalog = null);

    test('onSeasonDay unlocks every event whose window contains it', () async {
      StoryEvents.debugCatalog = testCatalog;

      expect(await StoryEvents.onSeasonDay(DateTime(2026, 12, 20)), isEmpty);
      // 12/25 同時落在兩個視窗 → 一次解鎖兩個、都排進揭曉佇列
      expect(await StoryEvents.onSeasonDay(DateTime(2026, 12, 25)), [
        'first_habit',
        'comeback',
      ]);
      expect(StoryStore.pendingReveal.value, ['first_habit', 'comeback']);
      // 一次性回憶：隔年同一天不再解鎖
      expect(await StoryEvents.onSeasonDay(DateTime(2027, 12, 25)), isEmpty);
    });

    test('onLoginStreak respects threshold and idempotency', () async {
      StoryEvents.debugCatalog = testCatalog;

      expect(await StoryEvents.onLoginStreak(29), isNull);
      expect(await StoryEvents.onLoginStreak(30), 'streak_7');
      expect(await StoryEvents.onLoginStreak(31), isNull);
    });
  });

  test('catalog events are well-formed with bundled CG assets', () async {
    final ids = <String>{};
    for (final event in storyCatalog) {
      expect(ids.add(event.id), true, reason: '事件 id 不可重複：${event.id}');
      expect(event.pages, isNotEmpty, reason: '${event.id} 至少要有一頁');
      if (event.trigger == StoryTrigger.season) {
        expect(event.season, isNotNull, reason: '${event.id} 是節日事件，要有視窗');
      }
      for (final page in event.pages) {
        expect(
          File(page.image).existsSync(),
          true,
          reason: '${event.id} 的 ${page.image} 應該存在於 repo',
        );
        final bytes = await rootBundle.load(page.image);
        expect(
          bytes.lengthInBytes,
          greaterThan(10000),
          reason: '${event.id} 的 ${page.image} 應該能從 Flutter assets 載入',
        );
        expect(page.captions, isNotEmpty, reason: '${event.id} 每頁都要有台詞');
      }
    }

    expect(
      storyEventById('first_habit').cover,
      'assets/scenes/home/home_bg.png',
    );
    for (final event in storyCatalog) {
      expect(event.label, isNotEmpty, reason: '${event.id} 需要收藏分類');
      expect(event.unlockHint, isNotEmpty, reason: '${event.id} 需要未解鎖提示');
      expect(event.cover, endsWith('.png'));
    }
  });
}
