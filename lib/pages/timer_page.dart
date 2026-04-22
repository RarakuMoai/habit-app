import 'package:flutter/material.dart';
import 'dart:async';

class TimerPage extends StatefulWidget {
  const TimerPage({super.key});

  @override
  State<TimerPage> createState() => _TimerPageState();
}

class _TimerPageState extends State<TimerPage> {
  static const int _workMinutes = 25;
  static const int _breakMinutes = 5;

  int _secondsLeft = _workMinutes * 60;
  bool _isRunning = false;
  bool _isWork = true;
  Timer? _timer;

  String get _timeString {
    final minutes = _secondsLeft ~/ 60;
    final seconds = _secondsLeft % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  void _startPause() {
    if (_isRunning) {
      _timer?.cancel();
      setState(() => _isRunning = false);
    } else {
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (_secondsLeft <= 0) {
          _timer?.cancel();
          setState(() {
            _isWork = !_isWork;
            _secondsLeft = (_isWork ? _workMinutes : _breakMinutes) * 60;
            _isRunning = false;
          });
        } else {
          setState(() => _secondsLeft--);
        }
      });
      setState(() => _isRunning = true);
    }
  }

  void _reset() {
    _timer?.cancel();
    setState(() {
      _isRunning = false;
      _isWork = true;
      _secondsLeft = _workMinutes * 60;
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = _isWork ? Colors.orange : Colors.green;

    return Scaffold(
      backgroundColor: const Color(0xFFFFF8F0),
      appBar: AppBar(
        backgroundColor: color,
        title: const Text('番茄鐘', style: TextStyle(color: Colors.white)),
        centerTitle: true,
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // 狀態標籤
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: color.withOpacity(0.3)),
              ),
              child: Text(
                _isWork ? '🍅 專注時間' : '☕ 休息時間',
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),

            const SizedBox(height: 48),

            // 計時圓圈
            Container(
              width: 220,
              height: 220,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: color.withOpacity(0.2),
                    blurRadius: 30,
                    spreadRadius: 5,
                  ),
                ],
                border: Border.all(color: color, width: 4),
              ),
              child: Center(
                child: Text(
                  _timeString,
                  style: TextStyle(
                    fontSize: 52,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
              ),
            ),

            const SizedBox(height: 48),

            // 按鈕
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // 重置按鈕
                GestureDetector(
                  onTap: _reset,
                  child: Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.refresh, color: Colors.grey.shade600),
                  ),
                ),

                const SizedBox(width: 24),

                // 開始/暫停按鈕
                GestureDetector(
                  onTap: _startPause,
                  child: Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: color.withOpacity(0.4),
                          blurRadius: 15,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: Icon(
                      _isRunning ? Icons.pause : Icons.play_arrow,
                      color: Colors.white,
                      size: 40,
                    ),
                  ),
                ),

                const SizedBox(width: 24),

                // 跳過按鈕
                GestureDetector(
                  onTap: () {
                    _timer?.cancel();
                    setState(() {
                      _isWork = !_isWork;
                      _secondsLeft =
                          (_isWork ? _workMinutes : _breakMinutes) * 60;
                      _isRunning = false;
                    });
                  },
                  child: Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.skip_next, color: Colors.grey.shade600),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 48),

            // 說明文字
            Text(
              _isWork ? '專注 25 分鐘，休息 5 分鐘' : '好好休息，準備下一輪！',
              style: TextStyle(color: Colors.grey.shade500, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }
}
