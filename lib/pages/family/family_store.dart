// 育兒模式共用儲存層：SharedPreferences 讀寫、日期/ID 工具、積分異動
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../utils/logical_date.dart';
import '../../utils/prefs_keys.dart';
import 'family_models.dart';

class PointRecordContext {
  final String? id;
  final String? kind;
  final String? sourceId;
  final String? reversesRecordId;

  const PointRecordContext({
    this.id,
    this.kind,
    this.sourceId,
    this.reversesRecordId,
  });
}

// ── 家庭模式的「今天」 ──
//
// 家庭模式**跟隨設定頁的換日時間**（`LogicalDate`），與習慣／喝水／體重同一條線。
//
// 為什麼：**登記的人是大人，不是小孩。** 小孩的家事不會在凌晨做，但大人很可能
// 忙到過午夜才想起要幫小孩補登。固定午夜換日的話，00:30 按下去會算成隔天——
// 習慣卡重置、當天的紀錄補不進去。換日線（預設 4:00）正是為這個族群存在的。
//
// ⚠️ 這三個函式必須**成套**使用同一個換日時間，不能只改其中一個：
// 積分紀錄的日期是 `nowStr()` 寫的，查詢走
// `record.time.split(' ').first == todayStr()` 比對日期前綴。兩邊用不同基準的話，
// 凌晨記錄後會查不到自己剛寫進去的那筆（卡片顯示「今天還沒有紀錄」，分數卻已經加了）。
//
// 時間部分刻意維持**真實時鐘**：00:30 記的就顯示 00:30，只是歸屬到前一個邏輯日。
// 這與首頁習慣的語意一致。
//
// 換日時間讀 `LogicalDate.notifier`（全 app 廣播，由 `LogicalDayCoordinator`
// 在啟動時與設定頁存檔時同步）。參數只給測試注入用。

int _dayStart(int? override) => override ?? LogicalDate.notifier.value;

// 今日日期字串（yyyy-MM-dd），依換日設定。
String todayStr({DateTime? now, int? dayStartHour}) =>
    LogicalDate.stringFor(now ?? DateTime.now(), _dayStart(dayStartHour));

// 本週一到週日的日期字串集合（以邏輯日的「今天」為基準推算週一）。
Set<String> currentWeekDateSet({DateTime? now, int? dayStartHour}) {
  final today = LogicalDate.dayOf(
    now ?? DateTime.now(),
    _dayStart(dayStartHour),
  );
  final monday = today.subtract(Duration(days: today.weekday - 1));
  return List.generate(7, (i) {
    final d = monday.add(Duration(days: i));
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }).toSet();
}

// 計算每週習慣本週已完成次數
int weeklyCount(ChildHabit habit) {
  final weekSet = currentWeekDateSet();
  return habit.weeklyDates.where(weekSet.contains).length;
}

// 產生唯一 ID（毫秒時間戳 + 隨機後綴，避免同毫秒碰撞）
String genId() =>
    '${DateTime.now().millisecondsSinceEpoch}_${Object().hashCode}';

// 格式化為 `yyyy-MM-dd HH:mm`：日期是邏輯日，時間是真實時鐘。
String nowStr({DateTime? now, int? dayStartHour}) {
  final at = now ?? DateTime.now();
  final date = LogicalDate.stringFor(at, _dayStart(dayStartHour));
  final time =
      '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';
  return '$date $time';
}

// ── 共用：讀寫各類資料的輔助方法 ──

Future<List<ChildHabit>> loadHabits(SharedPreferences prefs) async {
  final raw = prefs.getString(PrefsKeys.childHabits);
  if (raw == null) return [];
  return (jsonDecode(raw) as List)
      .map((e) => ChildHabit.fromJson(e as Map<String, dynamic>))
      .toList();
}

Future<void> saveHabits(
  SharedPreferences prefs,
  List<ChildHabit> habits,
) async {
  await prefs.setString(
    PrefsKeys.childHabits,
    jsonEncode(habits.map((h) => h.toJson()).toList()),
  );
}

// 新增小孩時自動帶入的預設習慣（3 個最基本，讓使用者有起點，可再自行調整）
List<ChildHabit> defaultHabitsForChild(String childId) => [
  ChildHabit(id: genId(), childId: childId, name: '刷牙', points: 10),
  ChildHabit(id: genId(), childId: childId, name: '寫作業', points: 30),
  ChildHabit(id: genId(), childId: childId, name: '整理房間', points: 20),
];

Future<List<DeductionItem>> loadDeductions(SharedPreferences prefs) async {
  final raw = prefs.getString(PrefsKeys.deductionItems);
  if (raw == null) return [];
  return (jsonDecode(raw) as List)
      .map((e) => DeductionItem.fromJson(e as Map<String, dynamic>))
      .toList();
}

Future<void> saveDeductions(
  SharedPreferences prefs,
  List<DeductionItem> items,
) async {
  await prefs.setString(
    PrefsKeys.deductionItems,
    jsonEncode(items.map((d) => d.toJson()).toList()),
  );
}

