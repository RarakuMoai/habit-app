import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'settings_page.dart';

class HomePage extends StatefulWidget {
  final VoidCallback? onSettingsChanged;
  const HomePage({super.key, this.onSettingsChanged});

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
    ]).animate(CurvedAnimation(parent: _celebCtrl, curve: Curves.elasticOut));

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
      final bool allDone = habits.isNotEmpty && habits.every((h) => h['done'] == true);
      yesterdayAllDone = allDone;
      if (allDone) {
        streak++;
      } else {
        streak = 0;
      }
      await prefs.setInt('streak', streak);
      for (var habit in habits) {
        habit['done'] = false;
      }
      await prefs.setString('habits', jsonEncode(habits));
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

  Future<void> saveHabits() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('habits', jsonEncode(habits));
  }

  int get doneCount => habits.where((h) => h['done'] == true).length;
  bool get allDone0 => habits.isNotEmpty && doneCount == habits.length;

  String get _mascotEmoji {
    if (habits.isEmpty) return '👾';
    final ratio = doneCount / habits.length;
    if (ratio == 1.0) return '🥳';
    if (ratio >= 0.5) return '😊';
    if (ratio > 0) return '😐';
    return '😴';
  }

  String get _mascotMessage {
    if (habits.isEmpty) return '新增一個習慣，我們一起努力！';
    final ratio = doneCount / habits.length;
    if (ratio == 1.0) return '太厲害了！今天全部完成！🎉';
    if (ratio >= 0.5) return '已經完成一半了！繼續加油！💪';
    if (ratio > 0) return '好的開始！繼續保持！🌟';
    return '今天要開始了嗎？我在等你！';
  }

  void toggleHabit(int index) {
    final wasAllDone = allDone0;
    setState(() {
      habits[index]['done'] = !habits[index]['done'];
    });
    saveHabits();
    if (!wasAllDone && allDone0) {
      _celebCtrl.forward(from: 0);
    }
  }

  void deleteHabit(int index) {
    final name = habits[index]['name'] as String;
    _animatedIn.remove(name);
    setState(() => habits.removeAt(index));
    saveHabits();
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

  static const List<String> _kHabitPresets = [
    '刷牙', '整理環境', '閱讀 15 分鐘', '早起', '運動 30 分鐘',
    '喝足夠的水', '冥想 10 分鐘', '早睡',
  ];

  Future<void> _showAddHabitSheet() async {
    final nameCtrl = TextEditingController();
    final existing = habits.map((h) => h['name'] as String).toSet();
    final available = _kHabitPresets.where((n) => !existing.contains(n)).toList();
    final selected = <String>{};

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
            padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(ctx).viewInsets.bottom + 32),
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
                const Text('新增習慣', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                TextField(
                  controller: nameCtrl,
                  autofocus: true,
                  onChanged: (_) => setS(() {}),
                  decoration: InputDecoration(
                    hintText: '自訂習慣名稱...',
                    prefixIcon: const Icon(Icons.edit_outlined, size: 18),
                    filled: true,
                    fillColor: Colors.grey.shade50,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                if (available.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text('常用習慣', style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8, runSpacing: 8,
                    children: available.map((name) {
                      final isSelected = selected.contains(name);
                      return FilterChip(
                        label: Text(name),
                        selected: isSelected,
                        selectedColor: Colors.orange.shade100,
                        checkmarkColor: Colors.orange,
                        labelStyle: TextStyle(
                          color: isSelected ? Colors.orange.shade800 : Colors.black87,
                          fontSize: 13,
                        ),
                        onSelected: (v) => setS(() {
                          if (v) { selected.add(name); } else { selected.remove(name); }
                        }),
                      );
                    }).toList(),
                  ),
                ],
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: total == 0
                        ? null
                        : () {
                            Navigator.pop(ctx);
                            setState(() {
                              if (customName.isNotEmpty) {
                                habits.add({'name': customName, 'done': false});
                              }
                              for (final name in selected) {
                                habits.add({'name': name, 'done': false});
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
      backgroundColor: const Color(0xFFF7F3EF),
      appBar: AppBar(
        backgroundColor: const Color(0xFFFF7043),
        elevation: 0,
        title: const Text('我的習慣'),
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
      body: Column(
        children: [
          _buildHeader(),
          const SizedBox(height: 12),
          _buildAddButton(),
          const SizedBox(height: 12),
          Expanded(child: _buildHabitList()),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    final progress = habits.isEmpty ? 0.0 : doneCount / habits.length;
    return ScaleTransition(
      scale: _celebScale,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 500),
        margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: allDone0
                ? [const Color(0xFF43A047), const Color(0xFF66BB6A)]
                : [const Color(0xFFFF7043), const Color(0xFFFFAB40)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: (allDone0 ? Colors.green : const Color(0xFFFF7043))
                  .withValues(alpha: 0.35),
              blurRadius: 18,
              offset: const Offset(0, 7),
            ),
          ],
        ),
        child: Column(
          children: [
            Row(
              children: [
                ScaleTransition(
                  scale: _pulseAnim,
                  child: Text(_mascotEmoji, style: const TextStyle(fontSize: 50)),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 300),
                        child: Text(
                          _mascotMessage,
                          key: ValueKey(_mascotMessage),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (streak > 0)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            '🔥 連續 $streak 天',
                            style: const TextStyle(color: Colors.white70, fontSize: 12),
                          ),
                        ),
                    ],
                  ),
                ),
                if (habits.isNotEmpty) ...[
                  const SizedBox(width: 10),
                  Column(
                    children: [
                      Text(
                        '$doneCount',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 32,
                          fontWeight: FontWeight.w800,
                          height: 1.0,
                        ),
                      ),
                      Text(
                        '/ ${habits.length}',
                        style: const TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                    ],
                  ),
                ],
              ],
            ),
            if (habits.isNotEmpty) ...[
              const SizedBox(height: 14),
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.0, end: progress),
                duration: const Duration(milliseconds: 700),
                curve: Curves.easeOut,
                builder: (_, value, _) => ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: value,
                    minHeight: 8,
                    backgroundColor: Colors.white.withValues(alpha: 0.3),
                    valueColor: const AlwaysStoppedAnimation(Colors.white),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildAddButton() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: _showAddHabitSheet,
          icon: const Icon(Icons.add),
          label: const Text('新增習慣'),
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.orange,
            side: BorderSide(color: Colors.orange.shade300),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            padding: const EdgeInsets.symmetric(vertical: 14),
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
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: habits.length,
      itemBuilder: (context, index) {
        final habit = habits[index];
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
            onRename: () => renameHabit(index),
            onDelete: () => _confirmDeleteHabit(index),
          ),
        );
      },
    );
  }
}

// ── 習慣卡片（含彈跳動畫）──

class _HabitCard extends StatefulWidget {
  final Map<String, dynamic> habit;
  final VoidCallback onToggle;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  const _HabitCard({
    super.key,
    required this.habit,
    required this.onToggle,
    required this.onRename,
    required this.onDelete,
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

  @override
  Widget build(BuildContext context) {
    final done = widget.habit['done'] as bool;
    final name = widget.habit['name'] as String;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        elevation: done ? 0 : 2,
        shadowColor: Colors.black12,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  width: 5,
                  color: done ? Colors.green.shade400 : Colors.orange.shade400,
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
                            color: done ? Colors.green.shade400 : Colors.transparent,
                            border: done
                                ? null
                                : Border.all(color: Colors.grey.shade300, width: 2),
                            shape: BoxShape.circle,
                          ),
                          child: done
                              ? const Icon(Icons.check, color: Colors.white, size: 18)
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
                      child: Text(name),
                    ),
                    trailing: PopupMenuButton<String>(
                      icon: Icon(Icons.more_vert, size: 20, color: Colors.grey.shade400),
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'rename', child: Text('改名')),
                        PopupMenuItem(
                          value: 'delete',
                          child: Text('刪除', style: TextStyle(color: Colors.red)),
                        ),
                      ],
                      onSelected: (action) {
                        if (action == 'rename') {
                          widget.onRename();
                        } else {
                          widget.onDelete();
                        }
                      },
                    ),
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
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                        color: Colors.orange.shade200, shape: BoxShape.circle),
                    child:
                        const Center(child: Text('🐰', style: TextStyle(fontSize: 26))),
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
