import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/app_feedback.dart';
import '../utils/app_style.dart';
import '../utils/mascot.dart';
import '../utils/prefs_keys.dart';
import '../utils/sfx_service.dart';
import '../utils/units.dart';
import '../utils/user_validators.dart';
import '../utils/weight_records.dart';
import '../widgets/birthday_picker.dart';
import '../widgets/habit_ui.dart';
import '../widgets/hold_repeat_button.dart';
import '../widgets/mascot_app_bar.dart';
import '../widgets/mascot_page_shell.dart';
import '../widgets/mascot_scene.dart';

class WeightPage extends StatefulWidget {
  final VoidCallback? onRecordsChanged;
  const WeightPage({super.key, this.onRecordsChanged});

  @override
  State<WeightPage> createState() => _WeightPageState();
}

enum _WeightSheetField { weight, fat }

class _WeightPageState extends State<WeightPage> {
  // 所有體重紀錄（按日期降序）
  List<Map<String, dynamic>> _records = [];
  double? _userHeight; // 身高（公分）
  String _gender = '';
  DateTime? _birthday;
  String _activityLevel = ''; // 活動量（久坐/輕度/中度/高度）
  // 控制 BottomSheet 是否顯示體脂欄位
  bool _weightTrackingEnabled = false;
  // 目標體重（從設定讀取）
  double? _targetWeight;
  // 圖表顯示範圍：0=本週, 1=本月, 2=三個月
  int _chartRangeIndex = 0;
  // 顯示用單位（公制 / 英制）
  UnitSystem _unit = UnitSystem.metric;
  bool _loaded = false;

  // 公制→當下單位的顯示值（kg → kg 或 lb）
  double _wDisp(double kg) =>
      _unit == UnitSystem.imperial ? UnitConvert.kgToLb(kg) : kg;
  String get _wLabel => UnitFormat.weightLabel(_unit);
  // 體重顯示成字串：英制四捨五入到 lb，公制走原本的 _fmt 邏輯
  String _fmtWeight(double kg) => _unit == UnitSystem.imperial
      ? UnitConvert.kgToLb(kg).round().toString()
      : _fmt(kg);

