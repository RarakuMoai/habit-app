// 測試期望值常落在月/日 = 1，撞 redundant default lint，整檔豁免
// ignore_for_file: avoid_redundant_argument_values
import 'package:flutter_test/flutter_test.dart';
import 'package:habit_app/utils/lenient_date.dart';

void main() {
  group('parseLenientDate 接受的格式', () {
    test('短橫線（不補零）', () {
      expect(parseLenientDate('1111-1-1'), DateTime(1111, 1, 1));
    });
    test('短橫線（補零）', () {
      expect(parseLenientDate('1111-01-01'), DateTime(1111, 1, 1));
    });
    test('八碼純數字', () {
      expect(parseLenientDate('11110101'), DateTime(1111, 1, 1));
    });
    test('斜線', () {
      expect(parseLenientDate('2000/2/29'), DateTime(2000, 2, 29));
    });
    test('點分隔', () {
      expect(parseLenientDate('1995.4.12'), DateTime(1995, 4, 12));
    });
    test('中文年月日', () {
      expect(parseLenientDate('2000年1月1日'), DateTime(2000, 1, 1));
    });
    test('夾雜空白', () {
      expect(parseLenientDate(' 2000 - 1 - 1 '), DateTime(2000, 1, 1));
    });
  });

  group('parseLenientDate 拒絕的輸入', () {
    test('非閏年 2/29', () {
      expect(parseLenientDate('2001-2-29'), isNull);
    });
    test('月份超界', () {
      expect(parseLenientDate('2000-13-1'), isNull);
    });
    test('月份為 0', () {
      expect(parseLenientDate('2000-0-1'), isNull);
    });
    test('日超界', () {
      expect(parseLenientDate('2000-4-31'), isNull);
    });
    test('純文字', () {
      expect(parseLenientDate('abc'), isNull);
    });
    test('空字串', () {
      expect(parseLenientDate(''), isNull);
    });
    test('只有年月（不猜成 2000-1-2）', () {
      expect(parseLenientDate('2000-12'), isNull);
    });
    test('七碼數字（歧義不猜）', () {
      expect(parseLenientDate('2026113'), isNull);
    });
  });
}
