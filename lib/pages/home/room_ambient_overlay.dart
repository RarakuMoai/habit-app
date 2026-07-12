// 首頁臥室背景的動態層，分上下兩塊：
//
//   [WindowBackdrop]（墊在背景圖之下）
//     窗外景。背景圖用 home_bg_glassless.png（窗玻璃已挖透明、窗框窗櫺
//     原圖像素全保留），這層只畫「洞後面的世界」：時段天空、日月、
//     星星、雲、灌木剪影。畫的範圍略大於玻璃開口，其餘被原圖蓋住，
//     所以完全不存在補畫窗櫺 / 對齊的問題。
//
//   [RoomAmbientOverlay]（疊在背景圖 + 時段色罩之上）
//     室內光影。晨/晝窗光斜射光束 + 塵埃微粒 + 地板光池；
//     暮/夜床頭檯燈暖光暈（呼吸）；深夜極淡冷色月光。
//
// 所有強度都用連續 hour 的 smoothstep 開關，時段交界不跳變。
// 幾何錨點對齊 home_bg 內容（BoxFit.cover + topCenter，圖檔長寬比 0.8
// → 顯示高度 = 寬度 / 0.8）；座標一律用 (寬度比例, 顯示圖高比例) 表達。
//
// 效能：兩層各自單 Ticker 節流 ~30fps + RepaintBoundary，只重繪自己。
//
// 時間來源：一律走 SceneTimeController（utils/scene_time.dart）——
// 真實時間 / 使用者固定時段 / dev 預覽覆寫都由它統一；painter 讀
// state.hour（每分鐘更新），不在 paint() 內讀 DateTime.now()。
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../utils/scene_time.dart';

/// 目前場景小時（0~24 連續值，已含固定時段/預覽覆寫）。首頁
/// _sceneColors/_sceneTint 也用它，確保光影層跟色罩/accent 一致。
double sceneHourNow() => SceneTimeController.instance.state.hour;

/// 時段色罩（純時間版；首頁另有「全完成」特例自己處理，故維持自有 _sceneTint）。
/// 四時段權重連續混色：夜(藍) / 晨(粉金) / 暮(薰衣草) / 白天透明。
Color sceneTintNow() {
  return SceneTimeController.instance.state.blendColor(
    morning: const Color(0xFFFFC4AD).withValues(alpha: 0.10),
    day: Colors.transparent,
    dusk: const Color(0xFFC9A1E8).withValues(alpha: 0.10),
    night: const Color(0xFF3F456B).withValues(alpha: 0.12),
  );
}

/// 全域總開關（快速恢復用）：設 false → 所有套了 [SceneAmbience] 的頁面
/// 立刻退回純背景圖，零風險。實驗翻車時改這一行即可。
const bool kRoomAmbienceEnabled = true;

/// 一個房間頁的環境光設定，傳給 [MascotSceneBackground] 的 ambience 參數。
/// 不傳（或總開關關閉）= 純背景圖，維持原本行為。
class SceneAmbience {
  /// 時段色罩：晨(粉金)/暮(薰衣草)/夜(藍)的全室變色。
  final bool tint;

  /// 檯燈暖光暈中心（圖比例座標：x=寬比例、y=顯示圖高比例）；
  /// null = 這房間沒檯燈，不畫燈暈。
  final Offset? lampCenter;

  /// 窗外動態天空用的「去背圖」路徑（玻璃挖透明、其餘保留的 *_glassless.png）。
  /// 給了就啟用窗景：背景改用此去背圖、後面墊 [WindowBackdrop] 畫時段天空。
  /// 去背圖還沒到位時 errorBuilder 會回退成原始背景圖（不崩、看起來如常）。
  /// 必須與 [windowRect] 同時提供才會啟用。
  final String? glasslessAsset;

  /// 窗玻璃開口矩形（比例座標 L,T,R,B），[WindowBackdrop] 在此畫天空。
  /// 可見形狀由去背圖 alpha 決定，所以略大於玻璃即可。
  final Rect? windowRect;

  const SceneAmbience({
    this.tint = false,
    this.lampCenter,
    this.glasslessAsset,
    this.windowRect,
  });

