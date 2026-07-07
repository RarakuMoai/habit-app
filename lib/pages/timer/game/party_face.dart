// 多人桌遊環桌面：手機放桌中央，整個畫面就是換人按鈕。
//
// 視覺層級：巨大倒數 > 目前玩家 > 下一位 > 座位環。
// 點擊任意處＝換下一位（角落小鍵由 stage 蓋在上層吸收點擊）。
// 自由輪流模式共用這張面，改為正數計時、無警示壓力。
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../utils/app_feedback.dart';
import '../../../utils/app_style.dart';
import '../../../utils/sfx_service.dart';
import 'table_timer_engine.dart';
import 'table_timer_theme.dart';

class PartyFace extends StatefulWidget {
  final TableTimerEngine engine;

  const PartyFace({super.key, required this.engine});

  @override
  State<PartyFace> createState() => _PartyFaceState();
}

class _PartyFaceState extends State<PartyFace> with TickerProviderStateMixin {
  // 呼吸光暈（目前玩家）：慢速來回。
  late final AnimationController _breath;

  // 點擊波紋：從點擊落點擴散一圈新玩家色光波。
  late final AnimationController _ripple;
  Offset? _rippleCenter; // null = 從畫面中心（自動換人時）
  Color _rippleColor = TableTheme.inkSoft;

  // 接力光點：換人時沿座位環從舊座位「傳」到新座位的彗尾光點。
  late final AnimationController _relay;
  double _relayFromAngle = 0;
  double _relaySweep = 0;
  Color _relayColor = TableTheme.inkSoft;

  int _lastTurnCount = 0;
  int _lastIndex = 0;
  bool _tapHandled = false;

  TableTimerEngine get engine => widget.engine;

