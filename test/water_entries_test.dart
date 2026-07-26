import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:habit_app/utils/water_entries.dart';

// water_page 實際使用的單筆上限（_maxGoalMl * 2）
const int kMaxEntryMl = 12000;

void main() {
  group('WaterEntry.tryParse', () {
    test('完整 map：ml/kind/at 都讀進來', () {
      final e = WaterEntry.tryParse({
        'ml': 250,
        'kind': 'cup',
        'at': '2026-06-09T08:30:00.000',
      });
      expect(e, isNotNull);
      expect(e!.ml, 250);
      expect(e.kind, 'cup');
      expect(e.at, DateTime(2026, 6, 9, 8, 30));
    });

    test('未知 kind 一律當 custom', () {
      final e = WaterEntry.tryParse({'ml': 300, 'kind': 'bottle'});
      expect(e!.kind, 'custom');
    });

    test('ml 為小數時四捨五入', () {
      expect(WaterEntry.tryParse({'ml': 250.6, 'kind': 'cup'})!.ml, 251);
    });

    test('裸數字（最舊格式）視為 custom entry', () {
      final e = WaterEntry.tryParse(250);
      expect(e!.ml, 250);
      expect(e.kind, 'custom');
    });

    test('at 缺漏或格式壞掉時回退現在時間，不整筆丟棄', () {
      final before = DateTime.now();
      final e = WaterEntry.tryParse({'ml': 250, 'at': 'not-a-date'});
      final after = DateTime.now();
      expect(e, isNotNull);
      expect(e!.at.isBefore(before), isFalse);
      expect(e.at.isAfter(after), isFalse);
    });

    test('壞資料回 null：非 map、缺 ml、ml 非數字', () {
      expect(WaterEntry.tryParse('250'), isNull);
      expect(WaterEntry.tryParse(null), isNull);
      expect(WaterEntry.tryParse({'kind': 'cup'}), isNull);
      expect(WaterEntry.tryParse({'ml': 'lots'}), isNull);
      expect(WaterEntry.tryParse([250]), isNull);
    });
  });

  group('parseWaterEntries', () {
    test('null / 空字串回空 list', () {
      expect(parseWaterEntries(null, maxEntryMl: kMaxEntryMl), isEmpty);
      expect(parseWaterEntries('', maxEntryMl: kMaxEntryMl), isEmpty);
    });

    test('正常 JSON list 全數解析', () {
      final raw = jsonEncode([
        {'ml': 250, 'kind': 'cup', 'at': '2026-06-09T08:00:00.000'},
        {'ml': 500, 'kind': 'custom', 'at': '2026-06-09T12:00:00.000'},
      ]);
      final entries = parseWaterEntries(raw, maxEntryMl: kMaxEntryMl);
      expect(entries.length, 2);
      expect(entries[0].kind, 'cup');
      expect(entries[1].ml, 500);
    });

    test('壞 JSON / 非 list 回空 list 不丟例外', () {
      expect(parseWaterEntries('{{{', maxEntryMl: kMaxEntryMl), isEmpty);
      expect(parseWaterEntries('{"ml":250}', maxEntryMl: kMaxEntryMl), isEmpty);
      expect(parseWaterEntries('42', maxEntryMl: kMaxEntryMl), isEmpty);
    });

    test('混入壞 entry 時只丟壞的，好的留下', () {
      final raw = jsonEncode([
        {'ml': 250, 'kind': 'cup'},
        {'kind': 'cup'}, // 缺 ml
        'garbage',
        {'ml': 300},
      ]);
      final entries = parseWaterEntries(raw, maxEntryMl: kMaxEntryMl);
      expect(entries.map((e) => e.ml), [250, 300]);
    });

    test('ml ≤ 0 或超過上限的 entry 被過濾', () {
      final raw = jsonEncode([
        {'ml': 0, 'kind': 'cup'},
        {'ml': -100, 'kind': 'custom'},
        {'ml': kMaxEntryMl, 'kind': 'custom'}, // 剛好在上限：保留
        {'ml': kMaxEntryMl + 1, 'kind': 'custom'}, // 超過：丟棄
      ]);
      final entries = parseWaterEntries(raw, maxEntryMl: kMaxEntryMl);
      expect(entries.map((e) => e.ml), [kMaxEntryMl]);
    });

    test('裸數字 list（最舊格式）整串可解析', () {
      final entries = parseWaterEntries(
        '[250, 300.4]',
        maxEntryMl: kMaxEntryMl,
      );
      expect(entries.map((e) => e.ml), [250, 300]);
      expect(entries.every((e) => e.kind == 'custom'), isTrue);
    });

    test('encode → parse roundtrip 保留 ml/kind/at', () {
      final original = [
        WaterEntry.cup(250, at: DateTime(2026, 6, 9, 8)),
        WaterEntry.custom(600, at: DateTime(2026, 6, 9, 15, 30)),
      ];
      final parsed = parseWaterEntries(
        encodeWaterEntries(original),
        maxEntryMl: kMaxEntryMl,
      );
      expect(parsed.length, 2);
      for (var i = 0; i < original.length; i++) {
        expect(parsed[i].ml, original[i].ml);
        expect(parsed[i].kind, original[i].kind);
        expect(parsed[i].at, original[i].at);
      }
    });
  });

  group('legacyWaterEntries（舊鍵 migrate）', () {
    test('杯數展開成 cup entries、extra 變一筆 custom', () {
      final entries = legacyWaterEntries(cups: 3, extraMl: 400, cupMl: 250);
      expect(entries.length, 4);
      expect(
        entries.take(3).every((e) => e.kind == 'cup' && e.ml == 250),
        isTrue,
      );
      expect(entries.last.kind, 'custom');
      expect(entries.last.ml, 400);
    });

    test('extra = 0 時不產生 custom entry', () {
      final entries = legacyWaterEntries(cups: 2, extraMl: 0, cupMl: 300);
      expect(entries.length, 2);
      expect(entries.every((e) => e.kind == 'cup'), isTrue);
    });

    test('沒有舊資料時回空 list', () {
      expect(legacyWaterEntries(cups: 0, extraMl: 0, cupMl: 250), isEmpty);
    });

    test('只有 extra 沒有杯數', () {
      final entries = legacyWaterEntries(cups: 0, extraMl: 500, cupMl: 250);
      expect(entries.length, 1);
      expect(entries.single.kind, 'custom');
      expect(entries.single.ml, 500);
    });
  });
}
