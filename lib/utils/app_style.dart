// 全 app 視覺 token：暖色文字階層 + 卡片陰影慣例。
// 陰影遵循插畫慣例：雙層（ambient 大模糊淡 + contact 小模糊貼地），
// 一律帶棕色調、不用純黑，跟兔咪暖色世界觀一致。
import 'package:flutter/material.dart';

/// 親子日常的共同色盤：奶油、蜜桃與暖棕，讓每個小習慣像家的延伸。
abstract final class AppPalette {
  static const brand = Color(0xFFB85F43);
  static const habit = Color(0xFFE88468);
  static const habitInk = Color(0xFFA55540);
  static const habitLight = Color(0xFFFFB887);
  static const habitDone = Color(0xFF4A926C);
  static const habitDoneLight = Color(0xFF69B17F);
  static const habitDoneSurface = Color(0xFFEEFAEE);
  static const focus = Color(0xFF9270A4);
  static const metronome = Color(0xFFB77B2C);
  static const water = Color(0xFF357E91);
  static const weight = Color(0xFFA96280);
  static const family = Color(0xFFAE7740);
  static const wardrobe = Color(0xFF9973A6);
  static const success = Color(0xFF638653);
  static const successSurface = Color(0xFFF0F6E6);
}

/// 有限、可取消的介面動效；持續的角色演出仍由各自的時間軸管理。
abstract final class AppMotion {
  static const quick = Duration(milliseconds: 160);
  static const settle = Duration(milliseconds: 260);
  static const enter = Duration(milliseconds: 360);
  static const curve = Curves.easeOutCubic;

  static Duration duration(BuildContext context, Duration value) =>
      MediaQuery.disableAnimationsOf(context) ? Duration.zero : value;
}

/// 室友選項與 AppPressable 共用的輕量按壓；不改變版面或觸控區尺寸。
abstract final class AppPressMotion {
  // 2.5% 內縮讓長卡片看得出按下，又不碰到相鄰選項。
  static const scale = 0.975;
  static const down = Duration(milliseconds: 90);
  static const release = Duration(milliseconds: 160);
  static const curve = Curves.easeOutCubic;
  static const tint = 0.06;
}

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

/// 文字墨色階層：柔和的暖棕，避免親子畫面變成冷硬的數據介面。
abstract final class AppInk {
  /// 主要文字：可讀的深咖啡色。
  static const Color strong = Color(0xFF594438);

  /// 次要文字（說明、副標）。
  /// 暖灰棕色說明字；主要資訊仍使用 strong。
  static const Color soft = Color(0xFF796657);

  /// 淡化文字（完成後劃線、停用、佔位）。低對比是刻意的——
  /// 只用在「已完成 / 停用」語意，不拿來排還需要閱讀的內容。
  static const Color faint = Color(0xFFBDAA9E);

  /// 淡化的圖示（more 選單、裝飾性 icon）。
  static const Color iconFaint = Color(0xFFC9BAAE);

  /// 危險操作（刪除、清空）：暖磚紅，取代裸寫 Colors.red。
  static const Color danger = Color(0xFFBF4E3B);
}

/// 表面／分隔色（暖色系，取代 Colors.white + grey.shade50~300 那組）。
abstract final class AppSurfaces {
  static const Color canvas = Color(0xFFFFF8ED);

  /// 暖白卡面（與 mascot_page_shell、popup/dialog theme 同色）。
  static const Color card = Color(0xFFFFFDFA);

  /// 輸入框、未選取 chip 的暖淺填色（取代 grey.shade50/100）。
  static const Color fill = Color(0xFFF8EDDE);

  /// 分隔線／描邊（取代 grey.shade200/300 與預設 Divider）。
  static const Color divider = Color(0xFFECDCCB);

  /// bottom sheet 頂端拖曳把手。
  static const Color dragHandle = Color(0xFFDCCFC2);
}

/// 等待狀態的顏色（見 `docs/visual_spec.md` §等待）。
///
/// 這組值原本只活在啟動畫面的載入條裡。U3 把它升成 token：全 app 的等待
/// 共用同一盞燈，使用者才讀得出「還是同一個地方，只是還沒亮完」。
abstract final class AppWaiting {
  /// 進度條本身：暖橘。**刻意不隨時段配色變動**——時段色說的是「現在幾點」，
  /// 等待說的是「東西還沒好」，兩件事疊在同一個元素上就都讀不出來。
  static const Color bar = Color(0xFFFF8A65);

  /// 底軌：白 78%（＝ `Colors.white.withValues(alpha: 0.78)`）。
  /// 半透明是刻意的，讓它在啟動的暖漸層與各頁的 `#F7F3EF` 上都只是淡一階。
  static const Color track = Color(0xC7FFFFFF);
}

/// 卡片陰影：暖棕雙層。
abstract final class AppShadows {
  static const Color _brown = Color(0xFF8D6E63);

  /// 浮起卡片：ambient（大模糊淡）+ contact（小模糊貼地）。
  static List<BoxShadow> get card => [
    BoxShadow(
      color: _brown.withValues(alpha: 0.055),
      blurRadius: 24,
      offset: const Offset(0, 8),
    ),
    BoxShadow(
      color: _brown.withValues(alpha: 0.035),
      blurRadius: 3,
      offset: const Offset(0, 1),
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
  static const double radius = 24;

  /// 底部面板的上緣圓角，比內容卡大一階；由 theme 統一供應。
  static const double sheetRadius = 32;

  /// 未完成卡片的髮絲線邊框，給輪廓一點精緻度。
  static Border get hairline => Border.all(color: const Color(0x12343E38));
}
