// 全螢幕桌面模式專屬視覺 token：兔咪家的暖奶油遊戲桌。
//
// 對局面延續 app 的暖紙、木質與鼠尾草綠，不再切進近黑賭場場景。
// `inkStrong/Soft/Faint` 仍保留給不可修改的深色骰盤使用；新的淺色桌面
// 請使用 `tableInk*`，避免骰盤的文字對比被連帶破壞。
import 'package:flutter/material.dart';

import '../../../utils/app_style.dart';

/// 「遊戲」模式在 app 淺色世界與家庭對局面共用的鼠尾草主色。
const Color kGameAccent = Color(0xFF3F7868);
const Color kGameAccentDark = Color(0xFF28594D);

abstract final class TableTheme {
  // ── 家庭遊戲桌 ───────────────────────────────────────────
  static const Color feltCenter = Color(0xFFFFF8EC);
  static const Color feltEdge = Color(0xFFDDE9E0);
  static const Color panel = Color(0xFFFFFDF9);

  /// 淺色桌面的文字與描邊；皆可在奶油底上保持清楚可讀。
  static const Color tableInkStrong = AppInk.strong;
  static const Color tableInkSoft = Color(0xFF6F6258);
  static const Color tableInkFaint = Color(0xFF796D63);
  static const Color tableDivider = Color(0xFFD8CEC2);

  /// 深色骰盤仍使用這組奶油墨色（骰盤檔案不屬於本次改造範圍）。
  static const Color hairline = Color(0x3DF6ECDD);
  static const Color inkStrong = Color(0xFFF6ECDD);
  static const Color inkSoft = Color(0xFFD8C8B5);
  static const Color inkFaint = Color(0xFFB9A58E);

  // ── 玩家座位色（淺底可讀；UI 仍會同時顯示號碼與姓名）──────────
  static const List<Color> seatColors = [
    Color(0xFFA84262), // 玫瑰
    Color(0xFF8B611B), // 蜂蜜棕
    Color(0xFF3F744E), // 苔玉綠
    Color(0xFF2F7078), // 青瓷藍
    Color(0xFF4E5FA6), // 藍紫
    Color(0xFF765084), // 莓紫
  ];

  static Color seatColor(int index) => seatColors[index % seatColors.length];

  // ── 警示色階 ─────────────────────────────────────────────
  /// 骰盤實色按鈕使用的柔和蜂蜜色。
  static const Color warn = Color(0xFFE4AE4B);

  /// 淺色桌面上的提醒文字／倒數弧。
  static const Color warnInk = Color(0xFF956313);
  static const Color critical = Color(0xFFB74736);
  static const Color overtime = Color(0xFFA93D32);

  static Color urgencyColor(int urgency, Color seat) => switch (urgency) {
    1 => warnInk,
    2 => critical,
    3 => overtime,
    _ => seat,
  };

  // ── 文字樣式 ─────────────────────────────────────────────
  static TextStyle bigDigits({Color color = tableInkStrong}) =>
      AppType.digits(fontSize: 120, fontWeight: FontWeight.w800, color: color);

  static TextStyle nameStyle({
    double fontSize = 26,
    Color color = tableInkStrong,
  }) =>
      TextStyle(fontSize: fontSize, fontWeight: FontWeight.w900, color: color);

  /// 奶油紙面到鼠尾草桌邊的柔和背景。
  static BoxDecoration feltBackground() => const BoxDecoration(
    gradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFFFFFAF1), feltCenter, feltEdge],
      stops: [0.0, 0.52, 1.0],
    ),
  );

  /// 保留舊常數供其他檔案編譯；新的 Stage 不再顯示深色絨布圖。
  static const String feltAsset = 'assets/scenes/game/game_felt_bg.png';

  /// 極淡的鼠尾草收邊，不把畫面壓暗。
  static BoxDecoration feltVignette() => const BoxDecoration(
    gradient: RadialGradient(
      center: Alignment(0, -0.1),
      radius: 1.25,
      colors: [Color(0x00FFFFFF), Color(0x245E8B79)],
      stops: [0.62, 1.0],
    ),
  );

  /// 中央暖陽光，讓奶油紙面仍有插畫層次。
  static BoxDecoration feltWarmLight() => const BoxDecoration(
    gradient: RadialGradient(
      center: Alignment(-0.25, -0.35),
      radius: 1.1,
      colors: [Color(0x8CFFFFFF), Color(0x00FFFFFF)],
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
