import 'dart:async';

import 'package:flutter/material.dart';

import '../utils/mascot.dart';
import '../utils/notification_service.dart';
import '../utils/sfx_service.dart';
import '../widgets/mascot_app_bar.dart';
import '../widgets/mascot_page_shell.dart';
import '../widgets/mascot_scene.dart';

class TimerPage extends StatefulWidget {
  const TimerPage({super.key});

  @override
  State<TimerPage> createState() => _TimerPageState();
}

class _TimerPageState extends State<TimerPage> with WidgetsBindingObserver {
  static const int _workMinutes = 25;
  static const int _breakMinutes = 5;

  // 通知 id（同 id 排程會覆蓋舊的，避免堆出一堆過期通知）
  static const int _notifId = 1001;

  int _secondsLeft = _workMinutes * 60;
  bool _isRunning = false;
  bool _isWork = true;
  Timer? _timer;
  // 執行中才有值：當前階段絕對結束時刻。
  // 用 wall-clock 算 remaining，這樣 app 切到背景再回來時間還是對的。
  DateTime? _endTime;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // App 從背景回來，立刻重算剩餘秒數，避免畫面停在背景前的舊值
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _isRunning) {
      _refreshFromEndTime();
    }
  }

  String get _timeString {
    final minutes = _secondsLeft ~/ 60;
    final seconds = _secondsLeft % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  int _phaseSeconds(bool isWork) =>
      (isWork ? _workMinutes : _breakMinutes) * 60;

  // 由絕對結束時刻反推當前剩餘秒數；若已過期則觸發階段結束。
  void _refreshFromEndTime() {
    final end = _endTime;
    if (end == null) return;
    final remaining = end.difference(DateTime.now()).inSeconds;
    if (remaining <= 0) {
      _onPhaseEnded();
    } else {
      setState(() => _secondsLeft = remaining);
    }
  }

  // 階段自然結束（倒數到 0）：通知早已由 OS 排程觸發過了，這裡只更新畫面
  void _onPhaseEnded() {
    _timer?.cancel();
    setState(() {
      _isWork = !_isWork;
      _secondsLeft = _phaseSeconds(_isWork);
      _isRunning = false;
      _endTime = null;
    });
    MascotPersona.interact(
      _isWork ? MascotContext.halfDone : MascotContext.completedOne,
    );
    SfxService.instance.play(SfxCue.complete);
  }

  Future<void> _scheduleEndNotification(DateTime when) async {
    // 第一次排程才會跳系統權限 dialog；使用者拒絕的話通知不會響，倒數還是會繼續走
    final ok = await NotificationService.ensurePermission();
    if (!ok) return;
    await NotificationService.scheduleAt(
      when,
      id: _notifId,
      title: _isWork ? '🍅 專注時間結束' : '☕ 休息結束',
      body: _isWork ? '休息一下，5 分鐘喘口氣。' : '回來放一段安靜時間。',
    );
  }

  void _startPause() {
    if (_isRunning) {
      // 暫停：留下當前剩餘秒數、取消排程通知
      final remaining = _endTime != null
          ? _endTime!
                .difference(DateTime.now())
                .inSeconds
                .clamp(0, _phaseSeconds(_isWork))
          : _secondsLeft;
      _timer?.cancel();
      NotificationService.cancel(_notifId);
      setState(() {
        _secondsLeft = remaining;
        _isRunning = false;
        _endTime = null;
      });
      SfxService.instance.play(SfxCue.tap);
    } else {
      // 開始：算結束時刻、排通知、起 UI tick
      if (_secondsLeft <= 0) _secondsLeft = _phaseSeconds(_isWork);
      final end = DateTime.now().add(Duration(seconds: _secondsLeft));
      setState(() {
        _endTime = end;
        _isRunning = true;
      });
      _scheduleEndNotification(end);
      _timer = Timer.periodic(
        const Duration(seconds: 1),
        (_) => _refreshFromEndTime(),
      );
      MascotPersona.interact(
        _isWork ? MascotContext.openApp : MascotContext.halfDone,
      );
      SfxService.instance.play(SfxCue.tap);
    }
  }

  void _reset() {
    _timer?.cancel();
    NotificationService.cancel(_notifId);
    setState(() {
      _isRunning = false;
      _isWork = true;
      _secondsLeft = _phaseSeconds(true);
      _endTime = null;
    });
    MascotPersona.interact(MascotContext.notStarted);
    SfxService.instance.play(SfxCue.cancel);
  }

  @override
  Widget build(BuildContext context) {
    final color = _isWork ? Colors.orange : Colors.green;

    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: const Color(0xFFFFF8F0),
      appBar: MascotAppBar(accent: color),
      body: Stack(
        children: [
          // 場景背景：延伸到 AppBar 後面，跟首頁同樣 56% 高度
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: MediaQuery.of(context).size.height * 0.56,
            child: const MascotSceneBackground(
              'assets/scenes/timer/timer_bg.png',
            ),
          ),
          SafeArea(
            child: MascotPageShell(
              accent: color,
              scene: PersonaScene(accent: color),
              child: _buildTimerContent(color),
            ),
          ),
        ],
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
                  NotificationService.cancel(_notifId);
                  setState(() {
                    _isWork = !_isWork;
                    _secondsLeft = _phaseSeconds(_isWork);
                    _isRunning = false;
                    _endTime = null;
                  });
                  // 互動：跳過 → 兔咪換對應模式情緒
                  MascotPersona.interact(
                    _isWork
                        ? MascotContext.openApp
                        : MascotContext.completedOne,
                  );
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