  @override
  void initState() {
    super.initState();
    _breath = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1700),
    )..repeat(reverse: true);
    _ripple = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 520),
    );
    _relay = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 560),
    );
    _lastTurnCount = engine.turnCount;
    _lastIndex = engine.currentIndex;
    engine.addListener(_onEngineChanged);
  }

  @override
  void dispose() {
    engine.removeListener(_onEngineChanged);
    _breath.dispose();
    _ripple.dispose();
    _relay.dispose();
    super.dispose();
  }

  // 換人回饋：光點沿座位環接力到新座位；超時自動換人（不是手點的）
  // 再補一圈從中心擴散的波。
  void _onEngineChanged() {
    final index = engine.currentIndex;
    if (engine.turnCount == _lastTurnCount && index == _lastIndex) return;
    final fromIndex = _lastIndex;
    _lastTurnCount = engine.turnCount;
    _lastIndex = index;
    if (index != fromIndex) _fireRelay(fromIndex, index);
    if (_tapHandled) {
      _tapHandled = false;
      return;
    }
    _fireRipple(
      center: null,
      color: TableTheme.seatColor(engine.currentPlayer.colorIndex),
    );
  }

  void _fireRelay(int from, int to) {
    if (!mounted) return;
    final n = engine.players.length;
    final double sweep;
    if (to == (from + 1) % n) {
      sweep = 2 * math.pi / n; // 前進：順時針傳一格
    } else if (to == (from - 1 + n) % n) {
      sweep = -2 * math.pi / n; // 回上一位：逆時針飄回去
    } else {
      return; // 重開之類的跳位不播
    }
    setState(() {
      _relayFromAngle = -math.pi / 2 + 2 * math.pi * from / n;
      _relaySweep = sweep;
      _relayColor = TableTheme.seatColor(engine.players[to].colorIndex);
    });
    _relay.forward(from: 0);
  }

  void _fireRipple({required Offset? center, required Color color}) {
    if (!mounted) return;
    setState(() {
      _rippleCenter = center;
      _rippleColor = color;
    });
    _ripple.forward(from: 0);
  }

  void _handleTap(TapUpDetails details) {
    switch (engine.phase) {
      case TablePhase.ready:
        _tapHandled = true;
        engine.start();
      case TablePhase.running:
        _tapHandled = true;
        engine.advance();
      case TablePhase.paused:
      case TablePhase.finished: // 旗倒只在棋鐘，這面到不了
        return; // 暫停層在上面，理論上到不了這裡
    }
    playFeedback(SfxCue.tap, haptic: HapticLevel.medium);
    _fireRipple(
      center: details.localPosition,
      color: TableTheme.seatColor(engine.currentPlayer.colorIndex),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ready = engine.phase == TablePhase.ready;
    final urgency = engine.urgency;
    final seat = TableTheme.seatColor(engine.currentPlayer.colorIndex);
    final accent = TableTheme.urgencyColor(urgency, seat);

    return Stack(
      fit: StackFit.expand,
      children: [
        // 超時的深紅氛圍（呼吸、不刺眼）
        if (engine.inOvertime)
          AnimatedBuilder(
            animation: _breath,
            builder: (context, _) => DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  radius: 1.2,
                  colors: [
                    Colors.transparent,
                    TableTheme.overtime.withValues(
                      alpha: 0.10 + 0.10 * _breath.value,
                    ),
                  ],
                ),
              ),
            ),
          ),
        SafeArea(
          child: Column(
            children: [
              const SizedBox(height: 52), // 角落鍵的空間
              Expanded(
                child: Center(
                  child: LayoutBuilder(
                    builder: (context, box) {
                      final dial = math.min(
                        math.min(box.maxWidth * 0.80, box.maxHeight * 0.74),
                        360.0,
                      );
                      return SizedBox(
                        // 座位環在盤外，多留一圈空間
                        width: dial + 44,
                        height: dial + 44,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            AnimatedBuilder(
                              animation: _breath,
                              builder: (context, _) => CustomPaint(
                                size: Size.square(dial),
                                painter: _DialPainter(
                                  progress: engine.isFree
                                      ? 1.0
                                      : engine.ringProgress,
                                  color: accent,
                                  glow: ready
                                      ? 0.35
                                      : 0.45 + 0.55 * _breath.value,
                                  dimmed: engine.isFree,
                                ),
                              ),
                            ),
                            _dialContent(dial, accent, seat, ready),
                            ..._seatTokens(dial),
                            AnimatedBuilder(
                              animation: _relay,
                              builder: (context, _) => CustomPaint(
                                size: Size.square(dial + 44),
                                painter: _RelayPainter(
                                  t: _relay.isAnimating ? _relay.value : 1.0,
                                  fromAngle: _relayFromAngle,
                                  sweep: _relaySweep,
                                  color: _relayColor,
                                  orbitRadius: dial / 2 + 10,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
              _nextPlayerLine(),
              const SizedBox(height: 14),
              _footer(ready),
              const SizedBox(height: 18),
            ],
          ),
        ),
        // 整面觸控區（最上層；角落鍵與暫停層由 stage 蓋更上面）
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: _handleTap,
            child: AnimatedBuilder(
              animation: _ripple,
              builder: (context, _) => CustomPaint(
                painter: _RipplePainter(
                  t: _ripple.isAnimating ? _ripple.value : 1.0,
                  center: _rippleCenter,
                  color: _rippleColor,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// 盤中央：目前玩家名 + 巨大時間 + 狀態小字。
  Widget _dialContent(double dial, Color accent, Color seat, bool ready) {
    final String timeText;
    final String? statusText;
    if (engine.isFree) {
      timeText = formatTableElapsed(engine.elapsedInTurn);
      statusText = ready ? null : '自由計時';
    } else if (engine.inOvertime) {
      timeText =
          '+${formatTableElapsed(Duration(seconds: engine.overtimeSeconds))}';
      statusText = '超時';
    } else {
      timeText = formatTableSeconds(
        ready ? engine.config.turnSeconds : engine.remainingSeconds,
      );
      statusText = null;
    }

    // 加強提醒區：每跨一秒數字彈一下（key 換掉就重播）。
    final pulse = engine.urgency >= 2 && !engine.inOvertime;
    Widget time = Text(
      timeText,
      maxLines: 1,
      style: TableTheme.bigDigits(color: accent),
    );
    if (pulse) {
      time = TweenAnimationBuilder<double>(
        key: ValueKey(engine.remainingSeconds),
        tween: Tween(begin: 1.13, end: 1.0),
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutBack,
        builder: (context, scale, child) =>
            Transform.scale(scale: scale, child: child),
        child: time,
      );
    }

    return SizedBox(
      width: dial * 0.72,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _dot(seat, 12),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  engine.currentPlayer.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TableTheme.nameStyle(fontSize: dial * 0.082),
                ),
              ),
            ],
          ),
          SizedBox(height: dial * 0.008),
          SizedBox(
            height: dial * 0.40,
            child: FittedBox(child: time),
          ),
          if (statusText != null)
            Text(
              statusText,
              style: TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 2,
                color: engine.inOvertime ? accent : TableTheme.inkFaint,
              ),
            ),
        ],
      ),
    );
  }

  /// 座位環：玩家色 token 沿盤外圓周排列，目前玩家放大發光、
  /// 下一位帶奶油細環。
  List<Widget> _seatTokens(double dial) {
    final n = engine.players.length;
    // 環線半徑是 dial/2 - stroke（見 _DialPainter），+10 讓 token
    // 貼著環外緣、不會浮在半空
    final radius = dial / 2 + 10;
    final nextIndex = (engine.currentIndex + 1) % n;
    return [
      for (var i = 0; i < n; i++)
        _seatToken(
          i,
          radius,
          isCurrent: i == engine.currentIndex,
          isNext: i == nextIndex && n > 2,
        ),
    ];
  }

  Widget _seatToken(
    int i,
    double radius, {
    required bool isCurrent,
    required bool isNext,
  }) {
    final n = engine.players.length;
    final angle = -math.pi / 2 + 2 * math.pi * i / n;
    final offset = Offset(math.cos(angle), math.sin(angle)) * radius;
    final color = TableTheme.seatColor(engine.players[i].colorIndex);

    Widget dot;
    if (isCurrent) {
      dot = AnimatedBuilder(
        animation: _breath,
        builder: (context, _) => Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(color: TableTheme.inkStrong, width: 2),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.5 + 0.35 * _breath.value),
                blurRadius: 12 + 6 * _breath.value,
              ),
            ],
          ),
        ),
      );
    } else {
      dot = Container(
        width: isNext ? 15.0 : 12.0,
        height: isNext ? 15.0 : 12.0,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.62),
          shape: BoxShape.circle,
          border: isNext
              ? Border.all(color: TableTheme.inkSoft, width: 1.6)
              : null,
        ),
      );
    }

    return Transform.translate(
      offset: offset,
      child: AnimatedScale(
        scale: isCurrent ? 1.0 : 0.9,
        duration: const Duration(milliseconds: 260),
        child: dot,
      ),
    );
  }

  Widget _nextPlayerLine() {
    if (engine.phase == TablePhase.ready) return const SizedBox(height: 22);
    final next = engine.nextPlayer;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Text(
          '下一位',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: TableTheme.inkFaint,
          ),
        ),
        const SizedBox(width: 8),
        const Icon(
          Icons.arrow_right_alt_rounded,
          size: 20,
          color: TableTheme.inkFaint,
        ),
        const SizedBox(width: 8),
        _dot(TableTheme.seatColor(next.colorIndex), 10),
        const SizedBox(width: 6),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 180),
          child: Text(
            next.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w900,
              color: TableTheme.inkSoft,
            ),
          ),
        ),
      ],
    );
  }

  Widget _footer(bool ready) {
    final hint = ready ? '點任意處開始' : '點任意處換下一位';
    return Column(
      children: [
        Text(
          hint,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: TableTheme.inkFaint,
          ),
        ),
        if (!ready) ...[
          const SizedBox(height: 4),
          Text(
            '第 ${engine.turnCount} 手',
            style: AppType.digits(fontSize: 12.5, color: TableTheme.inkFaint),
          ),
        ],
      ],
    );
  }

  Widget _dot(Color color, double size) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: color,
      shape: BoxShape.circle,
      boxShadow: [
        BoxShadow(color: color.withValues(alpha: 0.5), blurRadius: size * 0.5),
      ],
    ),
  );
}

