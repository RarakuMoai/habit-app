// 全螢幕「事件揭曉」：特殊事件解鎖當下的溫馨開場。
//
// 呈現節奏（每頁）：暖色書頁淡入 → 繪本圖緩緩浮現 → 兔咪台詞逐句亮起 →
// 「點一下繼續」。多頁事件逐頁走完，最後一頁點擊後收進回憶本（衣櫃 → 回憶）。
// 光塵微粒與光暈全在 Flutter 端 overlay（CG 只畫純角色，特效重用）。
//
// 誰來開這一頁：MainPage 監聽 StoryStore.pendingReveal，佇列有事件就 push；
// pop 後由 MainPage 呼叫 StoryStore.consumeReveal。開發者測試的「預覽揭曉」
// 直接 push 本頁、不動任何狀態，所以怎麼看都不會誤解鎖。

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../utils/app_feedback.dart';
import '../utils/app_style.dart';
import '../utils/sfx_service.dart';
import '../utils/story_catalog.dart';
import '../utils/usage_stats.dart';

class StoryRevealPage extends StatefulWidget {
  final StoryEventSpec event;

  /// 繪本上印的日期（正式＝解鎖日；預覽＝今天）。
  final DateTime date;

  const StoryRevealPage({super.key, required this.event, required this.date});

  /// 全螢幕淡入路線（揭曉要像一頁書慢慢亮起，不用平台推頁動畫）。
  static Route<void> route({required StoryEventSpec event, DateTime? date}) {
    return PageRouteBuilder<void>(
      fullscreenDialog: true,
      transitionDuration: const Duration(milliseconds: 550),
      reverseTransitionDuration: const Duration(milliseconds: 420),
      pageBuilder: (_, _, _) =>
          StoryRevealPage(event: event, date: date ?? DateTime.now()),
      transitionsBuilder: (_, animation, _, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
        );
        return FadeTransition(opacity: curved, child: child);
      },
    );
  }

  @override
  State<StoryRevealPage> createState() => _StoryRevealPageState();
}

