// 足跡 / 回顧：以陪伴語氣回看一段時間做了多少。
//
// 頂部只保留 [週 / 月] 唯讀統計；「補習慣」從 AppBar 進入獨立頁，
// 避免與統計的期間切換混在一起。
//
// 領域：習慣、喝水、番茄鐘、運動（各自有功能開關才顯示）。語氣刻意不打分、
// 不紅綠燈；數字只是「兔咪替你記得」。彙總邏輯在 utils/review_stats.dart。
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/app_style.dart';
import '../utils/coin_config.dart';
import '../utils/coin_service.dart';
import '../utils/habit_history.dart';
import '../utils/logical_date.dart';
import '../utils/prefs_keys.dart';
import '../utils/review_stats.dart';
import '../utils/units.dart';
import 'habit_backfill_page.dart';

const Color _accent = Color(0xFFFF8A50);
const Color _cardBorder = Color(0xFFEADBC8);
const Color _success = Color(0xFF74A65A);

class ReviewPage extends StatefulWidget {
  /// 進來預設停在哪個分頁：0=週 1=月。
  final int initialSegment;
  const ReviewPage({super.key, this.initialSegment = 0});

  @override
  State<ReviewPage> createState() => _ReviewPageState();
}

class _ReviewPageState extends State<ReviewPage> {
  late int _seg = widget.initialSegment.clamp(0, 1);
  int _offset = 0; // 0=當前週/月，-1=上一個…

