// 本機匿名使用統計（roadmap §7a-4）。
//
// 只記「事件名 → 當日次數」，不記任何輸入內容或個資、完全不上傳。
// 目的：Phase 1 之後用真實使用數據決定回顧/小屋/任務等主分頁要不要做、
// 衣櫃是否真的帶動回訪；沒有數據前不猜（roadmap §2）。
//
// 儲存：每個「真實日曆日」一個 JSON map（PrefsKeys.usageDay(yyyy-MM-dd)）。
// 刻意用真實日曆日而非邏輯日（同 coin_service 判重先例）：統計不需要
// 跟換日設定糾纏，也不會因為調設定產生重複/缺日。
// 寫入新的一天時順手清掉超過保留天數的舊 key，資料量有上限。
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'prefs_keys.dart';

/// 事件名集中定義；呼叫端不准寫裸字串，方便日後盤點有哪些事件。
abstract final class UsageEvents {
  /// 主分頁開啟：tab.home / tab.water ...（id 用 TabIds 常數）。
  static String tab(String tabId) => 'tab.$tabId';

  /// 首頁習慣打卡（每日勾選、每週累加各算一次；撤銷不計）。
  static const habitCheck = 'habit.check';

  /// 喝水頁記錄一杯 / 自訂量。
  static const waterAdd = 'water.add';

  /// 體重頁存一筆紀錄（新增或覆寫同日都算一次）。
  static const weightAdd = 'weight.add';

  /// 計時啟動：timer.focus.start / timer.exercise.start ...
  /// （含暫停後 resume，粗略當 engagement 即可，不求精確）。
  static String timerStart(String mode) => 'timer.$mode.start';

  /// 衣櫃購買成功（造型與音樂盒曲子共用）。
  static const wardrobeBuy = 'wardrobe.buy';

  /// 衣櫃套用造型。
  static const wardrobeApply = 'wardrobe.apply';

  /// 繪本全螢幕揭曉頁開啟。
  static const storyOpen = 'story.open';

  /// 回憶本開啟。
  static const memoryBookOpen = 'memory_book.open';

  /// 三指彩蛋「菜園小蛇」開啟／單局結算。
  static const snakeArcadeOpen = 'snake_arcade.open';
  static const snakeArcadeFinish = 'snake_arcade.finish';
}

abstract final class UsageStats {
  /// 保留天數；超過的舊日 key 在「寫入新的一天」時順手清掉。
  /// 取 90 天：足夠涵蓋 Phase 1 的 D30 觀察窗還有餘裕。
  static const retentionDays = 90;

  static String _ymd(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// 事件 +1。fire-and-forget：呼叫端 `unawaited(UsageStats.bump(...))`。
  /// 統計絕不能影響功能——任何失敗（極早期呼叫、測試環境沒 plugin）
  /// 一律吞掉。
  static Future<void> bump(String event, {DateTime? now}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final day = _ymd(now ?? DateTime.now());
      final key = PrefsKeys.usageDay(day);
      final isNewDay = !prefs.containsKey(key);
      // 讀改寫之間沒有 await（setString 同步更新記憶體快取），
      // 連續 bump 不會互相蓋寫。
      final counts = decodeDay(prefs.getString(key));
      counts[event] = (counts[event] ?? 0) + 1;
      await prefs.setString(key, jsonEncode(counts));
      if (isNewDay) await _trim(prefs, now: now);
    } catch (_) {
      // 統計失敗直接放棄這一筆，不重試、不打擾使用者。
    }
  }

  /// 讀某日的事件計數（沒資料回空 map）。
  static Map<String, int> dayCounts(SharedPreferences prefs, String ymd) =>
      decodeDay(prefs.getString(PrefsKeys.usageDay(ymd)));

  /// 已有紀錄的日期（yyyy-MM-dd，新→舊）。
  static List<String> recordedDays(SharedPreferences prefs) =>
      prefs
          .getKeys()
          .where((k) => k.startsWith(PrefsKeys.usageDayPrefix))
          .map((k) => k.substring(PrefsKeys.usageDayPrefix.length))
          .toList()
        ..sort((a, b) => b.compareTo(a));

  /// 解析單日 JSON；壞資料（非 map、非數字值）安靜回空/略過。
  static Map<String, int> decodeDay(String? raw) {
    if (raw == null || raw.isEmpty) return <String, int>{};
    try {
      final obj = jsonDecode(raw);
      if (obj is! Map<String, dynamic>) return <String, int>{};
      return {
        for (final e in obj.entries)
          if (e.value is num) e.key: (e.value as num).toInt(),
      };
    } on FormatException {
      return <String, int>{};
    }
  }

  static Future<void> _trim(SharedPreferences prefs, {DateTime? now}) async {
    final cutoff = _ymd(
      (now ?? DateTime.now()).subtract(const Duration(days: retentionDays)),
    );
    for (final day in recordedDays(prefs)) {
      // yyyy-MM-dd 有零填充，字串比較等同日期比較。
      if (day.compareTo(cutoff) < 0) {
        await prefs.remove(PrefsKeys.usageDay(day));
      }
    }
  }
}
