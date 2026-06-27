import 'package:flutter/material.dart';

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

/// 分頁的「顯示用」中繼資料（圖示 + 標籤）。實際頁面 widget 仍在 main.dart
/// 組（要帶各種 callback），這裡只放排序設定 UI 與預設順序需要的資訊。
class TabMeta {
  final String id;
  final IconData icon;
  final String label;
  const TabMeta(this.id, this.icon, this.label);
}

/// 預設順序：使用者沒自訂排序時的 fallback，也決定「新啟用但還沒排過」的
/// 分頁附加在尾端的先後。圖示用底部列實際顯示的實心版本。
const List<TabMeta> kTabCatalog = [
  TabMeta(TabIds.habit, Icons.home, '習慣'),
  TabMeta(TabIds.timer, Icons.timer, '計時'),
  TabMeta(TabIds.water, Icons.water_drop, '喝水'),
  TabMeta(TabIds.weight, Icons.monitor_weight, '體重'),
  TabMeta(TabIds.family, Icons.family_restroom, '家庭'),
  TabMeta(TabIds.wardrobe, Icons.checkroom_rounded, '衣櫃'),
];

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