  SharedPreferences? _prefs;
  List<Map<String, dynamic>> _habits = const [];
  List<Map<String, dynamic>> _tombstones = const [];
  List<CoinEntry> _coinLedger = const [];
  int _dayStart = LogicalDate.defaultHour;
  int _goalMl = 2000;
  int _cupMl = 250;
  int _coinBalance = 0;
  int _loginLevel = 0;
  int _loginStreak = 0;
  UnitSystem _unit = UnitSystem.metric;
  bool _waterEnabled = false;
  bool _timerEnabled = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    CoinService.notifier.addListener(_onCoinChanged);
    _load();
  }

  @override
  void dispose() {
    CoinService.notifier.removeListener(_onCoinChanged);
    super.dispose();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final ledger = await CoinService.ledger();
    _dayStart = LogicalDate.load(prefs);
    _habits = _parseHabits(prefs);
    _tombstones = HabitHistory.tombstones(prefs);
    _coinLedger = ledger;
    _coinBalance =
        prefs.getInt(PrefsKeys.coinBalance) ?? CoinService.notifier.value;
    _loginLevel = prefs.getInt(PrefsKeys.coinLoginLevel) ?? 0;
    _loginStreak = prefs.getInt(PrefsKeys.coinLoginStreak) ?? 0;
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

  void _onCoinChanged() {
    if (!mounted) return;
    setState(() => _coinBalance = CoinService.notifier.value);
    CoinService.ledger().then((ledger) {
      if (!mounted) return;
      setState(() => _coinLedger = ledger);
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

  DateTime get _periodStart => _seg == 0 ? _weekStart : _monthStart;

  DateTime get _periodEnd {
    final start = _periodStart;
    if (_seg == 0) return start.add(const Duration(days: 6));
    return DateTime(
      start.year,
      start.month + 1,
    ).subtract(const Duration(days: 1));
  }

  List<String> get _periodDates {
    if (_seg == 0) {
      final start = _weekStart;
      final end = start.add(const Duration(days: 6));
      return _range(start, end.isAfter(_today) ? _today : end);
    }
    final start = _monthStart;
    final last = DateTime(
      start.year,
      start.month + 1,
    ).subtract(const Duration(days: 1));
    return _range(start, last.isAfter(_today) ? _today : last);
  }

  String get _periodLabel {
    if (_seg == 0) {
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
                  _buildCoinWalletCard(),
                  _buildBackfillEntry(),
                  _buildSegmentBar(),
                  Expanded(child: _buildPeriodView()),
                ],
              ),
      ),
    );
  }

  void _openBackfill() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const HabitBackfillPage()));
  }

  Widget _buildBackfillEntry() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
      child: Material(
        color: const Color(0xFFFFF3E8),
        borderRadius: BorderRadius.circular(AppCardStyle.radius),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppCardStyle.radius),
          onTap: _openBackfill,
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppCardStyle.radius),
              border: Border.all(color: const Color(0xFFF3C49E)),
            ),
            child: const Row(
              children: [
                _BackfillIcon(),
                SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '忘了打勾？補上最近的習慣',
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w900,
                          color: AppInk.strong,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        '可補昨天起往前 7 天，不補發足跡幣與連勝',
                        style: TextStyle(fontSize: 11.5, color: AppInk.soft),
                      ),
                    ],
                  ),
                ),
                SizedBox(width: 6),
                Icon(Icons.chevron_right_rounded, color: Color(0xFFD77942)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSegmentBar() {
    const labels = ['週', '月'];
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

  Widget _buildCoinWalletCard() {
    final todayAmount = _todayLoginAmount();
    final periodStats = _coinPeriodStats();
    final periodWord = _seg == 0 ? '本週' : '本月';
    final periodLine = _periodCoinLine(periodWord, periodStats);
    final levelText = _loginLevel <= 0 ? '-' : 'Lv.$_loginLevel';

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 13),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Colors.white, Color(0xFFFFF6E6)],
          ),
          borderRadius: BorderRadius.circular(AppCardStyle.radius),
          border: Border.all(color: const Color(0xFFF0D8A7)),
          boxShadow: AppShadows.flat,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFC44D).withValues(alpha: 0.18),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: const Color(0xFFE5A327).withValues(alpha: 0.38),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(5),
                    child: Image.asset(
                      'assets/icon/ui/paw_footprint_coin_round.png',
                      filterQuality: FilterQuality.high,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '足跡錢包',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                          color: AppInk.strong,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        periodLine,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: AppInk.soft,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const Text(
                      '目前足跡幣',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        color: AppInk.soft,
                      ),
                    ),
                    Text(
                      _formatCoins(_coinBalance),
                      style: AppType.digits(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        color: const Color(0xFF7A4A17),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 13),
            Row(
              children: [
                Expanded(
                  child: _WalletMetric(
                    label: '今日登入',
                    value: todayAmount == null ? '未入帳' : '+$todayAmount',
                    color: const Color(0xFFE5A327),
                  ),
                ),
                const _WalletDivider(),
                Expanded(
                  child: _WalletMetric(
                    label: '連續登入',
                    value: _loginStreak > 999
                        ? '999+ 天'
                        : '${_loginStreak.clamp(0, 999)} 天',
                    color: _accent,
                  ),
                ),
                const _WalletDivider(),
                Expanded(
                  child: _WalletMetric(
                    label: '獎勵等級',
                    value: levelText,
                    color: _success,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: _milestoneProgressValue(),
                minHeight: 6,
                backgroundColor: const Color(0xFFF3E4CE),
                valueColor: const AlwaysStoppedAnimation(Color(0xFFE5A327)),
              ),
            ),
            const SizedBox(height: 7),
            Text(
              _milestoneLine(),
              style: const TextStyle(
                fontSize: 11.5,
                height: 1.25,
                fontWeight: FontWeight.w700,
                color: AppInk.soft,
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
        _buildFootprintCard(),
        const SizedBox(height: 12),
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

  _CoinPeriodStats _coinPeriodStats() {
    var earned = 0;
    var milestones = 0;
    final loginDates = <String>{};
    for (final entry in _coinLedger) {
      if (entry.amount <= 0) continue;
      if (!_isWithinCalendarRange(entry.at, _periodStart, _periodEnd)) {
        continue;
      }
      earned += entry.amount;
      if (entry.source == CoinSource.dailyLogin.name) {
        loginDates.add(_fmt(entry.at));
      }
      if (entry.source == CoinSource.weeklyStreak.name) {
        milestones++;
      }
    }
    return _CoinPeriodStats(
      earned: earned,
      loginDays: loginDates.length,
      milestones: milestones,
    );
  }

  String _periodCoinLine(String periodWord, _CoinPeriodStats stats) {
    final base = '$periodWord獲得 +${stats.earned} 足跡幣 · 登入 ${stats.loginDays} 天';
    return stats.milestones > 0 ? '$base · 獎勵 ${stats.milestones} 次' : base;
  }

  int? _todayLoginAmount() {
    final today = DateTime.now();
    for (final entry in _coinLedger) {
      if (entry.amount > 0 &&
          entry.source == CoinSource.dailyLogin.name &&
          _sameCalendarDay(entry.at, today)) {
        return entry.amount;
      }
    }
    return null;
  }

  bool _earnedMilestoneToday() {
    final today = DateTime.now();
    return _coinLedger.any(
      (entry) =>
          entry.amount > 0 &&
          entry.source == CoinSource.weeklyStreak.name &&
          _sameCalendarDay(entry.at, today),
    );
  }

  double _milestoneProgressValue() {
    if (_loginStreak <= 0) return 0;
    final milestone = CoinConfig.loginStreakMilestone;
    final cycleDays = _loginStreak % milestone;
    return (cycleDays == 0 ? milestone : cycleDays) / milestone;
  }

  String _milestoneLine() {
    final milestone = CoinConfig.loginStreakMilestone;
    if (_loginStreak <= 0) {
      return '登入獎勵會隨等級提高，連續 $milestone 天再 +${CoinConfig.weeklyStreak} 足跡幣。';
    }
    final cycleDays = _loginStreak % milestone;
    if (cycleDays == 0) {
      return _earnedMilestoneToday()
          ? '今天拿到 $milestone 天獎勵 +${CoinConfig.weeklyStreak} 足跡幣。'
          : '下一輪 $milestone 天獎勵準備開始。';
    }
    final remaining = milestone - cycleDays;
    return '距離 $milestone 天獎勵還差 $remaining 天（+${CoinConfig.weeklyStreak} 足跡幣）。';
  }

  bool _isWithinCalendarRange(DateTime at, DateTime start, DateTime end) {
    final day = DateTime(at.year, at.month, at.day);
    final startDay = DateTime(start.year, start.month, start.day);
    final endDay = DateTime(end.year, end.month, end.day);
    return !day.isBefore(startDay) && !day.isAfter(endDay);
  }

  bool _sameCalendarDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  String _formatCoins(int value) => value.toString().replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (_) => ',',
  );

  List<_DayFootprint> _periodFootprints() {
    final prefs = _prefs!;
    final today = _today;
    return [
      for (final day in _daysBetween(_periodStart, _periodEnd))
        _footprintFor(prefs, day, today),
    ];
  }

  _DayFootprint _footprintFor(
    SharedPreferences prefs,
    DateTime day,
    DateTime today,
  ) {
    final date = _fmt(day);
    if (day.isAfter(today)) {
      return _DayFootprint(
        date: date,
        day: day.day,
        done: 0,
        total: 0,
        status: _FootprintStatus.future,
      );
    }
    final asOf = HabitHistory.dailyHabitsAsOf(
      activeHabits: _habits,
      tombstones: _tombstones,
      date: date,
    );
    if (asOf.isEmpty) {
      return _DayFootprint(
        date: date,
        day: day.day,
        done: 0,
        total: 0,
        status: _FootprintStatus.none,
      );
    }

    final doneIds = HabitHistory.doneIdsOn(prefs, date).toSet();
    final done = asOf
        .map((h) => h['id'])
        .whereType<String>()
        .where(doneIds.contains)
        .length;
    final status = done == 0
        ? _FootprintStatus.missed
        : done >= asOf.length
        ? _FootprintStatus.done
        : _FootprintStatus.partial;
    return _DayFootprint(
      date: date,
      day: day.day,
      done: done,
      total: asOf.length,
      status: status,
    );
  }

  Widget _buildFootprintCard() {
    final days = _periodFootprints();
    final leadingBlanks = _seg == 1 ? _periodStart.weekday - 1 : 0;
    return _Card(
      icon: Icons.timeline_rounded,
      color: _success,
      title: '每日足跡',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _WeekdayLabels(),
          const SizedBox(height: 7),
          _FootprintGrid(days: days, leadingBlanks: leadingBlanks),
          const SizedBox(height: 12),
          const Wrap(
            spacing: 12,
            runSpacing: 6,
            children: [
              _FootprintLegend(color: _success, label: '全勤', filled: true),
              _FootprintLegend(color: _accent, label: '有留下'),
              _FootprintLegend(color: AppInk.faint, label: '空白'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTopSummary(HabitReview hr) {
    final String line;
    if (hr.trackedDays == 0) {
      line = '這段時間還沒有習慣紀錄。\n慢慢來，兔咪都在。';
    } else {
      final base = '這段時間你回來了 ${hr.daysActive} 天。';
      line = hr.daysAllDone > 0 ? '$base\n其中 ${hr.daysAllDone} 天全部完成了。' : base;
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 15),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFFF3E6), Color(0xFFFFE9D2)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(AppCardStyle.radius),
        border: Border.all(color: _cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.62),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.auto_awesome_rounded,
                  size: 18,
                  color: _accent,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                _seg == 0 ? '週回顧' : '月回顧',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                  color: AppInk.strong,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            line,
            style: const TextStyle(
              fontSize: 15,
              height: 1.45,
              fontWeight: FontWeight.w700,
              color: AppInk.strong,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _SummaryMetric(
                  label: '回來',
                  value: hr.daysActive,
                  color: _accent,
                ),
              ),
              const _SummaryDivider(),
              Expanded(
                child: _SummaryMetric(
                  label: '全勤',
                  value: hr.daysAllDone,
                  color: _success,
                ),
              ),
              const _SummaryDivider(),
              Expanded(
                child: _SummaryMetric(
                  label: '有習慣',
                  value: hr.trackedDays,
                  color: const Color(0xFF9D7B5E),
                ),
              ),
            ],
          ),
        ],
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
                  '留下 ${hr.daysActive}/${hr.trackedDays} 天 · 全勤 ${hr.daysAllDone} 天',
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

List<DateTime> _daysBetween(DateTime start, DateTime end) {
  if (start.isAfter(end)) return const [];
  return [
    for (var i = 0; i <= end.difference(start).inDays; i++)
      start.add(Duration(days: i)),
  ];
}

class _CoinPeriodStats {
  final int earned;
  final int loginDays;
  final int milestones;

  const _CoinPeriodStats({
    required this.earned,
    required this.loginDays,
    required this.milestones,
  });
}

class _WalletMetric extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _WalletMetric({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w800,
            color: AppInk.soft,
          ),
        ),
        const SizedBox(height: 3),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            value,
            maxLines: 1,
            style: AppType.digits(
              fontSize: 17,
              fontWeight: FontWeight.w900,
              color: color,
            ),
          ),
        ),
      ],
    );
  }
}

