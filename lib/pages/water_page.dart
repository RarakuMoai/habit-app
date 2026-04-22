import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class WaterPage extends StatefulWidget {
  const WaterPage({super.key});

  @override
  State<WaterPage> createState() => _WaterPageState();
}

class _WaterPageState extends State<WaterPage> {
  int _cups = 0;
  static const int _goal = 8;
  String _todayKey = '';

  @override
  void initState() {
    super.initState();
    _loadWater();
  }

  String _todayString() {
    final now = DateTime.now();
    return '${now.year}-${now.month}-${now.day}';
  }

  Future<void> _loadWater() async {
    final prefs = await SharedPreferences.getInstance();
    final today = _todayString();
    _todayKey = 'water_$today';
    setState(() {
      _cups = prefs.getInt(_todayKey) ?? 0;
    });
  }

  Future<void> _addCup() async {
    if (_cups >= _goal) return;
    final prefs = await SharedPreferences.getInstance();
    setState(() => _cups++);
    await prefs.setInt(_todayKey, _cups);
  }

  Future<void> _removeCup() async {
    if (_cups <= 0) return;
    final prefs = await SharedPreferences.getInstance();
    setState(() => _cups--);
    await prefs.setInt(_todayKey, _cups);
  }

  String get _message {
    if (_cups == 0) return '今天還沒喝水，記得補充！💧';
    if (_cups < 4) return '繼續加油，多喝點水！';
    if (_cups < _goal) return '快到了！剩 ${_goal - _cups} 杯就達標！';
    return '太棒了！今天喝水目標達成！🎉';
  }

  @override
  Widget build(BuildContext context) {
    final progress = _cups / _goal;

    return Scaffold(
      backgroundColor: const Color(0xFFF0F8FF),
      appBar: AppBar(
        backgroundColor: Colors.blue,
        title: const Text('喝水紀錄', style: TextStyle(color: Colors.white)),
        centerTitle: true,
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // 水杯圖示
            Text('💧', style: TextStyle(fontSize: 72)),

            const SizedBox(height: 16),

            // 杯數顯示
            Text(
              '$_cups / $_goal 杯',
              style: const TextStyle(
                fontSize: 36,
                fontWeight: FontWeight.bold,
                color: Colors.blue,
              ),
            ),

            const SizedBox(height: 8),

            Text(
              _message,
              style: TextStyle(color: Colors.blue.shade400, fontSize: 14),
              textAlign: TextAlign.center,
            ),

            const SizedBox(height: 32),

            // 進度條
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 48),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 16,
                  backgroundColor: Colors.blue.shade50,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    Colors.blue.shade300,
                  ),
                ),
              ),
            ),

            const SizedBox(height: 48),

            // 按鈕
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // 減少
                GestureDetector(
                  onTap: _removeCup,
                  child: Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.blue.shade200),
                    ),
                    child: Icon(Icons.remove, color: Colors.blue.shade400),
                  ),
                ),

                const SizedBox(width: 32),

                // 新增一杯
                GestureDetector(
                  onTap: _addCup,
                  child: Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: Colors.blue,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.blue.withOpacity(0.4),
                          blurRadius: 15,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: const Icon(Icons.add, color: Colors.white, size: 40),
                  ),
                ),

                const SizedBox(width: 32),

                // 佔位（保持對稱）
                const SizedBox(width: 56, height: 56),
              ],
            ),

            const SizedBox(height: 16),
            Text(
              '每天目標 $_goal 杯',
              style: TextStyle(color: Colors.grey.shade400, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}
