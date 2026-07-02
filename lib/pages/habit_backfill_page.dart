// 補打勾 / 補登：回到過去某一天，補上忘記勾的每日習慣。
//
// 只處理「昨天以前」的日子（今天在首頁勾即可，且首頁的 live 狀態才是今天的
// 真相，這裡若改今天會被首頁的歷史同步覆寫）。每天列出的習慣是用 createdAt /
// 刪除墓碑算出「那天當時實際存在」的條目（見 HabitHistory.dailyHabitsAsOf）。
//
// 喝水 / 體重是連動習慣，真相在各自的頁面，這裡不在此補（底部提示導去）。
// 補登只更新歷史紀錄，刻意不發金幣、不動連勝（避免回頭刷獎）。
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/app_style.dart';
import '../utils/habit_history.dart';
import '../utils/logical_date.dart';
import '../utils/prefs_keys.dart';
import '../utils/weight_records.dart';

const String _kWaterHabitName = '喝足夠的水';

bool _isLinkedHabit(String? name) =>
    name == _kWaterHabitName || isWeightHabitName(name);

/// 補打勾的整頁版（標題列 + 日視圖）。日視圖本身也內嵌在「足跡」頁的「補習慣」分頁。
class HabitBackfillPage extends StatelessWidget {
  const HabitBackfillPage({super.key});

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: const Color(0xFFFBF5EC),
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
          surfaceTintColor: Colors.transparent,
          systemOverlayStyle: SystemUiOverlayStyle.dark,
          foregroundColor: AppInk.strong,
          iconTheme: const IconThemeData(color: AppInk.strong),
          actionsIconTheme: const IconThemeData(color: AppInk.strong),
          title: const Text(
            '補上之前的足跡',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 17,
              color: AppInk.strong,
            ),
          ),
        ),
        body: const BackfillDayView(),
      ),
    );
  }
}

/// 補打勾的日視圖（日期條 + 當天習慣勾選）。可單獨用，也內嵌在足跡頁。
class BackfillDayView extends StatefulWidget {
  const BackfillDayView({super.key});

  @override
  State<BackfillDayView> createState() => _BackfillDayViewState();
}

class _BackfillDayViewState extends State<BackfillDayView> {
  SharedPreferences? _prefs;
  List<Map<String, dynamic>> _habits = const [];
  List<Map<String, dynamic>> _tombstones = const [];
  List<String> _dates = const [];
  String? _selected;
  Set<String> _doneIds = {};
  final Set<String> _activeDays = {}; // 有任何完成紀錄的日子（給日期條小圓點）
  bool _loading = true;

  final ScrollController _stripCtrl = ScrollController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _stripCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final dayStart = LogicalDate.hourOf(prefs);
    _habits = _parseHabits(prefs);
    _tombstones = HabitHistory.tombstones(prefs);

    final today = LogicalDate.dayOf(DateTime.now(), dayStart);
    final yesterday = today.subtract(const Duration(days: 1));

    // 最早可補到「最早建立的習慣」，但最多回看 60 天，避免清單過長。
    final earliest = _earliestCreated();
    final floor = yesterday.subtract(const Duration(days: 59));
    var start = earliest ?? yesterday.subtract(const Duration(days: 13));
    if (start.isBefore(floor)) start = floor;
    if (start.isAfter(yesterday)) start = yesterday;

    final span = yesterday.difference(start).inDays;
    final dates = [
      for (var i = 0; i <= span; i++) _fmt(start.add(Duration(days: i))),
    ];

    _activeDays.clear();
    for (final d in dates) {
      if (HabitHistory.doneIdsOn(prefs, d).isNotEmpty) _activeDays.add(d);
    }

