import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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

class _TimerPageState extends State<TimerPage>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
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
  // 本次開啟 app 後完成的專注輪數（不持久化，給當下的成就感用）
  int _roundsDone = 0;

  // 計時中圓圈的呼吸光暈（repeat reverse，暫停時停在原處不晃）
  late final AnimationController _breath;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _breath = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    _breath.dispose();
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

  // 當前階段已完成比例 0~1（給進度圓環用）
  double get _progress =>
      1 - (_secondsLeft / _phaseSeconds(_isWork)).clamp(0.0, 1.0);

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
    _breath.stop();
    setState(() {
      if (_isWork) _roundsDone++; // 完成一輪專注才算一顆番茄
      _isWork = !_isWork;
      _secondsLeft = _phaseSeconds(_isWork);
      _isRunning = false;
      _endTime = null;
    });
    MascotPersona.interact(
      _isWork ? MascotContext.halfDone : MascotContext.completedOne,
    );
    SfxService.instance.play(SfxCue.complete);
    unawaited(HapticFeedback.mediumImpact());
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
      _breath.stop();
      NotificationService.cancel(_notifId);
      setState(() {
        _secondsLeft = remaining;
        _isRunning = false;
        _endTime = null;
      });
      SfxService.instance.play(SfxCue.tap);
      unawaited(HapticFeedback.lightImpact());
    } else {
      // 開始：算結束時刻、排通知、起 UI tick
      if (_secondsLeft <= 0) _secondsLeft = _phaseSeconds(_isWork);
      final end = DateTime.now().add(Duration(seconds: _secondsLeft));
      setState(() {
        _endTime = end;
        _isRunning = true;
      });
      _breath.repeat(reverse: true);
      _scheduleEndNotification(end);
      _timer = Timer.periodic(
        const Duration(seconds: 1),
        (_) => _refreshFromEndTime(),
      );
      MascotPersona.interact(
        _isWork ? MascotContext.openApp : MascotContext.halfDone,
      );
      SfxService.instance.play(SfxCue.tap);
      unawaited(HapticFeedback.mediumImpact());
    }
  }

  void _reset() {
    _timer?.cancel();
    _breath.stop();
    NotificationService.cancel(_notifId);
    setState(() {
      _isRunning = false;
      _isWork = true;
      _secondsLeft = _phaseSeconds(true);
      _endTime = null;
    });
    MascotPersona.interact(MascotContext.notStarted);
    SfxService.instance.play(SfxCue.cancel);
    unawaited(HapticFeedback.lightImpact());
  }

  void _skipPhase() {
    _timer?.cancel();
    _breath.stop();
    NotificationService.cancel(_notifId);
    setState(() {
      _isWork = !_isWork;
      _secondsLeft = _phaseSeconds(_isWork);
      _isRunning = false;
      _endTime = null;
    });
    // 互動：跳過 → 兔咪換對應模式情緒
    MascotPersona.interact(
      _isWork ? MascotContext.openApp : MascotContext.completedOne,
    );
    SfxService.instance.play(SfxCue.tap);
    unawaited(HapticFeedback.selectionClick());
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
          // 狀態標籤（換階段時縮放淡入交接）
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 350),
            switchInCurve: Curves.easeOutBack,
            switchOutCurve: Curves.easeIn,
            transitionBuilder: (child, anim) =>
                ScaleTransition(scale: anim, child: child),
            child: Container(
              key: ValueKey(_isWork),
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
          ),

          const SizedBox(height: 20),

          // 計時圓圈：進度圓環 + 呼吸光暈（執行中才呼吸）
          _buildTimerCircle(color),

          const SizedBox(height: 20),

          // 按鈕
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _sideButton(icon: Icons.refresh, onTap: _reset),
              const SizedBox(width: 24),
              _mainButton(color),
              const SizedBox(width: 24),
              _sideButton(icon: Icons.skip_next, onTap: _skipPhase),
            ],
          ),

          const SizedBox(height: 14),

          Text(
            _statusLine(),
            style: TextStyle(color: Colors.grey.shade500, fontSize: 14),
          ),

          // 本次完成輪數（有完成過才顯示，pop 一下增加成就感）
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 350),
            switchInCurve: Curves.easeOutBack,
            transitionBuilder: (child, anim) =>
                ScaleTransition(scale: anim, child: child),
            child: _roundsDone == 0
                ? const SizedBox(height: 8)
                : Padding(
                    key: ValueKey(_roundsDone),
                    padding: const EdgeInsets.only(top: 10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.orange.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text(
                        '本次完成 ${'🍅' * _roundsDone.clamp(0, 4)}'
                        '${_roundsDone > 4 ? ' ×$_roundsDone' : ''}',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.orange.shade700,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  // 計時狀態說明：執行中顯示預計結束時刻，比固定口號更有「進行中」的感覺
  String _statusLine() {
    final end = _endTime;
    if (_isRunning && end != null) {
      final hh = end.hour.toString().padLeft(2, '0');
      final mm = end.minute.toString().padLeft(2, '0');
      return _isWork ? '專注中 · $hh:$mm 結束' : '休息中 · $hh:$mm 結束';
    }
    return _isWork ? '專注 25 分鐘，休息 5 分鐘' : '好好休息，準備下一輪！';
  }

  Widget _buildTimerCircle(Color color) {
    return SizedBox(
      width: 224,
      height: 224,
      child: AnimatedBuilder(
        animation: _breath,
        builder: (context, child) {
          // 執行中光暈隨呼吸放大縮小；暫停/待機固定在最小值
          final t = _isRunning
              ? Curves.easeInOut.transform(_breath.value)
              : 0.0;
          return DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.18 + 0.14 * t),
                  blurRadius: 26 + 14 * t,
                  spreadRadius: 3 + 5 * t,
                ),
              ],
            ),
            child: child,
          );
        },
        // 進度圓環：每秒 tick 之間用 1 秒線性補間，看起來是連續掃過
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: _progress),
          duration: const Duration(milliseconds: 1000),
          builder: (context, p, child) => CustomPaint(
            painter: _RingPainter(progress: p, color: color),
            child: child,
          ),
          child: Container(
            margin: const EdgeInsets.all(14),
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
            ),
            child: Center(
              child: Text(
                _timeString,
                style: TextStyle(
                  fontSize: 46,
                  fontWeight: FontWeight.bold,
                  color: color,
                  // 等寬數字：倒數時各位數不左右跳動
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // 主按鈕（開始/暫停）：Material ripple + 圖示縮放切換
  Widget _mainButton(Color color) {
    return DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.4),
            blurRadius: 15,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Material(
        color: color,
        shape: const CircleBorder(),
        child: InkWell(
          onTap: _startPause,
          customBorder: const CircleBorder(),
          child: SizedBox(
            width: 80,
            height: 80,
            child: Center(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                transitionBuilder: (child, anim) =>
                    ScaleTransition(scale: anim, child: child),
                child: Icon(
                  _isRunning ? Icons.pause : Icons.play_arrow,
                  key: ValueKey(_isRunning),
                  color: Colors.white,
                  size: 40,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // 兩側小按鈕（重設/跳過）：Material ripple
  Widget _sideButton({required IconData icon, required VoidCallback onTap}) {
    return Material(
      color: Colors.grey.shade100,
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: 56,
          height: 56,
          child: Icon(icon, color: Colors.grey.shade600),
        ),
      ),
    );
  }
}

// 計時進度圓環：淡色軌道 + 實色圓頭進度弧（從 12 點鐘方向順時針）
class _RingPainter extends CustomPainter {
  final double progress;
  final Color color;

  const _RingPainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 7.0;
    final center = size.center(Offset.zero);
    final radius = size.width / 2 - stroke / 2;

    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = color.withValues(alpha: 0.15);
    canvas.drawCircle(center, radius, track);

    if (progress <= 0) return;
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = color;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      2 * math.pi * progress.clamp(0.0, 1.0),
      false,
      arc,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.progress != progress || old.color != color;
}
