// 桌遊計時器設定與常用玩家名單的持久化出入口。
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../../utils/prefs_keys.dart';
import 'table_timer_models.dart';

abstract final class TableStore {
  static TableTimerConfig loadConfig(SharedPreferences prefs) =>
      TableTimerConfig.decode(prefs.getString(PrefsKeys.gameTableConfig));

  static Future<void> saveConfig(
    SharedPreferences prefs,
    TableTimerConfig config,
  ) => prefs.setString(PrefsKeys.gameTableConfig, config.encode());

  /// 常用玩家：純名字清單（去重、保序）。
  static List<String> loadRoster(SharedPreferences prefs) {
    final raw = prefs.getString(PrefsKeys.gameTableRoster);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final list = jsonDecode(raw);
      if (list is! List) return const [];
      final seen = <String>{};
      return [
        for (final e in list)
          if (e is String && e.trim().isNotEmpty && seen.add(e.trim()))
            e.trim(),
      ];
    } catch (_) {
      return const [];
    }
  }

  static Future<void> saveRoster(SharedPreferences prefs, List<String> names) =>
      prefs.setString(PrefsKeys.gameTableRoster, jsonEncode(names));

  // ── 常用組合 ─────────────────────────────────────────────

  static List<TablePreset> loadPresets(SharedPreferences prefs) =>
      TablePreset.decodeList(prefs.getString(PrefsKeys.gameTablePresets));

  static Future<void> savePresets(
    SharedPreferences prefs,
    List<TablePreset> presets,
  ) => prefs.setString(
    PrefsKeys.gameTablePresets,
    TablePreset.encodeList(presets),
  );
}
