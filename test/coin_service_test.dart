import 'package:flutter_test/flutter_test.dart';
import 'package:habit_app/utils/coin_config.dart';
import 'package:habit_app/utils/coin_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    CoinService.notifier.value = 0;
  });

  final d0612 = DateTime(2026, 6, 12, 9);

  group('award / revoke', () {
    test('固定金額來源入帳 + notifier 同步', () async {
      final got = await CoinService.award(CoinSource.habitDone, now: d0612);
      expect(got, CoinConfig.habitDone);
      expect(await CoinService.balance(), CoinConfig.habitDone);
      expect(CoinService.notifier.value, CoinConfig.habitDone);
    });

    test('打卡來源可重複入帳（一天多個習慣）', () async {
      await CoinService.award(CoinSource.habitDone, now: d0612);
      await CoinService.award(CoinSource.habitDone, now: d0612);
      expect(await CoinService.balance(), CoinConfig.habitDone * 2);
    });

    test('每日一次型來源同日第二次回 0', () async {
      final first = await CoinService.award(CoinSource.waterGoal, now: d0612);
      final second = await CoinService.award(CoinSource.waterGoal, now: d0612);
      expect(first, CoinConfig.waterGoal);
      expect(second, 0);
      expect(await CoinService.balance(), CoinConfig.waterGoal);
    });

    test('每日一次型來源隔天可再領', () async {
      await CoinService.award(CoinSource.waterGoal, now: d0612);
      final next = await CoinService.award(
        CoinSource.waterGoal,
        now: d0612.add(const Duration(days: 1)),
      );
      expect(next, CoinConfig.waterGoal);
    });

    test('revoke 對稱扣回；餘額地板 0', () async {
      await CoinService.award(CoinSource.habitDone, now: d0612);
      await CoinService.revoke(CoinSource.habitDone, now: d0612);
      expect(await CoinService.balance(), 0);
      // 餘額 0 再 revoke 不會變負
      await CoinService.revoke(CoinSource.habitDone, now: d0612);
      expect(await CoinService.balance(), 0);
      expect(CoinService.notifier.value, 0);
    });

    test('帳本新到舊、有撤銷負項', () async {
      await CoinService.award(CoinSource.habitDone, now: d0612);
      await CoinService.revoke(
        CoinSource.habitDone,
        now: d0612.add(const Duration(minutes: 1)),
      );
      final entries = await CoinService.ledger();
      expect(entries.length, 2);
      expect(entries.first.amount, -CoinConfig.habitDone); // 最新在前
      expect(entries.last.amount, CoinConfig.habitDone);
    });

    test('帳本封頂不超過上限', () async {
      for (var i = 0; i < CoinConfig.ledgerMaxEntries + 5; i++) {
        await CoinService.award(CoinSource.habitDone, now: d0612);
      }
      final entries = await CoinService.ledger();
      expect(entries.length, CoinConfig.ledgerMaxEntries);
    });
  });

  group('claimDailyLogin 等級曲線', () {
    test('第一次領取 = Lv.1、基礎金額', () async {
      final r = await CoinService.claimDailyLogin(now: d0612);
      expect(r, isNotNull);
      expect(r!.level, 1);
      expect(r.amount, CoinConfig.loginBase);
      expect(r.graceUsed, isFalse);
    });

    test('同日第二次領回 null', () async {
      await CoinService.claimDailyLogin(now: d0612);
      expect(await CoinService.claimDailyLogin(now: d0612), isNull);
    });

    test('連續領取每日 +1 並在封頂停住', () async {
      LoginReward? r;
      for (var i = 0; i < CoinConfig.loginMaxLevel + 2; i++) {
        r = await CoinService.claimDailyLogin(
          now: d0612.add(Duration(days: i)),
        );
      }
      expect(r!.level, CoinConfig.loginMaxLevel);
      expect(r.amount, CoinConfig.loginRewardAt(CoinConfig.loginMaxLevel));
    });

    test('缺席 1 天（寬限內）等級保住', () async {
      await CoinService.claimDailyLogin(now: d0612); // Lv.1
      await CoinService.claimDailyLogin(
        now: d0612.add(const Duration(days: 1)),
      ); // Lv.2
      // 缺席 6/14，6/15 再領
      final r = await CoinService.claimDailyLogin(
        now: d0612.add(const Duration(days: 3)),
      );
      expect(r!.level, 2); // 等級不動
      expect(r.graceUsed, isTrue);
    });

    test('缺席超過寬限：降 2 級不歸零、最低 Lv.1', () async {
      // 先爬到封頂
      for (var i = 0; i < CoinConfig.loginMaxLevel; i++) {
        await CoinService.claimDailyLogin(now: d0612.add(Duration(days: i)));
      }
      // 缺席 3 天（> 寬限 1 天）
      final r = await CoinService.claimDailyLogin(
        now: d0612.add(Duration(days: CoinConfig.loginMaxLevel - 1 + 4)),
      );
      expect(r!.level, CoinConfig.loginMaxLevel - CoinConfig.loginLevelDrop);
      expect(r.graceUsed, isFalse);

      // 從 Lv.1 缺席很久也不會低於 Lv.1
      SharedPreferences.setMockInitialValues({});
      await CoinService.claimDailyLogin(now: d0612); // Lv.1
      final r2 = await CoinService.claimDailyLogin(
        now: d0612.add(const Duration(days: 30)),
      );
      expect(r2!.level, 1);
    });
  });
}
