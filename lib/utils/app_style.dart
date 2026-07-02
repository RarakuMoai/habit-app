// 全 app 視覺 token：暖色文字階層 + 卡片陰影慣例。
// 陰影遵循插畫慣例：雙層（ambient 大模糊淡 + contact 小模糊貼地），
// 一律帶棕色調、不用純黑，跟兔咪暖色世界觀一致。
import 'package:flutter/material.dart';

/// 字型階層：內文走 theme 預設（Nunito + 中文系統字），
/// 數字/計數類元素用更圓滾的 display 字型做對比。
abstract final class AppType {
  /// 數字專用 display 字型（Baloo 2）。中文字 Baloo 2 沒有字形，
  /// 會自動 fallback 系統字，所以混排字串（「5 天」）可以整段套用。
  static TextStyle digits({
    double fontSize = 12,
    FontWeight fontWeight = FontWeight.w700,
    Color? color,
    double? letterSpacing,
  }) => TextStyle(
    fontFamily: 'Baloo 2',
    fontSize: fontSize,
    fontWeight: fontWeight,
    color: color,
    letterSpacing: letterSpacing,
    // Baloo 2 預設行高偏高，壓回 1.1 避免膠囊被撐高。
    // 注意：Baloo 2 ascent 佔比大，字形天生在行框內偏上，需要光學
    // 置中的場合（膠囊類）由呼叫端微調（見 MascotPill 的 Transform）
    height: 1.1,
  );
}

/// 文字墨色階層（暖棕系，取代 Colors.black87 / grey 系）。
abstract final class AppInk {
  /// 主要文字：深咖啡，比純黑柔和但對比足夠。
  static const Color strong = Color(0xFF453229);

  /// 次要文字（說明、副標）。
  static const Color soft = Color(0xFF8C7A6E);

  /// 淡化文字（完成後劃線、停用、佔位）。
  static const Color faint = Color(0xFFBDAA9E);

  /// 淡化的圖示（more 選單、裝飾性 icon）。
  static const Color iconFaint = Color(0xFFC9BAAE);
}

/// 卡片陰影：暖棕雙層。
abstract final class AppShadows {
  static const Color _brown = Color(0xFF8D6E63);

  /// 浮起卡片：ambient（大模糊淡）+ contact（小模糊貼地）。
  static List<BoxShadow> get card => [
    BoxShadow(
      color: _brown.withValues(alpha: 0.10),
      blurRadius: 16,
      offset: const Offset(0, 6),
    ),
    BoxShadow(
      color: _brown.withValues(alpha: 0.08),
      blurRadius: 4,
      offset: const Offset(0, 1.5),
    ),
  ];

  /// 完成/退場狀態：貼平，只留一點 contact。
  static List<BoxShadow> get flat => [
    BoxShadow(
      color: _brown.withValues(alpha: 0.06),
      blurRadius: 5,
      offset: const Offset(0, 2),
    ),
  ];
}

/// 卡片造型常數。
abstract final class AppCardStyle {
  static const double radius = 18;

  /// 未完成卡片的髮絲線邊框，給輪廓一點精緻度。
  static Border get hairline => Border.all(color: const Color(0x0A46342B));
}
