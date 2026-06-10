// 首頁（每日／每週習慣打卡 + 兔咪場景）。
// 其餘部分拆在 home/：習慣卡片、新增／編輯 bottom sheet、preset 定義、
// 問候橫幅、共用小元件與場景 painter。
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/mascot.dart';
import '../utils/sfx_service.dart';
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

    loadHabits();
  }

  @override
  void dispose() {
    _celebCtrl.dispose();
    super.dispose();
  }

  Future<void> loadHabits() async {
    final prefs = await SharedPreferences.getInstance();
    final today = todayString();
    final lastOpen = prefs.getString('last_open_date');
    streak = prefs.getInt('streak') ?? 0;
    _nickname = prefs.getString('user_nickname') ?? '你';
    mascotName0 = prefs.getString('mascot_name') ?? '兔咪';

    final obDateStr = prefs.getString('onboarding_date');
    if (obDateStr != null) {
      onboardingDate = DateTime.tryParse(obDateStr);
    } else {
      onboardingDate = DateTime.now();
      await prefs.setString(
        'onboarding_date',
        onboardingDate!.toIso8601String(),
      );
    }

    final habitsJson = prefs.getString('habits');
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
        } else {
          streak = 0;
        }
        await prefs.setInt('streak', streak);
      }
      for (final habit in habits) {
        if ((habit['frequency'] ?? 'daily') != 'weekly') {
          habit['done'] = false;
        }
      }
      await prefs.setString('habits', jsonEncode(habits));
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
      await prefs.setString('habits', jsonEncode(habits));
    }

    final isFirstOpenToday = lastOpen != today;
    await prefs.setString('last_open_date', today);
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
    await prefs.setString('habits', jsonEncode(habits));
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
    if ((habit['frequency'] ?? 'daily') == 'weekly') {
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
    } else {
      final wasDone = habit['done'] as bool;
      setState(() {
        habit['done'] = !wasDone;
      });
      if (wasDone) _showTransientMascot('sad');
    }
    saveHabits();
    if (!wasAllDone && allDone0) {
      SfxService.instance.play(SfxCue.complete);
      _celebCtrl.forward(from: 0);
      setState(() => _mascotReactionTick++);
    } else if (habits[index]['done'] == true) {
      if (!wasHabitDone) {
        SfxService.instance.play(SfxCue.success);
      } else {
        SfxService.instance.play(SfxCue.tap);
      }
      setState(() => _mascotReactionTick++);
    } else {
      SfxService.instance.play(SfxCue.cancel);
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
    saveHabits();
    SfxService.instance.play(SfxCue.cancel);
    _showTransientMascot('sad');
  }

  void deleteHabit(int index) {
    final name = habits[index]['name'] as String;
    _animatedIn.remove(name);
    setState(() => habits.removeAt(index));
    saveHabits();
    if (name == '喝足夠的水') {
      SharedPreferences.getInstance().then((prefs) async {
        await prefs.setBool('water_enabled', false);
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
          maxLength: 20,
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
    final name = ctrl.text.trim();
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
    final now = DateTime.now();
    final isNight = now.hour >= 22 || now.hour < 6;
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
                color:
                    (isNight
                            ? const Color(0xFF3F456B)
                            : allDone0 && habits.isNotEmpty
                            ? const Color(0xFFFFF3C4)
                            : Colors.transparent)
                        .withValues(
                          alpha: isNight
                              ? 0.12
                              : allDone0 && habits.isNotEmpty
                              ? 0.10
                              : 0,
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
            // 內容
            SafeArea(child: _buildMascotScene()),
          ],
        ),
      ),
    );
  }

  Widget _buildMascotScene() {
    final colors = _sceneColors;
    final dl = _dailyHabits;
    final displayDone = dl.isNotEmpty ? dailyDoneCount : weeklyMetCount;
    final displayTotal = dl.isNotEmpty ? dl.length : _weeklyHabits.length;
    final progress = habits.isEmpty ? 0.0 : displayDone / displayTotal;

    return MascotPageShell(
      accent: colors.accent,
      scene: ScaleTransition(
        scale: _celebScale,
        child: PersonaScene(
          accent: colors.accent,
          reactionTick: _mascotReactionTick,
          onTap: _onMascotTap,
        ),
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
    return Column(
      children: [
        if (habits.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
            child: Row(
              children: [
                Expanded(
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0.0, end: progress),
                    duration: const Duration(milliseconds: 700),
                    curve: Curves.easeOut,
                    builder: (_, value, _) => ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value: value,
                        minHeight: 6,
                        backgroundColor: Colors.grey.shade200,
                        valueColor: AlwaysStoppedAnimation(accent),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  '$displayDone / $displayTotal',
                  style: TextStyle(
                    color: accent,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 8),
        _buildAddButton(),
        const SizedBox(height: 10),
        Expanded(child: _buildHabitList()),
      ],
    );
  }

  // 場景配色：依據狀態切換（白天/夜晚/全完成）
  ({Color top, Color bottom, Color accent}) get _sceneColors {
    final hour = DateTime.now().hour;
    final isNight = hour >= 22 || hour < 6;
    if (allDone0 && habits.isNotEmpty) {
      return (
        top: const Color(0xFFE8F8E5),
        bottom: const Color(0xFFCDEFCD),
        accent: const Color(0xFF66BB6A),
      );
    }
    if (isNight) {
      return (
        top: const Color(0xFFE8EAF6),
        bottom: const Color(0xFFC5CAE9),
        accent: const Color(0xFF7986CB),
      );
    }
    return (
      top: const Color(0xFFFFF4E0),
      bottom: const Color(0xFFFFE5C7),
      accent: const Color(0xFFFF8A50),
    );
  }

  Widget _buildAddButton() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _showAddHabitSheet,
          borderRadius: BorderRadius.circular(14),
          splashColor: Colors.orange.withValues(alpha: 0.15),
          highlightColor: Colors.orange.withValues(alpha: 0.08),
          child: Ink(
            decoration: BoxDecoration(
              color: Colors.orange.shade50.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.orange.shade200, width: 1.2),
            ),
            padding: const EdgeInsets.symmetric(vertical: 13),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: Colors.orange.shade400,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.add, size: 16, color: Colors.white),
                ),
                const SizedBox(width: 10),
                Text(
                  '新增習慣',
                  style: TextStyle(
                    color: Colors.orange.shade800,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHabitList() {
    if (habits.isEmpty) {
      return const Center(
        child: Text('還沒有習慣，新增一個吧！', style: TextStyle(color: Colors.grey)),
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
          _habitSectionLabel(
            '每日習慣',
            Icons.wb_sunny_rounded,
            Colors.orange,
            done: dailyDoneCount,
            total: _dailyHabits.length,
          ),
          ...dailyEntries.map(buildCard),
        ],
        if (weeklyEntries.isNotEmpty) ...[
          if (dailyEntries.isNotEmpty) const SizedBox(height: 14),
          _habitSectionLabel(
            '每週習慣',
            Icons.calendar_view_week_rounded,
            Colors.indigo,
            done: weeklyMetCount,
            total: _weeklyHabits.length,
          ),
          ...weeklyEntries.map(buildCard),
        ],
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _habitSectionLabel(
    String label,
    IconData icon,
    Color color, {
    required int done,
    required int total,
  }) {
    final allDone = total > 0 && done == total;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, top: 6, left: 2),
      child: Row(
        children: [
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 15, color: color),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: color,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: allDone
                  ? Colors.green.shade50
                  : color.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              '$done / $total',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: allDone ? Colors.green.shade700 : color,
              ),
            ),
          ),
          if (allDone) ...[
            const SizedBox(width: 6),
            Icon(
              Icons.check_circle_rounded,
              size: 14,
              color: Colors.green.shade400,
            ),
          ],
        ],
      ),
    );
  }
}
