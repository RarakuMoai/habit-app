// 足跡 / 回顧：以陪伴語氣回看一段時間做了多少。
//
// 頂部 [日 / 週 / 月]：
// - 日 = 補登視圖（可勾、可補；沿用 BackfillDayView）。
// - 週 / 月 = 唯讀的溫柔摘要 + 極簡長條，可用 ← → 翻到過去的週/月。
//
// 領域：習慣、喝水、番茄鐘、運動（各自有功能開關才顯示）。語氣刻意不打分、
// 不紅綠燈；數字只是「兔咪替你記得」。彙總邏輯在 utils/review_stats.dart。
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/app_style.dart';
import '../utils/habit_history.dart';
import '../utils/logical_date.dart';
import '../utils/prefs_keys.dart';
import '../utils/review_stats.dart';
import '../utils/units.dart';
import 'habit_backfill_page.dart';

const Color _accent = Color(0xFFFF8A50);
const Color _cardBorder = Color(0xFFEADBC8);

class ReviewPage extends StatefulWidget {
  /// 進來預設停在哪個分頁：0=日 1=週 2=月。日曆鈕進來預設「週」。
  final int initialSegment;
  const ReviewPage({super.key, this.initialSegment = 1});

  @override
  State<ReviewPage> createState() => _ReviewPageState();
}

class _ReviewPageState extends State<ReviewPage> {
  late int _seg = widget.initialSegment.clamp(0, 2);
  int _offset = 0; // 0=當前週/月，-1=上一個…

  SharedPreferences? _prefs;
  List<Map<String, dynamic>> _habits = const [];
  List<Map<String, dynamic>> _tombstones = const [];
  int _dayStart = LogicalDate.defaultHour;
  int _goalMl = 2000;
  int _cupMl = 250;
  UnitSystem _unit = UnitSystem.metric;
  bool _waterEnabled = false;
  bool _timerEnabled = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    _dayStart = LogicalDate.load(prefs);
    _habits = _parseHabits(prefs);
    _tombstones = HabitHistory.tombstones(prefs);
    _goalMl = prefs.getInt(PrefsKeys.waterGoalMl) ?? 2000;
    _cupMl = prefs.getInt(PrefsKeys.waterCupMl) ?? 250;
    _unit = UnitSystem.load(prefs);
    _waterEnabled = prefs.getBool(PrefsKeys.waterEnabled) ?? false;
    _timerEnabled = prefs.getBool(PrefsKeys.timerEnabled) ?? false;
    if (!mounted) return;
    setState(() {
      _prefs = prefs;
      _loading = false;
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

  // ── 日期範圍 ─────────────────────────────────────────────

  DateTime get _today => LogicalDate.dayOf(DateTime.now(), _dayStart);

  String _fmt(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  List<String> _range(DateTime a, DateTime b) {
    if (a.isAfter(b)) return const [];
    final n = b.difference(a).inDays;
    return [for (var i = 0; i <= n; i++) _fmt(a.add(Duration(days: i)))];
  }

  DateTime get _weekStart {
    final t = _today;
    return t
        .subtract(Duration(days: t.weekday - 1))
        .add(Duration(days: _offset * 7));
  }

  DateTime get _monthStart {
    final t = _today;
    return DateTime(t.year, t.month + _offset);
  }

  List<String> get _periodDates {
    if (_seg == 1) {
      final start = _weekStart;
      final end = start.add(const Duration(days: 6));
      return _range(start, end.isAfter(_today) ? _today : end);
    }
    final start = _monthStart;
    final last = DateTime(start.year, start.month + 1)
        .subtract(const Duration(days: 1));
    return _range(start, last.isAfter(_today) ? _today : last);
  }

  String get _periodLabel {
    if (_seg == 1) {
      final s = _weekStart;
      final e = s.add(const Duration(days: 6));
      final suffix = _offset == 0 ? '（本週）' : '';
      return '${s.month}/${s.day} – ${e.month}/${e.day}$suffix';
    }
    final s = _monthStart;
    final suffix = _offset == 0 ? '（本月）' : '';
    return '${s.year} 年 ${s.month} 月$suffix';
  }

  void _changeSeg(int seg) {
    if (seg == _seg) return;
    setState(() {
      _seg = seg;
      _offset = 0;
    });
  }

  // ── build ────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFBF5EC),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        foregroundColor: AppInk.strong,
        title: const Text(
          '足跡',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 17,
            color: AppInk.strong,
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _buildSegmentBar(),
                Expanded(
                  child: _seg == 0
                      ? const BackfillDayView()
                      : _buildPeriodView(),
                ),
              ],
            ),
    );
  }

