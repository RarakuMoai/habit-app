// Water entry model + parsing / legacy-migration logic for water_page.
//
// 從 water_page.dart 抽出成獨立檔案，讓純 Dart 單元測試能覆蓋
// （原本是 StatefulWidget 的私有實作，測不到）。行為與抽出前一致。

import 'dart:convert';

class WaterEntry {
  final int ml;
  final String kind;
  final DateTime at;

  const WaterEntry._({required this.ml, required this.kind, required this.at});

  factory WaterEntry.cup(int ml, {DateTime? at}) {
    return WaterEntry._(
      ml: ml,
      kind: 'cup',
      at: at ?? DateTime.now(),
    ); // units-ok
  }

  factory WaterEntry.custom(int ml, {DateTime? at}) {
    return WaterEntry._(
      ml: ml, // units-ok
      kind: 'custom',
      at: at ?? DateTime.now(),
    );
  }

  static WaterEntry? tryParse(Object? raw) {
    if (raw is num) {
      return WaterEntry.custom(raw.round());
    }
    if (raw is! Map) return null;
    final ml = raw['ml']; // units-ok
    final kind = raw['kind'];
    final at = raw['at'];
    if (ml is! num) return null;
    return WaterEntry._(
      ml: ml.round(),
      kind: kind == 'cup' ? 'cup' : 'custom',
      at: at is String
          ? DateTime.tryParse(at) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  Map<String, Object> toJson() => {
    'ml': ml, // units-ok
    'kind': kind,
    'at': at.toIso8601String(),
  }; // units-ok
}

/// 解析 prefs 裡存的 entries JSON；壞資料（非 JSON、非 list、缺 ml、
/// ml ≤ 0 或超過 [maxEntryMl]）一律丟棄，整串壞掉就回空 list。
List<WaterEntry> parseWaterEntries(String? raw, {required int maxEntryMl}) {
  if (raw == null || raw.isEmpty) return [];
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! List) return [];
    return decoded
        .map(WaterEntry.tryParse)
        .whereType<WaterEntry>()
        .where((entry) => entry.ml > 0 && entry.ml <= maxEntryMl)
        .toList();
  } catch (_) {
    return [];
  }
}

/// 把 legacy 的「杯數 + 額外量」舊鍵資料轉成 entries。
List<WaterEntry> legacyWaterEntries({
  required int cups,
  required int extraMl,
  required int cupMl,
}) {
  return [
    for (var i = 0; i < cups; i++) WaterEntry.cup(cupMl),
    if (extraMl > 0) WaterEntry.custom(extraMl),
  ];
}

/// entries → prefs 字串（與 [parseWaterEntries] 互為 roundtrip）。
String encodeWaterEntries(List<WaterEntry> entries) =>
    jsonEncode(entries.map((entry) => entry.toJson()).toList());
