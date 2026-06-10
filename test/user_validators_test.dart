import 'package:flutter_test/flutter_test.dart';
import 'package:habit_app/utils/units.dart';
import 'package:habit_app/utils/user_validators.dart';

void main() {
  group('height（公制字串）', () {
    test('空值與合法範圍通過', () {
      expect(UserValidators.height(''), isNull);
      expect(UserValidators.height('  '), isNull);
      expect(UserValidators.height('80'), isNull); // 下界
      expect(UserValidators.height('230'), isNull); // 上界
      expect(UserValidators.height('173.5'), isNull);
    });

    test('非數字與越界擋下', () {
      expect(UserValidators.height('abc'), '請輸入數字');
      expect(UserValidators.height('79.9'), contains('80–230'));
      expect(UserValidators.height('231'), contains('80–230'));
    });
  });

  group('weight / targetWeight（公制字串）', () {
    test('空值與合法範圍通過', () {
      expect(UserValidators.weight(''), isNull);
      expect(UserValidators.weight('10'), isNull);
      expect(UserValidators.weight('250'), isNull);
      expect(UserValidators.targetWeight('70.5'), isNull);
    });

    test('非數字與越界擋下', () {
      expect(UserValidators.weight('七十'), '請輸入數字');
      expect(UserValidators.weight('9.9'), contains('10–250'));
      expect(UserValidators.weight('250.1'), contains('10–250'));
      expect(UserValidators.targetWeight('9'), contains('10–250'));
      expect(UserValidators.targetWeight('300'), contains('10–250'));
    });
  });

  group('weightIn / targetWeightIn（unit-aware）', () {
    test('metric 模式等同公制驗證', () {
      expect(UserValidators.weightIn('70', UnitSystem.metric), isNull);
      expect(
        UserValidators.weightIn('9', UnitSystem.metric),
        contains('10–250'),
      );
    });

    test('imperial 模式用 lb 範圍（10–250 kg ≈ 22–551 lb）', () {
      expect(UserValidators.weightIn('154', UnitSystem.imperial), isNull);
      expect(UserValidators.weightIn('22', UnitSystem.imperial), isNull);
      expect(UserValidators.weightIn('551', UnitSystem.imperial), isNull);
      expect(
        UserValidators.weightIn('21', UnitSystem.imperial),
        contains('22–551'),
      );
      expect(
        UserValidators.weightIn('552', UnitSystem.imperial),
        contains('22–551'),
      );
      expect(UserValidators.weightIn('', UnitSystem.imperial), isNull);
      expect(UserValidators.weightIn('x', UnitSystem.imperial), '請輸入數字');
    });

    test('targetWeightIn 範圍與 weightIn 相同', () {
      expect(UserValidators.targetWeightIn('154', UnitSystem.imperial), isNull);
      expect(
        UserValidators.targetWeightIn('21', UnitSystem.imperial),
        contains('22–551'),
      );
      expect(
        UserValidators.targetWeightIn('9', UnitSystem.metric),
        contains('10–250'),
      );
    });
  });

  group('heightCm（數值版）', () {
    test('null 與合法範圍通過、越界擋下', () {
      expect(UserValidators.heightCm(null), isNull);
      expect(UserValidators.heightCm(80), isNull);
      expect(UserValidators.heightCm(230), isNull);
      expect(UserValidators.heightCm(79.9), contains('80–230'));
      expect(UserValidators.heightCm(230.1), contains('80–230'));
    });
  });

  group('bmiPair', () {
    test('輸入不全或不合法時不擋（留給單欄驗證）', () {
      expect(UserValidators.bmiPair('', '70'), isNull);
      expect(UserValidators.bmiPair('173', 'abc'), isNull);
      expect(UserValidators.bmiPair('0', '70'), isNull);
      expect(UserValidators.bmiPair('-170', '70'), isNull);
    });

    test('正常與極端但真實的 BMI 通過', () {
      expect(UserValidators.bmiPair('173', '70'), isNull); // BMI ≈ 23.4
      expect(UserValidators.bmiPair('170', '30'), isNull); // BMI ≈ 10.4 重度過瘦
      expect(UserValidators.bmiPair('170', '185'), isNull); // BMI ≈ 64 極端肥胖
    });

    test('明顯打錯字（身高體重對調）擋下', () {
      // 70cm / 173kg → BMI ≈ 353
      expect(UserValidators.bmiPair('70', '173'), isNotNull);
      // BMI < 10：173cm / 25kg ≈ 8.4
      expect(UserValidators.bmiPair('173', '25'), isNotNull);
    });
  });

  group('birthday', () {
    test('null 與正常生日通過', () {
      expect(UserValidators.birthday(null), isNull);
      expect(UserValidators.birthday(DateTime(1990, 6, 15)), isNull);
      expect(
        UserValidators.birthday(
          DateTime.now().subtract(const Duration(days: 1)),
        ),
        isNull,
      );
    });

    test('未來日期擋下', () {
      expect(
        UserValidators.birthday(
          DateTime.now().add(const Duration(days: 1)),
        ),
        '生日不能是未來日期',
      );
    });

    test('超過 130 歲擋下，剛好 130 歲通過', () {
      final now = DateTime.now();
      final exactly130 = DateTime(now.year - 130, now.month, now.day);
      expect(UserValidators.birthday(exactly130), isNull);
      expect(
        UserValidators.birthday(
          exactly130.subtract(const Duration(days: 1)),
        ),
        contains('130'),
      );
    });
  });
}