class _WalletDivider extends StatelessWidget {
  const _WalletDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 34,
      margin: const EdgeInsets.symmetric(horizontal: 8),
      color: const Color(0xFFEADBC8),
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

class _SummaryMetric extends StatelessWidget {
  final String label;
  final int value;
  final Color color;
  const _SummaryMetric({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            color: AppInk.soft,
          ),
        ),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            '$value 天',
            style: AppType.digits(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              color: color,
            ),
          ),
        ),
      ],
    );
  }
}

class _SummaryDivider extends StatelessWidget {
  const _SummaryDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 38,
      color: Colors.white.withValues(alpha: 0.68),
    );
  }
}

enum _FootprintStatus { done, partial, missed, none, future }

class _DayFootprint {
  final String date;
  final int day;
  final int done;
  final int total;
  final _FootprintStatus status;

  const _DayFootprint({
    required this.date,
    required this.day,
    required this.done,
    required this.total,
    required this.status,
  });
}

class _WeekdayLabels extends StatelessWidget {
  const _WeekdayLabels();

  static const _labels = ['一', '二', '三', '四', '五', '六', '日'];

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final label in _labels)
          Expanded(
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: AppInk.faint,
              ),
            ),
          ),
      ],
    );
  }
}

class _FootprintGrid extends StatelessWidget {
  final List<_DayFootprint> days;
  final int leadingBlanks;
  const _FootprintGrid({required this.days, required this.leadingBlanks});