  Widget _buildSegmentBar() {
    const labels = ['日', '週', '月'];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _cardBorder),
        ),
        child: Row(
          children: [
            for (var i = 0; i < labels.length; i++)
              Expanded(
                child: GestureDetector(
                  onTap: () => _changeSeg(i),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      color: _seg == i ? _accent : Colors.transparent,
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Text(
                      labels[i],
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: _seg == i ? Colors.white : AppInk.soft,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildPeriodView() {
    final prefs = _prefs!;
    final dates = _periodDates;
    final hr = ReviewStats.habits(
      prefs,
      dates: dates,
      activeHabits: _habits,
      tombstones: _tombstones,
    );
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      children: [
        _buildPeriodNav(),
        const SizedBox(height: 12),
        _buildTopSummary(hr),
        const SizedBox(height: 14),
        _buildHabitCard(hr),
        if (_waterEnabled) ...[
          const SizedBox(height: 12),
          _buildWaterCard(
            ReviewStats.water(
              prefs,
              dates: dates,
              goalMl: _goalMl,
              cupMl: _cupMl,
            ),
          ),
        ],
        if (_timerEnabled) ...[
          const SizedBox(height: 12),
          _buildCountCard(
            icon: Icons.local_fire_department_rounded,
            color: const Color(0xFFEF7A5A),
            title: '專注',
            review: ReviewStats.focus(prefs, dates: dates),
            unitWord: '顆',
            emptyText: '這段時間還沒有專注紀錄',
          ),
          const SizedBox(height: 12),
          _buildCountCard(
            icon: Icons.fitness_center_rounded,
            color: const Color(0xFF6FAE8E),
            title: '運動',
            review: ReviewStats.exercise(prefs, dates: dates),
            unitWord: '次',
            emptyText: '這段時間還沒有運動紀錄',
          ),
        ],
        const SizedBox(height: 18),
        Text(
          '這些只是兔咪替你記得的，不是分數。',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 11.5, color: AppInk.faint),
        ),
      ],
    );
  }

  Widget _buildPeriodNav() {
    return Row(
      children: [
        IconButton(
          onPressed: () => setState(() => _offset -= 1),
          icon: const Icon(Icons.chevron_left_rounded),
          color: AppInk.soft,
          tooltip: '上一個',
        ),
        Expanded(
          child: Text(
            _periodLabel,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: AppInk.strong,
            ),
          ),
        ),
        IconButton(
          onPressed: _offset < 0 ? () => setState(() => _offset += 1) : null,
          icon: const Icon(Icons.chevron_right_rounded),
          color: AppInk.soft,
          tooltip: '下一個',
        ),
      ],
    );
  }

  Widget _buildTopSummary(HabitReview hr) {
    final String line;
    if (hr.trackedDays == 0) {
      line = '這段時間還沒有習慣紀錄。\n慢慢來，兔咪都在。';
    } else {
      final unit = _seg == 1 ? '週' : '月';
      final base = '這$unit你回來了 ${hr.daysActive} 天。';
      line = hr.daysAllDone > 0 ? '$base\n其中 ${hr.daysAllDone} 天全部完成了。' : base;
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFFF3E6), Color(0xFFFFE9D2)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(AppCardStyle.radius),
        border: Border.all(color: _cardBorder),
      ),
      child: Text(
        line,
        style: const TextStyle(
          fontSize: 15,
          height: 1.5,
          fontWeight: FontWeight.w700,
          color: AppInk.strong,
        ),
      ),
    );
  }

  Widget _buildHabitCard(HabitReview hr) {
    return _Card(
      icon: Icons.spa_rounded,
      color: _accent,
      title: '習慣',
      child: hr.perHabit.isEmpty
          ? _emptyLine('這段時間還沒有每日習慣')
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '回來 ${hr.daysActive} 天 · 全勤 ${hr.daysAllDone} 天',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppInk.soft,
                  ),
                ),
                const SizedBox(height: 12),
                for (final t in hr.perHabit) ...[
                  _HabitTallyRow(tally: t),
                  const SizedBox(height: 10),
                ],
              ],
            ),
    );
  }

  Widget _buildWaterCard(WaterReview wr) {
    return _Card(
      icon: Icons.water_drop_rounded,
      color: const Color(0xFF5FA8D8),
      title: '喝水',
      child: wr.daysWithData == 0
          ? _emptyLine('這段時間還沒有喝水紀錄')
          : Text(
              '達標 ${wr.daysMetGoal} 天 · 平均每天 '
              '${UnitFormat.volume(wr.avgMlOnDataDays, _unit)}',
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
                color: AppInk.soft,
              ),
            ),
    );
  }

  Widget _buildCountCard({
    required IconData icon,
    required Color color,
    required String title,
    required CountReview review,
    required String unitWord,
    required String emptyText,
  }) {
    return _Card(
      icon: icon,
      color: color,
      title: title,
      child: review.activeDays == 0
          ? _emptyLine(emptyText)
          : Text(
              '${review.count} $unitWord · ${review.minutes} 分鐘 · '
              '${review.activeDays} 天',
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
                color: AppInk.soft,
              ),
            ),
    );
  }

  Widget _emptyLine(String text) => Text(
    text,
    style: const TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w600,
      color: AppInk.faint,
    ),
  );
}

class _Card extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final Widget child;
  const _Card({
    required this.icon,
    required this.color,
    required this.title,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppCardStyle.radius),
        border: Border.all(color: _cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: AppInk.strong,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _HabitTallyRow extends StatelessWidget {
  final HabitTally tally;
  const _HabitTallyRow({required this.tally});

  @override
  Widget build(BuildContext context) {
    final frac = tally.total == 0 ? 0.0 : tally.done / tally.total;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                tally.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: tally.deleted ? AppInk.faint : AppInk.strong,
                ),
              ),
            ),
            if (tally.deleted)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0E6D8),
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: const Text(
                    '已刪除',
                    style: TextStyle(fontSize: 10, color: AppInk.soft),
                  ),
                ),
              ),
            Text(
              '${tally.done}/${tally.total}',
              style: AppType.digits(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: tally.deleted ? AppInk.faint : _accent,
              ),
            ),
          ],
        ),
        const SizedBox(height: 5),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: frac,
            minHeight: 5,
            backgroundColor: const Color(0xFFF1E7D8),
            valueColor: AlwaysStoppedAnimation(
              tally.deleted ? AppInk.faint : _accent,
            ),
          ),
        ),
      ],
    );
  }
}