Future<List<RewardItem>> loadRewards(SharedPreferences prefs) async {
  final raw = prefs.getString(PrefsKeys.rewardItems);
  if (raw == null) return [];
  return (jsonDecode(raw) as List)
      .map((e) => RewardItem.fromJson(e as Map<String, dynamic>))
      .toList();
}

Future<void> saveRewards(
  SharedPreferences prefs,
  List<RewardItem> rewards,
) async {
  await prefs.setString(
    PrefsKeys.rewardItems,
    jsonEncode(rewards.map((r) => r.toJson()).toList()),
  );
}

Future<List<VoucherLog>> loadVouchers(SharedPreferences prefs) async {
  final raw =
      prefs.getString(PrefsKeys.voucherLogs) ??
      prefs.getString(PrefsKeys.legacyRedemptionLogs);
  if (raw == null) return [];
  return (jsonDecode(raw) as List)
      .map((e) => VoucherLog.fromJson(e as Map<String, dynamic>))
      .toList();
}

Future<void> saveVouchers(
  SharedPreferences prefs,
  List<VoucherLog> logs,
) async {
  await prefs.setString(
    PrefsKeys.voucherLogs,
    jsonEncode(logs.map((l) => l.toJson()).toList()),
  );
}

Future<List<PointRecord>> loadRecords(SharedPreferences prefs) async {
  final raw = prefs.getString(PrefsKeys.pointRecords);
  if (raw == null) return [];
  return (jsonDecode(raw) as List)
      .map((e) => PointRecord.fromJson(e as Map<String, dynamic>))
      .toList();
}

Future<void> saveRecords(
  SharedPreferences prefs,
  List<PointRecord> records,
) async {
  await prefs.setString(
    PrefsKeys.pointRecords,
    jsonEncode(records.map((r) => r.toJson()).toList()),
  );
}

// 更新小孩積分並寫入積分紀錄；回傳更新後積分
// delta 可為正（加分）或負（扣分）；扣分可能使積分為負，呼叫端自行把關
Future<int> applyPoints({
  required SharedPreferences prefs,
  required ChildData child,
  required int delta,
  required String reason,
  PointRecordContext? recordContext,
}) => applyPointsBatch(
  prefs: prefs,
  child: child,
  entries: [(delta: delta, reason: reason)],
  recordContexts: [recordContext],
);

// 一次套用多筆積分異動（特殊積分多選用）。
// 積分寫入的唯一實作：小孩清單與紀錄各讀寫一次，整批一起落盤；
// 紀錄順序與逐筆呼叫 applyPoints 完全一致（新的在前、total 逐筆累計）。
Future<int> applyPointsBatch({
  required SharedPreferences prefs,
  required ChildData child,
  required List<({int delta, String reason})> entries,
  List<PointRecordContext?>? recordContexts,
}) async {
  if (recordContexts != null && recordContexts.length != entries.length) {
    throw ArgumentError.value(
      recordContexts.length,
      'recordContexts',
      'must contain one entry for each points delta',
    );
  }
  if (entries.isEmpty) return child.points;

  // 讀取最新小孩清單
  final raw = prefs.getString(PrefsKeys.children);
  final children = raw == null
      ? <ChildData>[]
      : (jsonDecode(raw) as List)
            .map((e) => ChildData.fromJson(e as Map<String, dynamic>))
            .toList();

  // 找到對應小孩
  final idx = children.indexWhere((c) => c.id == child.id);
  if (idx == -1) return child.points;

  final records = await loadRecords(prefs);
  var points = children[idx].points;
  for (var i = 0; i < entries.length; i++) {
    final entry = entries[i];
    final recordContext = recordContexts?[i];
    points += entry.delta;
    records.insert(
      0,
      PointRecord(
        id: recordContext?.id ?? genId(),
        childId: child.id,
        time: nowStr(),
        reason: entry.reason,
        delta: entry.delta,
        total: points,
        kind: recordContext?.kind,
        sourceId: recordContext?.sourceId,
        reversesRecordId: recordContext?.reversesRecordId,
      ),
    );
  }
  children[idx].points = points;
  child.points = points; // 同步更新傳入的物件

  await prefs.setString(
    PrefsKeys.children,
    jsonEncode(children.map((c) => c.toJson()).toList()),
  );
  await saveRecords(prefs, records);

  return points;
}

List<PointRecord> habitCompletionRecordsForDay({
  required Iterable<PointRecord> records,
  required String habitId,
  required String date,
}) {
  return records
      .where(
        (record) =>
            record.kind == PointRecordKind.habitCompletion &&
            record.sourceId == habitId &&
            record.time.split(' ').first == date,
      )
      .toList();
}

Map<String, PointRecord> habitReversalsByCompletionId(
  Iterable<PointRecord> records,
) {
  return {
    for (final record in records)
      if (record.kind == PointRecordKind.habitReversal &&
          record.reversesRecordId != null)
        record.reversesRecordId!: record,
  };
}
