import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:habit_app/pages/family/family_models.dart';
import 'package:habit_app/pages/family/family_store.dart';
import 'package:habit_app/pages/family/reward_tab.dart';
import 'package:habit_app/utils/backup_archive.dart';
import 'package:habit_app/utils/prefs_keys.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'l10n_test_app.dart';
import 'shared_preferences_delay_test_helper.dart';

List<dynamic> _entries(BackupArchive archive, String key) =>
    jsonDecode(archive.values[key] as String) as List;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'backup waits for the family ledger as well as the points total',
    () async {
      final child = ChildData(id: 'child-1', name: '小兔', points: 10);
      SharedPreferences.setMockInitialValues({
        PrefsKeys.children: jsonEncode([child.toJson()]),
      });
      final prefs = await SharedPreferences.getInstance();
      final store = installDelayFirstWriteStore(
        'flutter.${PrefsKeys.pointRecords}',
      );
      addTearDown(store.restore);

      final updating = applyPointsBatch(
        prefs: prefs,
        child: child,
        entries: [(delta: 5, reason: '整理房間'), (delta: 10, reason: '寫作業')],
      );
      for (var i = 0; i < 100 && !store.didDelay; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(store.didDelay, isTrue);
      expect(child.points, 25);

      var captured = false;
      final backup = BackupArchive.create(prefs).then((archive) {
        captured = true;
        return archive;
      });
      await Future<void>.delayed(Duration.zero);
      expect(captured, isFalse);

      store.release();
      expect(await updating, 25);
      final archive = await backup;
      expect(_entries(archive, PrefsKeys.children).single['points'], 25);
      final records = _entries(archive, PrefsKeys.pointRecords);
      expect(records.map((record) => record['total']), [25, 15]);
    },
  );

  testWidgets(
    'redeem dialog does not block backup, but confirmed redemption waits for its voucher',
    (tester) async {
      final child = ChildData(id: 'child-1', name: '小兔', points: 100);
      final reward = RewardItem(
        id: 'reward-1',
        name: '去公園',
        pointsCost: 20,
        childIds: [child.id],
      );
      SharedPreferences.setMockInitialValues({
        PrefsKeys.children: jsonEncode([child.toJson()]),
        PrefsKeys.rewardItems: jsonEncode([reward.toJson()]),
      });
      final prefs = await SharedPreferences.getInstance();
      var pointsChanged = 0;
      await tester.pumpWidget(
        l10nTestApp(
          home: Scaffold(
            body: RewardTab(
              child: child,
              onPointsChanged: () => pointsChanged++,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('兌換'));
      await tester.pumpAndSettle();
      expect(find.text('確認兌換'), findsOneWidget);

      BackupArchive? beforeConfirm;
      unawaited(
        BackupArchive.create(prefs).then((value) => beforeConfirm = value),
      );
      await tester.pump();
      expect(beforeConfirm, isNotNull);
      expect(
        _entries(beforeConfirm!, PrefsKeys.children).single['points'],
        100,
      );

      final store = installDelayFirstWriteStore(
        'flutter.${PrefsKeys.voucherLogs}',
      );
      addTearDown(store.restore);
      await tester.tap(find.text('確認兌換'));
      await tester.pumpAndSettle();
      expect(store.didDelay, isTrue);
      expect(child.points, 80);
      expect(pointsChanged, 0);

      BackupArchive? afterConfirm;
      unawaited(
        BackupArchive.create(prefs).then((value) => afterConfirm = value),
      );
      await tester.pump();
      expect(afterConfirm, isNull);

      store.release();
      await tester.pumpAndSettle();
      expect(afterConfirm, isNotNull);
      expect(pointsChanged, 1);
      expect(_entries(afterConfirm!, PrefsKeys.children).single['points'], 80);
      expect(
        _entries(afterConfirm!, PrefsKeys.pointRecords).single['delta'],
        -20,
      );
      expect(
        _entries(afterConfirm!, PrefsKeys.voucherLogs).single['reward_id'],
        reward.id,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
