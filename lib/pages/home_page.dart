import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final List<Map<String, dynamic>> _habits = [];
  final TextEditingController _controller = TextEditingController();
  bool _isLoading = true;
  int _streak = 0;

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

    final String? habitsJson = prefs.getString('habits');
    if (habitsJson != null) {
      final List<dynamic> decoded = jsonDecode(habitsJson);
      _habits.addAll(decoded.map((e) => Map<String, dynamic>.from(e)));
    }

    // 跨日處理
    if (lastOpen != null && lastOpen != today) {
      final bool allDone =
          _habits.isNotEmpty && _habits.every((h) => h['done'] == true);

      if (allDone) {
        // 昨天全部完成，連續天數 +1
        _streak++;
      } else {
        // 昨天沒完成，歸零
        _streak = 0;
      }

      await prefs.setInt('streak', _streak);

      // 重置打卡狀態
      for (var habit in _habits) {
        habit['done'] = false;
      }
      await prefs.setString('habits', jsonEncode(_habits));
    }

    await prefs.setString('last_open_date', today);
    setState(() => _isLoading = false);
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
