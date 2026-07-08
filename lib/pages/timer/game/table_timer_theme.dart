// 全螢幕桌面模式專屬視覺 token：深色絨布遊戲桌。
//
// 這是刻意的「場景切換」——推入對戰面就像把手機放上一張高級遊戲桌，
// 與 app 本體的暖紙質感形成儀式感對比；不是後場灰黑回潮。
// 色彩仍守全 app 慣例:深色以暖棕為基底、不用純黑，發光不用純白。
import 'package:flutter/material.dart';

import '../../../utils/app_style.dart';

/// 「遊戲」模式在 app 淺色世界裡的主色（計時頁分段鈕、入口卡用）。
/// 深色對戰面有自己的色盤（TableTheme），不共用這顆。
const Color kGameAccent = Color(0xFF5B8DEF);

abstract final class TableTheme {
  // ── 絨布桌面 ─────────────────────────────────────────────
  /// 桌面中心（受光處）。
  static const Color feltCenter = Color(0xFF33261C);

  /// 桌面邊緣（vignette 暗角）。
  static const Color feltEdge = Color(0xFF19110B);

  /// 桌面上的浮起面板（暫停層卡片、棋鐘半面底）。
  static const Color panel = Color(0xFF3C2D21);

  /// 桌面用的描邊/分隔（奶油色低透明）。
  static const Color hairline = Color(0x26F6ECDD);

  // ── 深色面上的墨色階層（奶油系）────────────────────────────
  static const Color inkStrong = Color(0xFFF6ECDD);
  static const Color inkSoft = Color(0xFFCBB9A4);
  static const Color inkFaint = Color(0xFF8F7B67);

  // ── 玩家座位色（6 色寶石盤，深底調校：鮮明但不螢光）──────────
  // 刻意避開警示色相：警示琥珀/猩紅要「一變色就看得出來」，
  // 所以 1 號位不用珊瑚紅（跟猩紅撞色），改玫瑰粉。
  static const List<Color> seatColors = [
    Color(0xFFEE7FA5), // 玫瑰
    Color(0xFFE9A94E), // 琥珀
    Color(0xFF83C58F), // 苔玉
    Color(0xFF5FBFCB), // 青瓷
    Color(0xFF8B9BEF), // 藍紫
    Color(0xFFCE8FDC), // 莓紫
  ];

  static Color seatColor(int index) => seatColors[index % seatColors.length];

  // ── 警示色階（正常時用玩家座位色）────────────────────────────
  /// 剩 warnSeconds 秒：明顯提醒。
  static const Color warn = Color(0xFFE9A94E);

  /// 加強提醒（每秒脈動）。深猩紅：與所有座位色拉開色相。
  static const Color critical = Color(0xFFE8452F);

  /// 超時。
  static const Color overtime = Color(0xFFD63A26);

  /// urgency（引擎的 0–3）對應主色；0 時用玩家座位色。
  static Color urgencyColor(int urgency, Color seat) => switch (urgency) {
    1 => warn,
    2 => critical,
    3 => overtime,
    _ => seat,
  };

  // ── 文字樣式 ─────────────────────────────────────────────
  /// 巨大倒數數字（實際尺寸由外層 FittedBox 決定，這裡給大基準）。
  static TextStyle bigDigits({Color color = inkStrong}) =>
      AppType.digits(fontSize: 120, fontWeight: FontWeight.w800, color: color);

  static TextStyle nameStyle({double fontSize = 26, Color color = inkStrong}) =>
      TextStyle(fontSize: fontSize, fontWeight: FontWeight.w900, color: color);

  /// 絨布桌面背景漸層（radial vignette）。
  /// CG 絨布圖（[feltAsset]）的後備：asset 載不出來也不會開天窗。
  static BoxDecoration feltBackground() => const BoxDecoration(
    gradient: RadialGradient(
      center: Alignment(0, -0.15),
      radius: 1.25,
      colors: [feltCenter, feltEdge],
      stops: [0.0, 1.0],
    ),
  );

  /// AI 生成的絨布桌面 CG（2026-07 素材整合）。
  static const String feltAsset = 'assets/scenes/game/game_felt_bg.png';

  /// 疊在 CG 上的保底暗角：把邊緣再壓深一階，確保中央發光數字
  /// 與角落鍵在任何縮放裁切下都有足夠對比。
  /// （2026-07-08 降到 35%：原 50% 讓桌面黑成虛空、失去絨布暖感。）
  static BoxDecoration feltVignette() => const BoxDecoration(
    gradient: RadialGradient(
      center: Alignment(0, -0.15),
      radius: 1.3,
      colors: [Color(0x00000000), Color(0x5919110B)],
      stops: [0.55, 1.0],
    ),
  );

  /// 桌面中央的暖光：像桌上方一盞吊燈，把絨布的暖棕托出來，
  /// 避免整面讀成冷硬的黑（家庭桌遊感 > 賭場感）。
  static BoxDecoration feltWarmLight() => const BoxDecoration(
    gradient: RadialGradient(
      center: Alignment(0, -0.2),
      radius: 1.0,
      colors: [Color(0x2EFFD9A0), Color(0x00FFD9A0)],
      stops: [0.0, 1.0],
    ),
  );
}

/// 對戰面共用時間文字：>= 60 秒顯示 m:ss，其他顯示整秒。
String formatTableSeconds(int seconds) {
  if (seconds >= 60) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }
  return '$seconds';
}

/// 正數計時（自由模式 / 超時）一律 m:ss。
String formatTableElapsed(Duration d) {
  final total = d.inSeconds;
  final m = total ~/ 60;
  final s = total % 60;
  return '$m:${s.toString().padLeft(2, '0')}';
}
