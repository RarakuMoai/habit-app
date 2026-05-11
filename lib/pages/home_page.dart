import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'settings_page.dart';

class _PresetConfig {
  int minutes;
  String frequency;
  int weeklyTarget;
  _PresetConfig({required this.minutes, this.frequency = 'daily', this.weeklyTarget = 3});
}

class _HomePreset {
  final String name;
  final String emoji;
  final String? linkedSetting;
  final String? linkedLabel;
  final int? defaultMinutes;
  final bool supportsFrequency;
  const _HomePreset(this.name, this.emoji,
      [this.linkedSetting, this.linkedLabel, this.defaultMinutes, this.supportsFrequency = false]);
}

const List<_HomePreset> _kHomePresets = [
  _HomePreset('刷牙', '🦷'),
  _HomePreset('整理環境', '🧹'),
  _HomePreset('閱讀', '📖', null, null, 0, true),
  _HomePreset('早起', '🌅'),
  _HomePreset('運動', '🏃', null, null, 0, true),
  _HomePreset('喝足夠的水', '💧', 'water_enabled', '選取後自動開啟喝水頁籤'),
  _HomePreset('冥想', '🧘', null, null, 0, true),
  _HomePreset('早睡', '🌙'),
];

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

  late AnimationController _pulseCtrl;
  late Animation<double> _pulseAnim;

  late AnimationController _celebCtrl;
  late Animation<double> _celebScale;

  final Set<String> _animatedIn = {};

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 1.0, end: 1.08).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );

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
    _pulseCtrl.dispose();
    _celebCtrl.dispose();
    super.dispose();
  }

  Future<void> loadHabits() async {
    final prefs = await SharedPreferences.getInstance();
    final String today = todayString();
    final String? lastOpen = prefs.getString('last_open_date');
    streak = prefs.getInt('streak') ?? 0;
    _nickname = prefs.getString('user_nickname') ?? '你';
    mascotName0 = prefs.getString('mascot_name') ?? '兔咪';

    final String? obDateStr = prefs.getString('onboarding_date');
    if (obDateStr != null) {
      onboardingDate = DateTime.tryParse(obDateStr);
    } else {
      onboardingDate = DateTime.now();
      await prefs.setString('onboarding_date', onboardingDate!.toIso8601String());
    }

    final String? habitsJson = prefs.getString('habits');
    if (habitsJson != null) {
      final List<dynamic> decoded = jsonDecode(habitsJson);
      habits.addAll(decoded.map((e) => Map<String, dynamic>.from(e)));
    }

    if (lastOpen != null && lastOpen != today) {
      final dailyHabits = habits.where((h) => (h['frequency'] ?? 'daily') != 'weekly').toList();
      final bool allDailyDone = dailyHabits.isNotEmpty && dailyHabits.every((h) => h['done'] == true);
      yesterdayAllDone = allDailyDone;
      if (dailyHabits.isNotEmpty) {
        if (allDailyDone) {
          streak++;
        } else {
          streak = 0;
        }
        await prefs.setInt('streak', streak);
      }
      for (var habit in habits) {
        if ((habit['frequency'] ?? 'daily') != 'weekly') {
          habit['done'] = false;
        }
      }
      await prefs.setString('habits', jsonEncode(habits));
    }

    // Always recompute done for weekly habits from weeklyDates
    for (var habit in habits) {
      if ((habit['frequency'] ?? 'daily') == 'weekly') {
        final target = (habit['weeklyTarget'] as int?) ?? 3;
        habit['done'] = _weeklyCount(habit) >= target;
      }
    }

    final bool isFirstOpenToday = lastOpen != today;
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
            '${parts[0]}-${parts[1].padLeft(2, '0')}-${parts[2].padLeft(2, '0')}');
        if (lastDate != null && DateTime.now().difference(lastDate).inDays >= 2) {
          return '你回來了！我好想你 🐰';
        }
      }
    }
    if (streak >= 7) return '連續一週了！你真的很厲害！🔥';
    if (yesterdayAllDone) return '昨天表現超棒！今天繼續！⭐';
    if (onboardingDate != null) {
      final daysSince = DateTime.now().difference(onboardingDate!).inDays + 1;
      if (daysSince <= 3) return '第$daysSince天！我們越來越熟了～';
    }
    return '早安 $_nickname！今天也要加油喔 🌟';
  }

  void showGreetingBanner(String message) {
    final overlay = Overlay.of(context);
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _GreetingBanner(
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

  String todayString() {
    final now = DateTime.now();
    return '${now.year}-${now.month}-${now.day}';
  }

  List<String> _currentWeekStrings() {
    final now = DateTime.now();
    final monday = now.subtract(Duration(days: now.weekday - 1));
    return List.generate(7, (i) {
      final d = monday.add(Duration(days: i));
      return '${d.year}-${d.month}-${d.day}';
    });
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
  int get weeklyMetCount => _weeklyHabits.where((h) => h['done'] == true).length;

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

  void _showTransientMascot(String name, {Duration duration = const Duration(seconds: 2)}) {
    setState(() => _transientMascot = name);
    Future.delayed(duration, () {
      if (mounted) setState(() => _transientMascot = null);
    });
  }

  // 兔咪圖選擇器（按進度、時間、streak 決定）
  String get _mascotAsset {
    if (_transientMascot != null) {
      return 'assets/images/mascot/tumi_$_transientMascot.png';
    }
    if (habits.isEmpty) {
      return 'assets/images/mascot/tumi_neutral_front.png';
    }
    final ref = _dailyHabits.isNotEmpty ? _dailyHabits : _weeklyHabits;
    final done = _dailyHabits.isNotEmpty ? dailyDoneCount : weeklyMetCount;
    final ratio = done / ref.length;

    if (ratio == 1.0) {
      if (streak >= 7) return 'assets/images/mascot/tumi_streak.png';
      return 'assets/images/mascot/tumi_happy.png';
    }
    if (ratio >= 0.5) return 'assets/images/mascot/tumi_smile.png';
    if (ratio > 0) return 'assets/images/mascot/tumi_expect.png';

    final hour = DateTime.now().hour;
    if (hour >= 22 || hour < 6) return 'assets/images/mascot/tumi_night.png';
    return 'assets/images/mascot/tumi_sleep.png';
  }

  String get _mascotMessage {
    if (habits.isEmpty) return '新增一個習慣，我們一起努力！';
    final ref = _dailyHabits.isNotEmpty ? _dailyHabits : _weeklyHabits;
    final done = _dailyHabits.isNotEmpty ? dailyDoneCount : weeklyMetCount;
    final ratio = done / ref.length;
    if (ratio == 1.0) return '太厲害了！今天全部完成！🎉';
    if (ratio >= 0.5) return '已經完成一半了！繼續加油！💪';
    if (ratio > 0) return '好的開始！繼續保持！🌟';
    return '今天要開始了嗎？我在等你！';
  }

  void toggleHabit(int index) {
    final wasAllDone = allDone0;
    final habit = habits[index];
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
      _celebCtrl.forward(from: 0);
    }
    if (habits[index]['name'] == '喝足夠的水') {
      widget.onWaterHabitToggled?.call(habits[index]['done'] as bool);
    }
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
    saveHabits();
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

  // 常用習慣子選單（可捲動清單 + 客製化設定）
  Future<Map<String, _PresetConfig>?> _showHabitPresetSheet(
    List<_HomePreset> available,
    Map<String, _PresetConfig> initialSelected,
  ) {
    final tempSelected = <String, _PresetConfig>{};
    for (final e in initialSelected.entries) {
      tempSelected[e.key] = _PresetConfig(
        minutes: e.value.minutes,
        frequency: e.value.frequency,
        weeklyTarget: e.value.weeklyTarget,
      );
    }
    return showModalBottomSheet<Map<String, _PresetConfig>>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (_, setS) => DraggableScrollableSheet(
          initialChildSize: 0.6,
          maxChildSize: 0.92,
          minChildSize: 0.4,
          expand: false,
          builder: (_, scrollCtrl) => Column(
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 12, bottom: 4),
                child: Container(
                  width: 36, height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                child: Row(
                  children: [
                    const Icon(Icons.auto_awesome, size: 18, color: Colors.orange),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text('常用習慣',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    ),
                    if (tempSelected.isNotEmpty)
                      Text('${tempSelected.length} 項已選',
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView.builder(
                  controller: scrollCtrl,
                  itemCount: available.length,
                  itemBuilder: (_, i) {
                    final p = available[i];
                    final sel = tempSelected.containsKey(p.name);
                    final config = tempSelected[p.name];
                    final hasCustom = p.defaultMinutes != null;
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      decoration: BoxDecoration(
                        color: sel ? Colors.orange.shade50 : Colors.white,
                        border: Border(
                          bottom: BorderSide(color: Colors.grey.shade100),
                        ),
                      ),
                      child: Column(
                        children: [
                          InkWell(
                            onTap: () => setS(() {
                              if (sel) {
                                tempSelected.remove(p.name);
                              } else {
                                tempSelected[p.name] = _PresetConfig(
                                  minutes: p.defaultMinutes ?? 0,
                                );
                              }
                            }),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                              child: Row(
                                children: [
                                  Text(p.emoji, style: const TextStyle(fontSize: 22)),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          p.name,
                                          style: TextStyle(
                                            fontSize: 15,
                                            fontWeight: sel ? FontWeight.w600 : FontWeight.normal,
                                            color: sel ? Colors.orange.shade800 : Colors.black87,
                                          ),
                                        ),
                                        if (p.linkedSetting != null)
                                          Padding(
                                            padding: const EdgeInsets.only(top: 2),
                                            child: Row(
                                              children: [
                                                Icon(Icons.link, size: 11, color: Colors.blue.shade400),
                                                const SizedBox(width: 3),
                                                Text(p.linkedLabel!,
                                                    style: TextStyle(fontSize: 11, color: Colors.blue.shade500)),
                                              ],
                                            ),
                                          ),
                                        if (!sel && hasCustom)
                                          Padding(
                                            padding: const EdgeInsets.only(top: 3),
                                            child: Text(
                                              '可自訂時間${p.supportsFrequency ? "・可設頻率" : ""}',
                                              style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                                            ),
                                          ),
                                        if (sel && hasCustom)
                                          Padding(
                                            padding: const EdgeInsets.only(top: 3),
                                            child: Text(
                                              '${config!.minutes > 0 ? "${config.minutes} 分鐘" : "未設時間"}${config.frequency == "weekly" ? "・每週 ${config.weeklyTarget} 次" : "・每日"}',
                                              style: TextStyle(fontSize: 11, color: Colors.orange.shade600, fontWeight: FontWeight.w500),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                  AnimatedContainer(
                                    duration: const Duration(milliseconds: 150),
                                    width: 24, height: 24,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: sel ? Colors.orange : Colors.transparent,
                                      border: Border.all(
                                        color: sel ? Colors.orange : Colors.grey.shade300,
                                        width: 2,
                                      ),
                                    ),
                                    child: sel
                                        ? const Icon(Icons.check, size: 14, color: Colors.white)
                                        : null,
                                  ),
                                ],
                              ),
                            ),
                          ),
                          AnimatedCrossFade(
                            firstChild: const SizedBox(width: double.infinity, height: 0),
                            secondChild: sel && hasCustom && config != null
                                ? _buildPresetCustomization(p, config, setS)
                                : const SizedBox(width: double.infinity, height: 0),
                            crossFadeState: (sel && hasCustom)
                                ? CrossFadeState.showSecond
                                : CrossFadeState.showFirst,
                            duration: const Duration(milliseconds: 220),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(20, 12, 20,
                    MediaQuery.of(ctx).viewInsets.bottom + 20),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(ctx, tempSelected),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: Text(
                      tempSelected.isEmpty ? '確認（未選取）' : '確認選取 (${tempSelected.length} 項)',
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<int?> _showMinutesDialog(int current) async {
    final ctrl = TextEditingController(text: current > 0 ? '$current' : '');
    return showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('持續時間'),
        contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          autofocus: true,
          decoration: InputDecoration(
            suffixText: '分鐘',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          ),
          onSubmitted: (v) {
            final n = int.tryParse(v.trim());
            if (n != null && n > 0) Navigator.pop(ctx, n.clamp(1, 999));
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('取消', style: TextStyle(color: Colors.grey.shade600)),
          ),
          TextButton(
            onPressed: () {
              final n = int.tryParse(ctrl.text.trim());
              if (n != null && n > 0) Navigator.pop(ctx, n.clamp(1, 999));
            },
            child: const Text('確定'),
          ),
        ],
      ),
    );
  }

  Widget _buildPresetCustomization(_HomePreset p, _PresetConfig config, StateSetter setS) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 14),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.orange.shade100),
      ),
      child: Column(
        children: [
          // 分鐘調整
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.timer_outlined, size: 15, color: Colors.orange.shade500),
              const SizedBox(width: 10),
              _AdjustBtn(
                icon: Icons.remove,
                enabled: config.minutes > 0,
                onTap: () => setS(() =>
                    config.minutes = config.minutes <= 5 ? 0 : config.minutes - 5),
              ),
              const SizedBox(width: 14),
              GestureDetector(
                onTap: () async {
                  final result = await _showMinutesDialog(config.minutes);
                  if (result != null) setS(() => config.minutes = result);
                },
                child: Container(
                  constraints: const BoxConstraints(minWidth: 44),
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(color: Colors.orange.shade300, width: 1.5),
                    ),
                  ),
                  child: Text(
                    config.minutes > 0 ? '${config.minutes}' : '--',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: config.minutes > 0 ? Colors.black87 : Colors.grey.shade400,
                    ),
                  ),
                ),
              ),
              Text('分鐘', style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
              const SizedBox(width: 14),
              _AdjustBtn(
                icon: Icons.add,
                enabled: config.minutes < 999,
                onTap: () => setS(() =>
                    config.minutes = config.minutes == 0 ? 5 : (config.minutes + 5).clamp(5, 999)),
              ),
            ],
          ),
          if (p.supportsFrequency) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Divider(height: 1, color: Colors.orange.shade100),
            ),
            // 頻率切換
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.repeat, size: 15, color: Colors.orange.shade500),
                const SizedBox(width: 10),
                _FreqChip(
                  label: '每日',
                  selected: config.frequency == 'daily',
                  onTap: () => setS(() => config.frequency = 'daily'),
                ),
                const SizedBox(width: 8),
                _FreqChip(
                  label: '每週',
                  selected: config.frequency == 'weekly',
                  onTap: () => setS(() => config.frequency = 'weekly'),
                ),
              ],
            ),
            // 每週目標次數（另起一行避免溢出）
            if (config.frequency == 'weekly')
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('每週目標', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                    const SizedBox(width: 12),
                    _AdjustBtn(
                      icon: Icons.remove,
                      enabled: config.weeklyTarget > 1,
                      onTap: () => setS(() => config.weeklyTarget--),
                    ),
                    const SizedBox(width: 10),
                    SizedBox(
                      width: 28,
                      child: Text(
                        '${config.weeklyTarget}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                    ),
                    Text('次', style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
                    const SizedBox(width: 10),
                    _AdjustBtn(
                      icon: Icons.add,
                      enabled: config.weeklyTarget < 7,
                      onTap: () => setS(() => config.weeklyTarget++),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }

  Future<void> _editHabitSheet(int index) async {
    final habit = habits[index];
    final fullName = habit['name'] as String;

    final minuteMatch = RegExp(r'^(.*)\s+(\d+)\s+分鐘$').firstMatch(fullName);
    final initBase = minuteMatch != null ? minuteMatch.group(1)! : fullName;
    final initMinutes = minuteMatch != null ? int.parse(minuteMatch.group(2)!) : 0;
    final initFreq = (habit['frequency'] ?? 'daily') as String;
    final initWeekly = (habit['weeklyTarget'] as int?) ?? 3;

    final nameCtrl = TextEditingController(text: initBase);
    String freq = initFreq;
    int weeklyTarget = initWeekly;
    int minutes = initMinutes;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (_, setS) {
          final baseName = nameCtrl.text.trim();
          return Padding(
            padding: EdgeInsets.fromLTRB(
                20, 16, 20, MediaQuery.of(ctx).viewInsets.bottom + 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36, height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text('編輯習慣',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                TextField(
                  controller: nameCtrl,
                  onChanged: (_) => setS(() {}),
                  maxLength: 20,
                  decoration: InputDecoration(
                    labelText: '習慣名稱',
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: Colors.grey.shade200),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: Colors.grey.shade200),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: Colors.orange.shade400),
                    ),
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  ),
                ),
                const SizedBox(height: 12),
                Text('頻率',
                    style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade500,
                        fontWeight: FontWeight.w500)),
                const SizedBox(height: 6),
                Row(
                  children: [
                    _FreqChip(
                      label: '每日',
                      selected: freq == 'daily',
                      onTap: () => setS(() => freq = 'daily'),
                    ),
                    const SizedBox(width: 8),
                    _FreqChip(
                      label: '每週',
                      selected: freq == 'weekly',
                      onTap: () => setS(() => freq = 'weekly'),
                    ),
                    if (freq == 'weekly') ...[
                      const SizedBox(width: 16),
                      _AdjustBtn(
                        icon: Icons.remove,
                        enabled: weeklyTarget > 1,
                        onTap: () => setS(() => weeklyTarget--),
                      ),
                      const SizedBox(width: 8),
                      Text('$weeklyTarget',
                          style: const TextStyle(
                              fontSize: 18, fontWeight: FontWeight.bold)),
                      Text('  次',
                          style: TextStyle(
                              fontSize: 13, color: Colors.grey.shade600)),
                      const SizedBox(width: 8),
                      _AdjustBtn(
                        icon: Icons.add,
                        enabled: weeklyTarget < 7,
                        onTap: () => setS(() => weeklyTarget++),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 12),
                Text('持續時間（選填）',
                    style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade500,
                        fontWeight: FontWeight.w500)),
                const SizedBox(height: 8),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(
                      color: minutes > 0
                          ? Colors.orange.shade300
                          : Colors.grey.shade300,
                      width: 1.5,
                    ),
                    color: minutes > 0 ? Colors.orange.shade50 : Colors.white,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      GestureDetector(
                        onTap: minutes > 0
                            ? () => setS(() =>
                                minutes = minutes <= 5 ? 0 : minutes - 5)
                            : null,
                        child: Container(
                          width: 44, height: 44,
                          alignment: Alignment.center,
                          child: Icon(Icons.remove, size: 18,
                              color: minutes > 0
                                  ? Colors.orange.shade700
                                  : Colors.grey.shade300),
                        ),
                      ),
                      Container(
                          width: 1, height: 28,
                          color: minutes > 0
                              ? Colors.orange.shade200
                              : Colors.grey.shade200),
                      GestureDetector(
                        onTap: () async {
                          final result = await _showMinutesDialog(minutes);
                          if (result != null) setS(() => minutes = result);
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 10),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.baseline,
                            textBaseline: TextBaseline.alphabetic,
                            children: [
                              Text(
                                minutes > 0 ? '$minutes' : '--',
                                style: TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                  color: minutes > 0
                                      ? Colors.black87
                                      : Colors.grey.shade400,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Text('分鐘',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: minutes > 0
                                        ? Colors.grey.shade600
                                        : Colors.grey.shade400,
                                  )),
                            ],
                          ),
                        ),
                      ),
                      Container(
                          width: 1, height: 28,
                          color: minutes > 0
                              ? Colors.orange.shade200
                              : Colors.grey.shade200),
                      GestureDetector(
                        onTap: minutes < 999
                            ? () => setS(() =>
                                minutes = minutes == 0
                                    ? 5
                                    : (minutes + 5).clamp(5, 999))
                            : null,
                        child: Container(
                          width: 44, height: 44,
                          alignment: Alignment.center,
                          child: Icon(Icons.add, size: 18,
                              color: minutes < 999
                                  ? Colors.orange.shade700
                                  : Colors.grey.shade300),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: baseName.isEmpty
                        ? null
                        : () {
                            Navigator.pop(ctx);
                            final newName = minutes > 0
                                ? '$baseName $minutes 分鐘'
                                : baseName;
                            setState(() {
                              habits[index]['name'] = newName;
                              habits[index]['frequency'] = freq;
                              if (freq == 'weekly') {
                                habits[index]['weeklyTarget'] = weeklyTarget;
                                habits[index].putIfAbsent(
                                    'weeklyDates', () => <String>[]);
                              } else {
                                habits[index].remove('weeklyTarget');
                                habits[index].remove('weeklyDates');
                                habits[index]['done'] = false;
                              }
                            });
                            saveHabits();
                          },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                      disabledBackgroundColor: Colors.grey.shade200,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: const Text('儲存',
                        style: TextStyle(color: Colors.white)),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _showAddHabitSheet() async {
    final nameCtrl = TextEditingController();
    final existing = habits.map((h) => h['name'] as String).toSet();
    final available = _kHomePresets.where((p) {
      if (p.defaultMinutes != null) {
        return !existing.any((n) => n == p.name || n.startsWith('${p.name} '));
      }
      return !existing.contains(p.name);
    }).toList();
    final selected = <String, _PresetConfig>{};
    String freq = 'daily';
    int weeklyTarget = 3;
    int customMinutes = 0;
    bool customExpanded = false;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (_, setS) {
          final customName = nameCtrl.text.trim();
          final total = (customName.isNotEmpty ? 1 : 0) + selected.length;
          return Padding(
            padding: EdgeInsets.fromLTRB(
                20, 16, 20, MediaQuery.of(ctx).viewInsets.bottom + 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text('新增習慣',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                // 常用習慣選取
                if (available.isNotEmpty)
                  InkWell(
                    onTap: () async {
                      final result = await _showHabitPresetSheet(available, selected);
                      if (result != null) {
                        setS(() {
                          selected.clear();
                          selected.addAll(result);
                        });
                      }
                    },
                    borderRadius: BorderRadius.circular(12),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      decoration: BoxDecoration(
                        color: selected.isEmpty ? Colors.grey.shade50 : Colors.orange.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: selected.isEmpty ? Colors.grey.shade300 : Colors.orange.shade300,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.auto_awesome, size: 18,
                              color: selected.isEmpty ? Colors.grey.shade500 : Colors.orange),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              selected.isEmpty ? '從常用習慣選取' : '已選 ${selected.length} 個常用習慣',
                              style: TextStyle(
                                color: selected.isEmpty ? Colors.grey.shade600 : Colors.orange.shade700,
                                fontSize: 14,
                              ),
                            ),
                          ),
                          Icon(
                            selected.isEmpty ? Icons.chevron_right : Icons.check_circle,
                            size: 20,
                            color: selected.isEmpty ? Colors.grey.shade400 : Colors.orange.shade600,
                          ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 10),
                // 自訂習慣 toggle
                InkWell(
                  onTap: () => setS(() => customExpanded = !customExpanded),
                  borderRadius: BorderRadius.circular(12),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      color: customExpanded
                          ? (customName.isNotEmpty ? Colors.deepOrange.shade50 : Colors.grey.shade100)
                          : Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: customExpanded
                            ? (customName.isNotEmpty ? Colors.deepOrange.shade300 : Colors.grey.shade300)
                            : Colors.grey.shade300,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.edit_note, size: 18,
                            color: customName.isNotEmpty
                                ? Colors.deepOrange.shade500
                                : Colors.grey.shade500),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            customName.isNotEmpty ? customName : '自訂習慣',
                            style: TextStyle(
                              color: customName.isNotEmpty
                                  ? Colors.deepOrange.shade700
                                  : Colors.grey.shade600,
                              fontSize: 14,
                            ),
                          ),
                        ),
                        Icon(
                          customExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                          size: 20,
                          color: Colors.grey.shade400,
                        ),
                      ],
                    ),
                  ),
                ),
                // 自訂習慣展開內容
                AnimatedCrossFade(
                  firstChild: const SizedBox(width: double.infinity, height: 0),
                  secondChild: Container(
                    margin: const EdgeInsets.only(top: 8),
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TextField(
                          controller: nameCtrl,
                          onChanged: (_) => setS(() {}),
                          maxLength: 20,
                          decoration: InputDecoration(
                            hintText: '習慣名稱',
                            filled: true,
                            fillColor: Colors.white,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide(color: Colors.grey.shade200),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide(color: Colors.grey.shade200),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide(color: Colors.orange.shade400),
                            ),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text('頻率',
                            style: TextStyle(fontSize: 12, color: Colors.grey.shade500, fontWeight: FontWeight.w500)),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            _FreqChip(
                              label: '每日',
                              selected: freq == 'daily',
                              onTap: () => setS(() => freq = 'daily'),
                            ),
                            const SizedBox(width: 8),
                            _FreqChip(
                              label: '每週',
                              selected: freq == 'weekly',
                              onTap: () => setS(() => freq = 'weekly'),
                            ),
                            if (freq == 'weekly') ...[
                              const SizedBox(width: 16),
                              _AdjustBtn(
                                icon: Icons.remove,
                                enabled: weeklyTarget > 1,
                                onTap: () => setS(() => weeklyTarget--),
                              ),
                              const SizedBox(width: 8),
                              Text('$weeklyTarget',
                                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                              Text('  次', style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
                              const SizedBox(width: 8),
                              _AdjustBtn(
                                icon: Icons.add,
                                enabled: weeklyTarget < 7,
                                onTap: () => setS(() => weeklyTarget++),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text('持續時間（選填）',
                            style: TextStyle(fontSize: 12, color: Colors.grey.shade500, fontWeight: FontWeight.w500)),
                        const SizedBox(height: 8),
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(28),
                            border: Border.all(
                              color: customMinutes > 0 ? Colors.orange.shade300 : Colors.grey.shade300,
                              width: 1.5,
                            ),
                            color: customMinutes > 0 ? Colors.orange.shade50 : Colors.white,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              GestureDetector(
                                onTap: customMinutes > 0
                                    ? () => setS(() =>
                                        customMinutes = customMinutes <= 5 ? 0 : customMinutes - 5)
                                    : null,
                                child: Container(
                                  width: 44, height: 44,
                                  alignment: Alignment.center,
                                  child: Icon(Icons.remove, size: 18,
                                      color: customMinutes > 0
                                          ? Colors.orange.shade700
                                          : Colors.grey.shade300),
                                ),
                              ),
                              Container(width: 1, height: 28,
                                  color: customMinutes > 0
                                      ? Colors.orange.shade200
                                      : Colors.grey.shade200),
                              GestureDetector(
                                onTap: () async {
                                  final result = await _showMinutesDialog(customMinutes);
                                  if (result != null) setS(() => customMinutes = result);
                                },
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment: CrossAxisAlignment.baseline,
                                    textBaseline: TextBaseline.alphabetic,
                                    children: [
                                      Text(
                                        customMinutes > 0 ? '$customMinutes' : '--',
                                        style: TextStyle(
                                          fontSize: 22,
                                          fontWeight: FontWeight.bold,
                                          color: customMinutes > 0
                                              ? Colors.black87
                                              : Colors.grey.shade400,
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      Text('分鐘',
                                          style: TextStyle(
                                            fontSize: 13,
                                            color: customMinutes > 0
                                                ? Colors.grey.shade600
                                                : Colors.grey.shade400,
                                          )),
                                    ],
                                  ),
                                ),
                              ),
                              Container(width: 1, height: 28,
                                  color: customMinutes > 0
                                      ? Colors.orange.shade200
                                      : Colors.grey.shade200),
                              GestureDetector(
                                onTap: customMinutes < 999
                                    ? () => setS(() =>
                                        customMinutes = customMinutes == 0
                                            ? 5
                                            : (customMinutes + 5).clamp(5, 999))
                                    : null,
                                child: Container(
                                  width: 44, height: 44,
                                  alignment: Alignment.center,
                                  child: Icon(Icons.add, size: 18,
                                      color: customMinutes < 999
                                          ? Colors.orange.shade700
                                          : Colors.grey.shade300),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  crossFadeState: customExpanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
                  duration: const Duration(milliseconds: 200),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: total == 0
                        ? null
                        : () async {
                            Navigator.pop(ctx);
                            bool settingsChanged = false;
                            final prefs = await SharedPreferences.getInstance();
                            for (final name in selected.keys) {
                              final idx = available.indexWhere((p) => p.name == name);
                              if (idx != -1 && available[idx].linkedSetting != null) {
                                final already = prefs.getBool(available[idx].linkedSetting!) ?? false;
                                if (!already) {
                                  await prefs.setBool(available[idx].linkedSetting!, true);
                                  settingsChanged = true;
                                }
                              }
                            }
                            if (settingsChanged) widget.onSettingsChanged?.call();
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
                            saveHabits();
                          },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                      disabledBackgroundColor: Colors.grey.shade200,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: Text(
                      total == 0 ? '請輸入或選擇習慣' : '新增 ($total 項)',
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      backgroundColor: const Color(0xFFFAF6F1),
      extendBodyBehindAppBar: false,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFFFF7043), Color(0xFFFF8A50)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        title: const Text(
          '我的習慣',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined, color: Colors.white),
            tooltip: '設定',
            onPressed: () async {
              await Navigator.of(context).push(
                PageRouteBuilder(
                  pageBuilder: (_, animation, _) => const SettingsPage(),
                  transitionsBuilder: (_, animation, _, child) => SlideTransition(
                    position: Tween(begin: const Offset(1.0, 0.0), end: Offset.zero)
                        .chain(CurveTween(curve: Curves.easeInOut))
                        .animate(animation),
                    child: child,
                  ),
                ),
              );
              widget.onSettingsChanged?.call();
            },
          ),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFFFAF6F1), Color(0xFFF3EDE5)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Column(
          children: [
            _buildHeader(),
            const SizedBox(height: 14),
            _buildAddButton(),
            const SizedBox(height: 12),
            Expanded(child: _buildHabitList()),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final dl = _dailyHabits;
    final displayDone = dl.isNotEmpty ? dailyDoneCount : weeklyMetCount;
    final displayTotal = dl.isNotEmpty ? dl.length : _weeklyHabits.length;
    final progress = habits.isEmpty ? 0.0 : displayDone / displayTotal;
    final percent = (progress * 100).round();
    final now = DateTime.now();
    const weekdays = ['一', '二', '三', '四', '五', '六', '日'];
    final dateStr = '${now.month}月${now.day}日 週${weekdays[now.weekday - 1]}';
    final primary = allDone0 ? const Color(0xFF43A047) : const Color(0xFFFF7043);
    final secondary = allDone0 ? const Color(0xFF7CB342) : const Color(0xFFFFB74D);

    return ScaleTransition(
      scale: _celebScale,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 500),
        margin: const EdgeInsets.fromLTRB(16, 14, 16, 0),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [primary, secondary],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(26),
          boxShadow: [
            BoxShadow(
              color: primary.withValues(alpha: 0.32),
              blurRadius: 22,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(26),
          child: Stack(
            children: [
              // 裝飾光暈
              Positioned(
                top: -32, right: -28,
                child: Container(
                  width: 120, height: 120,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: 0.10),
                  ),
                ),
              ),
              Positioned(
                bottom: -24, left: -18,
                child: Container(
                  width: 80, height: 80,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: 0.08),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // 日期 pill
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.22),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.calendar_today_rounded,
                                  size: 11, color: Colors.white),
                              const SizedBox(width: 5),
                              Text(
                                dateStr,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (streak > 0)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.22),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Text('🔥', style: TextStyle(fontSize: 12)),
                                const SizedBox(width: 4),
                                Text(
                                  '連續 $streak 天',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        // 吉祥物兔咪（變主角，更大）
                        ScaleTransition(
                          scale: _pulseAnim,
                          child: Container(
                            width: 100, height: 100,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white.withValues(alpha: 0.22),
                            ),
                            alignment: Alignment.center,
                            padding: const EdgeInsets.all(4),
                            child: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 400),
                              transitionBuilder: (child, anim) => FadeTransition(
                                opacity: anim,
                                child: ScaleTransition(
                                  scale: Tween(begin: 0.85, end: 1.0).animate(anim),
                                  child: child,
                                ),
                              ),
                              child: Image.asset(
                                _mascotAsset,
                                key: ValueKey(_mascotAsset),
                                fit: BoxFit.contain,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                '今日進度',
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 0.5,
                                ),
                              ),
                              const SizedBox(height: 2),
                              AnimatedSwitcher(
                                duration: const Duration(milliseconds: 300),
                                child: Text(
                                  _mascotMessage,
                                  key: ValueKey(_mascotMessage),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    height: 1.3,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (habits.isNotEmpty) ...[
                          const SizedBox(width: 10),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                '$displayDone',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 38,
                                  fontWeight: FontWeight.w800,
                                  height: 1.0,
                                  letterSpacing: -1,
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.only(bottom: 6),
                                child: Text(
                                  '/$displayTotal',
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                    if (habits.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: TweenAnimationBuilder<double>(
                              tween: Tween(begin: 0.0, end: progress),
                              duration: const Duration(milliseconds: 700),
                              curve: Curves.easeOut,
                              builder: (_, value, _) => ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: LinearProgressIndicator(
                                  value: value,
                                  minHeight: 9,
                                  backgroundColor: Colors.white.withValues(alpha: 0.25),
                                  valueColor: const AlwaysStoppedAnimation(Colors.white),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            '$percent%',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
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
              border: Border.all(
                color: Colors.orange.shade200,
                width: 1.2,
                style: BorderStyle.solid,
              ),
            ),
            padding: const EdgeInsets.symmetric(vertical: 13),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 22, height: 22,
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

    final dailyEntries = habits.asMap().entries
        .where((e) => (e.value['frequency'] ?? 'daily') != 'weekly')
        .toList();
    final weeklyEntries = habits.asMap().entries
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
          child: Transform.translate(offset: Offset(0, 16 * (1 - v)), child: child),
        ),
        child: _HabitCard(
          key: ValueKey(name),
          habit: habit,
          onToggle: () => toggleHabit(index),
          onEdit: () => _editHabitSheet(index),
          onDelete: () => _confirmDeleteHabit(index),
          isWeekly: (habit['frequency'] ?? 'daily') == 'weekly',
          weeklyCount: _weeklyCount(habit),
          weeklyTarget: (habit['weeklyTarget'] as int?) ?? 3,
          todayCount: List<String>.from((habit['weeklyDates'] as List?) ?? [])
              .where((d) => d == todayString()).length,
          onDecrement: (habit['frequency'] ?? 'daily') == 'weekly'
              ? () => decrementWeeklyHabit(index)
              : null,
          isLinked: _kHomePresets.any((p) =>
              p.linkedSetting != null && habit['name'] == p.name),
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

  Widget _habitSectionLabel(String label, IconData icon, Color color,
      {required int done, required int total}) {
    final allDone = total > 0 && done == total;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, top: 6, left: 2),
      child: Row(
        children: [
          Container(
            width: 26, height: 26,
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
              color: allDone ? Colors.green.shade50 : color.withValues(alpha: 0.10),
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
            Icon(Icons.check_circle_rounded, size: 14, color: Colors.green.shade400),
          ],
        ],
      ),
    );
  }
}

// ── 習慣卡片（含彈跳動畫）──

class _HabitCard extends StatefulWidget {
  final Map<String, dynamic> habit;
  final VoidCallback onToggle;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final bool isWeekly;
  final int weeklyCount;
  final int weeklyTarget;
  final int todayCount;
  final VoidCallback? onDecrement;
  final bool isLinked;

  const _HabitCard({
    super.key,
    required this.habit,
    required this.onToggle,
    required this.onEdit,
    required this.onDelete,
    this.isWeekly = false,
    this.weeklyCount = 0,
    this.weeklyTarget = 3,
    this.todayCount = 0,
    this.onDecrement,
    this.isLinked = false,
  });

  @override
  State<_HabitCard> createState() => _HabitCardState();
}

class _HabitCardState extends State<_HabitCard> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
    );
    _scale = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.78), weight: 25),
      TweenSequenceItem(tween: Tween(begin: 0.78, end: 1.18), weight: 45),
      TweenSequenceItem(tween: Tween(begin: 1.18, end: 1.0), weight: 30),
    ]).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _handleTap() {
    _ctrl.forward(from: 0);
    widget.onToggle();
  }

  Widget _weeklyBtn({required IconData icon, VoidCallback? onTap, double size = 30}) {
    final active = onTap != null;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: active ? Colors.indigo.shade50 : Colors.grey.shade100,
        ),
        child: Icon(icon, size: size * 0.53,
            color: active ? Colors.indigo.shade500 : Colors.grey.shade400),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isWeekly) return _buildWeeklyCard();
    return _buildDailyCard();
  }

  Widget _buildDailyCard() {
    final done = widget.habit['done'] as bool;
    final name = widget.habit['name'] as String;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: done ? const Color(0xFFF1F8E9) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        elevation: done ? 0 : 1.5,
        shadowColor: Colors.orange.withValues(alpha: 0.18),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: IntrinsicHeight(
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 66),
              child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  width: 5,
                  color: done
                      ? Colors.green.shade400
                      : widget.isLinked
                          ? Colors.blue.shade400
                          : Colors.orange.shade400,
                ),
                Expanded(
                  child: ListTile(
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
                    leading: GestureDetector(
                      onTap: _handleTap,
                      child: ScaleTransition(
                        scale: _scale,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 250),
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            gradient: done
                                ? LinearGradient(
                                    colors: [Colors.green.shade400, Colors.green.shade500],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  )
                                : null,
                            color: done ? null : Colors.grey.shade50,
                            border: done
                                ? null
                                : Border.all(color: Colors.grey.shade300, width: 1.8),
                            shape: BoxShape.circle,
                            boxShadow: done
                                ? [BoxShadow(
                                    color: Colors.green.withValues(alpha: 0.3),
                                    blurRadius: 6,
                                    offset: const Offset(0, 2),
                                  )]
                                : null,
                          ),
                          child: done
                              ? const Icon(Icons.check_rounded, color: Colors.white, size: 20)
                              : null,
                        ),
                      ),
                    ),
                    title: AnimatedDefaultTextStyle(
                      duration: const Duration(milliseconds: 250),
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        decoration:
                            done ? TextDecoration.lineThrough : TextDecoration.none,
                        color: done ? Colors.grey.shade400 : Colors.black87,
                      ),
                      child: Text(name, maxLines: 2, overflow: TextOverflow.ellipsis),
                    ),
                    subtitle: widget.isLinked
                        ? Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.link, size: 11, color: Colors.blue.shade400),
                                const SizedBox(width: 3),
                                Text('連動喝水頁面',
                                    style: TextStyle(
                                        fontSize: 11, color: Colors.blue.shade500)),
                              ],
                            ),
                          )
                        : null,
                    trailing: PopupMenuButton<String>(
                      icon: Icon(Icons.more_vert, size: 20, color: Colors.grey.shade400),
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'edit', child: Text('編輯')),
                        PopupMenuItem(
                            value: 'delete',
                            child: Text('刪除', style: TextStyle(color: Colors.red))),
                      ],
                      onSelected: (v) {
                        if (v == 'edit') { widget.onEdit(); }
                        else { widget.onDelete(); }
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
    );
  }

  Widget _buildWeeklyCard() {
    final done = widget.weeklyCount >= widget.weeklyTarget;
    final name = widget.habit['name'] as String;
    final todayCount = widget.todayCount;
    final inProgress = widget.weeklyCount > 0 && !done;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: done
            ? const Color(0xFFF1F8E9)
            : inProgress
                ? const Color(0xFFF3F2FB)
                : Colors.white,
        borderRadius: BorderRadius.circular(16),
        elevation: done ? 0 : 1.5,
        shadowColor: Colors.indigo.withValues(alpha: 0.18),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: IntrinsicHeight(
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 66),
              child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 左邊條
                AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  width: 5,
                  color: done ? Colors.green.shade400 : Colors.indigo.shade300,
                ),
                // ⊖ n ⊕ 計數區（取代 checkbox）
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Center(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _weeklyBtn(
                          icon: Icons.remove_rounded,
                          onTap: todayCount > 0
                              ? () { widget.onDecrement?.call(); }
                              : null,
                        ),
                        const SizedBox(width: 4),
                        ScaleTransition(
                          scale: _scale,
                          child: SizedBox(
                            width: 24,
                            child: Text(
                              '$todayCount',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: todayCount > 0
                                    ? Colors.indigo.shade700
                                    : Colors.grey.shade400,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        _weeklyBtn(
                          icon: Icons.add_rounded,
                          onTap: widget.weeklyCount < 20
                              ? () {
                                  _ctrl.forward(from: 0);
                                  widget.onToggle();
                                }
                              : null,
                        ),
                      ],
                    ),
                  ),
                ),
                // 習慣名稱
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: AnimatedDefaultTextStyle(
                      duration: const Duration(milliseconds: 250),
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        decoration:
                            done ? TextDecoration.lineThrough : TextDecoration.none,
                        color: done ? Colors.grey.shade400 : Colors.black87,
                      ),
                      child: Text(name, maxLines: 2, overflow: TextOverflow.ellipsis),
                    ),
                  ),
                ),
                // 本週 N/M 膠囊
                Center(
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: done
                          ? Colors.green.shade100
                          : Colors.indigo.shade50,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          done ? Icons.check_rounded : Icons.flag_rounded,
                          size: 11,
                          color: done ? Colors.green.shade700 : Colors.indigo.shade400,
                        ),
                        const SizedBox(width: 3),
                        Text(
                          '${widget.weeklyCount}/${widget.weeklyTarget}',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: done ? Colors.green.shade700 : Colors.indigo.shade500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                // 選單
                PopupMenuButton<String>(
                  icon: Icon(Icons.more_vert, size: 20, color: Colors.grey.shade400),
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'edit', child: Text('編輯')),
                    PopupMenuItem(
                        value: 'delete',
                        child: Text('刪除', style: TextStyle(color: Colors.red))),
                  ],
                  onSelected: (v) {
                    if (v == 'edit') { widget.onEdit(); }
                    else { widget.onDelete(); }
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    ),
    );
  }
}

