// 全螢幕桌面模式專屬視覺 token：兔咪家的暖奶油遊戲桌。
//
// 2026-07 與 Codex 版擇優融合：對局面從深色絨布改回 app 本體的
// 暖紙／鼠尾草世界（家庭桌遊感、與兔咪陪伴身分一致），淺色桌面
// 一律用 `tableInk*`；深色奶油墨階（`inkStrong/Soft/Faint`、`hairline`）
// 保留給刻意維持深色的骰盤墊，別在淺色桌面上用（會讀不到）。
import 'package:flutter/material.dart';

import '../../../utils/app_style.dart';

/// 「遊戲」模式在 app 淺色世界與對局面共用的鼠尾草主色。
const Color kGameAccent = Color(0xFF3F7868);

/// 鼠尾草主色的深階（文字/圖示在淺底上需要更高對比時用）。
const Color kGameAccentDark = Color(0xFF28594D);

abstract final class TableTheme {
  // ── 暖奶油桌面 ───────────────────────────────────────────
  /// 桌面中心（受光的奶油紙面）。
  static const Color feltCenter = Color(0xFFFFF8EC);

  /// 桌面邊緣（鼠尾草收邊）。
  static const Color feltEdge = Color(0xFFDDE9E0);

  /// 桌面上的浮起面板（棋鐘半面底）。
  static const Color panel = Color(0xFFFFFDF9);

  // ── 淺色桌面的墨階與分隔 ─────────────────────────────────
  static const Color tableInkStrong = AppInk.strong;
  static const Color tableInkSoft = Color(0xFF6F6258);
  static const Color tableInkFaint = Color(0xFF8A7C6F);
  static const Color tableDivider = Color(0xFFD8CEC2);

  // ── 深色骰盤墊專用（骰盤刻意保留深色，像桌上一塊真的骰盤墊）──
  static const Color hairline = Color(0x26F6ECDD);
  static const Color inkStrong = Color(0xFFF6ECDD);
  static const Color inkSoft = Color(0xFFCBB9A4);
  static const Color inkFaint = Color(0xFF8F7B67);

  // ── 玩家座位色（6 色，淺底調校：飽和降一階、亮度壓深）────────
  // 刻意避開警示色相：1 號位不用珊瑚紅（跟猩紅撞色），改玫瑰。
  static const List<Color> seatColors = [
    Color(0xFFA84262), // 玫瑰
    Color(0xFF8B611B), // 蜂蜜棕
    Color(0xFF3F744E), // 苔玉綠
    Color(0xFF2F7078), // 青瓷藍
    Color(0xFF4E5FA6), // 藍紫
    Color(0xFF765084), // 莓紫
  ];

  static Color seatColor(int index) => seatColors[index % seatColors.length];

  // ── 警示色階（正常時用玩家座位色）────────────────────────────
  /// 骰盤實色按鈕用的琥珀（深色墊上）。
  static const Color warn = Color(0xFFE9A94E);

  /// 淺色桌面上的提醒文字／倒數弧（琥珀壓深才讀得到）。
  static const Color warnInk = Color(0xFF956313);

  /// 加強提醒（每秒脈動）。深猩紅：與所有座位色拉開色相。
  static const Color critical = Color(0xFFB74736);

  /// 超時。
  static const Color overtime = Color(0xFFA93D32);

  /// urgency（引擎的 0–3）對應主色；0 時用玩家座位色。
  static Color urgencyColor(int urgency, Color seat) => switch (urgency) {
    1 => warnInk,
    2 => critical,
    3 => overtime,
    _ => seat,
  };

  // ── 文字樣式 ─────────────────────────────────────────────
  /// 巨大倒數數字（實際尺寸由外層 FittedBox 決定，這裡給大基準）。
  static TextStyle bigDigits({Color color = tableInkStrong}) =>
      AppType.digits(fontSize: 120, fontWeight: FontWeight.w800, color: color);

  static TextStyle nameStyle({
    double fontSize = 26,
    Color color = tableInkStrong,
  }) =>
      TextStyle(fontSize: fontSize, fontWeight: FontWeight.w900, color: color);

  /// 奶油紙面到鼠尾草桌邊的柔和背景。
  /// 家庭桌 CG（[tableAsset]）的後備：asset 載不出來也不會開天窗。
  static BoxDecoration feltBackground() => const BoxDecoration(
    gradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFFFFFAF1), feltCenter, feltEdge],
      stops: [0.0, 0.52, 1.0],
    ),
  );

  /// AI 生成的直向家庭遊戲桌 CG；比例貼近手機全螢幕，對局與獨立骰盤共用。
  static const String tableAsset =
      'assets/scenes/game/game_family_table_bg_v2.jpg';

  /// 疊在 CG 上的極淡鼠尾草收邊：聚焦中央，不把畫面壓暗。
  static BoxDecoration feltVignette() => const BoxDecoration(
    gradient: RadialGradient(
      center: Alignment(0, -0.1),
      radius: 1.25,
      colors: [Color(0x00FFFFFF), Color(0x245E8B79)],
      stops: [0.62, 1.0],
    ),
  );

  /// 中央暖陽光：讓奶油紙面仍有插畫層次（光影特效照慣例 Flutter 端疊）。
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