class _StoryRevealPageState extends State<StoryRevealPage>
    with SingleTickerProviderStateMixin {
  // 光塵與提示呼吸共用的環境時鐘（0→1 循環）。
  late final AnimationController _ambient;

  int _pageIndex = 0;
  bool _imageIn = false;
  int _shownCaptions = 0;
  final List<Timer> _timers = [];

  StoryPage get _page => widget.event.pages[_pageIndex];
  bool get _isLastPage => _pageIndex == widget.event.pages.length - 1;
  bool get _captionsDone => _shownCaptions >= _page.captions.length;

  @override
  void initState() {
    super.initState();
    _ambient = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 24),
    )..repeat();
    playFeedback(SfxCue.tumiHappy, haptic: HapticLevel.light);
    unawaited(UsageStats.bump(UsageEvents.storyOpen));
    _startPage();
  }

  @override
  void dispose() {
    _cancelTimers();
    _ambient.dispose();
    super.dispose();
  }

  void _cancelTimers() {
    for (final t in _timers) {
      t.cancel();
    }
    _timers.clear();
  }

  /// 目前頁重新開演：圖先浮現，台詞再逐句亮起。
  void _startPage() {
    _cancelTimers();
    _imageIn = false;
    _shownCaptions = 0;
    _timers.add(
      Timer(const Duration(milliseconds: 80), () {
        if (mounted) setState(() => _imageIn = true);
      }),
    );
    for (var i = 0; i < _page.captions.length; i++) {
      _timers.add(
        Timer(Duration(milliseconds: 1050 + i * 750), () {
          if (mounted) setState(() => _shownCaptions = i + 1);
        }),
      );
    }
  }

  void _onTap() {
    if (!_captionsDone) {
      // 還在逐句演出：一次亮完，不強迫等。
      _cancelTimers();
      setState(() {
        _imageIn = true;
        _shownCaptions = _page.captions.length;
      });
      playHaptic(HapticLevel.selection);
      return;
    }
    if (!_isLastPage) {
      playHaptic(HapticLevel.selection);
      setState(() => _pageIndex++);
      _startPage();
      return;
    }
    playFeedback(SfxCue.success, haptic: HapticLevel.light);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final event = widget.event;
    final multiPage = event.pages.length > 1;
    return Scaffold(
      backgroundColor: const Color(0xFFFBF3E8), // 暖書頁底（同回憶本閱讀器）
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _onTap,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // 上方暖光暈：像翻開書時燈光灑下來。
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment(0, -0.75),
                  radius: 1.25,
                  colors: [Color(0x66FFE3BE), Color(0x00FFE3BE)],
                ),
              ),
            ),
            // 光塵微粒（緩慢上飄 + 呼吸閃爍）。
            AnimatedBuilder(
              animation: _ambient,
              builder: (_, _) => CustomPaint(
                painter: _MotesPainter(t: _ambient.value),
              ),
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(22, 18, 22, 20),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 380),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeIn,
                  child: _buildSpread(key: ValueKey(_pageIndex)),
                ),
              ),
            ),
            if (multiPage)
              Positioned(
                top: 14,
                left: 0,
                right: 0,
                child: SafeArea(
                  child: Text(
                    '${_pageIndex + 1} / ${event.pages.length}',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: kMemoryAccent.withValues(alpha: 0.75),
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSpread({required Key key}) {
    final page = _page;
    return Column(
      key: key,
      children: [
        const SizedBox(height: 14),
        // 繪本圖：緩緩浮現（淡入 + 上浮 + 些微放大）。
        Expanded(
          child: AnimatedSlide(
            offset: _imageIn ? Offset.zero : const Offset(0, 0.035),
            duration: const Duration(milliseconds: 720),
            curve: Curves.easeOutCubic,
            child: AnimatedOpacity(
              opacity: _imageIn ? 1 : 0,
              duration: const Duration(milliseconds: 720),
              curve: Curves.easeOut,
              child: AnimatedScale(
                scale: _imageIn ? 1 : 0.965,
                duration: const Duration(milliseconds: 720),
                curve: Curves.easeOutCubic,
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: kMemoryAccent.withValues(alpha: 0.18),
                    ),
                    boxShadow: AppShadows.card,
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Image.asset(
                    page.image,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => const _ImageFallback(),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 18),
        AnimatedOpacity(
          opacity: _imageIn ? 1 : 0,
          duration: const Duration(milliseconds: 720),
          child: Column(
            children: [
              Text(
                widget.event.title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppInk.strong,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                _formatDate(widget.date),
                style: TextStyle(
                  color: kMemoryAccent.withValues(alpha: 0.9),
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        // 台詞逐句浮現。全部先佔位（透明），避免出現時版面往下跳。
        for (var i = 0; i < page.captions.length; i++)
          AnimatedSlide(
            offset: i < _shownCaptions ? Offset.zero : const Offset(0, 0.25),
            duration: const Duration(milliseconds: 460),
            curve: Curves.easeOutCubic,
            child: AnimatedOpacity(
              opacity: i < _shownCaptions ? 1 : 0,
              duration: const Duration(milliseconds: 460),
              child: Padding(
                padding: const EdgeInsets.only(bottom: 5),
                child: Text(
                  page.captions[i],
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppInk.soft,
                    fontSize: 14.5,
                    height: 1.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
        const SizedBox(height: 10),
        // 提示：台詞演完才亮起，輕輕呼吸。
        SizedBox(
          height: 22,
          child: AnimatedOpacity(
            opacity: _captionsDone ? 1 : 0,
            duration: const Duration(milliseconds: 400),
            child: AnimatedBuilder(
              animation: _ambient,
              builder: (_, child) => Opacity(
                opacity:
                    0.55 +
                    0.45 *
                        (0.5 +
                            0.5 * math.sin(_ambient.value * 2 * math.pi * 16)),
                child: child,
              ),
              child: Text(
                _isLastPage ? '點一下，收進回憶本 ✧' : '點一下，繼續 ✧',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: kMemoryAccent.withValues(alpha: 0.95),
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// 繪本圖缺檔時的柔和 fallback（出貨會放真的圖，平常看不到）。
class _ImageFallback extends StatelessWidget {
  const _ImageFallback();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            kMemoryAccent.withValues(alpha: 0.18),
            const Color(0xFFFFF6EC),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: Icon(
          Icons.auto_stories_rounded,
          size: 64,
          color: kMemoryAccent.withValues(alpha: 0.5),
        ),
      ),
    );
  }
}

/// 光塵微粒：暖色小光點緩慢上飄、呼吸閃爍。用畫面尺寸等比佈點，
/// 位置由固定種子推導（無狀態、每幀重算，不需要粒子物件）。
class _MotesPainter extends CustomPainter {
  final double t; // 0→1 循環

  const _MotesPainter({required this.t});

  static const _count = 16;

  // 穩定的偽隨機（同一顆粒子每幀拿到同一組參數）。
  double _rand(int i, int salt) {
    final v = math.sin(i * 127.1 + salt * 311.7) * 43758.5453;
    return v - v.floorToDouble();
  }

  @override
  void paint(Canvas canvas, Size size) {
    for (var i = 0; i < _count; i++) {
      final baseX = _rand(i, 1);
      final baseY = _rand(i, 2);
      final speed = 0.35 + 0.5 * _rand(i, 3); // 一輪循環內上飄的比例
      final radius = 1.6 + 2.6 * _rand(i, 4);
      final phase = _rand(i, 5) * 2 * math.pi;
      final sway = 0.012 * math.sin(t * 2 * math.pi * 2 + phase);

      final y = (baseY - t * speed) % 1.0;
      final x = (baseX + sway) % 1.0;
      final twinkle =
          0.5 + 0.5 * math.sin(t * 2 * math.pi * (6 + 4 * _rand(i, 6)) + phase);
      // 邊緣（剛出現/快消失）淡出，避免粒子在畫面頂端瞬間消失。
      final edgeFade = math.min(1.0, math.min(y, 1 - y) * 6).clamp(0.0, 1.0);
      final alpha = (0.10 + 0.22 * twinkle) * edgeFade;

      final paint = Paint()
        ..color = Color.lerp(
          kMemoryAccent,
          const Color(0xFFFFE9C8),
          0.35 + 0.5 * _rand(i, 7),
        )!.withValues(alpha: alpha)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, radius * 0.9);
      canvas.drawCircle(
        Offset(x * size.width, y * size.height),
        radius,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _MotesPainter old) => old.t != t;
}

String _formatDate(DateTime d) {
  final m = d.month.toString().padLeft(2, '0');
  final day = d.day.toString().padLeft(2, '0');
  return '${d.year} / $m / $day';
}