    final selected = dates.isNotEmpty ? dates.last : null;
    setState(() {
      _prefs = prefs;
      _dates = dates;
      _selected = selected;
      _doneIds = selected == null
          ? {}
          : HabitHistory.doneIdsOn(prefs, selected).toSet();
      _loading = false;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_stripCtrl.hasClients) {
        _stripCtrl.jumpTo(_stripCtrl.position.maxScrollExtent);
      }
    });
  }

  List<Map<String, dynamic>> _parseHabits(SharedPreferences prefs) {
    final raw = prefs.getString(PrefsKeys.habits);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map<dynamic, dynamic>>()
          .map(Map<String, dynamic>.from)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  DateTime? _earliestCreated() {
    String? earliest;
    void consider(Object? v) {
      if (v is String && v.isNotEmpty) {
        if (earliest == null || v.compareTo(earliest!) < 0) earliest = v;
      }
    }

    for (final h in _habits) {
      consider(h['createdAt']);
    }
    for (final t in _tombstones) {
      consider(t['createdAt']);
    }
    return earliest == null ? null : DateTime.tryParse(earliest!);
  }

  void _selectDate(String date) {
    final prefs = _prefs;
    if (prefs == null) return;
    setState(() {
      _selected = date;
      _doneIds = HabitHistory.doneIdsOn(prefs, date).toSet();
    });
  }

  Future<void> _toggle(String id, bool done) async {
    final prefs = _prefs;
    final date = _selected;
    if (prefs == null || date == null) return;
    await HabitHistory.setDoneOn(prefs, date, id, done: done);
    setState(() {
      if (done) {
        _doneIds.add(id);
      } else {
        _doneIds.remove(id);
      }
      if (_doneIds.isEmpty) {
        _activeDays.remove(date);
      } else {
        _activeDays.add(date);
      }
    });
  }

  // ── 顯示用 ───────────────────────────────────────────────

  String _fmt(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static const _weekdays = ['一', '二', '三', '四', '五', '六', '日'];

  ({int month, int day, String weekday}) _parts(String date) {
    final d = DateTime.parse(date);
    return (month: d.month, day: d.day, weekday: _weekdays[d.weekday - 1]);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    return Column(
      children: [
        _buildDateStrip(),
        const SizedBox(height: 4),
        Expanded(child: _buildDayBody()),
        _buildFooterNote(),
      ],
    );
  }

  Widget _buildDateStrip() {
    return SizedBox(
      height: 76,
      child: ListView.separated(
        controller: _stripCtrl,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        itemCount: _dates.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final date = _dates[i];
          final p = _parts(date);
          final selected = date == _selected;
          final hasActivity = _activeDays.contains(date);
          return GestureDetector(
            onTap: () => _selectDate(date),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              width: 52,
              decoration: BoxDecoration(
                color: selected ? const Color(0xFFFF8A50) : Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: selected
                      ? const Color(0xFFFF8A50)
                      : const Color(0xFFEADBC8),
                ),
                boxShadow: selected ? AppShadows.card : AppShadows.flat,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '週${p.weekday}',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: selected ? Colors.white : AppInk.soft,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${p.day}',
                    style: AppType.digits(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: selected ? Colors.white : AppInk.strong,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Container(
                    width: 5,
                    height: 5,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: hasActivity
                          ? (selected ? Colors.white : const Color(0xFFFF8A50))
                          : Colors.transparent,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildDayBody() {
    final date = _selected;
    if (date == null) {
      return _buildEmpty('還沒有可以補的日子');
    }
    final all = HabitHistory.dailyHabitsAsOf(
      activeHabits: _habits,
      tombstones: _tombstones,
      date: date,
    );
    final editable = all
        .where((h) => !_isLinkedHabit(h['name'] as String?))
        .toList();
    final hasLinked = all.any((h) => _isLinkedHabit(h['name'] as String?));
    final p = _parts(date);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 4, 4, 12),
          child: Text(
            '${p.month}月${p.day}日 週${p.weekday}',
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: AppInk.strong,
            ),
          ),
        ),
        if (editable.isEmpty)
          _buildEmpty('這天還沒有每日習慣')
        else
          ...editable.map(_buildHabitRow),
        if (hasLinked)
          const Padding(
            padding: EdgeInsets.fromLTRB(4, 14, 4, 0),
            child: Text(
              '喝水、體重的補登請到各自的頁面',
              style: TextStyle(fontSize: 12.5, color: AppInk.faint),
            ),
          ),
      ],
    );
  }

  Widget _buildHabitRow(Map<String, dynamic> habit) {
    final id = habit['id'] as String;
    final name = (habit['name'] as String?) ?? '習慣';
    final deleted = habit['deleted'] == true;
    final done = _doneIds.contains(id);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: done ? const Color(0xFFF1F8E9) : Colors.white,
        borderRadius: BorderRadius.circular(AppCardStyle.radius),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppCardStyle.radius),
          onTap: () => _toggle(id, !done),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppCardStyle.radius),
              border: Border.all(
                color: done ? const Color(0xFFAED581) : const Color(0xFFEADBC8),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: done ? const Color(0xFF8BC34A) : Colors.transparent,
                    border: Border.all(
                      color: done
                          ? const Color(0xFF8BC34A)
                          : const Color(0xFFD7C4AE),
                      width: 2,
                    ),
                  ),
                  child: done
                      ? const Icon(Icons.check, size: 17, color: Colors.white)
                      : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    name,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: done ? AppInk.faint : AppInk.strong,
                      decoration: done ? TextDecoration.lineThrough : null,
                      decorationColor: AppInk.faint,
                    ),
                  ),
                ),
                if (deleted)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF0E6D8),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      '已刪除',
                      style: TextStyle(fontSize: 11, color: AppInk.soft),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmpty(String message) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.spa_rounded,
              size: 30,
              color: AppInk.faint.withValues(alpha: 0.7),
            ),
            const SizedBox(height: 10),
            Text(
              message,
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: AppInk.soft,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFooterNote() {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 6, 20, 10),
        child: Text(
          '補登只是補上紀錄，不影響金幣與連勝。',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 11.5, color: AppInk.faint),
        ),
      ),
    );
  }
}
