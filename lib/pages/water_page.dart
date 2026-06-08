import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/mascot.dart';
import '../utils/sfx_service.dart';
import '../utils/units.dart';
import '../widgets/mascot_app_bar.dart';
import '../widgets/mascot_page_shell.dart';
import '../widgets/mascot_scene.dart';

const Color _kInk = Color(0xFF17657A);
const Color _kInkSoft = Color(0xFF4A8BA0);
const Color _kBgTop = Color(0xFFE8FAFF);
const Color _kBgMid = Color(0xFFDFF5FF);
const Color _kBgBottom = Color(0xFFFFFFFF);
const Color _kChipBg = Color(0xFFEAF8FF);

class WaterPage extends StatefulWidget {
  final void Function(bool)? onGoalStatusChanged;
  final int reloadTrigger;
  const WaterPage({
    super.key,
    this.onGoalStatusChanged,
    this.reloadTrigger = 0,
  });

  @override
  State<WaterPage> createState() => _WaterPageState();
}

class _WaterPageState extends State<WaterPage> with WidgetsBindingObserver {
  static const int _defaultCupMl = 250;
  static const int _defaultGoalMl = 2000;
  static const int _maxCups = 40;
  static const int _minCupMl = 50;
  static const int _maxCupMl = 1000;
  static const int _minGoalMl = 500;
  static const int _maxGoalMl = 6000;
  static const int _historyRetainDays = 30;
  static const String _keyPrefix = 'water_';
  // 自訂量累計（標準杯之外的補水）
  static const String _extraKeyPrefix = 'water_extra_';
  // home_page 那邊勾「喝足夠的水」習慣時暫存原本杯數用的 key prefix
  static const String _savedKeyPrefix = 'water_saved_';
  // 單次自訂量上限（2L 已經很多，超過就擋）
  static const int _maxSingleAddMl = 2000;

  int _cups = 0;
  int _extraMl = 0; // 標準杯之外的自訂量累計
  int _cupMl = _defaultCupMl;
  int _goalMl = _defaultGoalMl;
  String _todayKey = '';
  bool _lastReportedReached = false;
  DateTime? _lastMaxCupHint;
  UnitSystem _unit = UnitSystem.metric;

  // 顯示用：把公制 ml 轉成目前單位（imperial 顯示 fl oz）
  String _volStr(int ml) => UnitFormat.volume(ml, _unit);
  String get _volLabel => UnitFormat.volumeLabel(_unit);

  int get _totalMl => _cups * _cupMl + _extraMl;
  int get _goalCups => math.max(1, (_goalMl / _cupMl).ceil());
  bool get _goalReached => _totalMl >= _goalMl;
  double get _progress => (_totalMl / _goalMl).clamp(0.0, 1.0);