  @override
  Widget build(BuildContext context) {
    const columns = 7;
    const gap = 6.0;
    return LayoutBuilder(
      builder: (_, constraints) {
        final cell = (constraints.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (var i = 0; i < leadingBlanks; i++)
              SizedBox(width: cell, height: cell),
            for (final day in days)
              SizedBox(
                width: cell,
                height: cell,
                child: _FootprintCell(day: day),
              ),
          ],
        );
      },
    );
  }
}

class _FootprintCell extends StatelessWidget {
  final _DayFootprint day;
  const _FootprintCell({required this.day});

  @override
  Widget build(BuildContext context) {
    final colors = _cellColors(day.status);
    final label = _semanticLabel(day);
    return Semantics(
      label: label,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.background,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: colors.border),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '${day.day}',
              style: AppType.digits(
                fontSize: 13,
                fontWeight: FontWeight.w900,
                color: colors.text,
              ),
            ),
            const SizedBox(height: 2),
            _FootprintMarker(status: day.status, color: colors.marker),
          ],
        ),
      ),
    );
  }

  ({Color background, Color border, Color text, Color marker}) _cellColors(
    _FootprintStatus status,
  ) {
    switch (status) {
      case _FootprintStatus.done:
        return (
          background: _success,
          border: _success,
          text: Colors.white,
          marker: Colors.white,
        );
      case _FootprintStatus.partial:
        return (
          background: const Color(0xFFFFF1E6),
          border: _accent.withValues(alpha: 0.55),
          text: _accent,
          marker: _accent,
        );
      case _FootprintStatus.missed:
        return (
          background: Colors.white,
          border: _cardBorder,
          text: AppInk.faint,
          marker: AppInk.faint,
        );
      case _FootprintStatus.none:
        return (
          background: const Color(0xFFF8F0E7),
          border: Colors.transparent,
          text: AppInk.faint.withValues(alpha: 0.62),
          marker: Colors.transparent,
        );
      case _FootprintStatus.future:
        return (
          background: Colors.transparent,
          border: _cardBorder.withValues(alpha: 0.55),
          text: AppInk.faint.withValues(alpha: 0.50),
          marker: Colors.transparent,
        );
    }
  }

  String _semanticLabel(_DayFootprint day) {
    switch (day.status) {
      case _FootprintStatus.done:
        return '${day.date} 全勤';
      case _FootprintStatus.partial:
        return '${day.date} 完成 ${day.done}/${day.total}';
      case _FootprintStatus.missed:
        return '${day.date} 有習慣，尚未留下紀錄';
      case _FootprintStatus.none:
        return '${day.date} 沒有每日習慣';
      case _FootprintStatus.future:
        return '${day.date} 尚未到來';
    }
  }
}