/// 中央盤面：呼吸光暈 + 絨布內盤 + 軌道 + 進度弧。
class _DialPainter extends CustomPainter {
  final double progress;
  final Color color;
  final double glow; // 0–1 呼吸強度
  final bool dimmed; // 自由模式：滿環低調顯示

  const _DialPainter({
    required this.progress,
    required this.color,
    required this.glow,
    required this.dimmed,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final shortest = math.min(size.width, size.height);
    final stroke = math.max(10.0, shortest * 0.045);
    final radius = shortest / 2 - stroke;

    // 呼吸光暈（畫最底層）
    canvas.drawCircle(
      center,
      radius + stroke * 0.6,
      Paint()
        ..color = color.withValues(alpha: (dimmed ? 0.10 : 0.16) * glow)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 26),
    );

    // 絨布內盤：比桌面略亮一階，中央受光
    final discRect = Rect.fromCircle(center: center, radius: radius - stroke);
    canvas.drawCircle(
      center,
      radius - stroke,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.2, -0.3),
          radius: 1.0,
          colors: [const Color(0xFF413023), const Color(0xFF2B1F16)],
        ).createShader(discRect),
    );

    // 軌道
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = const Color(0x1FF6ECDD),
    );

    // 進度弧（帶一層柔光）
    final p = progress.clamp(0.0, 1.0);
    if (p <= 0) return;
    final rect = Rect.fromCircle(center: center, radius: radius);
    final sweep = 2 * math.pi * p;
    final alpha = dimmed ? 0.38 : 1.0;
    canvas.drawArc(
      rect,
      -math.pi / 2,
      sweep,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..color = color.withValues(alpha: 0.4 * alpha)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7),
    );
    canvas.drawArc(
      rect,
      -math.pi / 2,
      sweep,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..color = color.withValues(alpha: alpha),
    );
  }

  @override
  bool shouldRepaint(_DialPainter old) =>
      old.progress != progress ||
      old.color != color ||
      old.glow != glow ||
      old.dimmed != dimmed;
}