  // 兔咪情境：依目前喝水進度切換（互動時呼叫，用於 MascotPersona.interact）。
  MascotContext get _mascotCtx {
    if (_goalReached) return MascotContext.allDone;
    if (_cups == 0) return MascotContext.notStarted;
    if (_progress >= 0.5) return MascotContext.halfDone;
    return MascotContext.completedOne;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadWater();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didUpdateWidget(WaterPage old) {
    super.didUpdateWidget(old);
    if (old.reloadTrigger != widget.reloadTrigger) {
      _loadWater();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      final newKey = '$_keyPrefix${_todayString()}';
      if (newKey != _todayKey) _loadWater();
    }
  }

  String _todayString() {
    final now = DateTime.now();
    final m = now.month.toString().padLeft(2, '0');
    final d = now.day.toString().padLeft(2, '0');
    return '${now.year}-$m-$d';
  }

  void _notifyGoalStatus({bool force = false}) {
    if (!force && _lastReportedReached == _goalReached) return;
    _lastReportedReached = _goalReached;
    widget.onGoalStatusChanged?.call(_goalReached);
  }

  Future<void> _cleanupOldKeys(SharedPreferences prefs) async {
    final cutoff = DateTime.now().subtract(
      const Duration(days: _historyRetainDays),
    );
    // 長 prefix 先檢查，避免 'water_extra_2025-..' 被當作 'water_' 的 key 漏掉
    for (final key in prefs.getKeys()) {
      String? datePart;
      if (key.startsWith(_extraKeyPrefix)) {
        datePart = key.substring(_extraKeyPrefix.length);
      } else if (key.startsWith(_savedKeyPrefix)) {
        datePart = key.substring(_savedKeyPrefix.length);
      } else if (key.startsWith(_keyPrefix)) {
        datePart = key.substring(_keyPrefix.length);
      }
      if (datePart == null) continue;
      final parsed = DateTime.tryParse(datePart);
      if (parsed != null && parsed.isBefore(cutoff)) {
        await prefs.remove(key);
      }
    }
  }

  int _sanitizeCupMl(int? raw) =>
      (raw == null || raw < _minCupMl || raw > _maxCupMl) ? _defaultCupMl : raw;
  int _sanitizeGoalMl(int? raw) =>
      (raw == null || raw < _minGoalMl || raw > _maxGoalMl)
      ? _defaultGoalMl
      : raw;

  Future<void> _loadWater() async {
    final prefs = await SharedPreferences.getInstance();
    await _cleanupOldKeys(prefs);
    final today = _todayString();
    final todayKey = '$_keyPrefix$today';
    final cupMl = _sanitizeCupMl(prefs.getInt('water_cup_ml'));
    final goalMl = _sanitizeGoalMl(prefs.getInt('water_goal_ml'));
    final cups = (prefs.getInt(todayKey) ?? 0).clamp(0, _maxCups);
    final extra = (prefs.getInt('$_extraKeyPrefix$today') ?? 0).clamp(
      0,
      _maxGoalMl * 2,
    );
    final unit = UnitSystem.load(prefs);
    if (!mounted) return;
    setState(() {
      _todayKey = todayKey;
      _cupMl = cupMl;
      _goalMl = goalMl;
      _cups = cups;
      _extraMl = extra;
      _unit = unit;
    });
    _notifyGoalStatus(force: true);
  }

  // Re-anchor to today's key in case the app crossed midnight while open.
  String _ensureTodayKey() {
    final fresh = '$_keyPrefix${_todayString()}';
    if (fresh != _todayKey) _todayKey = fresh;
    return _todayKey;
  }

  Future<void> _saveCups(int cups) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_ensureTodayKey(), cups);
  }

  Future<void> _saveExtra(int amountMl) async {
    final prefs = await SharedPreferences.getInstance();
    final key = '$_extraKeyPrefix${_todayString()}';
    await prefs.setInt(key, amountMl);
  }

  Future<void> _addCup() async {
    if (_cups >= _maxCups) return;
    final wasReached = _goalReached;
    setState(() => _cups++);
    await _saveCups(_cups);
    _notifyGoalStatus();
    SfxService.instance.play(
      !wasReached && _goalReached ? SfxCue.complete : SfxCue.success,
    );
    MascotPersona.interact(_mascotCtx);
  }

  Future<void> _removeCup() async {
    if (_cups <= 0) return;
    setState(() => _cups--);
    await _saveCups(_cups);
    _notifyGoalStatus();
    SfxService.instance.play(SfxCue.cancel);
    MascotPersona.interact(_mascotCtx);
  }

  // 加入一個自訂量（不影響 _cups 與圓點數，只累加 _extraMl 進總量）
  Future<void> _addCustomMl(int ml) async {
    if (ml <= 0) return;
    final clamped = ml.clamp(1, _maxSingleAddMl);
    final wasReached = _goalReached;
    setState(() => _extraMl += clamped);
    await _saveExtra(_extraMl);
    _notifyGoalStatus();
    SfxService.instance.play(
      !wasReached && _goalReached ? SfxCue.complete : SfxCue.success,
    );
    MascotPersona.interact(_mascotCtx);
  }

  Future<void> _openCustomCupSheet() async {
    final result = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CustomCupSheet(unit: _unit, maxMl: _maxSingleAddMl),
    );
    if (result != null && result > 0) {
      await _addCustomMl(result);
    }
  }

  Future<void> _saveWaterSettings({
    required int cupMl,
    required int goalMl,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('water_cup_ml', cupMl);
    await prefs.setInt('water_goal_ml', goalMl);
    if (!mounted) return;
    setState(() {
      _cupMl = cupMl;
      _goalMl = goalMl;
    });
    _notifyGoalStatus();
  }

  int _roundToNearest50(num value, {int min = 1200, int max = 4200}) =>
      ((value / 50).round() * 50).clamp(min, max).toInt();

  // Latest tracked weight (from weight tracking page) takes priority over
  // the static profile weight, since the profile copy may be stale.
  double? _latestTrackedWeight(SharedPreferences prefs) {
    final raw = prefs.getString('weight_records');
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List || decoded.isEmpty) return null;
      // Records may be saved in any order; pick the entry with the
      // lexicographically largest yyyy-MM-dd.
      String? bestDate;
      num? bestWeight;
      for (final item in decoded) {
        if (item is! Map) continue;
        final date = item['date'];
        final weight = item['weight'];
        if (date is! String || weight is! num) continue;
        if (bestDate == null || date.compareTo(bestDate) > 0) {
          bestDate = date;
          bestWeight = weight;
        }
      }
      if (bestWeight == null) return null;
      final w = bestWeight.toDouble();
      if (w < 20 || w > 250) return null;
      return w;
    } catch (_) {
      return null;
    }
  }

  // Conservative beverage-water targets for children (rough USDA/EFSA
  // blended guidance), used as the baseline before activity bonus.
  int _childWaterBaseMl(int age) {
    if (age <= 3) return 900;
    if (age <= 8) return 1200;
    return 1600; // 9–13
  }

  int _ageFromBirthday(String? value) {
    if (value == null) return 0;
    final birthday = DateTime.tryParse(value);
    if (birthday == null) return 0;
    final now = DateTime.now();
    var age = now.year - birthday.year;
    if (now.month < birthday.month ||
        (now.month == birthday.month && now.day < birthday.day)) {
      age--;
    }
    return age;
  }

  // Map both legacy Chinese display strings and forward-looking enum keys
  // to a stable code so swapping the persisted value (for i18n) won't
  // break suggestion logic here.
  static const Map<String, String> _genderCode = {
    '男': 'male',
    'male': 'male',
    'M': 'male',
    '女': 'female',
    'female': 'female',
    'F': 'female',
  };
  static const Map<String, int> _activityBonusMl = {
    '輕度': 250,
    'light': 250,
    'low': 250,
    '中度': 500,
    'moderate': 500,
    'mid': 500,
    '高度': 750,
    'high': 750,
  };

  Future<({int ml, String reason})> _suggestGoal() async {
    final prefs = await SharedPreferences.getInstance();

    // Prefer the most recent tracked weight; only fall back to the
    // static profile weight when no records exist.
    final tracked = _latestTrackedWeight(prefs);
    final profileWeight = prefs.getDouble('user_weight');
    final weight = tracked ?? profileWeight;
    final usingTracked = tracked != null;

    final height = prefs.getDouble('user_height');
    final gender = _genderCode[prefs.getString('user_gender') ?? ''];
    final activity = prefs.getString('user_activity_level') ?? '';
    final age = _ageFromBirthday(prefs.getString('user_birthday'));

    // Children: age-tiered base. Activity bonus is halved (kids hydrate
    // less per workout than adults), and the lower bound of the rounder
    // is relaxed so we don't artificially push small kids up.
    if (age > 0 && age < 14) {
      num childBase = _childWaterBaseMl(age);
      childBase += (_activityBonusMl[activity] ?? 0) ~/ 2;
      return (
        ml: _roundToNearest50(childBase, min: 600, max: 2200),
        reason: '$age 歲建議',
      );
    }

    num base;
    String reason;
    if (weight != null && weight >= 20 && weight <= 250) {
      base = weight * 35;
      final wDisp = UnitFormat.weight(weight, _unit);
      reason = usingTracked ? '依最新體重 $wDisp 估算' : '依體重 $wDisp 估算';
    } else if (height != null && height >= 100 && height <= 230) {
      final h = height / 100;
      base = 22 * h * h * 35;
      reason = '依身高估算健康體重';
    } else if (gender == 'male') {
      base = 2500;
      reason = '依男性一般成人預設';
    } else if (gender == 'female') {
      base = 2000;
      reason = '依女性一般成人預設';
    } else {
      base = _defaultGoalMl;
      reason = '一般成人預設';
    }

    base += _activityBonusMl[activity] ?? 0;

    // Older adults: thirst sensation declines with age, so nudge up a
    // little to compensate.
    if (age >= 65) {
      base += 300;
      reason = '$reason · 銀髮加量';
    }

    return (ml: _roundToNearest50(base), reason: reason);
  }

  Future<void> _openWaterSettings() async {
    final suggestion = await _suggestGoal();
    if (!mounted) return;

    final result = await showModalBottomSheet<_WaterSettingsResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _WaterSettingsSheet(
        initialCupMl: _cupMl,
        initialGoalMl: _goalMl,
        suggestion: suggestion,
        minCupMl: _minCupMl,
        maxCupMl: _maxCupMl,
        minGoalMl: _minGoalMl,
        maxGoalMl: _maxGoalMl,
        unit: _unit,
      ),
    );

    if (result != null && mounted) {
      await _saveWaterSettings(cupMl: result.cupMl, goalMl: result.goalMl);
    }
  }

  @override
  Widget build(BuildContext context) {
    final goalCups = _goalCups;

    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: const Color(0xFFEFF9FF),
      appBar: MascotAppBar(accent: _kInk, onSettingsReturn: _loadWater),
      body: Stack(
        children: [
          const Positioned.fill(child: _BackdropDecor()),
          // 場景背景：延伸到 AppBar 後面（跟首頁同樣 56% 高度）
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: MediaQuery.of(context).size.height * 0.56,
            child: const MascotSceneBackground(
              'assets/scenes/water/water_bg.png',
            ),
          ),
          SafeArea(
            child: MascotPageShell(
              accent: _kInk,
              scene: const PersonaScene(accent: _kInk),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(22, 8, 22, 20),
                child: Column(
                  children: [
                    _summaryCard(goalCups),
                    const SizedBox(height: 8),
                    Expanded(
                      child: Center(
                        child: RepaintBoundary(
                          child: ValueListenableBuilder<double>(
                            valueListenable: MascotPanelPrefs.openValue,
                            builder: (_, openValue, _) => _WaterBottle(
                              progress: _progress,
                              reached: _goalReached,
                              bumpKey: _cups,
                              panelOpenValue: openValue,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    _progressNodes(goalCups),
                    const SizedBox(height: 18),
                    _controls(),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryCard(int goalCups) {
    final left = math.max(0, _goalMl - _totalMl);
    final goalDisp = _volStr(_goalMl);
    final leftDisp = _volStr(left);
    final subtitle = _goalReached
        ? '目標 $goalDisp · 已達標'
        : '目標 $goalDisp · 還差 $leftDisp';
    final totalDisp = _unit == UnitSystem.imperial
        ? UnitConvert.mlToFlOz(_totalMl.toDouble()).round().toString()
        : _totalMl.toString();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.86),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.7)),
        boxShadow: [
          BoxShadow(
            color: Colors.cyan.withValues(alpha: 0.10),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '今日補水',
            style: TextStyle(
              color: _kInkSoft,
              fontSize: 13,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                totalDisp,
                style: const TextStyle(
                  color: _kInk,
                  fontSize: 36,
                  fontWeight: FontWeight.w900,
                  height: 1.0,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                _volLabel,
                style: TextStyle(
                  color: _kInkSoft,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              if (_goalReached)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '已達標',
                    style: TextStyle(
                      color: Colors.green.shade700,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: TextStyle(
              color: _kInkSoft,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _summaryChip(
                icon: Icons.local_drink_outlined,
                label: '每杯 ${_volStr(_cupMl)}',
                onTap: _openWaterSettings,
              ),
              const SizedBox(width: 8),
              _summaryChip(
                icon: Icons.auto_awesome_outlined,
                label: '建議目標',
                onTap: _openWaterSettings,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _summaryChip({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return Material(
      color: _kChipBg,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: _kInk),
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(
                  color: _kInk,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _progressNodes(int goalCups) {
    // Always show 8 evenly-spaced nodes regardless of goalCups.
    // Each node represents a fractional share of the goal; filled count
    // mirrors the proportion already drunk (capped at full).
    const nodeCount = 8;
    final ratio = _goalMl == 0 ? 0.0 : (_totalMl / _goalMl).clamp(0.0, 1.0);
    final filledNodes = (ratio * nodeCount).round();
    return Semantics(
      label: '已喝 $_cups 杯，目標 $goalCups 杯',
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(nodeCount, (i) {
              final filled = i < filledNodes;
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 260),
                  curve: Curves.easeOut,
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: filled
                        ? (_goalReached
                              ? Colors.green.shade400
                              : Colors.cyan.shade400)
                        : Colors.white.withValues(alpha: 0.75),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: filled ? Colors.transparent : Colors.cyan.shade100,
                      width: 1.2,
                    ),
                    boxShadow: filled
                        ? [
                            BoxShadow(
                              color: Colors.cyan.withValues(alpha: 0.25),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            ),
                          ]
                        : null,
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 8),
          Text(
            _goalReached ? '$_cups 杯  ·  已達標' : '$_cups / $goalCups 杯',
            style: TextStyle(
              color: _kInkSoft,
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }

  void _onAddCupPressed() {
    if (_cups >= _maxCups) {
      // Debounce: while the user keeps spamming the button after hitting
      // the cap, only re-show the hint once every 4s and never stack
      // multiple snack bars.
      final now = DateTime.now();
      if (_lastMaxCupHint != null &&
          now.difference(_lastMaxCupHint!) < const Duration(seconds: 4)) {
        return;
      }
      _lastMaxCupHint = now;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text('今天已記錄 $_maxCups 杯，先休息一下吧'),
            duration: const Duration(seconds: 3),
          ),
        );
      return;
    }
    _addCup();
  }

  Widget _controls() {
    final atMax = _cups >= _maxCups;
    final canRemove = _cups > 0;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _SmallGhostButton(
          icon: Icons.remove_rounded,
          onTap: canRemove ? _removeCup : null,
          semanticsLabel: '少一杯',
        ),
        const SizedBox(width: 12),
        Expanded(child: _mainCupButton(atMax: atMax)),
        const SizedBox(width: 12),
        _SmallGhostButton(
          icon: Icons.more_horiz_rounded,
          onTap: _openCustomCupSheet,
          semanticsLabel: '自訂喝水量',
        ),
      ],
    );
  }

  Widget _mainCupButton({required bool atMax}) {
    return Semantics(
      button: true,
      label: '我喝了一杯，每杯 ${_volStr(_cupMl)}',
      child: Material(
        color: _kInk,
        borderRadius: BorderRadius.circular(22),
        elevation: 6,
        shadowColor: Colors.cyan.withValues(alpha: 0.35),
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: atMax ? _onAddCupPressed : _addCup,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.local_drink_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 14),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '我喝了一杯',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        height: 1.1,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _volStr(_cupMl),
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.85),
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SmallGhostButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final String? semanticsLabel;

  const _SmallGhostButton({
    required this.icon,
    required this.onTap,
    this.semanticsLabel,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Semantics(
      button: true,
      enabled: enabled,
      label: semanticsLabel,
      child: AnimatedOpacity(
        opacity: enabled ? 1 : 0.44,
        duration: const Duration(milliseconds: 180),
        child: Material(
          color: Colors.white.withValues(alpha: 0.92),
          shape: CircleBorder(
            side: BorderSide(
              color: enabled
                  ? Colors.cyan.shade100
                  : Colors.cyan.shade50.withValues(alpha: 0.5),
              width: 1.2,
            ),
          ),
          elevation: enabled ? 2 : 0,
          shadowColor: Colors.cyan.withValues(alpha: 0.14),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox(
              width: 54,
              height: 54,
              child: Icon(icon, color: _kInk, size: 22),
            ),
          ),
        ),
      ),
    );
  }
}

// Single source of truth for bottle layout.
//
// `imageAspectRatio` matches `assets/scenes/water/bottle_back.png` /
// `bottle_front.png` (1024 × 1536). When the bottle widget uses the same aspect ratio,
// `BoxFit.contain` does not letterbox the image, so the painter's
// normalized 0–1 coordinates map 1:1 onto the bottle artwork.
//
// `bodyLeft`/`bodyTop`/`bodyWidth`/`bodyHeight` describe the glass
// interior (where water can sit) as fractions of the image. If the
// asset is ever replaced, adjust ONLY these four numbers here.
class _BottleGeometry {
  static const double imageAspectRatio = 1024 / 1536;
  static const double bodyLeft = 195 / 1024;
  static const double bodyTop = 468 / 1536;
  static const double bodyWidth = 595 / 1024;
  static const double bodyHeight = 860 / 1536;

  static Rect bodyRectIn(Size size) => Rect.fromLTWH(
    size.width * bodyLeft,
    size.height * bodyTop,
    size.width * bodyWidth,
    size.height * bodyHeight,
  );

  static Path clipPathIn(Size size) {
    final r = bodyRectIn(size);
    final w = r.width;
    final h = r.height;
    return Path()
      ..moveTo(r.left + w * 0.24, r.top)
      ..lineTo(r.right - w * 0.24, r.top)
      ..cubicTo(
        r.right - w * 0.08,
        r.top + h * 0.03,
        r.right + w * 0.01,
        r.top + h * 0.18,
        r.right - w * 0.01,
        r.top + h * 0.34,
      )
      ..lineTo(r.right - w * 0.02, r.top + h * 0.72)
      ..cubicTo(
        r.right - w * 0.02,
        r.top + h * 0.90,
        r.right - w * 0.10,
        r.bottom - h * 0.02,
        r.right - w * 0.30,
        r.bottom,
      )
      ..lineTo(r.left + w * 0.30, r.bottom)
      ..cubicTo(
        r.left + w * 0.10,
        r.bottom - h * 0.02,
        r.left + w * 0.02,
        r.top + h * 0.90,
        r.left + w * 0.02,
        r.top + h * 0.72,
      )
      ..lineTo(r.left + w * 0.01, r.top + h * 0.34)
      ..cubicTo(
        r.left - w * 0.01,
        r.top + h * 0.18,
        r.left + w * 0.08,
        r.top + h * 0.03,
        r.left + w * 0.24,
        r.top,
      )
      ..close();
  }
}

class _WaterBottle extends StatefulWidget {
  final double progress;
  final bool reached;
  // bumpKey changes (e.g. cup count) trigger a brief scale bounce.
  final int bumpKey;
  final double panelOpenValue;

  const _WaterBottle({
    required this.progress,
    required this.reached,
    required this.bumpKey,
    required this.panelOpenValue,
  });

  @override
  State<_WaterBottle> createState() => _WaterBottleState();
}

class _WaterBottleState extends State<_WaterBottle>
    with SingleTickerProviderStateMixin {
  late final AnimationController _bumpCtl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
  );
  late final Animation<double> _bump = TweenSequence<double>([
    TweenSequenceItem(
      tween: Tween(
        begin: 1.0,
        end: 1.05,
      ).chain(CurveTween(curve: Curves.easeOut)),
      weight: 40,
    ),
    TweenSequenceItem(
      tween: Tween(
        begin: 1.05,
        end: 1.0,
      ).chain(CurveTween(curve: Curves.easeIn)),
      weight: 60,
    ),
  ]).animate(_bumpCtl);

  @override
  void didUpdateWidget(_WaterBottle old) {
    super.didUpdateWidget(old);
    if (old.bumpKey != widget.bumpKey) {
      _bumpCtl.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _bumpCtl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: widget.progress),
      duration: const Duration(milliseconds: 700),
      curve: Curves.easeOutCubic,
      builder: (context, value, _) {
        final compactReached = widget.reached
            ? ((widget.panelOpenValue - 0.55) / 0.45).clamp(0.0, 1.0)
            : 0.0;
        final bottleOpacity = 1.0 - compactReached;
        // AspectRatio locks the box to the bottle artwork's aspect ratio.
        // Every layer below shares this single coordinate system, so the
        // painter's body coords always land on the same pixels as the PNG.
        return ScaleTransition(
          scale: _bump,
          child: AspectRatio(
            aspectRatio: _BottleGeometry.imageAspectRatio,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Opacity(
                  opacity: bottleOpacity,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      // soft halo behind the bottle (purely decorative,
                      // sits outside the bottle interior).
                      Padding(
                        padding: const EdgeInsets.fromLTRB(0, 28, 0, 32),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: RadialGradient(
                              colors: [
                                Colors.cyan.withValues(alpha: 0.16),
                                Colors.cyan.withValues(alpha: 0.0),
                              ],
                            ),
                          ),
                        ),
                      ),
                      Image.asset(
                        'assets/scenes/water/bottle_back.png',
                        fit: BoxFit.contain,
                      ),
                      CustomPaint(painter: _WaterFillPainter(progress: value)),
                      Image.asset(
                        'assets/scenes/water/bottle_front.png',
                        fit: BoxFit.contain,
                      ),
                    ],
                  ),
                ),
                if (widget.reached)
                  _BottleGoalBadge(compactProgress: compactReached),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _BottleGoalBadge extends StatelessWidget {
  final double compactProgress;

  const _BottleGoalBadge({required this.compactProgress});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final smallSize = (constraints.maxWidth * 0.20).clamp(14.0, 36.0);
        final largeSize = constraints.maxWidth * 0.86;
        final badgeSize = ui.lerpDouble(smallSize, largeSize, compactProgress)!;
        final iconSize = badgeSize * 0.70;
        final blurRadius = (badgeSize * 0.33).clamp(5.0, 22.0);
        final alignment = Alignment.lerp(
          const Alignment(0.55, -0.72),
          Alignment.center,
          compactProgress,
        )!;

        return Align(
          alignment: alignment,
          child: Container(
            width: badgeSize,
            height: badgeSize,
            decoration: BoxDecoration(
              color: const Color(0xFFFFD54F),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFFFD54F).withValues(alpha: 0.35),
                  blurRadius: blurRadius,
                ),
              ],
            ),
            child: Icon(
              Icons.check_rounded,
              color: Colors.white,
              size: iconSize,
            ),
          ),
        );
      },
    );
  }
}

class _WaterFillPainter extends CustomPainter {
  final double progress;

  _WaterFillPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    // Drop shadow beneath the bottle (purely decorative, drawn outside
    // the body rect so it doesn't interact with the water clip).
    final shadow = Paint()
      ..color = Colors.cyan.withValues(alpha: 0.12)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(size.width / 2, size.height * 0.95),
        width: size.width * 0.55,
        height: 16,
      ),
      shadow,
    );

    // The water lives strictly inside the bottle interior, defined once
    // in _BottleGeometry. To change alignment for a new asset, edit that
    // class — do NOT sprinkle magic numbers here.
    final bodyRect = _BottleGeometry.bodyRectIn(size);
    final waterHeight = bodyRect.height * progress;
    final waterTop = bodyRect.bottom - waterHeight;

    final clip = _BottleGeometry.clipPathIn(size);
    canvas.save();
    canvas.clipPath(clip);

    final waveAmp = bodyRect.width * 0.045;
    final waterPath = Path()
      ..moveTo(bodyRect.left, waterTop + waveAmp * 0.5)
      ..cubicTo(
        bodyRect.left + bodyRect.width * 0.22,
        waterTop - waveAmp,
        bodyRect.left + bodyRect.width * 0.42,
        waterTop + waveAmp * 1.4,
        bodyRect.left + bodyRect.width * 0.66,
        waterTop + waveAmp * 0.3,
      )
      ..cubicTo(
        bodyRect.left + bodyRect.width * 0.82,
        waterTop - waveAmp * 0.8,
        bodyRect.right - bodyRect.width * 0.08,
        waterTop + waveAmp * 0.5,
        bodyRect.right,
        waterTop,
      )
      ..lineTo(bodyRect.right, bodyRect.bottom)
      ..lineTo(bodyRect.left, bodyRect.bottom)
      ..close();

    canvas.drawPath(
      waterPath,
      Paint()
        ..shader = const LinearGradient(
          colors: [Color(0xCC7DEBFF), Color(0xE622A9D8)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ).createShader(bodyRect),
    );

    // wave-line highlight along the water surface
    canvas.drawPath(
      waterPath,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.28)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );

    final bubblePaint = Paint()..color = Colors.white.withValues(alpha: 0.45);
    if (progress > 0.18) {
      canvas.drawCircle(
        Offset(
          bodyRect.left + bodyRect.width * 0.28,
          bodyRect.bottom - waterHeight * 0.42,
        ),
        bodyRect.width * 0.045,
        bubblePaint,
      );
    }
    if (progress > 0.42) {
      canvas.drawCircle(
        Offset(
          bodyRect.right - bodyRect.width * 0.30,
          bodyRect.bottom - waterHeight * 0.66,
        ),
        bodyRect.width * 0.035,
        bubblePaint,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _WaterFillPainter old) =>
      old.progress != progress;
}

class _WaterSettingsResult {
  final int cupMl;
  final int goalMl;
  const _WaterSettingsResult(this.cupMl, this.goalMl);
}

class _WaterSettingsSheet extends StatefulWidget {
  final int initialCupMl;
  final int initialGoalMl;
  final ({int ml, String reason}) suggestion;
  final int minCupMl;
  final int maxCupMl;
  final int minGoalMl;
  final int maxGoalMl;
  final UnitSystem unit;

  const _WaterSettingsSheet({
    required this.initialCupMl,
    required this.initialGoalMl,
    required this.suggestion,
    required this.minCupMl,
    required this.maxCupMl,
    required this.minGoalMl,
    required this.maxGoalMl,
    required this.unit,
  });

  @override
  State<_WaterSettingsSheet> createState() => _WaterSettingsSheetState();
}

class _WaterSettingsSheetState extends State<_WaterSettingsSheet> {
  // 顯示值依 unit；imperial 模式以 fl oz 進出，存的時候轉回 ml。
  late final TextEditingController _cupCtrl = TextEditingController(
    text: _initial(widget.initialCupMl),
  );
  late final TextEditingController _goalCtrl = TextEditingController(
    text: _initial(widget.initialGoalMl),
  );
  String? _cupErr;
  String? _goalErr;
  String? _appliedHint;

  bool get _imperial => widget.unit == UnitSystem.imperial;
  String get _label => UnitFormat.volumeLabel(widget.unit);

  String _initial(int ml) => _imperial
      ? UnitConvert.mlToFlOz(ml.toDouble()).round().toString()
      : ml.toString();

  int? _parseMl(String raw) {
    final v = double.tryParse(raw.trim());
    if (v == null) return null;
    return _imperial ? UnitConvert.flOzToMl(v).round() : v.round();
  }

  String _displayRange(int minMl, int maxMl) {
    if (!_imperial) return '$minMl–$maxMl $_label';
    final lo = UnitConvert.mlToFlOz(minMl.toDouble()).round();
    final hi = UnitConvert.mlToFlOz(maxMl.toDouble()).round();
    return '$lo–$hi $_label';
  }

  @override
  void dispose() {
    _cupCtrl.dispose();
    _goalCtrl.dispose();
    super.dispose();
  }

  void _applySuggestion() {
    final suggMl = widget.suggestion.ml;
    _goalCtrl.text = _initial(suggMl);
    setState(() {
      _goalErr = null;
      _appliedHint = '已套用建議 ${UnitFormat.volume(suggMl, widget.unit)}';
    });
  }

  void _submit() {
    final cupMl = _parseMl(_cupCtrl.text);
    final goalMl = _parseMl(_goalCtrl.text);
    final cupErr =
        (cupMl == null || cupMl < widget.minCupMl || cupMl > widget.maxCupMl)
        ? '請輸入 ${_displayRange(widget.minCupMl, widget.maxCupMl)}'
        : null;
    final goalErr =
        (goalMl == null ||
            goalMl < widget.minGoalMl ||
            goalMl > widget.maxGoalMl)
        ? '請輸入 ${_displayRange(widget.minGoalMl, widget.maxGoalMl)}'
        : null;
    if (cupErr != null || goalErr != null) {
      setState(() {
        _cupErr = cupErr;
        _goalErr = goalErr;
      });
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    Navigator.of(context).pop(_WaterSettingsResult(cupMl!, goalMl!));
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, bottom + 16),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 22,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '喝水設定',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 16),
            _NumField(
              controller: _cupCtrl,
              label: '每杯容量',
              suffix: _label,
              errorText: _cupErr,
              onChanged: () {
                if (_cupErr != null) setState(() => _cupErr = null);
              },
            ),
            const SizedBox(height: 12),
            _NumField(
              controller: _goalCtrl,
              label: '每日目標',
              suffix: _label,
              errorText: _goalErr,
              onChanged: () {
                if (_goalErr != null) setState(() => _goalErr = null);
              },
            ),
            const SizedBox(height: 12),
            Material(
              color: const Color(0xFFEAF8FF),
              borderRadius: BorderRadius.circular(14),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: _applySuggestion,
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      Icon(
                        Icons.auto_awesome,
                        color: Colors.cyan.shade700,
                        size: 18,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _appliedHint ??
                              '建議 ${UnitFormat.volume(widget.suggestion.ml, widget.unit)}\n${widget.suggestion.reason}',
                          style: TextStyle(
                            color: Colors.cyan.shade900,
                            fontSize: 13,
                            height: 1.35,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Icon(
                        Icons.north_west,
                        color: Colors.cyan.shade600,
                        size: 16,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '這是日常提醒用估算值；天氣、運動、健康狀況都會影響需求。',
              style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.cyan.shade600,
                  foregroundColor: Colors.white,
                ),
                onPressed: _submit,
                child: const Text('儲存設定'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NumField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String suffix;
  final String? errorText;
  final VoidCallback? onChanged;

  const _NumField({
    required this.controller,
    required this.label,
    required this.suffix,
    this.errorText,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      onChanged: onChanged == null ? null : (_) => onChanged!(),
      onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
      decoration: InputDecoration(
        labelText: label,
        suffixText: suffix,
        errorText: errorText,
        filled: true,
        fillColor: const Color(0xFFF7FBFD),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}

class _BackdropDecor extends StatelessWidget {
  const _BackdropDecor();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [_kBgTop, _kBgMid, _kBgBottom],
          stops: [0.0, 0.55, 1.0],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: CustomPaint(painter: _BackdropPainter()),
    );
  }
}

class _BackdropPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    // upper-left soft light spot
    final spot1 = Paint()
      ..shader =
          RadialGradient(
            colors: [
              Colors.white.withValues(alpha: 0.55),
              Colors.white.withValues(alpha: 0.0),
            ],
          ).createShader(
            Rect.fromCircle(
              center: Offset(size.width * 0.18, size.height * 0.18),
              radius: size.width * 0.55,
            ),
          );
    canvas.drawCircle(
      Offset(size.width * 0.18, size.height * 0.18),
      size.width * 0.55,
      spot1,
    );

    // lower-right faint cyan glow
    final spot2 = Paint()
      ..shader =
          RadialGradient(
            colors: [
              Colors.cyan.withValues(alpha: 0.10),
              Colors.cyan.withValues(alpha: 0.0),
            ],
          ).createShader(
            Rect.fromCircle(
              center: Offset(size.width * 0.85, size.height * 0.72),
              radius: size.width * 0.6,
            ),
          );
    canvas.drawCircle(
      Offset(size.width * 0.85, size.height * 0.72),
      size.width * 0.6,
      spot2,
    );

    // a few tiny bubble dots
    final bubble = Paint()..color = Colors.white.withValues(alpha: 0.55);
    final bubbles = <Offset>[
      Offset(size.width * 0.08, size.height * 0.62),
      Offset(size.width * 0.92, size.height * 0.34),
      Offset(size.width * 0.78, size.height * 0.84),
      Offset(size.width * 0.20, size.height * 0.86),
    ];
    final radii = [3.0, 4.5, 2.5, 3.5];
    for (var i = 0; i < bubbles.length; i++) {
      canvas.drawCircle(bubbles[i], radii[i], bubble);
    }
  }

  @override
  bool shouldRepaint(covariant _BackdropPainter old) => false;
}

// ── 自訂喝水量 sheet ──
//
// 快捷選擇（100/200/300/500）一點就直接記錄並關閉；
// 自訂輸入框輸入完按「加入」會回傳該量（已轉成 ml）。
class _CustomCupSheet extends StatefulWidget {
  final UnitSystem unit;
  final int maxMl;

  const _CustomCupSheet({required this.unit, required this.maxMl});

  @override
  State<_CustomCupSheet> createState() => _CustomCupSheetState();
}

class _CustomCupSheetState extends State<_CustomCupSheet> {
  static const List<int> _presetMl = [100, 200, 300, 500];

  final TextEditingController _ctrl = TextEditingController();
  String? _err;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _submitCustom() {
    final raw = _ctrl.text.trim();
    if (raw.isEmpty) {
      setState(() => _err = '請輸入數字');
      return;
    }
    final n = num.tryParse(raw);
    if (n == null || n <= 0) {
      setState(() => _err = '請輸入大於 0 的數字');
      return;
    }
    // 公制直接用，英制把 fl oz 轉成 ml
    final ml = widget.unit == UnitSystem.imperial
        ? UnitConvert.flOzToMl(n.toDouble()).round()
        : n.round();
    if (ml > widget.maxMl) {
      setState(() => _err = '單次量太大了'); // units-ok
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    Navigator.of(context).pop(ml);
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    final label = UnitFormat.volumeLabel(widget.unit);
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, bottom + 16),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 22,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '喝了多少？',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text(
              '快速選擇 或自己輸入',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _presetMl.map((ml) {
                final shown = UnitFormat.volume(ml, widget.unit);
                return _PresetChip(
                  label: '$shown $label',
                  onTap: () => Navigator.of(context).pop(ml),
                );
              }).toList(),
            ),
            const SizedBox(height: 18),
            const Text('自訂', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextField(
                    controller: _ctrl,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: false,
                    ),
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: InputDecoration(
                      hintText: '輸入數字',
                      suffixText: label,
                      errorText: _err,
                      border: const OutlineInputBorder(),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 12,
                      ),
                    ),
                    onChanged: (_) {
                      if (_err != null) setState(() => _err = null);
                    },
                    onSubmitted: (_) => _submitCustom(),
                  ),
                ),
                const SizedBox(width: 8),
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: FilledButton(
                    onPressed: _submitCustom,
                    style: FilledButton.styleFrom(
                      backgroundColor: _kInk,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 14,
                      ),
                    ),
                    child: const Text('加入'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PresetChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _PresetChip({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _kChipBg,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          child: Text(
            label,
            style: const TextStyle(
              color: _kInk,
              fontWeight: FontWeight.w700,
              fontSize: 14,
            ),
          ),
        ),
      ),
    );
  }
}