class _FootprintMarker extends StatelessWidget {
  final _FootprintStatus status;
  final Color color;
  const _FootprintMarker({required this.status, required this.color});

  @override
  Widget build(BuildContext context) {
    if (status == _FootprintStatus.done) {
      return Icon(Icons.check_rounded, size: 12, color: color);
    }
    if (status == _FootprintStatus.partial) {
      return Container(
        width: 14,
        height: 4,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(4),
        ),
      );
    }
    if (status == _FootprintStatus.missed) {
      return Container(
        width: 5,
        height: 5,
        decoration: BoxDecoration(shape: BoxShape.circle, color: color),
      );
    }
    return const SizedBox(height: 12);
  }
}

class _BackfillIcon extends StatelessWidget {
  const _BackfillIcon();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: const Color(0xFFFF8A50).withValues(alpha: 0.14),
        shape: BoxShape.circle,
      ),
      child: const Icon(
        Icons.edit_calendar_rounded,
        size: 21,
        color: Color(0xFFD77942),
      ),
    );
  }
}

class _FootprintLegend extends StatelessWidget {
  final Color color;
  final String label;
  final bool filled;
  const _FootprintLegend({
    required this.color,
    required this.label,
    this.filled = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: filled ? color : color.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(3),
            border: Border.all(color: color.withValues(alpha: 0.58)),
          ),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: const TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            color: AppInk.soft,
          ),
        ),
      ],
    );
  }
}
