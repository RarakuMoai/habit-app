import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'settings_page.dart';

class HomePage extends StatefulWidget {
  // 從設定頁返回時通知 MainPage 重新載入功能開關
  final VoidCallback? onSettingsChanged;

  const HomePage({super.key, this.onSettingsChanged});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final List<Map<String, dynamic>> habits = [];
  final TextEditingController controller = TextEditingController();
  bool isLoading = true;
  int streak = 0;

  // 用戶資訊
  String _nickname = '你';
  String mascotName0 = '兔咪';

  // 每日問候相關
  bool yesterdayAllDone = false;
  DateTime? onboardingDate;

  @override
  void initState() {
    super.initState();
    loadHabits();
  }

  Future<void> loadHabits() async {
    final prefs = await SharedPreferences.getInstance();

    final String today = todayString();
    final String? lastOpen = prefs.getString('last_open_date');
    streak = prefs.getInt('streak') ?? 0;

    // 讀取用戶資訊
    _nickname = prefs.getString('user_nickname') ?? '你';
    mascotName0 = prefs.getString('mascot_name') ?? '兔咪';

    // 讀取 onboarding 完成日期（用來判斷前三天問候語）
    final String? obDateStr = prefs.getString('onboarding_date');
    if (obDateStr != null) {
      onboardingDate = DateTime.tryParse(obDateStr);
    } else {
      // 第一次進入 HomePage 就記錄 onboarding 完成日期
      onboardingDate = DateTime.now();
      await prefs.setString('onboarding_date', onboardingDate!.toIso8601String());
    }

    final String? habitsJson = prefs.getString('habits');
    if (habitsJson != null) {
      final List<dynamic> decoded = jsonDecode(habitsJson);
      habits.addAll(decoded.map((e) => Map<String, dynamic>.from(e)));
    }

    // 跨日處理
    if (lastOpen != null && lastOpen != today) {
      final bool allDone =
          habits.isNotEmpty && habits.every((h) => h['done'] == true);
      yesterdayAllDone = allDone;

      if (allDone) {
        streak++;
      } else {
        streak = 0;
      }

      await prefs.setInt('streak', streak);

      // 重置打卡狀態
      for (var habit in habits) {
        habit['done'] = false;
      }
      await prefs.setString('habits', jsonEncode(habits));
    }

    // 判斷是否今天第一次開啟 → 顯示問候
    final bool isFirstOpenToday = lastOpen != today;
    await prefs.setString('last_open_date', today);

    setState(() => isLoading = false);

    // 今天第一次開啟才顯示問候
    if (isFirstOpenToday && mounted) {
      Future.delayed(const Duration(milliseconds: 400), () {
        if (mounted) showGreeting(prefs, lastOpen);
      });
    }
  }

  // 判斷並顯示每日問候
  void showGreeting(SharedPreferences prefs, String? lastOpen) {
    final String message = buildGreetingMessage(lastOpen);
    showGreetingBanner(message);
  }

  String buildGreetingMessage(String? lastOpen) {
    // 久違回來（上次超過2天前）
    if (lastOpen != null) {
      final parts = lastOpen.split('-');
      if (parts.length == 3) {
        final lastDate = DateTime.tryParse(
            '${parts[0]}-${parts[1].padLeft(2, '0')}-${parts[2].padLeft(2, '0')}');
        if (lastDate != null) {
          final diff = DateTime.now().difference(lastDate).inDays;
          if (diff >= 2) return '你回來了！我好想你 🐰';
        }
      }
    }

    // Streak >= 7 天
    if (streak >= 7) return '連續一週了！你真的很厲害！🔥';

    // 昨天全部完成
    if (yesterdayAllDone) return '昨天表現超棒！今天繼續！⭐';

    // onboarding 完成後前三天
    if (onboardingDate != null) {
      final daysSince = DateTime.now().difference(onboardingDate!).inDays + 1;
      if (daysSince <= 3) return '第$daysSince天！我們越來越熟了～';
    }

    // 一般問候
    return '早安 $_nickname！今天也要加油喔 🌟';
  }

  // 底部滑出問候卡片，2秒後自動關閉
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
    // 2秒後自動關閉
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

  Color get _mascotColor {
    if (habits.isEmpty) return Colors.orange.shade200;
    final ratio = doneCount / habits.length;
    if (ratio == 1.0) return Colors.green.shade300;
    if (ratio >= 0.5) return Colors.orange.shade300;
    if (ratio > 0) return Colors.orange.shade200;
    return Colors.grey.shade300;
  }

  void addHabit() {
    if (controller.text.trim().isEmpty) return;
    setState(() {
      habits.add({'name': controller.text.trim(), 'done': false});
      controller.clear();
    });
    saveHabits();
  }

