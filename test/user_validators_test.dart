import 'dart:ui' show Locale;

import 'package:flutter_test/flutter_test.dart';
import 'package:habit_app/l10n/app_localizations.dart';
import 'package:habit_app/utils/units.dart';
import 'package:habit_app/utils/user_validators.dart';

void main() {
  // 驗證器的錯誤訊息走 i18n；測試用繁中（模板語言）驗證文案。
  final l10n = lookupAppLocalizations(const Locale('zh'));

  group('height（公制字串）', () {
    test('空值與合法範圍通過', () {
      expect(UserValidators.height(l10n, ''), isNull);
      expect(UserValidators.height(l10n, '  '), isNull);
      expect(UserValidators.height(l10n, '80'), isNull); // 下界
      expect(UserValidators.height(l10n, '230'), isNull); // 上界
      expect(UserValidators.height(l10n, '173.5'), isNull);
    });

    test('非數字與越界擋下', () {
      expect(UserValidators.height(l10n, 'abc'), '請輸入數字');
      expect(UserValidators.height(l10n, '79.9'), contains('80–230'));
      expect(UserValidators.height(l10n, '231'), contains('80–230'));
    });
  });

  group('weight / targetWeight（公制字串）', () {
    test('空值與合法範圍通過', () {
      expect(UserValidators.weight(l10n, ''), isNull);
      expect(UserValidators.weight(l10n, '10'), isNull);
      expect(UserValidators.weight(l10n, '250'), isNull);
      expect(UserValidators.targetWeight(l10n, '70.5'), isNull);
    });

    test('非數字與越界擋下', () {
      expect(UserValidators.weight(l10n, '七十'), '請輸入數字');
      expect(UserValidators.weight(l10n, '9.9'), contains('10–250'));
      expect(UserValidators.weight(l10n, '250.1'), contains('10–250'));
      expect(UserValidators.targetWeight(l10n, '9'), contains('10–250'));
      expect(UserValidators.targetWeight(l10n, '300'), contains('10–250'));
    });
  });

  group('weightIn / targetWeightIn（unit-aware）', () {
    test('metric 模式等同公制驗證', () {
      expect(UserValidators.weightIn(l10n, '70', UnitSystem.metric), isNull);
      expect(
        UserValidators.weightIn(l10n, '9', UnitSystem.metric),
        contains('10–250'),
      );
    });

    test('imperial 模式用 lb 範圍（10–250 kg ≈ 22–551 lb）', () {
      expect(UserValidators.weightIn(l10n, '154', UnitSystem.imperial), isNull);
      expect(UserValidators.weightIn(l10n, '22', UnitSystem.imperial), isNull);
      expect(UserValidators.weightIn(l10n, '551', UnitSystem.imperial), isNull);
      expect(
        UserValidators.weightIn(l10n, '21', UnitSystem.imperial),
        contains('22–551'),
      );
      expect(
        UserValidators.weightIn(l10n, '552', UnitSystem.imperial),
        contains('22–551'),
      );
      expect(UserValidators.weightIn(l10n, '', UnitSystem.imperial), isNull);
      expect(UserValidators.weightIn(l10n, 'x', UnitSystem.imperial), '請輸入數字');
    });

    test('targetWeightIn 範圍與 weightIn 相同', () {
      expect(
        UserValidators.targetWeightIn(l10n, '154', UnitSystem.imperial),
        isNull,
      );
      expect(
        UserValidators.targetWeightIn(l10n, '21', UnitSystem.imperial),
        contains('22–551'),
      );
      expect(
        UserValidators.targetWeightIn(l10n, '9', UnitSystem.metric),
        contains('10–250'),
      );
    });
  });

  group('heightCm（數值版）', () {
    test('null 與合法範圍通過、越界擋下', () {
      expect(UserValidators.heightCm(l10n, null), isNull);
      expect(UserValidators.heightCm(l10n, 80), isNull);
      expect(UserValidators.heightCm(l10n, 230), isNull);
      expect(UserValidators.heightCm(l10n, 79.9), contains('80–230'));
      expect(UserValidators.heightCm(l10n, 230.1), contains('80–230'));
    });
  });

  group('bmiPair', () {
    test('輸入不全或不合法時不擋（留給單欄驗證）', () {
      expect(UserValidators.bmiPair(l10n, '', '70'), isNull);
      expect(UserValidators.bmiPair(l10n, '173', 'abc'), isNull);
      expect(UserValidators.bmiPair(l10n, '0', '70'), isNull);
      expect(UserValidators.bmiPair(l10n, '-170', '70'), isNull);
    });

    test('正常與極端但真實的 BMI 通過', () {
      expect(UserValidators.bmiPair(l10n, '173', '70'), isNull); // BMI ≈ 23.4
      expect(
        UserValidators.bmiPair(l10n, '170', '30'),
        isNull,
      ); // BMI ≈ 10.4 重度過瘦
      expect(
        UserValidators.bmiPair(l10n, '170', '185'),
        isNull,
      ); // BMI ≈ 64 極端肥胖
    });

    test('明顯打錯字（身高體重對調）擋下', () {
      // 70cm / 173kg → BMI ≈ 353
      expect(UserValidators.bmiPair(l10n, '70', '173'), isNotNull);
      // BMI < 10：173cm / 25kg ≈ 8.4
      expect(UserValidators.bmiPair(l10n, '173', '25'), isNotNull);
    });
  });

  group('birthday', () {
    test('null 與正常生日通過', () {
      expect(UserValidators.birthday(l10n, null), isNull);
      expect(UserValidators.birthday(l10n, DateTime(1990, 6, 15)), isNull);
      expect(
        UserValidators.birthday(
          l10n,
          DateTime.now().subtract(const Duration(days: 1)),
        ),
        isNull,
      );
    });

    test('未來日期擋下', () {
      expect(
        UserValidators.birthday(
          l10n,
          DateTime.now().add(const Duration(days: 1)),
        ),
        '生日不能是未來日期',
      );
    });

    test('超過 130 歲擋下，剛好 130 歲通過', () {
      final now = DateTime.now();
      final exactly130 = DateTime(now.year - 130, now.month, now.day);
      expect(UserValidators.birthday(l10n, exactly130), isNull);
      expect(
        UserValidators.birthday(
          l10n,
          exactly130.subtract(const Duration(days: 1)),
        ),
        contains('130'),
      );
    });
  });

  group('HealthAdvice.targetWeightSuggestion', () {
    test('公制：170cm 給 53–69 kg、建議 64', () {
      final s = HealthAdvice.targetWeightSuggestion(
        heightCm: 170,
        weightKg: 65,
        system: UnitSystem.metric,
      );
      expect(s, isNotNull);
      expect(s!.low, 53);
      expect(s.high, 69);
      expect(s.suggest, 64);
      expect(s.unit, 'kg'); // units-ok
    });

    test('身高缺漏或超出範圍 → null', () {
      expect(
        HealthAdvice.targetWeightSuggestion(
          heightCm: null,
          weightKg: 60,
          system: UnitSystem.metric,
        ),
        isNull,
      );
      expect(
        HealthAdvice.targetWeightSuggestion(
          heightCm: 79,
          weightKg: 60,
          system: UnitSystem.metric,
        ),
        isNull,
      );
      expect(
        HealthAdvice.targetWeightSuggestion(
          heightCm: 231,
          weightKg: 60,
          system: UnitSystem.metric,
        ),
        isNull,
      );
    });

    test('體重合理但 BMI 比例明顯不合理 → null（不給誤導建議）', () {
      // 170cm / 200kg → BMI 69.2 > 65
      expect(
        HealthAdvice.targetWeightSuggestion(
          heightCm: 170,
          weightKg: 200,
          system: UnitSystem.metric,
        ),
        isNull,
      );
      // 170cm / 25kg → BMI 8.7 < 10
      expect(
        HealthAdvice.targetWeightSuggestion(
          heightCm: 170,
          weightKg: 25,
          system: UnitSystem.metric,
        ),
        isNull,
      );
    });

    test('體重缺漏或本身超出範圍 → 不做比例檢查，照給建議', () {
      expect(
        HealthAdvice.targetWeightSuggestion(
          heightCm: 170,
          weightKg: null,
          system: UnitSystem.metric,
        ),
        isNotNull,
      );
      // 300kg 超出 weightMaxKg，交給欄位驗證提示，建議仍顯示
      expect(
        HealthAdvice.targetWeightSuggestion(
          heightCm: 170,
          weightKg: 300,
          system: UnitSystem.metric,
        ),
        isNotNull,
      );
    });

    test('英制：數值轉 lb、單位字串為 lb', () {
      final s = HealthAdvice.targetWeightSuggestion(
        heightCm: 170,
        weightKg: 65,
        system: UnitSystem.imperial,
      );
      expect(s, isNotNull);
      expect(s!.unit, 'lb'); // units-ok
      expect(s.suggest, UnitConvert.kgToLb(22 * 1.7 * 1.7).round());
    });
  });
}
