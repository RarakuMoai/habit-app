// 首頁（每日／每週習慣打卡 + 兔咪場景）。
// 其餘部分拆在 home/：習慣卡片、新增／編輯 bottom sheet、preset 定義、
// 問候橫幅、共用小元件與場景 painter。
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/app_feedback.dart';
import '../utils/app_style.dart';
import '../utils/coin_config.dart';
import '../utils/coin_service.dart';
import '../utils/input_formatters.dart';
import '../utils/mascot.dart';
import '../utils/prefs_keys.dart';
import '../utils/sfx_service.dart';
import '../widgets/habit_ui.dart';
import '../widgets/mascot_app_bar.dart';
import '../widgets/mascot_page_shell.dart';
import '../widgets/mascot_scene.dart';
import 'home/greeting_banner.dart';
import 'home/habit_card.dart';
import 'home/habit_sheets.dart';
import 'home/home_presets.dart';
import 'home/room_scene_painters.dart';

class HomePage extends StatefulWidget {
  final VoidCallback? onSettingsChanged;
  final bool waterHabitAutoComplete;
  final Future<void> Function(bool)? onWaterHabitToggled;
  const HomePage({
    super.key,
    this.onSettingsChanged,
    this.waterHabitAutoComplete = false,
    this.onWaterHabitToggled,
  });

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with TickerProviderStateMixin {
  final List<Map<String, dynamic>> habits = [];
  bool isLoading = true;
  int streak = 0;
  String _nickname = '你';
  String mascotName0 = '兔咪';
  bool yesterdayAllDone = false;
  DateTime? onboardingDate;

  // 兔咪近期採 CG/PNG 差分 + Flutter 輕量演出，不以 Rive 作為近期主線。

  late AnimationController _celebCtrl;
  late Animation<double> _celebScale;
  // 進度列尾端亮點的呼吸光暈（達標時 repeat，未達標停在 0）
  late AnimationController _glowCtrl;

  final Set<String> _animatedIn = {};

  @override
  void initState() {
    super.initState();
    _celebCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _celebScale = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.05), weight: 50),
      TweenSequenceItem(tween: Tween(begin: 1.05, end: 1.0), weight: 50),
    ]).animate(_celebCtrl);
    _glowCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );

    loadHabits();
  }

  @override
  void dispose() {
    _celebCtrl.dispose();
    _glowCtrl.dispose();
    super.dispose();
  }

  Future<void> loadHabits() async {
    final prefs = await SharedPreferences.getInstance();
    final today = todayString();
    final lastOpen = prefs.getString(PrefsKeys.lastOpenDate);
    streak = prefs.getInt(PrefsKeys.streak) ?? 0;
    _nickname = prefs.getString(PrefsKeys.userNickname) ?? '你';
    mascotName0 = prefs.getString(PrefsKeys.mascotName) ?? '兔咪';

    final obDateStr = prefs.getString(PrefsKeys.onboardingDate);
    if (obDateStr != null) {
      onboardingDate = DateTime.tryParse(obDateStr);
    } else {
      onboardingDate = DateTime.now();
      await prefs.setString(
        PrefsKeys.onboardingDate,
        onboardingDate!.toIso8601String(),
      );
    }

    final habitsJson = prefs.getString(PrefsKeys.habits);
    if (habitsJson != null) {
      final decoded = jsonDecode(habitsJson) as List<dynamic>;
      habits.addAll(decoded.map((e) => Map<String, dynamic>.from(e as Map)));
    }

    if (lastOpen != null && lastOpen != today) {
      final dailyHabits = habits
          .where((h) => (h['frequency'] ?? 'daily') != 'weekly')
          .toList();
      final allDailyDone =
          dailyHabits.isNotEmpty && dailyHabits.every((h) => h['done'] == true);
      yesterdayAllDone = allDailyDone;
      if (dailyHabits.isNotEmpty) {
        if (allDailyDone) {
          streak++;
          // 連續達標每滿 7 天發里程碑獎勵（每日一次 key 防重複）
          if (streak % 7 == 0) {
            await CoinService.award(
              CoinSource.weeklyStreak,
              note: '連續 $streak 天',
            );
          }
        } else {
          streak = 0;
        }
        await prefs.setInt(PrefsKeys.streak, streak);
      }
      for (final habit in habits) {
        if ((habit['frequency'] ?? 'daily') != 'weekly') {
          habit['done'] = false;
        }
      }
      await prefs.setString(PrefsKeys.habits, jsonEncode(habits));
    }

    // Always recompute done for weekly habits from weeklyDates
    for (final habit in habits) {
      if ((habit['frequency'] ?? 'daily') == 'weekly') {
        final target = (habit['weeklyTarget'] as int?) ?? 3;
        habit['done'] = _weeklyCount(habit) >= target;
      }
    }

    // 跨頁籤切換時首頁會整頁重建，didUpdateWidget 不會觸發，
    // 因此在這裡依喝水頁達標狀態同步「喝足夠的水」習慣的勾選狀態
    final waterIdx = habits.indexWhere((h) => h['name'] == '喝足夠的水');
    if (waterIdx != -1 &&
        habits[waterIdx]['done'] != widget.waterHabitAutoComplete) {
      habits[waterIdx]['done'] = widget.waterHabitAutoComplete;
      await prefs.setString(PrefsKeys.habits, jsonEncode(habits));
    }

    final isFirstOpenToday = lastOpen != today;
    await prefs.setString(PrefsKeys.lastOpenDate, today);
    setState(() => isLoading = false);

    if (isFirstOpenToday && mounted) {
      Future.delayed(const Duration(milliseconds: 400), () {
        if (mounted) showGreeting(prefs, lastOpen);
      });
    }
  }

  void showGreeting(SharedPreferences prefs, String? lastOpen) {
    showGreetingBanner(buildGreetingMessage(lastOpen));
  }

  String buildGreetingMessage(String? lastOpen) {
    if (lastOpen != null) {
      final parts = lastOpen.split('-');
      if (parts.length == 3) {
        final lastDate = DateTime.tryParse(
          '${parts[0]}-${parts[1].padLeft(2, '0')}-${parts[2].padLeft(2, '0')}',
        );
        if (lastDate != null &&
            DateTime.now().difference(lastDate).inDays >= 2) {
          return '你回來了。\n我還在。';
        }
      }
    }
    if (streak >= 7) return '連續一週了。\n你一直有回來。';
    if (yesterdayAllDone) return '昨天也完成了。\n兔咪有看到。';
    if (onboardingDate != null) {
      final daysSince = DateTime.now().difference(onboardingDate!).inDays + 1;
      if (daysSince <= 3) return '第$daysSince天。\n我們慢慢熟起來了。';
    }
    return '早安，$_nickname。\n今天也從一點點開始？';
  }

  void showGreetingBanner(String message) {
    final overlay = Overlay.of(context);
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => GreetingBanner(
        mascotName: mascotName0,
        message: message,
        onDismiss: () => entry.remove(),
      ),
    );
    overlay.insert(entry);
    Future.delayed(const Duration(seconds: 2), () {
      if (entry.mounted) entry.remove();
    });
  }

  String _fmtDate(DateTime d) {
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '${d.year}-$m-$day';
  }

  String todayString() => _fmtDate(DateTime.now());

  List<String> _currentWeekStrings() {
    final now = DateTime.now();
    final monday = now.subtract(Duration(days: now.weekday - 1));
    return List.generate(7, (i) => _fmtDate(monday.add(Duration(days: i))));
  }

  int _weeklyCount(Map<String, dynamic> habit) {
    final dates = List<String>.from((habit['weeklyDates'] as List?) ?? []);
    final weekSet = _currentWeekStrings().toSet();
    return dates.where(weekSet.contains).length;
  }

  Future<void> saveHabits() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(PrefsKeys.habits, jsonEncode(habits));
  }

  @override
  void didUpdateWidget(HomePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.waterHabitAutoComplete != widget.waterHabitAutoComplete) {
      _syncWaterHabit(widget.waterHabitAutoComplete);
    }
  }

  void _syncWaterHabit(bool done) {
    final idx = habits.indexWhere((h) => h['name'] == '喝足夠的水');
    if (idx == -1 || habits[idx]['done'] == done) return;
    setState(() => habits[idx]['done'] = done);
    saveHabits();
  }

  List<Map<String, dynamic>> get _dailyHabits =>
      habits.where((h) => (h['frequency'] ?? 'daily') != 'weekly').toList();

  List<Map<String, dynamic>> get _weeklyHabits =>
      habits.where((h) => (h['frequency'] ?? 'daily') == 'weekly').toList();

  int get dailyDoneCount => _dailyHabits.where((h) => h['done'] == true).length;
  int get weeklyMetCount =>
      _weeklyHabits.where((h) => h['done'] == true).length;

  int get doneCount {
    final weekSet = _currentWeekStrings().toSet();
    return habits.where((h) {
      if ((h['frequency'] ?? 'daily') == 'weekly') {
        final target = (h['weeklyTarget'] as int?) ?? 3;
        final dates = List<String>.from((h['weeklyDates'] as List?) ?? []);
        return dates.where(weekSet.contains).length >= target;
      }
      return h['done'] == true;
    }).length;
  }

  // 只有每日習慣全完成才算「全部完成」，每週習慣不影響
  bool get allDone0 => _dailyHabits.isNotEmpty
      ? dailyDoneCount == _dailyHabits.length
      : habits.isNotEmpty && weeklyMetCount == _weeklyHabits.length;

  // 兔咪短暫情緒：撤銷打卡後 2 秒顯示 sad
  String? _transientMascot;
  // 對話泡泡內的文字（點兔咪時暫時覆蓋）
  String? _transientSpeech;
  int _mascotReactionTick = 0;

  void _showTransientMascot(
    String name, {
    Duration duration = const Duration(seconds: 2),
  }) {
    setState(() {
      _transientMascot = name;
      _mascotReactionTick++;
    });
    _syncMascotToPersona();
    Future.delayed(duration, () {
      if (mounted) {
        setState(() => _transientMascot = null);
        _syncMascotToPersona();
      }
    });
  }

  void _onMascotTap() {
    _celebCtrl.forward(from: 0);
    final speech = MascotLines.randomLineFor(MascotContext.tapReaction);
    setState(() {
      _transientSpeech = speech;
      _mascotReactionTick++;
    });
    final accepted = _syncMascotToPersona();
    if (accepted) {
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) {
          setState(() => _transientSpeech = null);
          _syncMascotToPersona();
        }
      });
    } else {
      setState(() => _transientSpeech = null);
    }
  }

  // 兔咪圖選擇器（按進度、時間、streak 決定）。
  // 透過 [MascotEmotion.assetPath] 取，會自動走 _migratedToCG 的新/舊圖路由。
  String get _mascotAsset {
    if (_transientMascot != null) {
      final emo = MascotEmotion.values.firstWhere(
        (e) => e.assetKey == _transientMascot,
        orElse: () => MascotEmotion.neutralFront,
      );
      return emo.assetPath;
    }
    if (habits.isEmpty) return MascotEmotion.neutralFront.assetPath;

    final ref = _dailyHabits.isNotEmpty ? _dailyHabits : _weeklyHabits;
    final done = _dailyHabits.isNotEmpty ? dailyDoneCount : weeklyMetCount;
    final ratio = done / ref.length;

    if (ratio == 1.0) {
      return streak >= 7
          ? MascotEmotion.streak.assetPath
          : MascotEmotion.happy.assetPath;
    }
    if (ratio >= 0.5) return MascotEmotion.smile.assetPath;
    if (ratio > 0) return MascotEmotion.expect.assetPath;

    final hour = DateTime.now().hour;
    return hour >= 22 || hour < 6
        ? MascotEmotion.night.assetPath
        : MascotEmotion.sleep.assetPath;
  }

  MascotContext get _mascotContext {
    if (_transientMascot == 'sad') return MascotContext.undone;
    if (_transientSpeech != null) return MascotContext.tapReaction;
    if (habits.isEmpty) return MascotContext.emptyHabits;

    final ref = _dailyHabits.isNotEmpty ? _dailyHabits : _weeklyHabits;
    final done = _dailyHabits.isNotEmpty ? dailyDoneCount : weeklyMetCount;
    final ratio = done / ref.length;
    if (ratio == 1.0) {
      return streak >= 7 ? MascotContext.streak : MascotContext.allDone;
    }
    if (ratio >= 0.5) return MascotContext.halfDone;
    if (ratio > 0) return MascotContext.completedOne;

    final hour = DateTime.now().hour;
    if (hour >= 22 || hour < 6) return MascotContext.night;
    return MascotContext.notStarted;
  }

  void toggleHabit(int index) {
    final wasAllDone = allDone0;
    final habit = habits[index];
    final wasHabitDone = habit['done'] == true;
    final isWeekly = (habit['frequency'] ?? 'daily') == 'weekly';
    if (isWeekly) {
      final today = todayString();
      final dates = List<String>.from((habit['weeklyDates'] as List?) ?? []);
      final target = (habit['weeklyTarget'] as int?) ?? 3;
      final weekSet = _currentWeekStrings().toSet();
      if (dates.where(weekSet.contains).length >= 20) return; // 上限 20 次/週
      dates.add(today);
      setState(() {
        habit['weeklyDates'] = dates;
        habit['done'] = dates.where(weekSet.contains).length >= target;
      });
      // 每週習慣每次累加都是一次打卡（減少時對稱扣回，刷不了幣）
      CoinService.award(CoinSource.habitDone, note: habit['name'] as String?);
    } else {
      final wasDone = habit['done'] as bool;
      setState(() {
        habit['done'] = !wasDone;
      });
      if (wasDone) _showTransientMascot('sad');
      // 打卡 +金幣／取消打卡對稱扣回
      if (wasDone) {
        CoinService.revoke(CoinSource.habitDone, note: habit['name'] as String?);
      } else {
        CoinService.award(CoinSource.habitDone, note: habit['name'] as String?);
      }
    }
    saveHabits();
    if (!wasAllDone && allDone0) {
      // 當日全完成加碼（每日一次，service 內建防重複）
      CoinService.award(CoinSource.allHabitsDone, note: '今日全完成');
      playFeedback(SfxCue.complete);
      _celebCtrl.forward(from: 0);
      setState(() => _mascotReactionTick++);
    } else if (habits[index]['done'] == true) {
      if (!wasHabitDone) {
        playFeedback(SfxCue.success);
      } else {
        playFeedback(SfxCue.tap);
      }
      setState(() => _mascotReactionTick++);
    } else if (isWeekly) {
      // 每週習慣累加但還沒達標：是正向操作，給 tap 不給 cancel
      playFeedback(SfxCue.tap);
      setState(() => _mascotReactionTick++);
    } else {
      playFeedback(SfxCue.cancel);
    }
    if (habits[index]['name'] == '喝足夠的水') {
      widget.onWaterHabitToggled?.call(habits[index]['done'] as bool);
    }
    _syncMascotToPersona();
  }

  void decrementWeeklyHabit(int index) {
    final habit = habits[index];
    final today = todayString();
    final dates = List<String>.from((habit['weeklyDates'] as List?) ?? []);
    final lastIdx = dates.lastIndexOf(today);
    if (lastIdx == -1) return;
    dates.removeAt(lastIdx);
    final target = (habit['weeklyTarget'] as int?) ?? 3;
    final weekSet = _currentWeekStrings().toSet();
    setState(() {
      habit['weeklyDates'] = dates;
      habit['done'] = dates.where(weekSet.contains).length >= target;
    });
    // 對稱扣回（對應 toggleHabit 的每週累加 +金幣）
    CoinService.revoke(CoinSource.habitDone, note: habit['name'] as String?);
    saveHabits();
    playFeedback(SfxCue.cancel);
    _showTransientMascot('sad');
  }

  void deleteHabit(int index) {
    final name = habits[index]['name'] as String;
    _animatedIn.remove(name);
    setState(() => habits.removeAt(index));
    saveHabits();
    if (name == '喝足夠的水') {
      SharedPreferences.getInstance().then((prefs) async {
        await prefs.setBool(PrefsKeys.waterEnabled, false);
        widget.onSettingsChanged?.call();
      });
    }
  }

  Future<void> renameHabit(int index) async {
    final ctrl = TextEditingController(text: habits[index]['name'] as String);
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('改名'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLength: kHabitNameMaxLength,
          decoration: const InputDecoration(labelText: '習慣名稱'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('取消', style: TextStyle(color: Colors.grey.shade600)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('儲存'),
          ),
        ],
      ),
    );
    if (result != true) return;
    final name = clampHabitName(ctrl.text);
    if (name.isEmpty) return;
    setState(() => habits[index]['name'] = name);
    unawaited(saveHabits());
  }

  Future<void> _confirmDeleteHabit(int index) async {
    final name = habits[index]['name'] as String;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('刪除習慣'),
        content: Text('確定要刪除「$name」嗎？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('取消', style: TextStyle(color: Colors.grey.shade600)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('刪除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirm == true) deleteHabit(index);
  }

  Future<void> _editHabitSheet(int index) async {
    await showEditHabitSheet(
      context,
      habit: habits[index],
      onSave: (newName, freq, weeklyTarget) {
        setState(() {
          habits[index]['name'] = newName;
          habits[index]['frequency'] = freq;
          if (freq == 'weekly') {
            habits[index]['weeklyTarget'] = weeklyTarget;
            habits[index].putIfAbsent('weeklyDates', () => <String>[]);
          } else {
            habits[index].remove('weeklyTarget');
            habits[index].remove('weeklyDates');
            habits[index]['done'] = false;
          }
        });
        saveHabits();
      },
    );
  }

  Future<void> _showAddHabitSheet() async {
    final existing = habits.map((h) => h['name'] as String).toSet();
    final available = kHomePresets.where((p) {
      if (p.defaultMinutes != null) {
        return !existing.any((n) => n == p.name || n.startsWith('${p.name} '));
      }
      return !existing.contains(p.name);
    }).toList();
    await showAddHabitSheet(
      context,
      available: available,
      onConfirm:
          (customName, customMinutes, freq, weeklyTarget, selected) async {
            var settingsChanged = false;
            final prefs = await SharedPreferences.getInstance();
            for (final name in selected.keys) {
              final idx = available.indexWhere((p) => p.name == name);
              if (idx != -1 && available[idx].linkedSetting != null) {
                final already =
                    prefs.getBool(available[idx].linkedSetting!) ?? false;
                if (!already) {
                  await prefs.setBool(available[idx].linkedSetting!, true);
                  settingsChanged = true;
                }
              }
            }
            if (settingsChanged) {
              widget.onSettingsChanged?.call();
            }
            setState(() {
              if (customName.isNotEmpty) {
                final fullName = customMinutes > 0
                    ? '$customName $customMinutes 分鐘'
                    : customName;
                final map = <String, dynamic>{
                  'name': fullName,
                  'done': false,
                  'frequency': freq,
                };
                if (freq == 'weekly') {
                  map['weeklyTarget'] = weeklyTarget;
                  map['weeklyDates'] = <String>[];
                }
                habits.add(map);
              }
              for (final entry in selected.entries) {
                final p = available.firstWhere((p) => p.name == entry.key);
                final cfg = entry.value;
                final habitName = (p.defaultMinutes != null && cfg.minutes > 0)
                    ? '${p.name} ${cfg.minutes} 分鐘'
                    : p.name;
                final map = <String, dynamic>{
                  'name': habitName,
                  'done': false,
                  'frequency': cfg.frequency,
                };
                if (cfg.frequency == 'weekly') {
                  map['weeklyTarget'] = cfg.weeklyTarget;
                  map['weeklyDates'] = <String>[];
                }
                habits.add(map);
              }
            });
            unawaited(saveHabits());
          },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final colors = _sceneColors;
    final sceneProgress = habits.isEmpty ? 0.0 : doneCount / habits.length;
    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: Colors.transparent,
      appBar: MascotAppBar(
        accent: colors.accent,
        onSettingsReturn: () => widget.onSettingsChanged?.call(),
        extraActions: [
          if (streak > 0)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Center(
                child: MascotPill(
                  icon: Icons.local_fire_department_rounded,
                  label: '$streak 天',
                  color: Colors.orange.shade600,
                ),
              ),
            ),
        ],
      ),
      body: AnimatedContainer(
        duration: const Duration(milliseconds: 600),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [colors.top, colors.bottom],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Stack(
          children: [
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: MediaQuery.of(context).size.height * 0.56,
              child: ClipRect(
                child: Align(
                  alignment: Alignment.topCenter,
                  child: Image.asset(
                    'assets/scenes/home/home_bg.png',
                    height: double.infinity,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    alignment: Alignment.topCenter,
                  ),
                ),
              ),
            ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: MediaQuery.of(context).size.height * 0.56,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 600),
                color: _sceneTint,
              ),
            ),
            // 概念版：房間下緣融入地面色（原本由白色面板蓋住的接縫）
            Positioned(
              top: MediaQuery.of(context).size.height * 0.56 - 130,
              left: 0,
              right: 0,
              height: 132,
              child: IgnorePointer(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 600),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        colors.bottom.withValues(alpha: 0.0),
                        colors.bottom.withValues(alpha: 0.55),
                        colors.bottom,
                      ],
                      stops: const [0.0, 0.62, 1.0],
                    ),
                  ),
                ),
              ),
            ),
            // 互動狀態效果（完成星光、連續天數獎盃）
            Positioned.fill(
              child: CustomPaint(
                painter: RoomSceneEffectsPainter(
                  accent: colors.accent,
                  progress: sceneProgress.clamp(0.0, 1.0),
                  allDone: allDone0 && habits.isNotEmpty,
                  streak: streak,
                ),
              ),
            ),
            // 內容（概念版：小徑世界，無面板）
            SafeArea(child: _buildPathWorld()),
          ],
        ),
      ),
    );
  }

  // ── 概念版「兔咪的小徑」：整頁就是世界，習慣是小徑上的石頭 ──
  Widget _buildPathWorld() {
    final colors = _sceneColors;
    final w = MediaQuery.of(context).size.width;
    final entries = habits.asMap().entries.toList();
    const headerH = 270.0;
    const stepH = 104.0;
    final contentH = headerH + entries.length * stepH + 170;

    // 石頭節點座標（左右交錯），painter 與石頭共用
    final nodes = <Offset>[
      for (var i = 0; i < entries.length; i++)
        Offset(w * (i.isEven ? 0.28 : 0.72), headerH + 46 + i * stepH),
    ];
    final addPos = Offset(
      w * (entries.length.isEven ? 0.28 : 0.72),
      headerH + 46 + entries.length * stepH,
    );

    return SingleChildScrollView(
      physics: const ClampingScrollPhysics(),
      child: SizedBox(
        height: contentH,
        width: double.infinity,
        child: Stack(
          children: [
            // 小徑（最底層）
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _TrailPainter(
                    accent: colors.accent,
                    start: Offset(w * 0.5, headerH - 34),
                    nodes: [...nodes, addPos],
                  ),
                ),
              ),
            ),
            // 兔咪 + 對話框
            SizedBox(
              height: headerH,
              width: double.infinity,
              child: PersonaScene(
                accent: colors.accent,
                reactionTick: _mascotReactionTick,
                onTap: _onMascotTap,
              ),
            ),
            // 習慣石
            for (var i = 0; i < entries.length; i++)
              ..._stoneNode(entries[i].key, entries[i].value, nodes[i], w),
            ..._addStone(addPos, w),
          ],
        ),
      ),
    );
  }

  // 一顆習慣石 + 名字牌（回傳兩個 Positioned）
  List<Widget> _stoneNode(
    int index,
    Map<String, dynamic> habit,
    Offset pos,
    double w,
  ) {
    final isWeekly = (habit['frequency'] ?? 'daily') == 'weekly';
    final done = habit['done'] == true;
    final name = habit['name'] as String;
    final weeklyCount = _weeklyCount(habit);
    final weeklyTarget = (habit['weeklyTarget'] as int?) ?? 3;
    final size = done ? 40.0 : 58.0;
    final leftSide = pos.dx < w / 2;

    void onTap() => toggleHabit(index);
    void onLong() => _editHabitSheet(index);

    final stone = GestureDetector(
      onTap: onTap,
      onLongPress: onLong,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: done
              ? LinearGradient(
                  colors: [Colors.green.shade400, Colors.green.shade500],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
              : null,
          color: done ? null : Colors.white,
          border: done
              ? null
              : Border.all(color: const Color(0xFFDDD0C4), width: 2),
          boxShadow: done
              ? [
                  BoxShadow(
                    color: Colors.green.withValues(alpha: 0.30),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ]
              : AppShadows.card,
        ),
        child: Center(
          child: done
              ? const Icon(Icons.check_rounded, color: Colors.white, size: 22)
              : isWeekly
              ? Text(
                  '$weeklyCount/$weeklyTarget',
                  style: AppType.digits(
                    color: Colors.indigo.shade400,
                    fontWeight: FontWeight.w800,
                  ),
                )
              : Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.orange.withValues(alpha: 0.22),
                  ),
                ),
        ),
      ),
    );

    final pill = GestureDetector(
      onTap: onTap,
      onLongPress: onLong,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 320),
        constraints: BoxConstraints(maxWidth: w * 0.44),
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: done ? 0.55 : 0.95),
          borderRadius: BorderRadius.circular(16),
          boxShadow: done ? null : AppShadows.flat,
        ),
        child: Text(
          name,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: done ? 12.5 : 14.5,
            height: 1.25,
            fontWeight: FontWeight.w600,
            decoration: done ? TextDecoration.lineThrough : null,
            decorationColor: AppInk.faint,
            color: done ? AppInk.faint : AppInk.strong,
          ),
        ),
      ),
    );

    return [
      Positioned(
        left: pos.dx - size / 2,
        top: pos.dy - size / 2,
        child: stone,
      ),
      Positioned(
        top: pos.dy - 19,
        left: leftSide ? pos.dx + size / 2 + 10 : null,
        right: leftSide ? null : w - pos.dx + size / 2 + 10,
        child: pill,
      ),
    ];
  }

  // 路徑盡頭的「+」幽靈石
  List<Widget> _addStone(Offset pos, double w) {
    final leftSide = pos.dx < w / 2;
    return [
      Positioned(
        left: pos.dx - 24,
        top: pos.dy - 24,
        child: GestureDetector(
          onTap: _showAddHabitSheet,
          child: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: 0.55),
              border: Border.all(
                color: Colors.orange.withValues(alpha: 0.40),
                width: 1.6,
              ),
            ),
            child: Icon(
              Icons.add_rounded,
              color: Colors.orange.shade400,
              size: 24,
            ),
          ),
        ),
      ),
      Positioned(
        top: pos.dy - 14,
        left: leftSide ? pos.dx + 34 : null,
        right: leftSide ? null : w - pos.dx + 34,
        child: GestureDetector(
          onTap: _showAddHabitSheet,
          child: Text(
            '新增習慣',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Colors.orange.withValues(alpha: 0.75),
            ),
          ),
        ),
      ),
    ];
  }

  Widget _buildMascotScene() {
    final colors = _sceneColors;
    final dl = _dailyHabits;
    final displayDone = dl.isNotEmpty ? dailyDoneCount : weeklyMetCount;
    final displayTotal = dl.isNotEmpty ? dl.length : _weeklyHabits.length;
    final progress = habits.isEmpty ? 0.0 : displayDone / displayTotal;

    final hour = DateTime.now().hour;
    return MascotPageShell(
      accent: colors.accent,
      scene: Stack(
        children: [
          // 概念版：天空進度弧 — 每日進度化作太陽（夜晚是星星）在
          // 天空的位置，全完成時光芒迸發。進度不再是一條 UI bar，
          // 而是兔咪世界的一部分。畫在兔咪/對話框下層，避開 app bar。
          if (habits.isNotEmpty)
            Positioned(
              top: 46,
              left: 22,
              right: 22,
              height: 62,
              child: IgnorePointer(
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0.0, end: progress),
                  duration: const Duration(milliseconds: 900),
                  curve: Curves.easeOutCubic,
                  builder: (_, v, _) => CustomPaint(
                    painter: _SkyArcPainter(
                      progress: v,
                      accent: colors.accent,
                      night: hour >= 22 || hour < 6,
                      done: displayDone,
                      total: displayTotal,
                    ),
                  ),
                ),
              ),
            ),
          ScaleTransition(
            scale: _celebScale,
            child: PersonaScene(
              accent: colors.accent,
              reactionTick: _mascotReactionTick,
              onTap: _onMascotTap,
            ),
          ),
        ],
      ),
      child: _habitCardContent(
        progress: progress,
        displayDone: displayDone,
        displayTotal: displayTotal,
        accent: colors.accent,
      ),
    );
  }

  /// 把首頁當下計算出的兔咪狀態同步到全域 [MascotPersona]。
  /// 只在「使用者互動後」呼叫（toggleHabit / onMascotTap / showTransientMascot）。
  bool _syncMascotToPersona() {
    return MascotPersona.setForContext(
      _mascotAsset,
      _mascotContext,
      speech: _transientSpeech,
    );
  }

  Widget _habitCardContent({
    required double progress,
    required int displayDone,
    required int displayTotal,
    required Color accent,
  }) {
    // 概念版：進度視覺整個交給場景天空弧，卡片區直接從清單開始；
    // 新增鈕沉到清單底部成幽靈卡，把頂部讓給內容
    return Column(
      children: [
        const SizedBox(height: 6),
        Expanded(child: _buildHabitList()),
      ],
    );
  }

  // 房間背景圖上的時段色罩（順序與 _sceneColors 一致：全完成 > 夜 > 晨 > 暮）
  Color get _sceneTint {
    final hour = DateTime.now().hour;
    if (allDone0 && habits.isNotEmpty) {
      return const Color(0xFFFFF3C4).withValues(alpha: 0.10);
    }
    if (hour >= 22 || hour < 6) {
      return const Color(0xFF3F456B).withValues(alpha: 0.12);
    }
    if (hour < 9) {
      return const Color(0xFFFFC4AD).withValues(alpha: 0.10);
    }
    if (hour >= 17) {
      return const Color(0xFFC9A1E8).withValues(alpha: 0.10);
    }
    return Colors.transparent;
  }

  // 場景配色：全完成 > 夜晚(22-6) > 清晨(6-9 粉金) > 傍晚(17-22 橘紫) > 白天
  ({Color top, Color bottom, Color accent}) get _sceneColors {
    final hour = DateTime.now().hour;
    if (allDone0 && habits.isNotEmpty) {
      return (
        top: const Color(0xFFE8F8E5),
        bottom: const Color(0xFFCDEFCD),
        accent: const Color(0xFF66BB6A),
      );
    }
    if (hour >= 22 || hour < 6) {
      return (
        top: const Color(0xFFE8EAF6),
        bottom: const Color(0xFFC5CAE9),
        accent: const Color(0xFF7986CB),
      );
    }
    if (hour < 9) {
      // 清晨：粉金日出
      return (
        top: const Color(0xFFFFF1E8),
        bottom: const Color(0xFFFFD9CB),
        accent: const Color(0xFFF0826E),
      );
    }
    if (hour >= 17) {
      // 傍晚：橘光收進薰衣草暮色
      return (
        top: const Color(0xFFFFE6CD),
        bottom: const Color(0xFFE9D7F2),
        accent: const Color(0xFFA984D6),
      );
    }
    return (
      top: const Color(0xFFFFF4E0),
      bottom: const Color(0xFFFFE5C7),
      accent: const Color(0xFFFF8A50),
    );
  }

  // 概念版幽靈新增卡：沉在清單最底，存在感低但永遠在手邊
  Widget _buildGhostAddCard() {
    return Material(
      color: Colors.white.withValues(alpha: 0.45),
      borderRadius: BorderRadius.circular(24),
      child: InkWell(
        onTap: _showAddHabitSheet,
        borderRadius: BorderRadius.circular(24),
        splashColor: Colors.orange.withValues(alpha: 0.12),
        highlightColor: Colors.orange.withValues(alpha: 0.06),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: Colors.orange.withValues(alpha: 0.30),
              width: 1.4,
            ),
          ),
          padding: const EdgeInsets.symmetric(vertical: 13),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.add_circle_outline_rounded,
                size: 18,
                color: Colors.orange.shade400,
              ),
              const SizedBox(width: 8),
              Text(
                '新增習慣',
                style: TextStyle(
                  color: Colors.orange.shade700,
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHabitList() {
    if (habits.isEmpty) {
      return Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _buildGhostAddCard(),
          ),
          Expanded(child: _buildEmptyState()),
        ],
      );
    }

    final dailyEntries = habits
        .asMap()
        .entries
        .where((e) => (e.value['frequency'] ?? 'daily') != 'weekly')
        .toList();
    final weeklyEntries = habits
        .asMap()
        .entries
        .where((e) => (e.value['frequency'] ?? 'daily') == 'weekly')
        .toList();

    Widget buildCard(MapEntry<int, Map<String, dynamic>> entry) {
      final index = entry.key;
      final habit = entry.value;
      final name = habit['name'] as String;
      final alreadyShown = _animatedIn.contains(name);
      _animatedIn.add(name);
      return TweenAnimationBuilder<double>(
        key: ValueKey('anim_$name'),
        tween: Tween(begin: alreadyShown ? 1.0 : 0.0, end: 1.0),
        duration: Duration(milliseconds: alreadyShown ? 0 : 220 + index * 55),
        curve: Curves.easeOut,
        builder: (_, v, child) => Opacity(
          opacity: v,
          child: Transform.translate(
            offset: Offset(0, 16 * (1 - v)),
            child: child,
          ),
        ),
        child: HabitCard(
          key: ValueKey(name),
          habit: habit,
          onToggle: () => toggleHabit(index),
          onEdit: () => _editHabitSheet(index),
          onDelete: () => _confirmDeleteHabit(index),
          isWeekly: (habit['frequency'] ?? 'daily') == 'weekly',
          weeklyCount: _weeklyCount(habit),
          weeklyTarget: (habit['weeklyTarget'] as int?) ?? 3,
          todayCount: List<String>.from(
            (habit['weeklyDates'] as List?) ?? [],
          ).where((d) => d == todayString()).length,
          onDecrement: (habit['frequency'] ?? 'daily') == 'weekly'
              ? () => decrementWeeklyHabit(index)
              : null,
          isLinked: kHomePresets.any(
            (p) => p.linkedSetting != null && habit['name'] == p.name,
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      children: [
        if (dailyEntries.isNotEmpty) ...[
          HabitSectionHeader(
            label: '每日習慣',
            icon: Icons.wb_sunny_rounded,
            color: Colors.orange,
            done: dailyDoneCount,
            total: _dailyHabits.length,
          ),
          ...dailyEntries.map(buildCard),
        ],
        if (weeklyEntries.isNotEmpty) ...[
          if (dailyEntries.isNotEmpty) const SizedBox(height: 20),
          HabitSectionHeader(
            label: '每週習慣',
            icon: Icons.calendar_view_week_rounded,
            color: Colors.indigo,
            done: weeklyMetCount,
            total: _weeklyHabits.length,
          ),
          ...weeklyEntries.map(buildCard),
        ],
        const SizedBox(height: 8),
        _buildGhostAddCard(),
        const SizedBox(height: 24),
      ],
    );
  }

  // 空狀態：淡入＋上浮，視覺語言對齊喝水頁的「今天還沒有補水紀錄」
  Widget _buildEmptyState() {
    final accent = _sceneColors.accent;
    return Center(
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0.0, end: 1.0),
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeOut,
        builder: (_, v, child) => Opacity(
          opacity: v,
          child: Transform.translate(
            offset: Offset(0, 12 * (1 - v)),
            child: child,
          ),
        ),
        // FittedBox：兔咪面板展開時卡片高度有限，等比縮小避免 overflow
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(32, 0, 32, 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.10),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.spa_rounded, size: 30, color: accent),
                ),
                const SizedBox(height: 14),
                const Text(
                  '還沒有任何習慣',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: AppInk.strong,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  '點上面的「新增習慣」\n從一件小事開始吧',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.5,
                    fontWeight: FontWeight.w500,
                    color: AppInk.soft,
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

// 概念版：兔咪的小徑。柔光路徑帶 + 點點中線，從兔咪腳下蜿蜒
// 連起所有習慣石；accent 跟著時段/全完成配色走。
class _TrailPainter extends CustomPainter {
  final Color accent;
  final Offset start;
  final List<Offset> nodes;

  const _TrailPainter({
    required this.accent,
    required this.start,
    required this.nodes,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (nodes.isEmpty) return;
    final path = Path()..moveTo(start.dx, start.dy);
    var prev = start;
    for (final n in nodes) {
      final midY = (prev.dy + n.dy) / 2;
      path.cubicTo(prev.dx, midY, n.dx, midY, n.dx, n.dy);
      prev = n;
    }

    // 柔光路徑帶
    final ribbon = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 24
      ..strokeCap = StrokeCap.round
      ..color = Colors.white.withValues(alpha: 0.65)
      ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 5);
    canvas.drawPath(path, ribbon);
    final tint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 24
      ..strokeCap = StrokeCap.round
      ..color = accent.withValues(alpha: 0.10);
    canvas.drawPath(path, tint);

    // 點點中線（散步感）
    final dot = Paint()..color = accent.withValues(alpha: 0.45);
    for (final metric in path.computeMetrics()) {
      for (var d = 0.0; d < metric.length; d += 17) {
        final t = metric.getTangentForOffset(d);
        if (t != null) canvas.drawCircle(t.position, 2.1, dot);
      }
    }

    // 路邊小花（固定 pattern 的偽隨機，避免每次 repaint 跳動）
    final petal = Paint()..color = accent.withValues(alpha: 0.30);
    final core = Paint()..color = Colors.white.withValues(alpha: 0.85);
    for (final metric in path.computeMetrics()) {
      for (var d = 60.0; d < metric.length - 40; d += 96) {
        final t = metric.getTangentForOffset(d);
        if (t == null) continue;
        // 垂直於路徑方向偏移到路邊，左右交替、距離微變化
        final side = (d ~/ 96).isEven ? 1.0 : -1.0;
        final wobble = 30 + (d % 53) * 0.35;
        final n = Offset(-t.vector.dy, t.vector.dx) / t.vector.distance;
        final c = t.position + n * side * wobble;
        for (var i = 0; i < 5; i++) {
          final a = i * 2 * math.pi / 5;
          canvas.drawCircle(
            c + Offset(math.cos(a), math.sin(a)) * 3.4,
            2.2,
            petal,
          );
        }
        canvas.drawCircle(c, 1.9, core);
      }
    }
  }

  @override
  bool shouldRepaint(_TrailPainter old) =>
      old.accent != accent || old.nodes.length != nodes.length;
}

// 概念版：天空進度弧。
// 每日進度 = 太陽（夜晚是星星）沿著天空軌道的位置；走過的軌跡上色，
// 全完成時太陽抵達頂點、光芒迸發。把「進度條」還給世界觀。
class _SkyArcPainter extends CustomPainter {
  final double progress; // 0~1
  final Color accent;
  final bool night;
  final int done;
  final int total;

  const _SkyArcPainter({
    required this.progress,
    required this.accent,
    required this.night,
    required this.done,
    required this.total,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    // 上升弧：左下 → 右上爬升（quadratic）。太陽跟著進度往上爬，
    // 100% 時在頂端迸發光芒 —「今天走到最高處」
    final path = Path()
      ..moveTo(w * 0.04, h * 0.88)
      ..quadraticBezierTo(w * 0.60, h * 0.84, w * 0.90, h * 0.32);
    final metric = path.computeMetrics().first;

    // 柔光緞帶底：把弧從豐富的房間背景里抬出來（寬模糊白帶）
    final ribbon = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 16
      ..strokeCap = StrokeCap.round
      ..color = Colors.white.withValues(alpha: 0.42)
      ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 6);
    canvas.drawPath(path, ribbon);

    // 軌道（白底襯 + accent 淡彩，柔和不搶兔咪）
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..color = Colors.white.withValues(alpha: 0.9);
    canvas.drawPath(path, track);
    final trackTint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..color = accent.withValues(alpha: 0.35);
    canvas.drawPath(path, trackTint);

    final p = progress.clamp(0.0, 1.0);
    final reached = total > 0 && done >= total;

    // 已走過的軌跡
    if (p > 0.01) {
      final trail = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.4
        ..strokeCap = StrokeCap.round
        ..color = accent.withValues(alpha: 0.85);
      canvas.drawPath(metric.extractPath(0, metric.length * p), trail);
    }

    // 太陽 / 星星位置
    final tangent = metric.getTangentForOffset(metric.length * p);
    if (tangent == null) return;
    final pos = tangent.position;

    // 達標光芒
    if (reached) {
      final ray = Paint()
        ..strokeWidth = 2.2
        ..strokeCap = StrokeCap.round
        ..color = accent.withValues(alpha: 0.75);
      for (var i = 0; i < 8; i++) {
        final a = i * math.pi / 4 + math.pi / 8;
        canvas.drawLine(
          pos + Offset(math.cos(a), math.sin(a)) * 13,
          pos + Offset(math.cos(a), math.sin(a)) * 19,
          ray,
        );
      }
    }

    // 本體：白心 + accent 邊 + 柔光（夜晚改四芒星）
    final glow = Paint()
      ..color = accent.withValues(alpha: reached ? 0.60 : 0.42)
      ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 8);
    canvas.drawCircle(pos, 11, glow);
    if (night) {
      final star = Path();
      const r1 = 8.0, r2 = 3.2;
      for (var i = 0; i < 8; i++) {
        final r = i.isEven ? r1 : r2;
        final a = -math.pi / 2 + i * math.pi / 4;
        final v = pos + Offset(math.cos(a), math.sin(a)) * r;
        i == 0 ? star.moveTo(v.dx, v.dy) : star.lineTo(v.dx, v.dy);
      }
      star.close();
      canvas.drawPath(star, Paint()..color = Colors.white);
      canvas.drawPath(
        star,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6
          ..color = accent,
      );
    } else {
      canvas.drawCircle(pos, 8.5, Paint()..color = Colors.white);
      canvas.drawCircle(
        pos,
        8.5,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.6
          ..color = accent,
      );
    }

    // 進度數字（跟著太陽走，貼在下方）
    final tp = TextPainter(
      text: TextSpan(
        text: '$done/$total',
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w800,
          color: accent,
          shadows: const [Shadow(color: Colors.white, blurRadius: 6)],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, pos + Offset(-tp.width / 2, 13));
  }

  @override
  bool shouldRepaint(_SkyArcPainter old) =>
      old.progress != progress ||
      old.accent != accent ||
      old.done != done ||
      old.total != total ||
      old.night != night;
}