  /// 是否啟用窗外動態天空（去背圖 + 窗區都給齊）。
  bool get hasWindow => glasslessAsset != null && windowRect != null;
}

double _smooth(double a, double b, double x) {
  final t = ((x - a) / (b - a)).clamp(0.0, 1.0);
  return t * t * (3 - 2 * t);
}

/// 首頁檯燈點亮強度（0~1）：16:48 起與黃昏同步漸亮、清晨 5:24~6:24 漸滅。
/// 程式光暈（painter）與燈罩發亮差分圖（overlay）共用這一條曲線。
double homeLampIntensity(double h) =>
    h >= 12 ? _smooth(16.8, 18.0, h) : (1 - _smooth(5.4, 6.4, h));

/// 首頁黃昏強度（0~1）：黃昏核心（~17:00–19:00）全程都在，
/// 暮→夜交接（18:18–19:12）收掉。斜光、地板光池、長影差分圖共用。
double homeDuskIntensity(double h) =>
    _smooth(16.0, 16.8, h) * (1 - _smooth(18.3, 19.2, h));

/// 首頁靜態差分 overlay（燈罩發亮 / 黃昏長影）。
///
/// 與背景圖同一套 cover-by-width + topCenter 版位鋪滿，直接疊在底圖上；
/// opacity 走 [SceneTimeController] 的分鐘級時段權重——沒有動畫幀成本，
/// ticker 全停時也會跟著分鐘更新。圖檔缺失時 errorBuilder 回退為空層。
class HomeSceneStaticOverlays extends StatelessWidget {
  const HomeSceneStaticOverlays({super.key});

