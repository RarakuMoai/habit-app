import 'package:flutter_test/flutter_test.dart';
import 'package:habit_app/utils/units.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('UnitSystem', () {
    test('fromString 解析 imperial，其他一律 metric', () {
      expect(UnitSystem.fromString('imperial'), UnitSystem.imperial);
      expect(UnitSystem.fromString('metric'), UnitSystem.metric);
      expect(UnitSystem.fromString('garbage'), UnitSystem.metric);
      expect(UnitSystem.fromString(''), UnitSystem.metric);
      expect(UnitSystem.fromString(null), UnitSystem.metric);
    });

    test('load 讀 prefs 已存值', () async {
      SharedPreferences.setMockInitialValues({UnitSystem.prefsKey: 'imperial'});
      final prefs = await SharedPreferences.getInstance();
      expect(UnitSystem.load(prefs), UnitSystem.imperial);
    });

    test('load 遇壞值回退 metric', () async {
      SharedPreferences.setMockInitialValues({UnitSystem.prefsKey: 'bogus'});
      final prefs = await SharedPreferences.getInstance();
      expect(UnitSystem.load(prefs), UnitSystem.metric);
    });

    test('save 後 load 能讀回', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      await UnitSystem.save(prefs, UnitSystem.imperial);
      expect(UnitSystem.load(prefs), UnitSystem.imperial);
    });

    test('save / load 會同步 notifier（反應式廣播）', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      // notifier 是全域 static，先歸位避免受前面測試影響
      UnitSystem.notifier.value = UnitSystem.metric;

      var fired = 0;
      void listener() => fired++;
      UnitSystem.notifier.addListener(listener);
      addTearDown(() => UnitSystem.notifier.removeListener(listener));

      await UnitSystem.save(prefs, UnitSystem.imperial);
      expect(UnitSystem.notifier.value, UnitSystem.imperial);
      expect(fired, 1);

      // load 也要把 notifier 拉回 prefs 的值
      await UnitSystem.save(prefs, UnitSystem.metric);
      SharedPreferences.setMockInitialValues({UnitSystem.prefsKey: 'imperial'});
      final prefs2 = await SharedPreferences.getInstance();
      UnitSystem.load(prefs2);
      expect(UnitSystem.notifier.value, UnitSystem.imperial);
    });
  });

  group('UnitConvert', () {
    test('cmToFtIn 四捨五入到整數吋', () {
      expect(UnitConvert.cmToFtIn(173), (5, 8)); // 68.1 in → 68
      expect(UnitConvert.cmToFtIn(152.4), (5, 0)); // 剛好 60 in
      expect(UnitConvert.cmToFtIn(30.48), (1, 0)); // 剛好 12 in
      expect(UnitConvert.cmToFtIn(182.88), (6, 0));
    });

    test('inch 進位不會出現 12 吋', () {
      // 182.5 cm = 71.85 in → round 72 → 應為 6'0"，不是 5'12"
      expect(UnitConvert.cmToFtIn(182.5), (6, 0));
    });

    test('ftInToCm 與 cmToFtIn 互逆（整吋值）', () {
      expect(UnitConvert.ftInToCm(5, 8), closeTo(172.72, 0.001));
      final (ft, inches) = UnitConvert.cmToFtIn(UnitConvert.ftInToCm(5, 8));
      expect((ft, inches), (5, 8));
    });

    test('kg ↔ lb', () {
      expect(UnitConvert.kgToLb(70), closeTo(154.32, 0.01));
      expect(UnitConvert.lbToKg(154), closeTo(69.85, 0.01));
      expect(UnitConvert.lbToKg(UnitConvert.kgToLb(70)), closeTo(70, 1e-9));
    });

    test('ml ↔ fl oz', () {
      expect(UnitConvert.mlToFlOz(250), closeTo(8.45, 0.01));
      expect(UnitConvert.flOzToMl(8), closeTo(236.59, 0.01));
      expect(
        UnitConvert.flOzToMl(UnitConvert.mlToFlOz(500)),
        closeTo(500, 1e-9),
      );
    });
  });

  group('UnitFormat', () {
    test('height：metric 整數不帶小數，非整數留一位', () {
      expect(UnitFormat.height(173, UnitSystem.metric), '173 cm');
      expect(UnitFormat.height(162.5, UnitSystem.metric), '162.5 cm');
    });

    test('height：imperial 用 ft\'in" 形式', () {
      expect(UnitFormat.height(173, UnitSystem.imperial), '5\'8"');
      expect(UnitFormat.height(152.4, UnitSystem.imperial), '5\'0"');
    });

    test('weight：metric 整數/小數、imperial 取整 lb', () {
      expect(UnitFormat.weight(70, UnitSystem.metric), '70 kg');
      expect(UnitFormat.weight(70.5, UnitSystem.metric), '70.5 kg');
      expect(UnitFormat.weight(70, UnitSystem.imperial), '154 lb');
    });

    test('volume：metric 原值、imperial 取整 oz', () {
      expect(UnitFormat.volume(250, UnitSystem.metric), '250 ml');
      expect(UnitFormat.volume(250, UnitSystem.imperial), '8 oz');
      expect(UnitFormat.volume(2000, UnitSystem.metric), '2000 ml');
      expect(UnitFormat.volume(2000, UnitSystem.imperial), '68 oz');
    });

    test('單位字串 label', () {
      expect(UnitFormat.volumeLabel(UnitSystem.metric), 'ml');
      expect(UnitFormat.volumeLabel(UnitSystem.imperial), 'oz');
      expect(UnitFormat.weightLabel(UnitSystem.metric), 'kg');
      expect(UnitFormat.weightLabel(UnitSystem.imperial), 'lb');
      expect(UnitFormat.heightLabel(UnitSystem.metric), 'cm');
      expect(UnitFormat.heightLabel(UnitSystem.imperial), 'ft / in');
    });
  });

  group('UnitParse', () {
    test('heightCm：metric 直接收 cm，imperial 應回 null（走兩格輸入）', () {
      expect(UnitParse.heightCm('173', UnitSystem.metric), 173);
      expect(UnitParse.heightCm(' 173.5 ', UnitSystem.metric), 173.5);
      expect(UnitParse.heightCm('173', UnitSystem.imperial), isNull);
      expect(UnitParse.heightCm('abc', UnitSystem.metric), isNull);
      expect(UnitParse.heightCm('', UnitSystem.metric), isNull);
    });

    test('weightKg：imperial 輸入視為 lb 轉公斤', () {
      expect(UnitParse.weightKg('70', UnitSystem.metric), 70);
      expect(
        UnitParse.weightKg('154', UnitSystem.imperial),
        closeTo(69.85, 0.01),
      );
      expect(UnitParse.weightKg('x', UnitSystem.imperial), isNull);
    });

    test('volumeMl：imperial 輸入視為 fl oz 轉毫升', () {
      expect(UnitParse.volumeMl('250', UnitSystem.metric), 250);
      expect(
        UnitParse.volumeMl('8', UnitSystem.imperial),
        closeTo(236.59, 0.01),
      );
      expect(UnitParse.volumeMl('', UnitSystem.metric), isNull);
    });
  });
}
