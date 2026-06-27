import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:habit_app/utils/input_formatters.dart';

/// 模擬一次鍵盤輸入：把 [oldText] 變成 [newText] 後丟給 formatter，回傳結果文字。
String _apply(TextInputFormatter f, String oldText, String newText) {
  return f
      .formatEditUpdate(
        TextEditingValue(
          text: oldText,
          selection: TextSelection.collapsed(offset: oldText.length),
        ),
        TextEditingValue(
          text: newText,
          selection: TextSelection.collapsed(offset: newText.length),
        ),
      )
      .text;
}

void main() {
  group('autoDecimalForRange', () {
    test('體脂：超出 0–75 但 ÷10 落回範圍 → 補小數', () {
      expect(autoDecimalForRange('365', 75), '36.5'); // 使用者範例
      expect(autoDecimalForRange('205', 75), '20.5');
      expect(autoDecimalForRange('80', 75), '8.0'); // 兩位也補
      expect(autoDecimalForRange('76', 75), '7.6');
    });

    test('體脂：本來就合法的整數不動', () {
      expect(autoDecimalForRange('36', 75), '36');
      expect(autoDecimalForRange('75', 75), '75'); // 上界
      expect(autoDecimalForRange('8', 75), '8');
      expect(autoDecimalForRange('0', 75), '0');
    });

    test('公制體重：705 → 70.5、範圍內不動', () {
      expect(autoDecimalForRange('705', 250), '70.5');
      expect(autoDecimalForRange('999', 250), '99.9');
      expect(autoDecimalForRange('70', 250), '70');
      expect(autoDecimalForRange('250', 250), '250'); // 上界
      expect(autoDecimalForRange('100', 250), '100');
    });

    test('已含小數點 / 空字串 → 原樣回傳', () {
      expect(autoDecimalForRange('36.5', 75), '36.5');
      expect(autoDecimalForRange('70.', 250), '70.');
      expect(autoDecimalForRange('', 75), '');
    });

    test('÷10 後仍超出範圍 → 不亂補（維持原值讓驗證擋下）', () {
      // 7600 / 10 = 760 仍 > 75（此處不會發生 4 位，但確保邏輯安全）
      expect(autoDecimalForRange('7600', 75), '7600');
    });
  });

  group('bodyMetricFormatter', () {
    test('身高：打第 4 位數時自動補小數（1708 → 170.8）', () {
      final f = bodyMetricFormatter(230);
      expect(_apply(f, '170', '1708'), '170.8');
      expect(_apply(f, '165', '1655'), '165.5');
    });

    test('體重：705 → 70.5、1505 → 150.5', () {
      final f = bodyMetricFormatter(250);
      expect(_apply(f, '70', '705'), '70.5');
      expect(_apply(f, '150', '1505'), '150.5');
    });

    test('合法整數放行不動', () {
      final f = bodyMetricFormatter(230);
      expect(_apply(f, '17', '170'), '170');
      expect(_apply(f, '23', '230'), '230'); // 上界
    });

    test('已補小數後不准再多打一位小數', () {
      final f = bodyMetricFormatter(230);
      expect(_apply(f, '170.8', '170.85'), '170.8');
    });

    test('補不回範圍的 4 位純整數 → 擋下維持原值', () {
      final f = bodyMetricFormatter(250);
      // 2509 / 10 = 250.9 仍 > 250 → 不補、4 位整數擋下
      expect(_apply(f, '250', '2509'), '250');
    });
  });
}