  // 新增/編輯 BottomSheet 共用的輸入控制器（頁面層級，避免 sheet 關閉時的釋放競態）
  final TextEditingController _weightCtrl = TextEditingController();
  final TextEditingController _fatCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    UnitSystem.notifier.addListener(_onUnitChanged);
    _loadData();
  }

  @override
  void dispose() {
    UnitSystem.notifier.removeListener(_onUnitChanged);
    _weightCtrl.dispose();
    _fatCtrl.dispose();
    super.dispose();
  }

  // 設定頁切換公制/英制 → 立即反映，不用重開頁
  void _onUnitChanged() {
    if (!mounted) return;
    setState(() => _unit = UnitSystem.notifier.value);
  }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString(PrefsKeys.weightRecords);
    final bday = prefs.getString(PrefsKeys.userBirthday);

    var records = <Map<String, dynamic>>[];
    if (json != null) {
      final decoded = jsonDecode(json) as List<dynamic>;
      records = decoded
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    }
    // 按日期降序排列（最新在上）
    records.sort(
      (a, b) => (b['date'] as String).compareTo(a['date'] as String),
    );

    setState(() {
      _records = records;
      _userHeight = prefs.getDouble(PrefsKeys.userHeight);
      _gender = prefs.getString(PrefsKeys.userGender) ?? '';
      _activityLevel = prefs.getString(PrefsKeys.userActivityLevel) ?? '';
      if (bday != null) _birthday = DateTime.tryParse(bday);
      _weightTrackingEnabled =
          prefs.getBool(PrefsKeys.weightTrackingEnabled) ?? false;
      _targetWeight = prefs.getDouble(PrefsKeys.targetWeight);
      _unit = UnitSystem.load(prefs);
      _loaded = true;
    });
  }

  Future<void> _saveRecords() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(PrefsKeys.weightRecords, jsonEncode(_records));
    await syncWeightHabitForDate(prefs);
    widget.onRecordsChanged?.call();
  }

  // 今天日期字串（yyyy-MM-dd）
  String _todayString() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  // DateTime 轉 yyyy-MM-dd 字串
  String _dateStr(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  // BMI = 體重 ÷ 身高(m)²
  double? _calcBMI(double weight) {
    if (_userHeight == null || _userHeight! <= 0) return null;
    final hM = _userHeight! / 100;
    return weight / (hM * hM);
  }

  // 從生日計算年齡
  int? _calcAge() {
    if (_birthday == null) return null;
    final now = DateTime.now();
    var age = now.year - _birthday!.year;
    if (now.month < _birthday!.month ||
        (now.month == _birthday!.month && now.day < _birthday!.day)) {
      age--;
    }
    return age;
  }

  // BMR（Mifflin-St Jeor）：男 10w+6.25h-5a+5，女 10w+6.25h-5a-161
  double? _calcBMR(double weight) {
    if (_userHeight == null) return null;
    final age = _calcAge();
    if (age == null) return null;
    if (_gender == '男') return 10 * weight + 6.25 * _userHeight! - 5 * age + 5;
    if (_gender == '女') {
      return 10 * weight + 6.25 * _userHeight! - 5 * age - 161;
    }
    return null;
  }

  // 活動量係數（Harris-Benedict）
  double? _activityMultiplier() {
    switch (_activityLevel) {
      case '久坐':
        return 1.2;
      case '輕度':
        return 1.375;
      case '中度':
        return 1.55;
      case '高度':
        return 1.725;
    }
    return null;
  }

  // TDEE（每日總消耗）= BMR × 活動量係數
  double? _calcTDEE(double weight) {
    final bmr = _calcBMR(weight);
    final m = _activityMultiplier();
    if (bmr == null || m == null) return null;
    return bmr * m;
  }

  // BMI 分類（衛福部標準）：過輕／正常／過重／肥胖
  (String, Color) _bmiCategory(double bmi) {
    if (bmi < 18.5) return ('過輕', Colors.blue.shade400);
    if (bmi < 24) return ('正常', Colors.green.shade500);
    if (bmi < 27) return ('過重', Colors.orange.shade600);
    return ('肥胖', Colors.red.shade400);
  }

  // 本週週一到週日的 DateTime 列表（x=0~6 對應週一~週日）
  List<DateTime> _currentWeekDays() {
    final now = DateTime.now();
    final monday = now.subtract(Duration(days: now.weekday - 1));
    return List.generate(
      7,
      (i) => DateTime(monday.year, monday.month, monday.day + i),
    );
  }

  // 本週折線圖資料點（x = 0~6）
  // 歷史不足7天時只顯示有資料的點，不強制補滿
  List<FlSpot> _weekSpots() {
    final weekDays = _currentWeekDays();
    final spots = <FlSpot>[];
    for (var i = 0; i < weekDays.length; i++) {
      final dayStr = _dateStr(weekDays[i]);
      final idx = _records.indexWhere((r) => r['date'] == dayStr);
      if (idx >= 0) {
        spots.add(
          FlSpot(
            i.toDouble(),
            _wDisp((_records[idx]['weight'] as num).toDouble()),
          ),
        );
      }
    }
    return spots;
  }

  // 本月折線圖資料點（x = 當月日期數字）
  List<FlSpot> _monthSpots() {
    final now = DateTime.now();
    final prefix = '${now.year}-${now.month.toString().padLeft(2, '0')}';
    final spots = <FlSpot>[];
    // reversed 讓資料從舊到新（ascending order for chart）
    for (final rec in _records.reversed) {
      final date = rec['date'] as String;
      if (date.startsWith(prefix)) {
        final day = int.tryParse(date.split('-')[2]);
        if (day != null) {
          spots.add(
            FlSpot(day.toDouble(), _wDisp((rec['weight'] as num).toDouble())),
          );
        }
      }
    }
    return spots;
  }

  // 三個月折線圖資料點（x = 距90天前的偏移天數, 0~89）
  List<FlSpot> _threeMonthSpots() {
    final now = DateTime.now();
    // 起始日期：89 天前（含今天共 90 天）
    final startDate = DateTime(
      now.year,
      now.month,
      now.day,
    ).subtract(const Duration(days: 89));
    final spots = <FlSpot>[];
    for (final rec in _records.reversed) {
      final date = DateTime.tryParse(rec['date'] as String);
      if (date == null) continue;
      final offset = date.difference(startDate).inDays;
      if (offset >= 0 && offset <= 89) {
        spots.add(
          FlSpot(offset.toDouble(), _wDisp((rec['weight'] as num).toDouble())),
        );
      }
    }
    return spots;
  }

  // 新增或覆蓋同日紀錄（同一天只保留一筆）
  void _upsertRecord(Map<String, dynamic> record) {
    setState(() {
      _records.removeWhere((r) => r['date'] == record['date']);
      _records.add(record);
      _records.sort(
        (a, b) => (b['date'] as String).compareTo(a['date'] as String),
      );
    });
    _saveRecords();
    MascotPersona.interact(MascotContext.completedOne);
    playFeedback(SfxCue.success, haptic: HapticLevel.medium);
  }

  // 刪除指定日期的紀錄
  void _deleteRecord(Map<String, dynamic> rec) {
    setState(() {
      _records.removeWhere((r) => r['date'] == rec['date']);
    });
    _saveRecords();
    playFeedback(SfxCue.cancel, haptic: HapticLevel.light);
  }

  // 格式化數字（整數不顯示小數點，否則保留指定位數）
  String _fmt(double v, {int decimal = 1}) {
    if (decimal == 0) return v.round().toString();
    if (v == v.truncateToDouble()) return v.toInt().toString();
    return v.toStringAsFixed(decimal);
  }

  // 取得目前圖表範圍的資料點與 X 軸設定（封裝為 _ChartData）
  _ChartData _getChartData() {
    switch (_chartRangeIndex) {
      case 1: // 本月：x = 當月日期數字
        final spots = _monthSpots();
        final now = DateTime.now();
        final daysInMonth = DateTime(now.year, now.month + 1, 0).day;
        return _ChartData(
          spots: spots,
          minX: 1,
          maxX: daysInMonth.toDouble(),
          getBottomTitle: (value, meta) {
            final day = value.toInt();
            // 只顯示 1、8、15、22 及月底
            if (day == 1 ||
                day == 8 ||
                day == 15 ||
                day == 22 ||
                day == daysInMonth) {
              return Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '$day',
                  style: AppType.digits(
                    fontSize: 10,
                    color: day == now.day ? Colors.orange : AppInk.faint,
                    fontWeight: day == now.day
                        ? FontWeight.w800
                        : FontWeight.w600,
                  ),
                ),
              );
            }
            return const SizedBox.shrink();
          },
          xLabel: (x) => '${now.month}/${x.toInt()}',
        );

      case 2: // 三個月：x = 距90天前的偏移天數
        final spots = _threeMonthSpots();
        final now = DateTime.now();
        final startDate = DateTime(
          now.year,
          now.month,
          now.day,
        ).subtract(const Duration(days: 89));
        return _ChartData(
          spots: spots,
          minX: 0,
          maxX: 89,
          getBottomTitle: (value, meta) {
            final offset = value.toInt();
            final d = startDate.add(Duration(days: offset));
            // 每月 1 日或起始日才顯示標籤
            if (d.day == 1 || offset == 0) {
              return Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '${d.month}/${d.day}',
                  style: AppType.digits(
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                    color:
                        (d.year == now.year &&
                            d.month == now.month &&
                            d.day == now.day)
                        ? Colors.orange
                        : AppInk.faint,
                  ),
                ),
              );
            }
            return const SizedBox.shrink();
          },
          xLabel: (x) {
            final d = startDate.add(Duration(days: x.toInt()));
            return '${d.month}/${d.day}';
          },
        );

      case 0: // 本週（預設）：x = 0~6 對應週一~週日
      default:
        final spots = _weekSpots();
        final weekDays = _currentWeekDays();
        const labels = ['一', '二', '三', '四', '五', '六', '日'];
        final now = DateTime.now();
        return _ChartData(
          spots: spots,
          minX: 0,
          maxX: 6,
          getBottomTitle: (value, meta) {
            final idx = value.toInt();
            if (idx < 0 || idx > 6) return const SizedBox.shrink();
            final d = weekDays[idx];
            final isToday =
                d.year == now.year && d.month == now.month && d.day == now.day;
            return Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                labels[idx],
                style: TextStyle(
                  fontSize: 11,
                  color: isToday ? Colors.orange : AppInk.faint,
                  fontWeight: isToday ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            );
          },
          xLabel: (x) {
            final idx = x.toInt().clamp(0, 6);
            final d = weekDays[idx];
            return '${d.month}/${d.day} 週${labels[idx]}';
          },
        );
    }
  }

  // 日期顯示標籤：今天/昨天直接講人話，其他日期照舊
  String _dateLabel(DateTime d) {
    final now = DateTime.now();
    final diff = DateTime(
      now.year,
      now.month,
      now.day,
    ).difference(DateTime(d.year, d.month, d.day)).inDays;
    if (diff == 0) return '今天';
    if (diff == 1) return '昨天';
    return '${d.year} 年 '
        '${d.month.toString().padLeft(2, '0')} 月 '
        '${d.day.toString().padLeft(2, '0')} 日';
  }

  // 歷史 tile 的精簡日期：今天／昨天／M/D
  String _shortDateLabel(String dateStr) {
    final d = DateTime.tryParse(dateStr);
    if (d == null) return dateStr;
    final now = DateTime.now();
    final diff = DateTime(
      now.year,
      now.month,
      now.day,
    ).difference(DateTime(d.year, d.month, d.day)).inDays;
    if (diff == 0) return '今天';
    if (diff == 1) return '昨天';
    return '${d.month}/${d.day}';
  }

  // 與更早一筆紀錄的體重差（kg，正＝變重）；沒有更早紀錄回 null
  double? _deltaBefore(Map<String, dynamic> rec) {
    final idx = _records.indexWhere((r) => r['date'] == rec['date']);
    if (idx < 0 || idx + 1 >= _records.length) return null;
    return (rec['weight'] as num).toDouble() -
        (_records[idx + 1]['weight'] as num).toDouble();
  }

  // 差值語意色：朝目標走＝綠、遠離＝橘；無目標或幾乎持平＝中性
  Color _deltaColor(double diff, double prevWeight) {
    if (diff.abs() < 0.05) return AppInk.soft;
    final t = _targetWeight;
    if (t == null) return AppInk.soft;
    final toward = (t - prevWeight) * diff > 0;
    return toward ? Colors.green.shade600 : Colors.orange.shade700;
  }

  // 差值顯示字串（顯示單位、永遠帶 1 位小數的絕對值）
  String _deltaText(double diffKg) {
    final v = _unit == UnitSystem.imperial
        ? UnitConvert.kgToLb(diffKg).abs()
        : diffKg.abs();
    return v.toStringAsFixed(1);
  }

  // 開啟新增／編輯 BottomSheet
  // existing 不為 null 時為編輯模式，預填現有資料；
  // 新增模式預填上次體重（全選，直接打字就覆蓋），通常只需微調
  void _openAddSheet({Map<String, dynamic>? existing}) {
    var selectedDate = existing != null
        ? (DateTime.tryParse(existing['date'] as String) ?? DateTime.now())
        : DateTime.now();
    if (existing != null) {
      _weightCtrl.text = _fmtWeight((existing['weight'] as num).toDouble());
    } else if (_records.isNotEmpty) {
      _weightCtrl.text = _fmtWeight(
        (_records.first['weight'] as num).toDouble(),
      );
    } else {
      _weightCtrl.text = '';
    }
    _weightCtrl.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _weightCtrl.text.length,
    );
    _fatCtrl.text = existing != null && existing['body_fat'] != null
        ? _fmt((existing['body_fat'] as num).toDouble())
        : '';
    String? weightError;
    String? fatError;
    var activeField = _WeightSheetField.weight;
    // 仍是預填舊值、使用者還沒打過字：第一次按數字要先清空（覆蓋而非接在後面）。
    var weightPristine = true;
    var fatPristine = true;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            // ± 微調鈕：公制一格 0.1 kg、英制一格 1 lb
            // ± 微調：在目前值上加減（保持 pristine，之後直接打數字仍會覆蓋）。
            // 觸覺由 HoldRepeatButton 負責，這裡不再重複震動。
            void stepWeight(double delta) {
              final cur = double.tryParse(_weightCtrl.text.trim());
              final fallback = _records.isNotEmpty
                  ? _wDisp((_records.first['weight'] as num).toDouble())
                  : _wDisp(60);
              var next = (cur ?? fallback) + delta;
              if (next < 0) next = 0;
              _weightCtrl.text = _unit == UnitSystem.imperial
                  ? next.round().toString()
                  : _fmt(next);
              setSheetState(() => weightError = null);
            }

            TextEditingController activeController() =>
                activeField == _WeightSheetField.weight
                ? _weightCtrl
                : _fatCtrl;

            void pressDigit(String digit) {
              final isWeight = activeField == _WeightSheetField.weight;
              final ctrl = activeController();
              final maxLength = isWeight ? 6 : 5;
              // 還是預填舊值就先清空＝直接打數字會覆蓋掉舊的，不接在後面
              final pristine = isWeight ? weightPristine : fatPristine;
              var text = pristine ? '' : ctrl.text.trim();
              if (text.length >= maxLength) return;
              if (text == '0') text = '';
              ctrl.text = '$text$digit';
              setSheetState(() {
                if (isWeight) {
                  weightPristine = false;
                  weightError = null;
                } else {
                  fatPristine = false;
                  fatError = null;
                }
              });
              playHaptic(HapticLevel.selection);
            }

            void pressDecimal() {
              final isWeight = activeField == _WeightSheetField.weight;
              if (isWeight && _unit == UnitSystem.imperial) return;
              final ctrl = activeController();
              final pristine = isWeight ? weightPristine : fatPristine;
              final text = pristine ? '' : ctrl.text.trim();
              if (text.contains('.')) return;
              ctrl.text = text.isEmpty ? '0.' : '$text.';
              setSheetState(() {
                if (isWeight) {
                  weightPristine = false;
                  weightError = null;
                } else {
                  fatPristine = false;
                  fatError = null;
                }
              });
              playHaptic(HapticLevel.selection);
            }

            void pressBackspace() {
              final isWeight = activeField == _WeightSheetField.weight;
              final ctrl = activeController();
              final text = ctrl.text.trim();
              if (text.isEmpty) return;
              ctrl.text = text.substring(0, text.length - 1);
              setSheetState(() {
                if (isWeight) {
                  weightPristine = false;
                  weightError = null;
                } else {
                  fatPristine = false;
                  fatError = null;
                }
              });
              playHaptic(HapticLevel.selection);
            }

            void pressClear() {
              final isWeight = activeField == _WeightSheetField.weight;
              final ctrl = activeController();
              if (ctrl.text.isEmpty) return;
              ctrl.clear();
              setSheetState(() {
                if (isWeight) {
                  weightPristine = false;
                  weightError = null;
                } else {
                  fatPristine = false;
                  fatError = null;
                }
              });
              playHaptic(HapticLevel.selection);
            }

            void submit() {
              final rawText = _weightCtrl.text.trim();
              // 體重清空＝把這天的紀錄刪掉（當作今天沒量）；
              // _deleteRecord → _saveRecords 會同步取消體重習慣的勾選。
              if (rawText.isEmpty) {
                final dateStr = _dateStr(selectedDate);
                final idx = _records.indexWhere((r) => r['date'] == dateStr);
                if (idx >= 0) _deleteRecord(_records[idx]);
                Navigator.pop(ctx);
                return;
              }
              final wErr = UserValidators.weightIn(rawText, _unit);
              String? fErr;
              final fatText = _fatCtrl.text.trim();
              double? fat;
              if (fatText.isNotEmpty) {
                fat = double.tryParse(fatText);
                if (fat == null || fat <= 0 || fat >= 75) {
                  fErr = '請輸入 0–75 之間的數值';
                  fat = null;
                }
              }
              if (wErr != null || fErr != null) {
                setSheetState(() {
                  weightError = wErr;
                  fatError = fErr;
                });
                playHaptic(HapticLevel.light);
                return;
              }
              // 輸入是當下單位（kg 或 lb），統一轉成 kg 存
              final raw = double.parse(rawText);
              final weightKg = _unit == UnitSystem.imperial
                  ? UnitConvert.lbToKg(raw)
                  : raw;
              final now = DateTime.now();
              final time =
                  '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
              final record = <String, dynamic>{
                'date': _dateStr(selectedDate),
                // 編輯模式保留原始時間；新增模式使用當前時間
                'time': existing?['time'] ?? time,
                'weight': weightKg,
              };
              if (fat != null) record['body_fat'] = fat;
              _upsertRecord(record);
              Navigator.pop(ctx);
            }

            final latestForSheet = existing != null
                ? (existing['weight'] as num).toDouble()
                : _records.isNotEmpty
                ? (_records.first['weight'] as num).toDouble()
                : null;
            final headerSubtitle = existing != null
                ? '更新 ${_dateLabel(selectedDate)} 的體重資料'
                : latestForSheet == null
                ? '先留下一筆今天的身體讀數'
                : '上次 ${_fmtWeight(latestForSheet)} $_wLabel，直接微調即可';

            return SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(ctx).size.height * 0.86,
                  ),
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(18, 10, 18, 14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.orange.withValues(alpha: 0.18),
                          blurRadius: 24,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: SingleChildScrollView(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Center(
                                  child: Container(
                                    width: 40,
                                    height: 4,
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFE8DDD4),
                                      borderRadius: BorderRadius.circular(99),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    Container(
                                      width: 36,
                                      height: 36,
                                      decoration: BoxDecoration(
                                        color: Colors.orange.withValues(
                                          alpha: 0.12,
                                        ),
                                        borderRadius: BorderRadius.circular(13),
                                      ),
                                      child: const Icon(
                                        Icons.monitor_weight_rounded,
                                        color: Colors.orange,
                                        size: 20,
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            existing != null
                                                ? '編輯體重紀錄'
                                                : '新增體重紀錄',
                                            style: const TextStyle(
                                              fontSize: 18,
                                              fontWeight: FontWeight.w900,
                                              color: AppInk.strong,
                                            ),
                                          ),
                                          const SizedBox(height: 1),
                                          Text(
                                            headerSubtitle,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontSize: 12.5,
                                              color: AppInk.soft,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    IconButton(
                                      visualDensity: VisualDensity.compact,
                                      icon: const Icon(
                                        Icons.close_rounded,
                                        color: AppInk.iconFaint,
                                      ),
                                      onPressed: () => Navigator.pop(ctx),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                _datePickCard(
                                  dateLabel: _dateLabel(selectedDate),
                                  onTap: () async {
                                    final picked = await showAppDatePicker(
                                      ctx,
                                      initial: selectedDate,
                                      firstDate: DateTime(2000),
                                      lastDate: DateTime.now(),
                                      accent: Colors.orange,
                                      title: '選擇紀錄日期',
                                    );
                                    if (picked != null) {
                                      setSheetState(
                                        () => selectedDate = picked,
                                      );
                                    }
                                  },
                                ),
                                const SizedBox(height: 10),
                                _WeightInputCard(
                                  value: _weightCtrl.text,
                                  unitLabel: _wLabel,
                                  errorText: weightError,
                                  active:
                                      activeField == _WeightSheetField.weight,
                                  onTap: () {
                                    setSheetState(
                                      () => activeField =
                                          _WeightSheetField.weight,
                                    );
                                  },
                                  onDecrease: () => stepWeight(
                                    _unit == UnitSystem.imperial ? -1 : -0.1,
                                  ),
                                  onIncrease: () => stepWeight(
                                    _unit == UnitSystem.imperial ? 1 : 0.1,
                                  ),
                                ),
                                if (_weightTrackingEnabled) ...[
                                  const SizedBox(height: 8),
                                  _BodyFatInputCard(
                                    value: _fatCtrl.text,
                                    errorText: fatError,
                                    active:
                                        activeField == _WeightSheetField.fat,
                                    onTap: () {
                                      setSheetState(
                                        () =>
                                            activeField = _WeightSheetField.fat,
                                      );
                                    },
                                  ),
                                ],
                                const SizedBox(height: 12),
                                _WeightSheetKeypad(
                                  decimalEnabled:
                                      activeField == _WeightSheetField.fat ||
                                      _unit == UnitSystem.metric,
                                  onDigit: pressDigit,
                                  onDecimal: pressDecimal,
                                  onBackspace: pressBackspace,
                                  onClear: pressClear,
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        _SheetSaveButton(
                          label: existing != null ? '儲存更新' : '儲存紀錄',
                          onPressed: submit,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _datePickCard({
    required String dateLabel,
    required VoidCallback onTap,
  }) {
    return Material(
      color: const Color(0xFFFFFCF8),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 9, 10, 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0x0A46342B)),
            boxShadow: AppShadows.flat,
          ),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: const Icon(
                  Icons.calendar_today_rounded,
                  color: Colors.orange,
                  size: 17,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  dateLabel,
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800,
                    color: AppInk.strong,
                  ),
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: AppInk.iconFaint),
            ],
          ),
        ),
      ),
    );
  }

  // 顯示紀錄操作選單（長按或左滑呼叫）
  void _showRecordActions(Map<String, dynamic> rec) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            // 把手指示條
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppInk.faint.withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.edit_outlined, color: Colors.orange),
              title: const Text('編輯'),
              onTap: () {
                Navigator.pop(ctx);
                _openAddSheet(existing: rec);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: const Text('刪除', style: TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.pop(ctx);
                _confirmDelete(rec);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  // 刪除二次確認 Dialog
  void _confirmDelete(Map<String, dynamic> rec) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('確認刪除'),
        content: Text('確定要刪除 ${rec['date']} 的體重紀錄嗎？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _deleteRecord(rec);
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('刪除'),
          ),
        ],
      ),
    );
  }

  // 目標體重進度條（若未設定目標或無紀錄則回傳 null）
  Widget? _buildTargetProgress() {
    if (_targetWeight == null || _records.isEmpty) return null;

    final target = _targetWeight!;
    // _records 降序排列，last 為最早一筆（作為起始體重）
    final initialWeight = (_records.last['weight'] as num).toDouble();
    final latestWeight = (_records.first['weight'] as num).toDouble();

    // 起始與目標相同則不顯示
    if ((target - initialWeight).abs() < 0.001) return null;

    // 進度 = (目前改變量) / (總目標改變量)，0~1
    final rawProgress =
        (latestWeight - initialWeight) / (target - initialWeight);
    final progress = rawProgress.clamp(0.0, 1.0);
    final isGoalReached = rawProgress >= 1.0;
    final diff = (latestWeight - target).abs();

    final barColor = isGoalReached ? Colors.green.shade500 : Colors.orange;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppCardStyle.radius),
        border: AppCardStyle.hairline,
        boxShadow: AppShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isGoalReached ? Icons.emoji_events_rounded : Icons.flag_rounded,
                color: barColor,
                size: 18,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  isGoalReached
                      ? '目標：${_fmtWeight(target)} $_wLabel　已達成！'
                      : '目標：${_fmtWeight(target)} $_wLabel，還差 ${_fmtWeight(diff)} $_wLabel',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppInk.strong,
                    height: 1.3,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // 漸層進度條 + 尾端白心亮點（同首頁進度列語彙）
          _GradientProgressBar(value: progress, accent: barColor),
          const SizedBox(height: 6),
          // 起始與目標標籤
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '起始 ${_fmtWeight(initialWeight)} $_wLabel',
                style: const TextStyle(fontSize: 11, color: AppInk.faint),
              ),
              Text(
                '目標 ${_fmtWeight(target)} $_wLabel',
                style: const TextStyle(fontSize: 11, color: AppInk.faint),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final today = _todayString();
    // 今天的紀錄（若有）
    final todayIdx = _records.indexWhere((r) => r['date'] == today);
    final todayRec = todayIdx >= 0 ? _records[todayIdx] : null;

    // 提前計算，避免 build() 中重複呼叫
    final chartData = _getChartData();
    final targetProgressWidget = _buildTargetProgress();

    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: const Color(0xFFFFF8F0),
      appBar: MascotAppBar(accent: Colors.orange, onSettingsReturn: _loadData),
      // 不用 FAB：核心動作鈕（記錄今天／更新今日）釘在捲動區外的最上方，
      // 跟習慣頁「新增習慣」一致，常駐明顯、不被捲動蓋掉。
      body: Stack(
        children: [
          // 場景背景：延伸到 AppBar 後面（跟首頁同樣 56% 高度）
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: MediaQuery.of(context).size.height * 0.56,
            child: const MascotSceneBackground(
              'assets/scenes/weight/weight_bg.png',
            ),
          ),
          SafeArea(
            child: MascotPageShell(
              accent: Colors.orange,
              scene: const PersonaScene(accent: Colors.orange),
              // 核心動作鈕釘在捲動區外（與習慣頁「新增習慣」一致）：
              // 永遠在最上面明顯處，不會因捲動而消失。
              child: Column(
                children: [
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                      children: [
                        // ── 今日數據放最前：面板展開時第一眼就是今天的體重 ──
                        const HabitSectionHeader(
                          label: '今日數據',
                          icon: Icons.today_rounded,
                          color: Colors.orange,
                        ),
                        todayRec != null
                            ? Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(
                                    AppCardStyle.radius,
                                  ),
                                  border: AppCardStyle.hairline,
                                  boxShadow: AppShadows.card,
                                ),
                                child: _buildStatGrid(todayRec),
                              )
                            : _buildTodayEmptyCard(),

                        const SizedBox(height: 16),

                        // ── 趨勢圖卡片（範圍切換 + 折線圖） ──
                        const HabitSectionHeader(
                          label: '趨勢',
                          icon: Icons.show_chart_rounded,
                          color: Colors.orange,
                        ),
                        Container(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(
                              AppCardStyle.radius,
                            ),
                            border: AppCardStyle.hairline,
                            boxShadow: AppShadows.card,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  _rangeSelector(),
                                  const Spacer(),
                                  if (chartData.spots.isNotEmpty)
                                    _chartCountPill(chartData.spots.length),
                                ],
                              ),
                              const SizedBox(height: 14),
                              // 無資料時顯示友善提示，否則顯示折線圖
                              chartData.spots.isEmpty
                                  ? SizedBox(
                                      height: 158,
                                      child: Center(
                                        child: Column(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            Icon(
                                              Icons.show_chart,
                                              size: 36,
                                              color: Colors.orange.shade200,
                                            ),
                                            const SizedBox(height: 8),
                                            const Text(
                                              '此區間沒有紀錄',
                                              style: TextStyle(
                                                color: AppInk.faint,
                                                fontSize: 14,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    )
                                  : SizedBox(
                                      height: 158,
                                      child: Column(
                                        children: [
                                          _chartSummaryRow(chartData),
                                          const SizedBox(height: 8),
                                          Expanded(
                                            child: _buildLineChart(chartData),
                                          ),
                                        ],
                                      ),
                                    ),
                            ],
                          ),
                        ),

                        // ── 目標體重進度條（有設定目標才顯示） ──
                        if (targetProgressWidget != null) ...[
                          const SizedBox(height: 12),
                          targetProgressWidget,
                        ],

                        const SizedBox(height: 12),

                        // ── 歷史紀錄列表 ──
                        const HabitSectionHeader(
                          label: '歷史紀錄',
                          icon: Icons.history_rounded,
                          color: Colors.orange,
                        ),
                        if (_records.isEmpty)
                          const Center(
                            child: Padding(
                              padding: EdgeInsets.all(24),
                              child: Text(
                                '還沒有體重紀錄',
                                style: TextStyle(color: AppInk.faint),
                              ),
                            ),
                          )
                        else
                          ..._records.map(_buildHistoryTile),
                      ],
                    ),
                  ),
                  // 核心動作鈕釘在最下方、捲動區外：最常用、隨時可按，不被捲動蓋掉
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                    child: _TodayActionButton(
                      label: todayRec != null ? '更新今日體重' : '記錄今天體重',
                      icon: todayRec != null
                          ? Icons.edit_rounded
                          : Icons.add_rounded,
                      onTap: _openAddSheet,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // 折線圖本體：漸層線＋資料點＋觸控 tooltip＋虛線格線＋目標線
  Widget _buildLineChart(_ChartData chartData) {
    var minV = chartData.spots.map((s) => s.y).reduce(math.min);
    var maxV = chartData.spots.map((s) => s.y).reduce(math.max);

    // 目標線：離資料太遠（>5 顯示單位）就不畫，避免把曲線壓扁
    var targetLine = _targetWeight != null ? _wDisp(_targetWeight!) : null;
    if (targetLine != null &&
        targetLine >= minV - 5 &&
        targetLine <= maxV + 5) {
      minV = math.min(minV, targetLine);
      maxV = math.max(maxV, targetLine);
    } else {
      targetLine = null;
    }

    // 週檢視點少、點畫大顆；月／三個月點多、縮小避免擠成一團
    final dotRadius = _chartRangeIndex == 0 ? 4.0 : 2.5;
    final yAxis = _niceYAxis(minV, maxV);

    return LineChart(
      LineChartData(
        minX: chartData.minX,
        maxX: chartData.maxX,
        // Y 軸用好讀的刻度，不讓 fl_chart 自動塞滿奇怪的小數。
        minY: yAxis.min,
        maxY: yAxis.max,
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => Colors.orange.shade600,
            tooltipRoundedRadius: 10,
            fitInsideHorizontally: true,
            fitInsideVertically: true,
            getTooltipItems: (touchedSpots) => touchedSpots
                .map(
                  (s) => LineTooltipItem(
                    '${chartData.xLabel(s.x)}\n',
                    const TextStyle(color: Colors.white70, fontSize: 11),
                    children: [
                      TextSpan(
                        text: '${_fmt(s.y)} $_wLabel',
                        style: AppType.digits(
                          fontSize: 13,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                )
                .toList(),
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: chartData.spots,
            isCurved: true,
            curveSmoothness: 0.3,
            // 避免單調資料間的曲線過衝出現假波峰
            preventCurveOverShooting: true,
            gradient: LinearGradient(
              colors: [Colors.orange.shade300, Colors.deepOrange.shade400],
            ),
            barWidth: 3,
            dotData: FlDotData(
              // 最新一筆（最右）畫大一點，視覺錨點落在「現在」
              getDotPainter: (spot, percent, bar, index) {
                final isLatest = index == chartData.spots.length - 1;
                return FlDotCirclePainter(
                  radius: isLatest ? dotRadius + 1.5 : dotRadius,
                  color: Colors.white,
                  strokeWidth: isLatest ? 2.6 : 2,
                  strokeColor: isLatest
                      ? Colors.deepOrange.shade400
                      : Colors.deepOrange.shade300,
                );
              },
            ),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.orange.withValues(alpha: 0.18),
                  Colors.orange.withValues(alpha: 0.0),
                ],
              ),
            ),
          ),
        ],
        gridData: FlGridData(
          drawVerticalLine: false,
          getDrawingHorizontalLine: (value) => FlLine(
            color: Colors.orange.shade100.withValues(alpha: 0.6),
            strokeWidth: 1,
            dashArray: [4, 4],
          ),
        ),
        extraLinesData: ExtraLinesData(
          horizontalLines: [
            if (targetLine != null)
              HorizontalLine(
                y: targetLine,
                color: Colors.green.shade400,
                strokeWidth: 1.5,
                dashArray: [6, 4],
                label: HorizontalLineLabel(
                  show: true,
                  padding: const EdgeInsets.only(left: 4, bottom: 2),
                  style: TextStyle(
                    fontSize: 10,
                    color: Colors.green.shade600,
                    fontWeight: FontWeight.w600,
                  ),
                  labelResolver: (_) => '目標',
                ),
              ),
          ],
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          leftTitles: const AxisTitles(),
          topTitles: const AxisTitles(),
          rightTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 38,
              interval: yAxis.step,
              getTitlesWidget: (value, meta) {
                if (!_isYAxisTick(value, yAxis)) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: Text(
                    _axisLabel(value, yAxis.step),
                    style: AppType.digits(fontSize: 10, color: AppInk.faint),
                  ),
                );
              },
            ),
          ),
          // 底部標籤由各範圍自行提供；interval 固定 1，
          // 否則 fl_chart 自動取樣會跳過我們想顯示的日期
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 28,
              interval: 1,
              getTitlesWidget: chartData.getBottomTitle,
            ),
          ),
        ),
      ),
    );
  }

  // 範圍切換：segmented 膠囊（選中浮白卡，未選沉在底色裡）
  Widget _rangeSelector() {
    const labels = ['本週', '本月', '三個月'];
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: const Color(0xFFFAF7F2),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(labels.length, (i) {
          final selected = _chartRangeIndex == i;
          return GestureDetector(
            onTap: () {
              if (_chartRangeIndex == i) return;
              playHaptic(HapticLevel.selection);
              setState(() => _chartRangeIndex = i);
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutCubic,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
              decoration: selected
                  ? BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(9),
                      border: AppCardStyle.hairline,
                      boxShadow: AppShadows.flat,
                    )
                  : null,
              child: Text(
                labels[i],
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                  color: selected ? Colors.orange.shade800 : AppInk.soft,
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  ({double min, double max, double step}) _niceYAxis(
    double minValue,
    double maxValue,
  ) {
    final span = math.max(0.1, maxValue - minValue);
    final rawStep = span / 3;
    final exponent = (math.log(rawStep) / math.ln10).floor();
    final magnitude = math.pow(10, exponent).toDouble();
    final normalized = rawStep / magnitude;
    final niceNormalized = normalized <= 1
        ? 1
        : normalized <= 2
        ? 2
        : normalized <= 5
        ? 5
        : 10;
    var step = niceNormalized * magnitude;
    if (_unit == UnitSystem.imperial && step < 1) step = 1;
    if (_unit == UnitSystem.metric && step < 0.5) step = 0.5;

    var min = (minValue / step).floorToDouble() * step;
    var max = (maxValue / step).ceilToDouble() * step;
    if ((max - min).abs() < step) {
      min -= step;
      max += step;
    }
    return (min: min, max: max, step: step.toDouble());
  }

  bool _isYAxisTick(
    double value,
    ({double min, double max, double step}) axis,
  ) {
    const eps = 0.001;
    if (value < axis.min - eps || value > axis.max + eps) return false;
    final n = ((value - axis.min) / axis.step).roundToDouble();
    return ((axis.min + n * axis.step) - value).abs() < eps;
  }

  String _axisLabel(double value, double step) {
    final decimals = step < 1 ? 1 : 0;
    return _fmt(value, decimal: decimals);
  }

  Widget _chartCountPill(int count) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFFFAF7F2),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        '$count 筆',
        style: const TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w800,
          color: AppInk.soft,
        ),
      ),
    );
  }

  Widget _chartSummaryRow(_ChartData chartData) {
    final spots = chartData.spots;
    final latest = spots.last.y;
    final first = spots.first.y;
    final diff = latest - first;
    final low = spots.map((s) => s.y).reduce(math.min);
    final high = spots.map((s) => s.y).reduce(math.max);
    final diffColor = diff.abs() < 0.05
        ? AppInk.soft
        : _deltaColor(diff, first);
    final diffIcon = diff.abs() < 0.05
        ? Icons.remove_rounded
        : diff < 0
        ? Icons.south_rounded
        : Icons.north_rounded;

    return Row(
      children: [
        Expanded(
          child: _chartMetricPill(
            label: '最新',
            value: '${_fmt(latest)} $_wLabel',
            icon: Icons.place_rounded,
            color: Colors.deepOrange.shade400,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _chartMetricPill(
            label: '變化',
            value: '${diff >= 0 ? '+' : '-'}${_deltaText(diff)} $_wLabel',
            icon: diffIcon,
            color: diffColor,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _chartMetricPill(
            label: '範圍',
            value: '${_fmt(low)}-${_fmt(high)}',
            icon: Icons.unfold_more_rounded,
            color: const Color(0xFF66BB6A),
          ),
        ),
      ],
    );
  }

  Widget _chartMetricPill({
    required String label,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(13),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                '$label $value',
                maxLines: 1,
                style: AppType.digits(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  color: color,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTodayEmptyCard() {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(AppCardStyle.radius),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppCardStyle.radius),
        onTap: _openAddSheet,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(18, 22, 18, 20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppCardStyle.radius),
            border: AppCardStyle.hairline,
            boxShadow: AppShadows.flat,
          ),
          child: Column(
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.monitor_weight_rounded,
                  color: Colors.orange,
                  size: 28,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                '今天還沒量體重喔',
                style: TextStyle(
                  color: AppInk.strong,
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                '記錄一筆，趨勢圖就會更準',
                style: TextStyle(
                  color: AppInk.soft,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // 今日數據：體重大字 hero + 與上一筆的差值，其餘指標走小格子
  // （BMI/BMR 缺資料時顯示友善提示）
  Widget _buildStatGrid(Map<String, dynamic> rec) {
    final weight = (rec['weight'] as num).toDouble();
    final fat = rec['body_fat'] != null
        ? (rec['body_fat'] as num).toDouble()
        : null;
    final bmi = _calcBMI(weight);
    final bmr = _calcBMR(weight);
    final tdee = _calcTDEE(weight);
    final hintMessages = <String>[
      if (bmi == null || bmr == null) '請至設定補充身高、生日或性別以計算 BMI / BMR',
      if (_activityLevel.isEmpty && bmr != null) '補上每週運動天數，就能估算 TDEE',
    ];
    final bmiCat = bmi == null ? null : _bmiCategory(bmi);
    final delta = _deltaBefore(rec);

    final items = <_StatItem>[
      if (fat != null)
        _StatItem(
          label: '體脂率',
          value: '${_fmt(fat)} %',
          icon: Icons.water_drop_rounded,
          iconColor: const Color(0xFF4FA8C7),
        ),
      if (bmi != null)
        _StatItem(
          label: 'BMI',
          value: _fmt(bmi),
          sub: bmiCat!.$1,
          subColor: bmiCat.$2,
          icon: Icons.monitor_weight_rounded,
          iconColor: const Color(0xFFEF8E4E),
        ),
      if (bmr != null)
        _StatItem(
          label: 'BMR',
          value: '${_fmt(bmr, decimal: 0)} kcal',
          icon: Icons.local_fire_department_rounded,
          iconColor: const Color(0xFFFF7043),
        ),
      if (tdee != null)
        _StatItem(
          label: 'TDEE',
          value: '${_fmt(tdee, decimal: 0)} kcal',
          icon: Icons.bolt_rounded,
          iconColor: const Color(0xFFF2A93B),
        ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── 體重 hero：大數字 + 單位 + 差值膠囊 ──
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              _fmtWeight(weight),
              style: AppType.digits(
                fontSize: 40,
                fontWeight: FontWeight.w800,
                color: AppInk.strong,
              ),
            ),
            const SizedBox(width: 5),
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                _wLabel,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppInk.soft,
                ),
              ),
            ),
            const Spacer(),
            if (delta != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: _DeltaPill(
                  delta: delta,
                  color: _deltaColor(delta, weight - delta),
                  text: _deltaText(delta),
                ),
              ),
          ],
        ),
        if (items.isNotEmpty) ...[
          const SizedBox(height: 12),
          GridView.count(
            crossAxisCount: 2,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            childAspectRatio: 2.45,
            children: items
                .map(
                  (item) => Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFFFAF7F2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    child: Row(
                      children: [
                        // 小圖示泡泡：每個指標一個識別色，掃一眼就分得開
                        Container(
                          width: 30,
                          height: 30,
                          decoration: BoxDecoration(
                            color: item.iconColor.withValues(alpha: 0.13),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            item.icon,
                            size: 16,
                            color: item.iconColor,
                          ),
                        ),
                        const SizedBox(width: 9),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                item.label,
                                style: const TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w600,
                                  color: AppInk.soft,
                                ),
                              ),
                              const SizedBox(height: 1),
                              Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      item.value,
                                      overflow: TextOverflow.ellipsis,
                                      style: AppType.digits(
                                        fontSize: 15.5,
                                        color: AppInk.strong,
                                      ),
                                    ),
                                  ),
                                  if (item.sub != null) ...[
                                    const SizedBox(width: 5),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 1,
                                      ),
                                      decoration: BoxDecoration(
                                        color: item.subColor!.withValues(
                                          alpha: 0.12,
                                        ),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        item.sub!,
                                        style: TextStyle(
                                          fontSize: 10.5,
                                          fontWeight: FontWeight.w700,
                                          color: item.subColor,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                )
                .toList(),
          ),
        ],
        if (hintMessages.isNotEmpty) ...[
          const SizedBox(height: 8),
          ...hintMessages.map(
            (message) => Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Row(
                children: [
                  const Icon(
                    Icons.info_outline,
                    size: 13,
                    color: AppInk.iconFaint,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      message,
                      style: const TextStyle(fontSize: 11, color: AppInk.faint),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  // 歷史紀錄單筆 tile
  // 長按或向左滑動（endToStart）皆呼叫操作選單（編輯／刪除）
  Widget _buildHistoryTile(Map<String, dynamic> rec) {
    final weight = (rec['weight'] as num).toDouble();
    final fat = rec['body_fat'] != null
        ? (rec['body_fat'] as num).toDouble()
        : null;
    final bmi = _calcBMI(weight);
    final date = rec['date'] as String;
    final time = rec['time'] as String;
    final delta = _deltaBefore(rec);

    return Dismissible(
      key: Key(date),
      direction: DismissDirection.endToStart,
      // confirmDismiss 回傳 false：不自動刪除，改由選單確認
      confirmDismiss: (_) async {
        _showRecordActions(rec);
        return false;
      },
      // 左滑時顯示的背景提示（橘底 + 更多圖示）
      background: Container(
        margin: const EdgeInsets.only(bottom: 12),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: Colors.orange.shade50,
          borderRadius: BorderRadius.circular(AppCardStyle.radius),
        ),
        child: Icon(Icons.more_horiz, color: Colors.orange.shade400, size: 26),
      ),
      child: GestureDetector(
        onLongPress: () => _showRecordActions(rec),
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(AppCardStyle.radius),
            border: AppCardStyle.hairline,
            boxShadow: AppShadows.flat,
          ),
          child: Row(
            children: [
              // 日期與時間
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _shortDateLabel(date),
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppInk.strong,
                    ),
                  ),
                  Text(
                    time,
                    style: const TextStyle(fontSize: 11, color: AppInk.faint),
                  ),
                ],
              ),
              const Spacer(),
              // 體重（含與更早一筆的差值）、體脂、BMI
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (delta != null && delta.abs() >= 0.05) ...[
                        Icon(
                          delta < 0 ? Icons.south_rounded : Icons.north_rounded,
                          size: 11,
                          color: _deltaColor(delta, weight - delta),
                        ),
                        Text(
                          _deltaText(delta),
                          style: AppType.digits(
                            fontSize: 11,
                            color: _deltaColor(delta, weight - delta),
                          ),
                        ),
                        const SizedBox(width: 6),
                      ],
                      Text(
                        '${_fmtWeight(weight)} $_wLabel',
                        style: AppType.digits(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: AppInk.strong,
                        ),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      if (fat != null) ...[
                        Text(
                          '體脂 ${_fmt(fat)}%',
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppInk.soft,
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      if (bmi != null)
                        Text(
                          'BMI ${_fmt(bmi)}',
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppInk.soft,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WeightInputCard extends StatelessWidget {
  final String value;
  final String unitLabel;
  final String? errorText;
  final bool active;
  final VoidCallback onTap;
  final VoidCallback onDecrease;
  final VoidCallback onIncrease;

  const _WeightInputCard({
    required this.value,
    required this.unitLabel,
    required this.errorText,
    required this.active,
    required this.onTap,
    required this.onDecrease,
    required this.onIncrease,
  });

  @override
  Widget build(BuildContext context) {
    final hasError = errorText != null;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFCF8),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: hasError
              ? Colors.red.shade300
              : active
              ? Colors.orange.withValues(alpha: 0.46)
              : const Color(0x0A46342B),
          width: active || hasError ? 1.4 : 1,
        ),
        boxShadow: AppShadows.flat,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _NumericDisplayBox(
                  label: '體重',
                  value: value,
                  suffix: unitLabel,
                  active: active,
                  color: Colors.orange,
                  placeholder: '輸入體重',
                  onTap: onTap,
                ),
              ),
              const SizedBox(width: 10),
              Column(
                children: [
                  // 點一下 ±一格，按住連發加速（HoldRepeatButton）
                  HoldRepeatButton(
                    onTrigger: onIncrease,
                    child: const _SheetRoundButton(
                      icon: Icons.add_rounded,
                      color: Colors.orange,
                    ),
                  ),
                  const SizedBox(height: 8),
                  HoldRepeatButton(
                    onTrigger: onDecrease,
                    child: const _SheetRoundButton(
                      icon: Icons.remove_rounded,
                      color: Colors.orange,
                    ),
                  ),
                ],
              ),
            ],
          ),
          if (hasError) ...[
            const SizedBox(height: 6),
            Text(
              errorText!,
              style: TextStyle(
                color: Colors.red.shade700,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _BodyFatInputCard extends StatelessWidget {
  final String value;
  final String? errorText;
  final bool active;
  final VoidCallback onTap;

  const _BodyFatInputCard({
    required this.value,
    required this.errorText,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final hasError = errorText != null;
    const accent = Color(0xFF4FA8C7);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFCF8),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: hasError
              ? Colors.red.shade300
              : active
              ? accent.withValues(alpha: 0.46)
              : const Color(0x0A46342B),
          width: active || hasError ? 1.4 : 1,
        ),
        boxShadow: AppShadows.flat,
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(13),
            ),
            child: const Icon(
              Icons.water_drop_rounded,
              color: accent,
              size: 19,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _NumericDisplayBox(
                  label: '體脂率（選填）',
                  value: value,
                  suffix: '%',
                  active: active,
                  color: accent,
                  placeholder: '未輸入',
                  onTap: onTap,
                ),
                if (hasError) ...[
                  const SizedBox(height: 6),
                  Text(
                    errorText!,
                    style: TextStyle(
                      color: Colors.red.shade700,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NumericDisplayBox extends StatelessWidget {
  final String label;
  final String value;
  final String suffix;
  final bool active;
  final Color color;
  final String placeholder;
  final VoidCallback onTap;

  const _NumericDisplayBox({
    required this.label,
    required this.value,
    required this.suffix,
    required this.active,
    required this.color,
    required this.placeholder,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final hasValue = value.trim().isNotEmpty;
    return Material(
      color: active ? color.withValues(alpha: 0.08) : Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: active
                  ? color.withValues(alpha: 0.34)
                  : const Color(0x0A46342B),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  color: active ? color : AppInk.soft,
                ),
              ),
              const SizedBox(height: 3),
              // 固定高度：空值（小字）與有值（大字）行高不同，固定住才不會
              // 一輸入數字格子就變高（體脂率輸入時尤其明顯）。
              SizedBox(
                height: 34,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Text(
                        hasValue ? value : placeholder,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: hasValue
                            ? AppType.digits(
                                fontSize: 28,
                                fontWeight: FontWeight.w900,
                                color: AppInk.strong,
                              )
                            : const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                                color: AppInk.faint,
                              ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 3),
                      child: Text(
                        suffix,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: AppInk.soft,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WeightSheetKeypad extends StatelessWidget {
  final bool decimalEnabled;
  final void Function(String digit) onDigit;
  final VoidCallback onDecimal;
  final VoidCallback onBackspace;
  final VoidCallback onClear;

  const _WeightSheetKeypad({
    required this.decimalEnabled,
    required this.onDigit,
    required this.onDecimal,
    required this.onBackspace,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(7),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7EC),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.orange.withValues(alpha: 0.12)),
      ),
      child: Column(
        children: [
          for (final row in const [
            ['1', '2', '3'],
            ['4', '5', '6'],
            ['7', '8', '9'],
          ])
            Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: Row(
                children: [
                  for (final digit in row) ...[
                    Expanded(
                      child: _WeightKeyButton(
                        label: digit,
                        onTap: () => onDigit(digit),
                      ),
                    ),
                    if (digit != row.last) const SizedBox(width: 5),
                  ],
                ],
              ),
            ),
          Row(
            children: [
              Expanded(
                child: _WeightKeyButton(
                  label: 'C',
                  onTap: onClear,
                  muted: true,
                ),
              ),
              const SizedBox(width: 5),
              Expanded(
                child: _WeightKeyButton(label: '0', onTap: () => onDigit('0')),
              ),
              const SizedBox(width: 5),
              Expanded(
                child: _WeightKeyButton(
                  label: '.',
                  onTap: decimalEnabled ? onDecimal : null,
                  muted: true,
                ),
              ),
              const SizedBox(width: 5),
              Expanded(
                child: _WeightKeyButton(
                  icon: Icons.backspace_outlined,
                  onTap: onBackspace,
                  muted: true,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _WeightKeyButton extends StatelessWidget {
  final String? label;
  final IconData? icon;
  final VoidCallback? onTap;
  final bool muted;

  const _WeightKeyButton({
    this.label,
    this.icon,
    required this.onTap,
    this.muted = false,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final fg = enabled
        ? muted
              ? AppInk.soft
              : AppInk.strong
        : AppInk.faint;
    final bg = enabled
        ? muted
              ? const Color(0xFFFFFCF8)
              : Colors.white
        : const Color(0xFFF2E9E1);
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(13),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(13),
        splashColor: Colors.orange.withValues(alpha: 0.10),
        highlightColor: Colors.orange.withValues(alpha: 0.06),
        child: Ink(
          height: 40,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(13),
            border: Border.all(
              color: enabled
                  ? Colors.orange.withValues(alpha: muted ? 0.08 : 0.13)
                  : const Color(0x0A46342B),
            ),
            boxShadow: enabled && !muted ? AppShadows.flat : null,
          ),
          child: Center(
            child: icon != null
                ? Icon(icon, size: 18, color: fg)
                : Text(
                    label!,
                    style: AppType.digits(
                      fontSize: muted ? 17 : 20,
                      fontWeight: FontWeight.w900,
                      color: fg,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

class _SheetSaveButton extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;

  const _SheetSaveButton({required this.label, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: Colors.orange,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          elevation: 0,
        ),
        icon: const Icon(Icons.check_rounded, size: 19),
        label: Text(label, style: const TextStyle(fontWeight: FontWeight.w900)),
      ),
    );
  }
}

class _SheetRoundButton extends StatelessWidget {
  final IconData icon;
  final Color color;

  const _SheetRoundButton({required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    // 純外觀；點擊與長按連發由外層 HoldRepeatButton 處理
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        shape: BoxShape.circle,
      ),
      child: Icon(icon, size: 20, color: color),
    );
  }
}

class _TodayActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  const _TodayActionButton({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          splashColor: Colors.white.withValues(alpha: 0.16),
          highlightColor: Colors.white.withValues(alpha: 0.08),
          child: Ink(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.orange.shade400, Colors.deepOrange.shade400],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(
                  color: Colors.orange.withValues(alpha: 0.24),
                  blurRadius: 14,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.20),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, size: 17, color: Colors.white),
                ),
                const SizedBox(width: 10),
                Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// 圖表資料封裝（各範圍的資料點與 X 軸標籤邏輯）
class _ChartData {
  final List<FlSpot> spots;
  final double minX;
  final double maxX;
  final Widget Function(double, TitleMeta) getBottomTitle;
  // 觸控 tooltip 的日期標籤（x 值 → 人看的日期字串）
  final String Function(double x) xLabel;

  const _ChartData({
    required this.spots,
    required this.minX,
    required this.maxX,
    required this.getBottomTitle,
    required this.xLabel,
  });
}

// 今日數據卡片的格子資料模型
class _StatItem {
  final String label;
  final String value;
  final String? sub; // 數值旁的小標籤（例：BMI 分類）
  final Color? subColor;
  final IconData icon;
  final Color iconColor;
  const _StatItem({
    required this.label,
    required this.value,
    required this.icon,
    required this.iconColor,
    this.sub,
    this.subColor,
  });
}

// 差值膠囊：箭頭 + 數字（今日 hero 用；持平時顯示 — ）
class _DeltaPill extends StatelessWidget {
  final double delta;
  final Color color;
  final String text;
  const _DeltaPill({
    required this.delta,
    required this.color,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    final flat = delta.abs() < 0.05;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            flat
                ? Icons.remove_rounded
                : delta < 0
                ? Icons.south_rounded
                : Icons.north_rounded,
            size: 12,
            color: color,
          ),
          const SizedBox(width: 2),
          Text(text, style: AppType.digits(color: color)),
        ],
      ),
    );
  }
}

// 漸層進度條 + 尾端白心亮點：首頁進度列的靜態版（目標卡用）。
// 之後喝水頁也要用的話再抽到共用 widget。
class _GradientProgressBar extends StatelessWidget {
  final double value;
  final Color accent;
  const _GradientProgressBar({required this.value, required this.accent});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 14,
      child: LayoutBuilder(
        builder: (_, constraints) {
          final w = constraints.maxWidth;
          final x = (w * value).clamp(0.0, w);
          return Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.centerLeft,
            children: [
              Container(
                height: 6,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              Container(
                height: 6,
                width: x,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [accent.withValues(alpha: 0.72), accent],
                  ),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              if (value > 0.03)
                Positioned(
                  left: (x - 5).clamp(0.0, w - 10),
                  child: Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      border: Border.all(color: accent, width: 2.5),
                      boxShadow: [
                        BoxShadow(
                          color: accent.withValues(alpha: 0.35),
                          blurRadius: 4,
                          spreadRadius: 0.5,
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
