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
  final List<Map<String, dynamic>> _habits = [];
  final TextEditingController _controller = TextEditingController();
  bool _isLoading = true;
  int _streak = 0;

  // 用戶資訊
  String _nickname = '你';
  String _mascotName = '兔咪';

  // 每日問候相關
  bool _yesterdayAllDone = false;
  DateTime? _onboardingDate;

  @override
  void initState() {
    super.initState();
    _loadHabits();
  }

  Future<void> _loadHabits() async {
    final prefs = await SharedPreferences.getInstance();

    final String today = _todayString();
    final String? lastOpen = prefs.getString('last_open_date');
    _streak = prefs.getInt('streak') ?? 0;

    // 讀取用戶資訊
    _nickname = prefs.getString('user_nickname') ?? '你';
    _mascotName = prefs.getString('mascot_name') ?? '兔咪';

    // 讀取 onboarding 完成日期（用來判斷前三天問候語）
    final String? obDateStr = prefs.getString('onboarding_date');
    if (obDateStr != null) {
      _onboardingDate = DateTime.tryParse(obDateStr);
    } else {
      // 第一次進入 HomePage 就記錄 onboarding 完成日期
      _onboardingDate = DateTime.now();
      await prefs.setString('onboarding_date', _onboardingDate!.toIso8601String());
    }

    final String? habitsJson = prefs.getString('habits');
    if (habitsJson != null) {
      final List<dynamic> decoded = jsonDecode(habitsJson);
      _habits.addAll(decoded.map((e) => Map<String, dynamic>.from(e)));
    }

    // 跨日處理
    if (lastOpen != null && lastOpen != today) {
      final bool allDone =
          _habits.isNotEmpty && _habits.every((h) => h['done'] == true);
      _yesterdayAllDone = allDone;

      if (allDone) {
        _streak++;
      } else {
        _streak = 0;
      }

      await prefs.setInt('streak', _streak);

      // 重置打卡狀態
      for (var habit in _habits) {
        habit['done'] = false;
      }
      await prefs.setString('habits', jsonEncode(_habits));
    }

    // 判斷是否今天第一次開啟 → 顯示問候
    final bool isFirstOpenToday = lastOpen != today;
    await prefs.setString('last_open_date', today);

    setState(() => _isLoading = false);

    // 今天第一次開啟才顯示問候
    if (isFirstOpenToday && mounted) {
      Future.delayed(const Duration(milliseconds: 400), () {
        if (mounted) _showGreeting(prefs, lastOpen);
      });
    }
  }

  // 判斷並顯示每日問候
  void _showGreeting(SharedPreferences prefs, String? lastOpen) {
    final String message = _buildGreetingMessage(lastOpen);
    _showGreetingBanner(message);
  }

  String _buildGreetingMessage(String? lastOpen) {
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
    if (_streak >= 7) return '連續一週了！你真的很厲害！🔥';

    // 昨天全部完成
    if (_yesterdayAllDone) return '昨天表現超棒！今天繼續！⭐';

    // onboarding 完成後前三天
    if (_onboardingDate != null) {
      final daysSince = DateTime.now().difference(_onboardingDate!).inDays + 1;
      if (daysSince <= 3) return '第$daysSince天！我們越來越熟了～';
    }

    // 一般問候
    return '早安 $_nickname！今天也要加油喔 🌟';
  }

  // 底部滑出問候卡片，2秒後自動關閉
  void _showGreetingBanner(String message) {
    final overlay = Overlay.of(context);
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _GreetingBanner(
        mascotName: _mascotName,
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

  String _todayString() {
    final now = DateTime.now();
    return '${now.year}-${now.month}-${now.day}';
  }

  Future<void> _saveHabits() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('habits', jsonEncode(_habits));
  }

  int get _doneCount => _habits.where((h) => h['done'] == true).length;

  bool get _allDone => _habits.isNotEmpty && _doneCount == _habits.length;

  String get _mascotEmoji {
    if (_habits.isEmpty) return '👾';
    final ratio = _doneCount / _habits.length;
    if (ratio == 1.0) return '🥳';
    if (ratio >= 0.5) return '😊';
    if (ratio > 0) return '😐';
    return '😴';
  }

  String get _mascotMessage {
    if (_habits.isEmpty) return '新增一個習慣，我們一起努力！';
    final ratio = _doneCount / _habits.length;
    if (ratio == 1.0) return '太厲害了！今天全部完成！🎉';
    if (ratio >= 0.5) return '已經完成一半了！繼續加油！💪';
    if (ratio > 0) return '好的開始！繼續保持！🌟';
    return '今天要開始了嗎？我在等你！';
  }

  Color get _mascotColor {
    if (_habits.isEmpty) return Colors.orange.shade200;
    final ratio = _doneCount / _habits.length;
    if (ratio == 1.0) return Colors.green.shade300;
    if (ratio >= 0.5) return Colors.orange.shade300;
    if (ratio > 0) return Colors.orange.shade200;
    return Colors.grey.shade300;
  }

  void _addHabit() {
    if (_controller.text.trim().isEmpty) return;
    setState(() {
      _habits.add({'name': _controller.text.trim(), 'done': false});
      _controller.clear();
    });
    _saveHabits();
  }

  void _toggleHabit(int index) {
    setState(() {
      _habits[index]['done'] = !_habits[index]['done'];
    });
    _saveHabits();
  }

  void _deleteHabit(int index) {
    setState(() {
      _habits.removeAt(index);
    });
    _saveHabits();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
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
          if (_streak > 0)
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: Container(
                key: ValueKey(_streak),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.orange.shade100,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '🔥 已連續 $_streak 天達成！',
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
          if (_habits.isNotEmpty)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 24),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: _allDone ? Colors.green.shade50 : Colors.orange.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _allDone
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
                      color: _allDone
                          ? Colors.green.shade700
                          : Colors.orange.shade700,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    '$_doneCount / ${_habits.length} 完成',
                    style: TextStyle(
                      color: _allDone
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
                    controller: _controller,
                    decoration: InputDecoration(
                      hintText: '新增一個習慣...',
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    onSubmitted: (_) => _addHabit(),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _addHabit,
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
            child: _habits.isEmpty
                ? const Center(
                    child: Text(
                      '還沒有習慣，新增一個吧！',
                      style: TextStyle(color: Colors.grey),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    itemCount: _habits.length,
                    itemBuilder: (context, index) {
                      final habit = _habits[index];
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
                              onTap: () => _toggleHabit(index),
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
                              onTap: () => _deleteHabit(index),
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
  late AnimationController _anim;
  late Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(vsync: this, duration: const Duration(milliseconds: 350));
    _slide = Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero)
        .animate(CurvedAnimation(parent: _anim, curve: Curves.easeOut));
    _anim.forward();
  }

  @override
  void dispose() {
    _anim.dispose();
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
          position: _slide,
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
                    decoration: BoxDecoration(color: Colors.orange.shade200, shape: BoxShape.circle),
                    child: const Center(child: Text('🐰', style: TextStyle(fontSize: 26))),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      widget.message,
                      style: TextStyle(fontSize: 15, color: Colors.orange.shade900, fontWeight: FontWeight.w600),
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