// ── 問候橫幅 ──

class _GreetingBanner extends StatefulWidget {
  final String mascotName;
  final String message;
  final VoidCallback onDismiss;

  const _GreetingBanner({
    required this.mascotName,
    required this.message,
    required this.onDismiss,
  });

  @override
  State<_GreetingBanner> createState() => _GreetingBannerState();
}

class _GreetingBannerState extends State<_GreetingBanner>
    with SingleTickerProviderStateMixin {
  late AnimationController anim;
  late Animation<Offset> slide;

  @override
  void initState() {
    super.initState();
    anim = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 350));
    slide = Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero)
        .animate(CurvedAnimation(parent: anim, curve: Curves.easeOut));
    anim.forward();
  }

  @override
  void dispose() {
    anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      bottom: 80,
      left: 20,
      right: 20,
      child: GestureDetector(
        onTap: widget.onDismiss,
        child: SlideTransition(
          position: slide,
          child: Material(
            color: Colors.transparent,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.orange.withValues(alpha: 0.2),
                    blurRadius: 20,
                    spreadRadius: 2,
                  ),
                ],
                border: Border.all(color: Colors.orange.shade200),
              ),
              child: Row(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                        color: Colors.orange.shade100, shape: BoxShape.circle),
                    padding: const EdgeInsets.all(3),
                    child: Image.asset(
                      'assets/images/mascot/tumi_cheer.png',
                      fit: BoxFit.contain,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      widget.message,
                      style: TextStyle(
                        fontSize: 15,
                        color: Colors.orange.shade900,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── 調整按鈕（＋ / −）──
class _AdjustBtn extends StatelessWidget {
  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;
  const _AdjustBtn({required this.icon, required this.enabled, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        width: 32, height: 32,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: enabled ? Colors.white : Colors.grey.shade100,
          border: Border.all(
            color: enabled ? Colors.orange.shade300 : Colors.grey.shade200,
            width: 1.5,
          ),
          boxShadow: enabled
              ? [BoxShadow(color: Colors.orange.withValues(alpha: 0.15), blurRadius: 4, offset: const Offset(0, 2))]
              : null,
        ),
        child: Icon(icon, size: 16,
            color: enabled ? Colors.orange.shade700 : Colors.grey.shade400),
      ),
    );
  }
}

// ── 頻率切換 Chip ──
class _FreqChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _FreqChip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? Colors.orange : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? Colors.orange : Colors.grey.shade300,
            width: 1.5,
          ),
          boxShadow: selected
              ? [BoxShadow(color: Colors.orange.withValues(alpha: 0.25), blurRadius: 6, offset: const Offset(0, 2))]
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: selected ? Colors.white : Colors.grey.shade600,
          ),
        ),
      ),
    );
  }
}