  static Widget _cover(String path) {
    return ClipRect(
      child: Align(
        alignment: Alignment.topCenter,
        child: Image.asset(
          path,
          height: double.infinity,
          width: double.infinity,
          fit: BoxFit.cover,
          alignment: Alignment.topCenter,
          errorBuilder: (_, _, _) => const SizedBox.shrink(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: ListenableBuilder(
        listenable: SceneTimeController.instance,
        builder: (_, _) {
          final h = SceneTimeController.instance.state.hour;
          final lamp = homeLampIntensity(h);
          final dusk = homeDuskIntensity(h);
          return Stack(
            fit: StackFit.expand,
            children: [
              if (dusk > 0.01)
                Opacity(
                  opacity: dusk,
                  child: _cover('assets/scenes/home/home_shadow_dusk.png'),
                ),
              if (lamp > 0.01)
                Opacity(
                  opacity: lamp,
                  child: _cover('assets/scenes/home/home_lamp_lit.png'),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// 單一場景動畫時鐘：一條 Ticker 驅動同場景所有動態層（窗景/室內光影/
/// 互動特效共享相位），完整模式節流 20fps（計劃書 §5.2）。
/// 由頁面 State 持有並負責 start/stop/dispose：閒置凍結呼叫 [stop]（0fps），
/// 互動喚醒呼叫 [start]；切分頁/退背景由 TickerProvider 的 TickerMode 靜音。
class SceneAnimationClock {
  SceneAnimationClock({required TickerProvider vsync, double maxFps = 20})
    : _minInterval = 1 / maxFps {
    _ticker = vsync.createTicker(_onTick);
  }

  late final Ticker _ticker;
  final double _minInterval;

  /// painter 的 repaint listenable：值 = 時鐘啟動至今秒數（無界）。
  final ValueNotifier<double> time = ValueNotifier<double>(0);
  double _lastNotified = 0;

  void _onTick(Duration elapsed) {
    final t = elapsed.inMicroseconds / 1e6;
    if (t - _lastNotified < _minInterval) return;
    _lastNotified = t;
    time.value = t;
  }

  void start() {
    if (!_ticker.isActive) _ticker.start();
  }

  /// 完全停止（0fps）。之後的時段配色更新走 SceneTimeController 的
  /// 分鐘級單次 repaint，不需要動畫幀。
  void stop() => _ticker.stop();

  void dispose() {
    _ticker.dispose();
    time.dispose();
  }
}

/// Ticker + ValueNotifier 的共用底座（動態層自有時鐘用，30fps 節流）。
/// 覆寫 [externalClock] 提供共享時鐘時，不建立自己的 Ticker（首頁模式；
/// 計劃書 §5.2「同一場景單一 clock」）。
mixin ThrottledSceneTicker<T extends StatefulWidget>
    on State<T>, SingleTickerProviderStateMixin<T> {
  Ticker? _ticker;
  // painter 的 repaint listenable：值 = 開場至今秒數（無界）
  final ValueNotifier<double> _time = ValueNotifier<double>(0);
  double _lastNotified = 0;

  /// 外部共享時鐘（例：首頁的 [SceneAnimationClock.time]）；null = 自建。
  ValueNotifier<double>? get externalClock => null;

  /// painter 的 repaint listenable（跨檔案重用，例：room_scene_painters 的
  /// [RoomSceneEffects]）。
  ValueNotifier<double> get sceneTime => externalClock ?? _time;

  @override
  void initState() {
    super.initState();
    if (externalClock == null) {
      _ticker = createTicker((elapsed) {
        final t = elapsed.inMicroseconds / 1e6;
        if (t - _lastNotified < 1 / 30) return; // 節流 ~30fps
        _lastNotified = t;
        _time.value = t;
      })..start();
    }
  }

  @override
  void dispose() {
    _ticker?.dispose();
    _time.dispose();
    super.dispose();
  }
}

// ════════════════════════════════════════════════════════════════
// 窗外景（墊在背景圖之下）
// ════════════════════════════════════════════════════════════════

class WindowBackdrop extends StatefulWidget {
  /// 窗玻璃開口矩形（比例座標：left/right = 寬比例、top/bottom = 顯示圖高比例）。
  /// 天空畫在此矩形內，實際可見形狀由上層去背圖的 alpha 決定，所以略大於玻璃即可。
  /// 預設為首頁拱窗位置，故首頁 `const WindowBackdrop()` 行為不變。
  final Rect windowRect;

  /// 共享場景時鐘（見 [SceneAnimationClock]）；null = 自建 30fps ticker。
  final ValueNotifier<double>? clock;

  const WindowBackdrop({
    super.key,
    this.windowRect = const Rect.fromLTRB(0, 0.040, 0.21, 0.345),
    this.clock,
  });

  @override
  State<WindowBackdrop> createState() => _WindowBackdropState();
}

class _WindowBackdropState extends State<WindowBackdrop>
    with SingleTickerProviderStateMixin, ThrottledSceneTicker {
  @override
  ValueNotifier<double>? get externalClock => widget.clock;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: RepaintBoundary(
        child: CustomPaint(
          isComplex: true,
          willChange: true,
          size: Size.infinite,
          painter: _WindowBackdropPainter(
            time: sceneTime,
            windowRect: widget.windowRect,
          ),
        ),
      ),
    );
  }
}

class _WindowBackdropPainter extends CustomPainter {
  final ValueNotifier<double> time;
  final Rect windowRect;

  // repaint 合併分鐘級的時段更新：ticker 被凍結（閒置/省電）時，跨過
  // 時段交界仍會做單次 repaint 更新配色，不會停格在舊時段。
  _WindowBackdropPainter({required this.time, required this.windowRect})
    : super(repaint: Listenable.merge([time, SceneTimeController.instance]));

  // 夜空星點（窗區座標：x = 區寬比例、y = 區高比例的上半）
  static const _stars = <(double, double, double)>[
    (0.16, 0.10, 1.1),
    (0.36, 0.05, 0.9),
    (0.55, 0.14, 1.3),
    (0.74, 0.08, 0.9),
    (0.88, 0.18, 1.1),
    (0.27, 0.24, 0.8),
    (0.64, 0.30, 1.0),
    (0.45, 0.38, 0.8),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final t = time.value;
    final h = sceneHourNow();
    final w = size.width;
    final imgH = w / 0.8;
    final pal = _windowPalette(h);

    // 窗區（比玻璃開口略大，邊緣被上層去背圖的窗框蓋掉）
    final region = Rect.fromLTRB(
      w * windowRect.left,
      imgH * windowRect.top,
      w * windowRect.right,
      imgH * windowRect.bottom,
    );
    final xL = region.left;
    final xR = region.right;
    final winW = region.width;
    final top = region.top;
    final bottom = region.bottom;

    canvas.save();
    canvas.clipRect(region);

    // 1. 天空
    canvas.drawRect(
      region,
      Paint()
        ..shader = ui.Gradient.linear(Offset(0, top), Offset(0, bottom), [
          pal.top,
          pal.bot,
        ]),
    );

    // 2. 星星（夜間，各自相位眨眼）
    if (pal.star > 0.01) {
      final starPaint = Paint();
      for (var i = 0; i < _stars.length; i++) {
        final (sx, sy, sr) = _stars[i];
        final tw = 0.55 + 0.45 * math.sin(t * (1.3 + i * 0.31) + i * 2.1);
        starPaint.color = const Color(
          0xFFFFF6DE,
        ).withValues(alpha: (pal.star * tw).clamp(0.0, 1.0));
        canvas.drawCircle(
          Offset(xL + winW * sx, top + region.height * sy),
          sr,
          starPaint,
        );
      }
    }

    // 3. 太陽（6~19）/ 月亮（19~6）沿窗內小弧移動
    _paintCelestial(canvas, xL, xR, top, bottom, h);

    // 4. 兩朵小雲慢慢飄過（夜裡淡到幾乎看不見）
    final cloudPaint = Paint()
      ..color = pal.cloud.withValues(alpha: 1.0 - pal.nightness * 0.55);
    for (final (x0, cy, s, sp) in <(double, double, double, double)>[
      (0.15, 0.30, 1.0, 0.011),
      (0.65, 0.16, 0.72, 0.017),
    ]) {
      final fx = (x0 + t * sp) % 1.3 - 0.15;
      final c = Offset(xL + winW * fx, top + region.height * cy);
      canvas.drawOval(
        Rect.fromCenter(
          center: c,
          width: winW * 0.34 * s,
          height: winW * 0.13 * s,
        ),
        cloudPaint,
      );
      canvas.drawCircle(
        c.translate(-winW * 0.07 * s, -winW * 0.045 * s),
        winW * 0.075 * s,
        cloudPaint,
      );
      canvas.drawCircle(
        c.translate(winW * 0.05 * s, -winW * 0.035 * s),
        winW * 0.06 * s,
        cloudPaint,
      );
    }

    // 5. 遠/近兩層灌木剪影帶（顏色隨時段入夜變深）
    final far = Color.lerp(
      const Color(0xFFA7CF8B),
      const Color(0xFF46566E),
      pal.nightness,
    )!;
    final near = Color.lerp(
      const Color(0xFF86BB68),
      const Color(0xFF38485C),
      pal.nightness,
    )!;
    _paintBushBand(canvas, region, 0.60, 14, 16, 2.1, 0, far);
    _paintBushBand(canvas, region, 0.76, 10, 14, 1.7, 1, near);

    canvas.restore();
  }

  void _paintBushBand(
    Canvas canvas,
    Rect region,
    double topFrac,
    double stagger,
    double arc,
    double seed,
    int phase,
    Color color,
  ) {
    final bandTop = region.top + region.height * topFrac;
    const bumps = 4;
    final path = Path()
      ..moveTo(region.left, region.bottom)
      ..lineTo(region.left, bandTop + 8);
    for (var i = 0; i <= bumps; i++) {
      final bx = region.left + region.width * (i / bumps);
      final wave = (i % 2 == phase) ? 0.0 : stagger;
      final by = bandTop + wave + 4 * math.sin(i * seed + phase);
      if (i == 0) {
        path.lineTo(bx, by);
      } else {
        path.quadraticBezierTo(bx - region.width / bumps / 2, by - arc, bx, by);
      }
    }
    path
      ..lineTo(region.right, region.bottom)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  void _paintCelestial(
    Canvas canvas,
    double xL,
    double xR,
    double top,
    double bottom,
    double h,
  ) {
    final winW = xR - xL;
    final isMoon = !(h >= 6 && h < 19);
    final tArc = isMoon ? ((h - 19) % 24) / 11 : (h - 6) / 13;
    final lift = math.sin(math.pi * tArc.clamp(0.0, 1.0));
    final c = Offset(
      xL + winW * ui.lerpDouble(0.18, 0.82, tArc)!,
      ui.lerpDouble(
        bottom - (bottom - top) * 0.32,
        top + (bottom - top) * 0.14,
        lift,
      )!,
    );
    if (!isMoon) {
      final disc = Color.lerp(
        const Color(0xFFFFB36B),
        const Color(0xFFFFE9A8),
        lift,
      )!;
      canvas.drawCircle(
        c,
        winW * 0.30,
        Paint()
          ..shader = ui.Gradient.radial(c, winW * 0.30, [
            disc.withValues(alpha: 0.40),
            disc.withValues(alpha: 0),
          ]),
      );
      canvas.drawCircle(c, winW * 0.10, Paint()..color = disc);
    } else {
      const moon = Color(0xFFF6F1DE);
      canvas.drawCircle(
        c,
        winW * 0.24,
        Paint()
          ..shader = ui.Gradient.radial(c, winW * 0.24, [
            moon.withValues(alpha: 0.30),
            moon.withValues(alpha: 0),
          ]),
      );
      final r = winW * 0.085;
      final crescent = Path.combine(
        PathOperation.difference,
        Path()..addOval(Rect.fromCircle(center: c, radius: r)),
        Path()..addOval(
          Rect.fromCircle(
            center: c.translate(r * 0.45, -r * 0.25),
            radius: r * 0.88,
          ),
        ),
      );
      canvas.drawPath(crescent, Paint()..color = moon);
    }
  }

  @override
  bool shouldRepaint(covariant _WindowBackdropPainter old) =>
      old.windowRect != windowRect;
}

// 窗外景時段調色盤：keyframe 線性插值。時間點對齊 scene_time.dart 的
// 交接視窗：黃昏核心 17:00–19:00 天空要明顯金橘（原本 18.6 才到位，
// 17:30 只混 39% 看起來還是白天）；夜空在暮→夜交接（18:45–19:45）
// 收尾後的 20:30 完全就位。
({Color top, Color bot, Color cloud, double star, double nightness})
_windowPalette(double h) {
  const stops = <(double, (int, int, int, double, double))>[
    // (hour, (skyTop, skyBot, cloud, star, nightness))
    (0.0, (0xFF3D4673, 0xFF6E78AC, 0xFF9FA8CE, 1.0, 1.0)),
    (5.0, (0xFF3D4673, 0xFF6E78AC, 0xFF9FA8CE, 1.0, 1.0)),
    (6.6, (0xFFB8B5E0, 0xFFFFD9B3, 0xFFFFE7DC, 0.2, 0.15)),
    (8.5, (0xFF8FC9EC, 0xFFD6EFF7, 0xFFFFFFFF, 0.0, 0.0)),
    (16.5, (0xFF8FC9EC, 0xFFD6EFF7, 0xFFFFFFFF, 0.0, 0.0)),
    (17.6, (0xFF8F8BC9, 0xFFFFC08A, 0xFFF4CDC2, 0.1, 0.2)),
    (19.4, (0xFF5D5C96, 0xFFB98FB4, 0xFFB9AED6, 0.55, 0.55)),
    (20.5, (0xFF3D4673, 0xFF6E78AC, 0xFF9FA8CE, 1.0, 1.0)),
    (24.0, (0xFF3D4673, 0xFF6E78AC, 0xFF9FA8CE, 1.0, 1.0)),
  ];
  for (var i = 0; i < stops.length - 1; i++) {
    final (h0, a) = stops[i];
    final (h1, b) = stops[i + 1];
    if (h >= h0 && h <= h1) {
      final t = (h - h0) / (h1 - h0);
      return (
        top: Color.lerp(Color(a.$1), Color(b.$1), t)!,
        bot: Color.lerp(Color(a.$2), Color(b.$2), t)!,
        cloud: Color.lerp(Color(a.$3), Color(b.$3), t)!,
        star: ui.lerpDouble(a.$4, b.$4, t)!,
        nightness: ui.lerpDouble(a.$5, b.$5, t)!,
      );
    }
  }
  return (
    top: const Color(0xFF3D4673),
    bot: const Color(0xFF6E78AC),
    cloud: const Color(0xFF9FA8CE),
    star: 1.0,
    nightness: 1.0,
  );
}

// ════════════════════════════════════════════════════════════════
// 室內光影（疊在背景圖 + 時段色罩之上）
// ════════════════════════════════════════════════════════════════

class RoomAmbientOverlay extends StatefulWidget {
  /// 檯燈暖光暈中心（圖比例座標）；null = 這房間沒檯燈不畫。
  /// 預設為首頁床頭燈位置，所以首頁 `const RoomAmbientOverlay()` 行為不變。
  final Offset? lampCenter;

  /// 是否在光影層內畫「時段色罩」。首頁自己用 AnimatedContainer 畫色罩
  /// （還含全完成特例），所以維持 false；其他頁設 true 由本層代畫。
  final bool tint;

  /// 首頁陪伴感光影時序：6 點日光起、12 點最強、16 點收光，
  /// 16~18 點黃昏，夜晚以暖桌燈為主。預設 false，避免影響其他頁。
  final bool companionTiming;

  /// 共享場景時鐘（見 [SceneAnimationClock]）；null = 自建 30fps ticker。
  final ValueNotifier<double>? clock;

  const RoomAmbientOverlay({
    super.key,
    this.lampCenter = const Offset(0.645, 0.41),
    this.tint = false,
    this.companionTiming = false,
    this.clock,
  });

  @override
  State<RoomAmbientOverlay> createState() => _RoomAmbientOverlayState();
}

class _RoomAmbientOverlayState extends State<RoomAmbientOverlay>
    with SingleTickerProviderStateMixin, ThrottledSceneTicker {
  @override
  ValueNotifier<double>? get externalClock => widget.clock;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: RepaintBoundary(
        child: CustomPaint(
          isComplex: true,
          willChange: true,
          size: Size.infinite,
          painter: _RoomAmbientPainter(
            time: sceneTime,
            lampCenter: widget.lampCenter,
            tint: widget.tint,
            companionTiming: widget.companionTiming,
          ),
        ),
      ),
    );
  }
}

class _RoomAmbientPainter extends CustomPainter {
  final ValueNotifier<double> time;
  final Offset? lampCenter;
  final bool tint;
  final bool companionTiming;

  _RoomAmbientPainter({
    required this.time,
    required this.lampCenter,
    required this.tint,
    required this.companionTiming,
  }) : super(repaint: Listenable.merge([time, SceneTimeController.instance]));

  // 塵埃微粒：固定 seed，沿光束軸向參數化（s = 0~1 位置、off = 垂直偏移）
  static final List<({double s, double off, double r, double p1, double p2})>
  _motes = () {
    final rng = math.Random(5);
    return List.generate(16, (_) {
      return (
        s: rng.nextDouble(),
        off: (rng.nextDouble() - 0.5) * 2,
        r: 0.8 + rng.nextDouble() * 1.2,
        p1: rng.nextDouble() * math.pi * 2,
        p2: rng.nextDouble() * math.pi * 2,
      );
    });
  }();

  @override
  void paint(Canvas canvas, Size size) {
    final t = time.value;
    final h = sceneHourNow();
    final w = size.width;
    final imgH = w / 0.8; // home_bg cover + topCenter 的顯示高度

    // 時段色罩（其他頁用；首頁 tint=false，走自己的 AnimatedContainer）
    if (tint) {
      final tc = sceneTintNow();
      if (tc.a > 0) {
        canvas.drawRect(Offset.zero & size, Paint()..color = tc);
      }
    }

    late final double lamp;
    late final double moon;
    if (companionTiming) {
      final sun = _companionSun(h);
      final noon = _smooth(6.0, 12.0, h);
      // 黃昏斜光：與長影差分/光池共用同一條首頁黃昏曲線
      final dusk = homeDuskIntensity(h);
      if (sun > 0.01) {
        // (1 - 0.70*noon)＝能量補償：正午光束加寬 9 倍（spreadScale 8）
        // 又三道 additive 疊加，不補償會把窗簾/牆面 45% 沖到全白
        //（實測過曝率 45.3%→補償後應 <5%）。與其他頁 shaftStrength 的
        // (1 - 0.875*dayness) 同一個道理。
        _paintSunShafts(
          canvas,
          w,
          imgH,
          t,
          0.68 * sun * (1 - 0.70 * noon),
          noon,
          spreadScale: 8.0,
        );
      }
      if (dusk > 0.01) {
        _paintSunShafts(
          canvas,
          w,
          imgH,
          t,
          0.26 * dusk,
          0.22,
          colorOverride: const Color(0xFFFFB36F),
          spreadScale: 3.2,
        );
      }
      // 檯燈與黃昏同步暖起來（16:48 起漸亮）；與燈罩差分共用曲線
      lamp = homeLampIntensity(h);
      moon =
          (h >= 12 ? _smooth(21.0, 22.8, h) : (1 - _smooth(4.0, 5.5, h))) *
          0.45;
    } else {
      // ── 時段強度曲線（連續、平滑）──
      // 窗光：5:30 亮起、晨間最強、白天轉柔、16~19 收掉
      final shaft = _smooth(5.5, 7.5, h) * (1 - _smooth(16.0, 18.8, h));
      final dayness = _smooth(7.5, 11.0, h); // 0 = 晨金, 1 = 晝奶油
      final shaftStrength = shaft * (1.0 - 0.875 * dayness);
      if (shaftStrength > 0.01) {
        _paintSunShafts(canvas, w, imgH, t, shaftStrength, dayness);
      }
      // 檯燈：傍晚 16:30 漸亮、清晨 5~6:30 漸滅（跨日分段）
      lamp = h >= 12 ? _smooth(16.5, 18.0, h) : (1 - _smooth(5.0, 6.5, h));
      // 月光：22 點後 / 清晨 5 點前的極淡冷色窗光
      moon = h >= 12 ? _smooth(21.0, 22.8, h) : (1 - _smooth(4.0, 5.5, h));
    }

    if (moon > 0.01) _paintMoonShaft(canvas, w, imgH, moon);
    final lc = lampCenter;
    if (lamp > 0.01 && lc != null) {
      _paintLampGlow(canvas, w, imgH, t, lamp, lc);
    }
  }

  double _companionSun(double h) {
    if (h < 6 || h >= 16) return 0;
    if (h <= 12) return _smooth(6.0, 12.0, h);
    return 1 - _smooth(12.0, 16.0, h);
  }

  // ── 窗光光束 + 地板光池 + 塵埃 ──────────────────────────────
  void _paintSunShafts(
    Canvas canvas,
    double w,
    double imgH,
    double t,
    double strength,
    double dayness, {
    Color? colorOverride,
    double spreadScale = 11.0,
  }) {
    final color =
        colorOverride ??
        Color.lerp(
          const Color(0xFFFFC388), // 晨金
          const Color(0xFFFFEFCF), // 晝奶油
          dayness,
        )!;
    final dir = Offset(1, 0.9) / Offset(1, 0.9).distance;
    final perp = Offset(-dir.dy, dir.dx);
    final len = w * 0.95;
    // 白天太陽高 → 光束大幅加寬成一片柔光（晨光 dayness≈0 仍窄而戲劇）。
    // 調這個係數改白天「範圍」：越大越寬。
    final spread = 1.0 + spreadScale * dayness;

    // 三道光束沿窗格錯開，亮度微微呼吸（極慢，幾乎察覺不到才高級）
    final beams = <({Offset start, double halfW, double alpha})>[
      (start: Offset(w * 0.07, imgH * 0.09), halfW: w * 0.030, alpha: 0.18),
      (start: Offset(w * 0.12, imgH * 0.16), halfW: w * 0.042, alpha: 0.22),
      (start: Offset(w * 0.17, imgH * 0.24), halfW: w * 0.034, alpha: 0.16),
    ];
    final breath = 0.9 + 0.1 * math.sin(t * 0.35);
    final blur = Paint()
      ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 9)
      ..blendMode = BlendMode.plus;

    for (final b in beams) {
      final end = b.start + dir * len;
      final hw = b.halfW * spread;
      final path = Path()
        ..moveTo(b.start.dx + perp.dx * hw, b.start.dy + perp.dy * hw)
        ..lineTo(b.start.dx - perp.dx * hw, b.start.dy - perp.dy * hw)
        // 尾端略張開，像真的光錐
        ..lineTo(end.dx - perp.dx * hw * 1.6, end.dy - perp.dy * hw * 1.6)
        ..lineTo(end.dx + perp.dx * hw * 1.6, end.dy + perp.dy * hw * 1.6)
        ..close();
      blur.shader = ui.Gradient.linear(b.start, end, [
        color.withValues(alpha: b.alpha * strength * breath),
        color.withValues(alpha: 0),
      ]);
      canvas.drawPath(path, blur);
    }

    // 塵埃微粒：沿中央光束緩慢漂移 + 各自閃爍
    final mid = beams[1];
    final motePaint = Paint()..blendMode = BlendMode.plus;
    for (final m in _motes) {
      final s = (m.s + t * 0.009) % 1.0;
      final wobble =
          perp *
          (m.off * mid.halfW * 2.2 + w * 0.012 * math.sin(t * 0.13 + m.p2));
      final pos =
          mid.start +
          dir * (s * len * 0.92 + w * 0.015 * math.sin(t * 0.09 + m.p1)) +
          wobble;
      final twinkle = 0.5 + 0.5 * math.sin(t * (0.6 + m.p1 * 0.2) + m.p2);
      // 沿光束尾端淡出，跟光束的衰減一致
      final fade = (1 - s) * strength * twinkle;
      motePaint.color = color.withValues(alpha: 0.38 * fade);
      canvas.drawCircle(pos, m.r, motePaint);
    }
  }

  // ── 深夜月光：一道極淡的冷色斜光 ────────────────────────────
  void _paintMoonShaft(Canvas canvas, double w, double imgH, double moon) {
    const color = Color(0xFFBFC9EE);
    final dir = Offset(1, 0.9) / Offset(1, 0.9).distance;
    final perp = Offset(-dir.dy, dir.dx);
    final start = Offset(w * 0.11, imgH * 0.14);
    final end = start + dir * (w * 0.9);
    final halfW = w * 0.055;
    final path = Path()
      ..moveTo(start.dx + perp.dx * halfW, start.dy + perp.dy * halfW)
      ..lineTo(start.dx - perp.dx * halfW, start.dy - perp.dy * halfW)
      ..lineTo(end.dx - perp.dx * halfW * 1.5, end.dy - perp.dy * halfW * 1.5)
      ..lineTo(end.dx + perp.dx * halfW * 1.5, end.dy + perp.dy * halfW * 1.5)
      ..close();
    canvas.drawPath(
      path,
      Paint()
        ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 11)
        ..blendMode = BlendMode.plus
        ..shader = ui.Gradient.linear(start, end, [
          color.withValues(alpha: 0.07 * moon),
          color.withValues(alpha: 0),
        ]),
    );
  }

  // ── 床頭檯燈暖光暈（呼吸）────────────────────────────────────
  void _paintLampGlow(
    Canvas canvas,
    double w,
    double imgH,
    double t,
    double lamp,
    Offset center,
  ) {
    final c = Offset(w * center.dx, imgH * center.dy);
    final breath = 0.86 + 0.14 * math.sin(t * 0.8);
    const warm = Color(0xFFFFC98A);
    // 外暈大而淡、內暈小而暖，疊出柔和的燈光層次
    canvas.drawCircle(
      c,
      w * 0.30,
      Paint()
        ..blendMode = BlendMode.plus
        ..shader = ui.Gradient.radial(c, w * 0.30, [
          warm.withValues(alpha: 0.16 * lamp * breath),
          warm.withValues(alpha: 0),
        ]),
    );
    canvas.drawCircle(
      c,
      w * 0.12,
      Paint()
        ..blendMode = BlendMode.plus
        ..shader = ui.Gradient.radial(c, w * 0.12, [
          const Color(0xFFFFE0B0).withValues(alpha: 0.22 * lamp * breath),
          const Color(0xFFFFE0B0).withValues(alpha: 0),
        ]),
    );
  }

  @override
  bool shouldRepaint(covariant _RoomAmbientPainter old) =>
      old.lampCenter != lampCenter ||
      old.tint != tint ||
      old.companionTiming != companionTiming;
}