/// 接力光點：沿座位環傳遞的彗尾光點（換人轉場）。
class _RelayPainter extends CustomPainter {
  final double t; // 0–1；1 = 播完（不畫）
  final double fromAngle;
  final double sweep; // 正 = 順時針一格、負 = 逆時針
  final Color color;
  final double orbitRadius;

  const _RelayPainter({
    required this.t,
    required this.fromAngle,
    required this.sweep,
    required this.color,
    required this.orbitRadius,
  });

  Offset _at(Offset center, double angle) =>
      center + Offset(math.cos(angle), math.sin(angle)) * orbitRadius;

  @override
  void paint(Canvas canvas, Size size) {
    if (t <= 0 || t >= 1 || sweep == 0) return;
    final center = size.center(Offset.zero);
    final eased = Curves.easeInOutCubic.transform(t);
    // 抵達前收尾淡出，跟座位 token 的放大自然交棒
    final fade = t > 0.8 ? (1 - t) / 0.2 : 1.0;

    // 彗尾殘影：沿走過的路徑放幾顆漸小漸淡的殘點
    for (var k = 5; k >= 1; k--) {
      final tt = eased - k * 0.05;
      if (tt <= 0) continue;
      canvas.drawCircle(
        _at(center, fromAngle + sweep * tt),
        7.0 - k,
        Paint()..color = color.withValues(alpha: 0.26 * fade * (1 - k / 6)),
      );
    }

    // 光點本體：外圈光暈＋偏白亮芯
    final head = _at(center, fromAngle + sweep * eased);
    canvas.drawCircle(
      head,
      13,
      Paint()
        ..color = color.withValues(alpha: 0.45 * fade)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
    );
    canvas.drawCircle(
      head,
      6.5,
      Paint()
        ..color = Color.lerp(
          color,
          TableTheme.inkStrong,
          0.35,
        )!.withValues(alpha: fade),
    );
  }

  @override
  bool shouldRepaint(_RelayPainter old) =>
      old.t != t ||
      old.fromAngle != fromAngle ||
      old.sweep != sweep ||
      old.color != color ||
      old.orbitRadius != orbitRadius;
}

/// 點擊波紋：從落點擴散的玩家色光圈。
class _RipplePainter extends CustomPainter {
  final double t; // 0–1；1 = 播完（不畫）
  final Offset? center; // null = 畫面中心
  final Color color;

  const _RipplePainter({
    required this.t,
    required this.center,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (t >= 1.0 || t <= 0.0) return;
    final origin = center ?? size.center(Offset.zero);
    final maxRadius = size.longestSide * 0.9;
    final eased = Curves.easeOutCubic.transform(t);
    final radius = 40 + maxRadius * eased;
    final fade = 1 - t;

    canvas.drawCircle(
      origin,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 30 * (1 - t * 0.6)
        ..color = color.withValues(alpha: 0.30 * fade)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18),
    );
    canvas.drawCircle(
      origin,
      radius * 0.66,
      Paint()..color = color.withValues(alpha: 0.05 * fade),
    );
  }

  @override
  bool shouldRepaint(_RipplePainter old) =>
      old.t != t || old.center != center || old.color != color;
}
