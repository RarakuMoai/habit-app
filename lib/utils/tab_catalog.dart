import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';

/// 底部主分頁的穩定識別碼。持久化排序（PrefsKeys.tabOrder）只存這些字串，
/// 不存 index，這樣即使之後新增/移除分頁，使用者排序也不會錯位。
class TabIds {
  static const habit = 'habit';
  static const timer = 'timer';
  static const water = 'water';
  static const weight = 'weight';
  static const family = 'family';
  static const wardrobe = 'wardrobe';

  const TabIds._();
}

/// 分頁的「顯示用」中繼資料（圖示；標籤走 [tabLabel] 取 l10n）。實際頁面
/// widget 仍在 main.dart 組（要帶各種 callback），這裡只放排序設定 UI 與
/// 預設順序需要的資訊。
class TabMeta {
  final String id;
  final IconData icon;
  const TabMeta(this.id, this.icon);
}

/// 分頁的顯示名稱（i18n）。未知 id（debug 模擬分頁）回傳 id 本身當保底。
String tabLabel(BuildContext context, String id) {
  final l10n = AppLocalizations.of(context);
  return switch (id) {
    TabIds.habit => l10n.tabHabits,
    TabIds.timer => l10n.tabTimer,
    TabIds.water => l10n.tabWater,
    TabIds.weight => l10n.tabWeight,
    TabIds.family => l10n.tabFamily,
    TabIds.wardrobe => l10n.tabWardrobe,
    _ => id,
  };
}

/// 底部導覽的換排規則。六個分頁在一般手機寬度維持單排，只有窄到每格
/// 不足 54px 才改為兩排。主畫面與設定預覽共用，避免兩邊排版不一致。
const double kBottomNavMinCellWidth = 54;

bool bottomNavUsesTwoRows({required double width, required int itemCount}) =>
    itemCount > 5 && width / itemCount < kBottomNavMinCellWidth;

/// 預設順序：使用者沒自訂排序時的 fallback，也決定「新啟用但還沒排過」的
/// 分頁附加在尾端的先後。圖示用底部列實際顯示的實心版本。
const List<TabMeta> kTabCatalog = [
  TabMeta(TabIds.habit, Icons.home),
  TabMeta(TabIds.timer, Icons.timer),
  TabMeta(TabIds.water, Icons.water_drop),
  TabMeta(TabIds.weight, Icons.monitor_weight),
  TabMeta(TabIds.family, Icons.family_restroom),
  TabMeta(TabIds.wardrobe, Icons.checkroom_rounded),
];

/// 分頁圖示改用手繪貼紙 PNG（取代原本的 Material `IconData`）。只有這 6 個
/// 正式分頁有素材；debug 模擬分頁沒有對應圖，仍回退到 `IconData`。
class TabIcons {
  static const _dir = 'assets/icon/tabs';
  static const _byId = <String, String>{
    TabIds.habit: '$_dir/tab_habit.png',
    TabIds.timer: '$_dir/tab_timer.png',
    TabIds.water: '$_dir/tab_water.png',
    TabIds.weight: '$_dir/tab_weight.png',
    TabIds.family: '$_dir/tab_family.png',
    TabIds.wardrobe: '$_dir/tab_wardrobe.png',
  };

  /// 有貼紙素材回傳資產路徑，否則 null（呼叫端退回 IconData）。
  static String? assetFor(String id) => _byId[id];

  const TabIcons._();
}

/// 底部列 / 排序頁共用的分頁圖示。
/// - 正式分頁 → 手繪貼紙 PNG。彩色圖沒法像線稿那樣「選中變色、未選中變灰」，
///   所以未選中改用降透明退場，選中狀態靠這個 + 藥丸底一起撐。
/// - debug 模擬分頁 → 沿用傳入的 [fallbackIcon]（Material 線稿）＋ [fallbackColor]。
class TabGlyph extends StatelessWidget {
  final String tabId;
  final IconData fallbackIcon;
  final Color fallbackColor;
  final double size;
  final bool selected;

  const TabGlyph({
    super.key,
    required this.tabId,
    required this.fallbackIcon,
    required this.fallbackColor,
    required this.size,
    this.selected = true,
  });

  @override
  Widget build(BuildContext context) {
    final asset = TabIcons.assetFor(tabId);
    if (asset == null) {
      return Icon(fallbackIcon, size: size, color: fallbackColor);
    }
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 140),
      opacity: selected ? 1.0 : 0.56,
      child: Image.asset(
        asset,
        width: size,
        height: size,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.high,
      ),
    );
  }
}

/// 把「已啟用的分頁 id」依使用者排序排好：
/// 1. 先照 [savedOrder]（使用者自訂）取出仍啟用的；
/// 2. 沒被排過的（新啟用分頁）照 [kTabCatalog] 預設順序補在尾端。
List<String> orderedTabIds(List<String> savedOrder, Set<String> enabledIds) {
  final result = <String>[];
  for (final id in savedOrder) {
    if (enabledIds.contains(id) && !result.contains(id)) result.add(id);
  }
  for (final meta in kTabCatalog) {
    if (enabledIds.contains(meta.id) && !result.contains(meta.id)) {
      result.add(meta.id);
    }
  }
  return result;
}