  void toggleHabit(int index) {
    setState(() {
      habits[index]['done'] = !habits[index]['done'];
    });
    saveHabits();
  }

  void deleteHabit(int index) {
    setState(() {
      habits.removeAt(index);
    });
    saveHabits();
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      backgroundColor: const Color(0xFFFFF8F0),
      appBar: AppBar(
        backgroundColor: Colors.orange,
        title: const Text('我的習慣', style: TextStyle(color: Colors.white)),
        centerTitle: true,
        actions: [
          // 齒輪按鈕：進入設定頁，返回後通知 MainPage 重新載入功能開關
          IconButton(
            icon: const Icon(Icons.settings_outlined, color: Colors.white),
            tooltip: '設定',
            onPressed: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SettingsPage()),
              );
              widget.onSettingsChanged?.call();
            },
          ),
        ],
      ),
      body: Column(
        children: [
          const SizedBox(height: 24),

          // 吉祥物
          AnimatedContainer(
            duration: const Duration(milliseconds: 400),
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              color: _mascotColor,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(_mascotEmoji, style: const TextStyle(fontSize: 48)),
            ),
          ),

          const SizedBox(height: 12),

          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: Text(
              _mascotMessage,
              key: ValueKey(_mascotMessage),
              style: const TextStyle(fontSize: 15, color: Colors.orange),
              textAlign: TextAlign.center,
            ),
          ),

          const SizedBox(height: 12),

          // 連續天數
          if (streak > 0)
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: Container(
                key: ValueKey(streak),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.orange.shade100,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '🔥 已連續 $streak 天達成！',
                  style: TextStyle(
                    color: Colors.orange.shade800,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ),
            ),

          const SizedBox(height: 12),

          // 今日進度
          if (habits.isNotEmpty)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 24),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: allDone0 ? Colors.green.shade50 : Colors.orange.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: allDone0
                      ? Colors.green.shade300
                      : Colors.orange.shade200,
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '今日進度',
                    style: TextStyle(
                      color: allDone0
                          ? Colors.green.shade700
                          : Colors.orange.shade700,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    '$doneCount / ${habits.length} 完成',
                    style: TextStyle(
                      color: allDone0
                          ? Colors.green.shade700
                          : Colors.orange.shade700,
                    ),
                  ),
                ],
              ),
            ),

          const SizedBox(height: 16),

          // 新增習慣
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: controller,
                    decoration: InputDecoration(
                      hintText: '新增一個習慣...',
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    onSubmitted: (_) => addHabit(),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: addHabit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 16,
                    ),
                  ),
                  child: const Icon(Icons.add, color: Colors.white),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // 習慣清單
          Expanded(
            child: habits.isEmpty
                ? const Center(
                    child: Text(
                      '還沒有習慣，新增一個吧！',
                      style: TextStyle(color: Colors.grey),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    itemCount: habits.length,
                    itemBuilder: (context, index) {
                      final habit = habits[index];
                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: habit['done']
                              ? Colors.orange.shade50
                              : Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: habit['done']
                                ? Colors.orange
                                : Colors.grey.shade200,
                          ),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                habit['name'],
                                style: TextStyle(
                                  fontSize: 16,
                                  decoration: habit['done']
                                      ? TextDecoration.lineThrough
                                      : null,
                                  color: habit['done']
                                      ? Colors.grey
                                      : Colors.black87,
                                ),
                              ),
                            ),
                            GestureDetector(
                              onTap: () => toggleHabit(index),
                              child: Container(
                                width: 32,
                                height: 32,
                                decoration: BoxDecoration(
                                  color: habit['done']
                                      ? Colors.orange
                                      : Colors.grey.shade200,
                                  shape: BoxShape.circle,
                                ),
                                child: habit['done']
                                    ? const Icon(
                                        Icons.check,
                                        color: Colors.white,
                                        size: 18,
                                      )
                                    : null,
                              ),
                            ),
                            const SizedBox(width: 8),
                            GestureDetector(
                              onTap: () => deleteHabit(index),
                              child: Container(
                                width: 32,
                                height: 32,
                                decoration: BoxDecoration(
                                  color: Colors.red.shade50,
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  Icons.delete_outline,
                                  color: Colors.red.shade300,
                                  size: 18,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

// 底部問候卡片 Widget（Overlay 方式顯示）
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
              padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
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
                        color: Colors.orange.shade200,
                        shape: BoxShape.circle),
                    child: const Center(
                        child: Text('🐰',
                            style: TextStyle(fontSize: 26))),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      widget.message,
                      style: TextStyle(
                          fontSize: 15,
                          color: Colors.orange.shade900,
                          fontWeight: FontWeight.w600),
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
