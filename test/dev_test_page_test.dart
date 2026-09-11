import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:habit_app/l10n/app_localizations.dart';
import 'package:habit_app/pages/dev_test_page.dart';
import 'package:habit_app/utils/coin_config.dart';
import 'package:habit_app/utils/coin_service.dart';
import 'package:habit_app/utils/companion_story_preview.dart';
import 'package:habit_app/utils/companion_story_progress.dart';
import 'package:habit_app/utils/prefs_keys.dart';
import 'package:habit_app/utils/scene_time.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'l10n_test_app.dart';

// A lazy ListView can build a card before the button inside it is on screen.
// ensureVisible also needs a layout frame after jumpTo before the hit test.
Future<void> _tapVisible(WidgetTester tester, Finder target) async {
  await tester.scrollUntilVisible(
    target,
    400,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
  expect(target.hitTestable(), findsOneWidget);
  await tester.tap(target);
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SceneTimeController sceneTime;

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    sceneTime = SceneTimeController(clock: () => DateTime(2026, 7, 13, 13));
    SceneTimeController.debugInstance = sceneTime;
  });

  tearDown(() {
    CompanionStoryPreview.setEnabled(false);
    sceneTime.dispose();
    SceneTimeController.debugInstance = null;
  });

  testWidgets('場景預覽使用正式四時段與 50/50 交界，原始統計不再佔據頁首', (tester) async {
    await tester.pumpWidget(l10nTestApp(home: const DevTestPage()));
    await tester.pumpAndSettle();

    expect(find.text('使用統計（本機匿名）'), findsNothing);
    expect(find.text('足跡幣（測試）'), findsOneWidget);
    for (final amount in [1, 5, 10, 100]) {
      expect(find.text('+$amount'), findsOneWidget);
    }
    expect(find.text('+50'), findsNothing);

    final list = find.byType(ListView);
    for (var i = 0; i < 5 && find.text('場景時段').evaluate().isEmpty; i++) {
      await tester.drag(list, const Offset(0, -600));
      await tester.pumpAndSettle();
    }

    expect(find.text('場景時段'), findsOneWidget);
    expect(find.text('清晨 06:30'), findsOneWidget);
    expect(find.text('白天 13:00'), findsOneWidget);
    expect(find.text('黃昏 17:30'), findsOneWidget);
    expect(find.text('夜晚 23:00'), findsOneWidget);
    expect(find.text('晝→暮 16:30:00'), findsOneWidget);

    await _tapVisible(tester, find.text('晝→暮 16:30:00'));

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getDouble(PrefsKeys.debugSceneHour), 16.5);
    expect(find.text('16:30'), findsOneWidget);
  });

  testWidgets('單一回憶預覽開關不改正式進度，前導與資料工具仍可用', (tester) async {
    final savedProgress = jsonEncode(
      CompanionProgressState(
        days: 1,
        creditedDayKeys: {'2026-09-11'},
        completed: {
          'story_01': CompanionCompletion(
            firstCompletedAt: '2026-09-11',
            skipped: true,
            read: false,
          ),
        },
      ).toJson(),
    );
    SharedPreferences.setMockInitialValues({
      PrefsKeys.companionStoryProgress: savedProgress,
      'unrelated_saved_record': 'keep me',
    });
    final prefs = await SharedPreferences.getInstance();
    final before = {for (final key in prefs.getKeys()) key: prefs.get(key)};
    await tester.pumpWidget(l10nTestApp(home: const DevTestPage()));
    await tester.pumpAndSettle();

    final preview = find.byKey(const ValueKey('companion-preview-all'));
    await _tapVisible(tester, preview);
    expect(CompanionStoryPreview.active, isTrue);
    expect(find.byKey(const ValueKey('companion-open-review')), findsNothing);
    expect(
      find.byKey(const ValueKey('onboarding-open-preview')),
      findsOneWidget,
    );
    final l10n = lookupAppLocalizations(const Locale('zh'));
    expect(find.text(l10n.dvMemoryPreviewSection), findsNothing);
    expect(find.text(l10n.dvSimFirstHabit), findsNothing);
    expect(find.text(l10n.dvClearMemories), findsNothing);
    final dataTools = find.byKey(const ValueKey('memory-data-tools'));
    expect(dataTools, findsOneWidget);
    final dataToolsHeader = find.descendant(
      of: dataTools,
      matching: find.text(l10n.dvMemoryDataTools),
    );
    await _tapVisible(tester, dataToolsHeader);
    expect(find.text(l10n.dvSimFirstHabit), findsOneWidget);
    expect(find.text(l10n.dvClearMemories), findsOneWidget);
    expect({for (final key in prefs.getKeys()) key: prefs.get(key)}, before);
    await _tapVisible(tester, dataToolsHeader);
    expect(find.text(l10n.dvSimFirstHabit), findsNothing);
    expect(find.text(l10n.dvClearMemories), findsNothing);

    await _tapVisible(tester, preview);
    expect(CompanionStoryPreview.active, isFalse);
    expect({for (final key in prefs.getKeys()) key: prefs.get(key)}, before);
  });

  testWidgets('快轉日子會重開當日登入獎勵並可再觸發報到', (tester) async {
    final now = DateTime.now();
    final today =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
    SharedPreferences.setMockInitialValues(<String, Object>{
      PrefsKeys.coinLastLoginDate: today,
      PrefsKeys.coinLoginLevel: 2,
      PrefsKeys.coinLoginStreak: 2,
      PrefsKeys.coinClaim(CoinSource.dailyLogin.name, today): true,
      PrefsKeys.coinClaim(CoinSource.weeklyStreak.name, today): true,
    });

    await tester.pumpWidget(l10nTestApp(home: const DevTestPage()));
    await tester.pumpAndSettle();
    await _tapVisible(tester, find.text('快轉一天'));

    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getBool(PrefsKeys.coinClaim(CoinSource.dailyLogin.name, today)),
      isNull,
    );
    expect(
      prefs.getBool(PrefsKeys.coinClaim(CoinSource.weeklyStreak.name, today)),
      isNull,
    );
    final reward = await CoinService.claimDailyLogin(
      now: now,
      l10n: lookupAppLocalizations(const Locale('zh')),
    );
    expect(reward, isNotNull);
    expect(reward!.level, 3);
  });
}
