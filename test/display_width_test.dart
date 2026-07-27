// 兔咪名字的「顯示寬度」限長：全寬字算 2、其餘算 1。
// 這是為了讓「中文 6 字」與「英文 12 字元」用同一個上限，且混打也算得對。
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:habit_app/utils/input_formatters.dart';

void main() {
  group('displayWidth', () {
    test('中文全寬字算 2', () {
      expect(displayWidth('兔咪'), 4);
      expect(displayWidth('棉花糖'), 6);
      // 上限 12 = 中文 6 字，與遷移前的 maxLength 6 等價
      expect(displayWidth('棉花糖麻糬布'), kMascotNameMaxUnits);
    });

    test('拉丁字母算 1', () {
      expect(displayWidth('Tumi'), 4);
      expect(displayWidth('Marshmallow'), 11);
      expect(displayWidth('Snowball'), 8);
    });

    test('混打分別計算', () {
      expect(displayWidth('小雲Cloud'), 4 + 5);
      expect(displayWidth('Momo糖'), 4 + 2);
    });

    test('全寬標點與 emoji 算 2', () {
      expect(displayWidth('！'), 2); // 全寬驚嘆號
      expect(displayWidth('🐰'), 2);
    });

    test('英文名字池每個都在上限內', () {
      const pool = [
        'Tumi',
        'Chirpy',
        'Dango',
        'Mochi',
        'Marshmallow',
        'Snowball',
        'Adzuki',
        'Pudding',
        'Milktea',
        'Ricecake',
        'Chestnut',
        'Snowdrop',
      ];
      for (final n in pool) {
        expect(
          displayWidth(n) <= kMascotNameMaxUnits,
          isTrue,
          reason: '$n 超出 $kMascotNameMaxUnits 個半寬單位',
        );
      }
    });
  });

  group('clampToDisplayWidth', () {
    test('中文按字截斷', () {
      expect(clampToDisplayWidth('棉花糖麻糬布丁', 12), '棉花糖麻糬布');
      expect(clampToDisplayWidth('棉花糖', 12), '棉花糖');
    });

    test('英文按字元截斷', () {
      expect(clampToDisplayWidth('Marshmallowww', 12), 'Marshmalloww');
    });

    test('剩 1 單位時放不進全寬字，不會砍半', () {
      // 5 個全寬 = 10，剩 1 單位放不進第 6 個字
      expect(clampToDisplayWidth('棉花糖麻糬布', 11), '棉花糖麻糬');
    });

    test('emoji 不會被砍成半個', () {
      expect(clampToDisplayWidth('ab🐰', 3), 'ab');
      expect(clampToDisplayWidth('ab🐰', 4), 'ab🐰');
    });
  });

  group('DisplayWidthLimitingFormatter', () {
    const f = DisplayWidthLimitingFormatter(kMascotNameMaxUnits);

    TextEditingValue apply(String oldText, String newText) =>
        f.formatEditUpdate(
          TextEditingValue(text: oldText),
          TextEditingValue(
            text: newText,
            selection: TextSelection.collapsed(offset: newText.length),
          ),
        );

    test('沒超出就原樣放行', () {
      expect(apply('棉花', '棉花糖').text, '棉花糖');
      expect(apply('Marsh', 'Marshmallow').text, 'Marshmallow');
    });

    test('超出就截到上限，游標收到尾端', () {
      final r = apply('棉花糖麻糬布', '棉花糖麻糬布丁');
      expect(r.text, '棉花糖麻糬布');
      expect(r.selection.baseOffset, r.text.length);
    });

    test('英文超出也擋住（上限 12 字元，不是 11）', () {
      expect(apply('Marshmallow', 'Marshmallows').text, 'Marshmallows');
      expect(apply('Marshmallows', 'Marshmallowsss').text, 'Marshmallows');
    });

    test('混打依顯示寬度擋住', () {
      // 「小雲」4 + "Cloudy" 6 = 10，還能再加 2 個半寬
      expect(apply('小雲Cloud', '小雲Cloudy').text, '小雲Cloudy');
      // 再加就超過 12
      expect(apply('小雲Cloudyxx', '小雲Cloudyxxx').text, '小雲Cloudyxx');
    });
  });
}
