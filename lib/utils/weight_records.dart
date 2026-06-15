import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'prefs_keys.dart';

const String kWeightHabitName = '體重紀錄';
const List<String> kWeightHabitAliases = [kWeightHabitName, '每日量體重'];

bool isWeightHabitName(String? name) => kWeightHabitAliases.contains(name);

String weightRecordDate(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

String weightRecordTime(DateTime d) =>
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

List<Map<String, dynamic>> parseWeightRecords(String? raw) {
  if (raw == null || raw.trim().isEmpty) return <Map<String, dynamic>>[];
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! List) return <Map<String, dynamic>>[];
    return decoded
        .whereType<Map<String, dynamic>>()
        .map(Map<String, dynamic>.from)
        .where((e) => e['date'] is String && e['weight'] is num)
        .toList();
  } catch (_) {
    return <Map<String, dynamic>>[];
  }
}

bool hasWeightRecordForDate(List<Map<String, dynamic>> records, String date) =>
    records.any((r) => r['date'] == date);

Future<bool> hasSavedWeightRecordForDate(
  SharedPreferences prefs,
  String date,
) async {
  final records = parseWeightRecords(prefs.getString(PrefsKeys.weightRecords));
  return hasWeightRecordForDate(records, date);
}

Future<void> upsertSavedWeightRecord(
  SharedPreferences prefs, {
  required double weightKg,
  DateTime? at,
}) async {
  final ts = at ?? DateTime.now();
  final records = parseWeightRecords(prefs.getString(PrefsKeys.weightRecords));
  final date = weightRecordDate(ts);
  records
    ..removeWhere((r) => r['date'] == date)
    ..add({'date': date, 'time': weightRecordTime(ts), 'weight': weightKg})
    ..sort((a, b) => (b['date'] as String).compareTo(a['date'] as String));
  await prefs.setString(PrefsKeys.weightRecords, jsonEncode(records));
}

Future<void> ensureWeightHabit(SharedPreferences prefs) async {
  final habits = _loadHabits(prefs);
  if (habits.any((h) => isWeightHabitName(h['name'] as String?))) return;
  habits.add({'name': kWeightHabitName, 'done': false, 'frequency': 'daily'});
  await prefs.setString(PrefsKeys.habits, jsonEncode(habits));
}

Future<bool> syncWeightHabitForDate(
  SharedPreferences prefs, {
  DateTime? date,
}) async {
  final targetDate = weightRecordDate(date ?? DateTime.now());
  final records = parseWeightRecords(prefs.getString(PrefsKeys.weightRecords));
  final done = hasWeightRecordForDate(records, targetDate);
  final habits = _loadHabits(prefs);
  final idx = habits.indexWhere((h) {
    final isDaily = (h['frequency'] ?? 'daily') != 'weekly';
    return isDaily && isWeightHabitName(h['name'] as String?);
  });
  if (idx == -1 || habits[idx]['done'] == done) return false;
  habits[idx]['done'] = done;
  await prefs.setString(PrefsKeys.habits, jsonEncode(habits));
  return true;
}

List<Map<String, dynamic>> _loadHabits(SharedPreferences prefs) {
  final raw = prefs.getString(PrefsKeys.habits);
  if (raw == null || raw.trim().isEmpty) return <Map<String, dynamic>>[];
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! List) return <Map<String, dynamic>>[];
    return decoded
        .whereType<Map<String, dynamic>>()
        .map(Map<String, dynamic>.from)
        .toList();
  } catch (_) {
    return <Map<String, dynamic>>[];
  }
}
