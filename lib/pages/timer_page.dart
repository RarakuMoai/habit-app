import 'package:flutter/material.dart';
import 'dart:async';

import '../utils/mascot.dart';
import '../widgets/mascot_app_bar.dart';
import '../widgets/mascot_page_shell.dart';
import '../widgets/mascot_scene.dart';

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

  // 兔咪情境：上班 → openApp 鼓勵；休息 → completedOne 安慰。
  MascotContext get _ctx =>
      _isWork ? MascotContext.openApp : MascotContext.completedOne;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = _isWork ? Colors.orange : Colors.green;
    final emotion = MascotLines.emotionFor(_ctx);
    final speech = MascotLines.lineFor(_ctx, seed: _isWork ? 0 : 1);

    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: const Color(0xFFFFF8F0),
      appBar: MascotAppBar(accent: color),
      body: SafeArea(
        child: MascotPageShell(
          accent: color,
          scene: MascotScene(
            asset: emotion.assetPath,
            accent: color,
            speech: speech,
          ),
          child: _buildTimerContent(color),
        ),
      ),
    );
  }

  Widget _buildTimerContent(Color color) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // 狀態標籤
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: color.withValues(alpha: 0.3)),
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

          const SizedBox(height: 24),

          // 計時圓圈
          Container(
            width: 200,
            height: 200,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.2),
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
                  fontSize: 46,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ),
          ),

          const SizedBox(height: 24),

          // 按鈕
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
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
                        color: color.withValues(alpha: 0.4),
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

          const SizedBox(height: 16),

          Text(
            _isWork ? '專注 25 分鐘，休息 5 分鐘' : '好好休息，準備下一輪！',
            style: TextStyle(color: Colors.grey.shade500, fontSize: 14),
          ),
        ],
      ),
    );
  }
}
