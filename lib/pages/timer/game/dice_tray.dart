// 骰盤：對戰面內建的擲骰工具（霧面 overlay，不打斷計時）。
//
// 互動：任意方向滑一下＝擲出（滑越快滾越久），也有「擲骰子」鈕；
// 顆數 1–6 可調並記住。動畫走 2D tumble：滾動期快速換面＋旋轉抖動
// ＋彈跳，結尾 easeOut 定格；多顆時定格後顯示總和。
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../utils/app_feedback.dart';
import '../../../utils/app_style.dart';
import '../../../utils/prefs_keys.dart';
import '../../../utils/sfx_service.dart';
import 'table_timer_theme.dart';

class DiceTrayOverlay extends StatefulWidget {
  final VoidCallback onClose;

  const DiceTrayOverlay({super.key, required this.onClose});

  @override
  State<DiceTrayOverlay> createState() => _DiceTrayOverlayState();
}

class _DiceTrayOverlayState extends State<DiceTrayOverlay>
    with SingleTickerProviderStateMixin {
  static const int maxDice = 6;

  final _rng = math.Random();
  late final AnimationController _roll;

  SharedPreferences? _prefs;
  int _count = 2;
  List<int> _values = const [1, 1];

  /// 每顆骰子的滾動個性（相位差、旋轉方向），每次擲重抽。
  List<double> _stagger = const [0, 0];
  List<double> _spinDir = const [1, -1];
  bool _hasRolled = false; // 定格前不顯示總和

  @override
  void initState() {
    super.initState();
    _roll = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    _roll.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        playHaptic(HapticLevel.medium); // 定格
        setState(() {});
      }
    });
    SharedPreferences.getInstance().then((p) {
      if (!mounted) return;
      setState(() {
        _prefs = p;
        _count = (p.getInt(PrefsKeys.gameTableDiceCount) ?? 2).clamp(
          1,
          maxDice,
        );
        _resetDice();
      });
    });
    _resetDice();
  }

  @override
  void dispose() {
    _roll.dispose();
    super.dispose();
  }

  void _resetDice() {
    _values = [for (var i = 0; i < _count; i++) 1 + _rng.nextInt(6)];
    _stagger = [for (var i = 0; i < _count; i++) _rng.nextDouble() * 0.18];
    _spinDir = [for (var i = 0; i < _count; i++) _rng.nextBool() ? 1 : -1];
    _hasRolled = false;
  }

  void _setCount(int delta) {
    final next = (_count + delta).clamp(1, maxDice);
    if (next == _count || _roll.isAnimating) return;
    playHaptic(HapticLevel.selection);
    setState(() {
      _count = next;
      _resetDice();
    });
    _prefs?.setInt(PrefsKeys.gameTableDiceCount, next);
  }

  /// [power] 0–1：滑動力道，決定滾多久。
  void _throwDice([double power = 0.6]) {
    if (_roll.isAnimating) return;
    setState(() {
      _values = [for (var i = 0; i < _count; i++) 1 + _rng.nextInt(6)];
      _stagger = [for (var i = 0; i < _count; i++) _rng.nextDouble() * 0.18];
      _spinDir = [for (var i = 0; i < _count; i++) _rng.nextBool() ? 1 : -1];
      _hasRolled = true;
    });
    _roll.duration = Duration(
      milliseconds: (750 + 650 * power.clamp(0.0, 1.0)).round(),
    );
    playFeedback(SfxCue.tap, haptic: HapticLevel.medium);
    _roll.forward(from: 0);
  }

  void _onPanEnd(DragEndDetails details) {
    final speed = details.velocity.pixelsPerSecond.distance;
    if (speed < 250) return; // 太輕不算擲
    _throwDice((speed / 3000).clamp(0.25, 1.0));
  }

  int get _total => _values.fold(0, (sum, v) => sum + v);

  @override
  Widget build(BuildContext context) {
    final settled = _hasRolled && !_roll.isAnimating;
    return Positioned.fill(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onClose, // 點骰盤外空白＝收起
          onPanEnd: _onPanEnd, // 整面都能滑動擲
          child: ColoredBox(
            color: const Color(0xA61A120C),
            child: SafeArea(
              child: Center(
                child: GestureDetector(
                  onTap: () {}, // 吸掉骰盤本體的點擊，避免誤關
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _countRow(),
                      const SizedBox(height: 22),
                      _diceArea(),
                      const SizedBox(height: 18),
                      SizedBox(
                        height: 44,
                        child: _count > 1 && settled
                            ? Text(
                                '合計 $_total',
                                style: AppType.digits(
                                  fontSize: 30,
                                  fontWeight: FontWeight.w800,
                                  color: TableTheme.inkStrong,
                                ),
                              )
                            : null,
                      ),
                      const SizedBox(height: 6),
                      _throwButton(),
                      const SizedBox(height: 10),
                      const Text(
                        '往任何方向滑一下也可以擲',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: TableTheme.inkFaint,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: widget.onClose,
                        child: const Text(
                          '收起',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: TableTheme.inkSoft,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _countRow() {
    Widget btn(IconData icon, int delta, bool enabled) {
      return Material(
        color: const Color(0x2EF6ECDD),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: enabled ? () => _setCount(delta) : null,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Icon(
              icon,
              size: 20,
              color: enabled ? TableTheme.inkStrong : TableTheme.inkFaint,
            ),
          ),
        ),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        btn(Icons.remove_rounded, -1, _count > 1),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: Text(
            '$_count 顆骰子',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w900,
              color: TableTheme.inkStrong,
              fontFamily: AppType.digits().fontFamily,
            ),
          ),
        ),
        btn(Icons.add_rounded, 1, _count < maxDice),
      ],
    );
  }

  Widget _diceArea() {
    // 1–3 顆一排、4–6 顆兩排，骰子大小隨顆數縮
    final dieSize = _count <= 2 ? 96.0 : (_count <= 4 ? 84.0 : 72.0);
    return AnimatedBuilder(
      animation: _roll,
      builder: (context, _) {
        final t = _roll.isAnimating ? _roll.value : 1.0;
        return Wrap(
          spacing: 16,
          runSpacing: 16,
          alignment: WrapAlignment.center,
          children: [for (var i = 0; i < _count; i++) _die(i, dieSize, t)],
        );
      },
    );
  }

  Widget _die(int i, double size, double t) {
    // 各骰子相位差：晚起跑、同時結束
    final phase = _hasRolled && _roll.isAnimating
        ? ((t - _stagger[i]) / (1 - _stagger[i])).clamp(0.0, 1.0)
        : 1.0;

    final int shown;
    if (phase < 0.72) {
      // 滾動中：快速換面（determinstic per tick，避免每幀閃爍過快）
      final tick = (phase * 14).floor();
      shown = 1 + ((i * 7 + tick * 5 + _values[i]) % 6);
    } else {
      shown = _values[i];
    }

    // 旋轉抖動與彈跳都隨 phase 收斂
    final wobble = 1 - Curves.easeOut.transform(phase);
    final angle =
        _spinDir[i] * wobble * math.sin(phase * math.pi * 5 + i) * 0.45;
    final lift = wobble * math.sin(phase * math.pi * 3 + i * 1.3).abs() * 14;

    return Transform.translate(
      offset: Offset(0, -lift),
      child: Transform.rotate(
        angle: angle,
        child: CustomPaint(
          size: Size.square(size),
          painter: _DiePainter(value: shown),
        ),
      ),
    );
  }

  Widget _throwButton() {
    final rolling = _roll.isAnimating;
    return Material(
      color: rolling ? const Color(0x33E9A94E) : TableTheme.warn,
      shape: const StadiumBorder(),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: rolling ? null : _throwDice,
        child: SizedBox(
          width: 210,
          height: 56,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.casino_rounded,
                size: 24,
                color: rolling ? TableTheme.inkFaint : const Color(0xFF241A12),
              ),
              const SizedBox(width: 8),
              Text(
                rolling ? '骰子滾動中…' : '擲骰子',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                  color: rolling
                      ? TableTheme.inkFaint
                      : const Color(0xFF241A12),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 單顆骰面：奶油底圓角方塊＋深棕點數＋貼地陰影。
class _DiePainter extends CustomPainter {
  final int value;

  const _DiePainter({required this.value});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(
      rect.deflate(size.width * 0.04),
      Radius.circular(size.width * 0.22),
    );

    // 貼地陰影（暖棕不用純黑）
    canvas.drawRRect(
      rrect.shift(Offset(0, size.height * 0.05)),
      Paint()
        ..color = const Color(0x59120B07)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );

    // 骰身：奶油底、左上受光
    canvas.drawRRect(
      rrect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFFF8EC), Color(0xFFE9DAC4)],
        ).createShader(rect),
    );
    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.width * 0.02
        ..color = const Color(0x33513A28),
    );

    // 點數
    final pip = Paint()..color = const Color(0xFF3C2D21);
    final c = size.width / 2;
    final o = size.width * 0.24; // 點位偏移
    final r = size.width * 0.085;
    void dot(double dx, double dy) =>
        canvas.drawCircle(Offset(c + dx, c + dy), r, pip);

    if (value.isOdd) dot(0, 0);
    if (value >= 2) {
      dot(-o, -o);
      dot(o, o);
    }
    if (value >= 4) {
      dot(o, -o);
      dot(-o, o);
    }
    if (value == 6) {
      dot(-o, 0);
      dot(o, 0);
    }
  }

  @override
  bool shouldRepaint(_DiePainter old) => old.value != value;
}
