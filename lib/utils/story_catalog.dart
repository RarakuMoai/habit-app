// 回憶本（特殊事件 / 劇情）的「目錄」單一真相來源。
//
// 事件的靜態資料都集中在這裡，衣櫃的「回憶」分區、繪本閱讀器（MemoryBookReader）、
// 全螢幕揭曉（StoryRevealPage）、觸發判定（StoryEvents）共用。
//
// ── 新增一個事件（未來只要有圖 + 台詞就照這三步）─────────────────
// 1. 圖丟進 assets/story/：單頁事件叫 `<id>.png`；多頁隨意命名，路徑寫進 pages。
// 2. 在 [storyCatalog] 加一筆（模板見下），一頁 = 一張圖 + 幾句台詞：
//
//    StoryEventSpec(
//      id: 'xmas_2026',
//      title: '一起過的聖誕節',
//      trigger: StoryTrigger.season,
//      season: SeasonWindow(month: 12, day: 24, days: 3), // 12/24–12/26
//      pages: [
//        StoryPage('assets/story/xmas_2026.png', ['台詞一句。', '再一句。']),
//      ],
//    ),
//
// 3. 開發者測試 → 回憶本：「預覽揭曉」看動畫排版、「模擬觸發」驗證真實接線。
//
// 事件「自己來」：不靠按鈕隨時觸發，而是掛在連勝、久違回來、節日等既有時刻上
// （見 story_store.dart 的 StoryEvents）。台詞短、溫柔，照兔咪人設
// （docs/tumi_character_guide.md）。

import 'package:flutter/painting.dart';

/// 回憶本主題色（暖棕／書頁感；與造型紫 kWardrobeAccent、音樂藍 kMusicAccent 區分）。
const Color kMemoryAccent = Color(0xFFC08552);

/// 事件觸發來源。判定邏輯在 StoryEvents，掛在 app 裡本來就會發生的時刻。
enum StoryTrigger {
  /// 習慣連勝達 [StoryEventSpec.threshold] 天（首頁跨日結算處）。
  habitStreak,

  /// 連續登入達 threshold 天（每日登入獎勵處）。
  loginStreak,

  /// 第一次建立習慣。
  firstHabit,

  /// 第一次當日習慣全部完成。
  firstAllDone,

  /// 離開 threshold 天以上後回來。
  comeback,

  /// 節日／季節：真實日曆日落在 [StoryEventSpec.season] 視窗內就觸發。
  /// 一次性回憶——解鎖一次後不再重複，繪本印的是「第一次一起過」的日期。
  season,
}

/// 事件層級。免費事件直接解鎖；訂閱事件（未來「劇情包」）等接金流再開。
enum EventTier { free, subscriber }

/// 繪本的一頁：一張圖 + 兔咪旁白幾句（翻到該頁時逐句浮現）。
class StoryPage {
  /// 繪本圖（`assets/story/…png`）；缺檔時閱讀器/揭曉頁有柔和 fallback。
  final String image;

  /// 兔咪旁白，一句一行。短、溫柔，照角色人設。
  final List<String> captions;

  const StoryPage(this.image, this.captions);
}

/// 節日視窗：每年 [month]/[day] 起連續 [days] 天（含起始日）。
/// 跨年視窗也支援（例：12/30 起 5 天 → 到隔年 1/3）。
class SeasonWindow {
  final int month;
  final int day;
  final int days;

  const SeasonWindow({required this.month, required this.day, this.days = 1})
    : assert(month >= 1 && month <= 12),
      assert(day >= 1 && day <= 31),
      assert(days >= 1 && days <= 60);

  /// [date] 的日曆日是否落在視窗內（年份不限，每年適用）。
  bool contains(DateTime date) {
    final d = DateTime(date.year, date.month, date.day);
    // 視窗可能跨年，所以分別檢查「今年開始」與「去年開始」兩個視窗。
    for (final startYear in [d.year - 1, d.year]) {
      final start = DateTime(startYear, month, day);
      final end = start.add(Duration(days: days));
      if (!d.isBefore(start) && d.isBefore(end)) return true;
    }
    return false;
  }
}

/// 一個特殊事件 = 一本小繪本（一或多頁，每頁單圖 + 台詞）。
class StoryEventSpec {
  final String id;

  /// 書籤 / 目錄顯示用的事件名。
  final String title;

  /// 目錄與閱讀器使用的短分類，讓每則回憶有自己的收藏語意。
  final String label;

  /// 尚未解鎖時顯示的溫和提示；不直接洩漏完整故事。
  final String unlockHint;

  /// 繪本頁（至少一頁）。
  final List<StoryPage> pages;

  final StoryTrigger trigger;

  /// 觸發門檻（連勝天數、離開天數等）；不需要的事件填 0。
  final int threshold;

  /// 節日視窗；只有 `trigger == StoryTrigger.season` 的事件需要。
  final SeasonWindow? season;

  final EventTier tier;

  const StoryEventSpec({
    required this.id,
    required this.title,
    this.label = '{name}回憶',
    this.unlockHint = '和{name}一起生活，就會遇見這一頁',
    required this.pages,
    required this.trigger,
    this.threshold = 0,
    this.season,
    this.tier = EventTier.free,
    // pages 至少一頁（const assert 摸不到 List.length，由 story_store_test 把關）
  }) : assert(
         trigger != StoryTrigger.season || season != null,
         'season 事件必須提供 SeasonWindow',
       );

  /// 封面圖（衣櫃「回憶」縮圖用）＝第一頁的圖。
  String get cover => pages.first.image;
}

const List<StoryEventSpec> storyCatalog = [
  StoryEventSpec(
    id: 'first_habit',
    title: '我們的第一頁',
    label: '初次相遇',
    unlockHint: '寫下第一個想慢慢做到的小習慣',
    trigger: StoryTrigger.firstHabit,
    pages: [
      // TODO(story-art): 正式回憶圖補回前，暫借現有場景圖避免缺檔。
      StoryPage('assets/scenes/home/home_day.webp', [
        '你寫下第一個想做到的小事。',
        '嗯...原來我們是從這裡開始的。',
        '這一頁，我會替你收好。',
      ]),
    ],
  ),
  StoryEventSpec(
    id: 'first_all_done',
    title: '燈都亮起來了',
    label: '小小完成',
    unlockHint: '第一次完成今天的所有習慣',
    trigger: StoryTrigger.firstAllDone,
    pages: [
      // TODO(story-art): 正式回憶圖補回前，暫借現有場景圖避免缺檔。
      StoryPage('assets/scenes/family/family_day.webp', [
        '最後一件小事，也亮起來了。',
        '我有看到你一路做到這裡。',
        '今天，可以放心休息了。',
      ]),
    ],
  ),
  StoryEventSpec(
    id: 'streak_7',
    title: '七顆星星的晚上',
    label: '一起走過',
    unlockHint: '讓一個習慣連續七天留下足跡',
    trigger: StoryTrigger.habitStreak,
    threshold: 7,
    pages: [
      // TODO(story-art): 正式回憶圖補回前，暫借現有場景圖避免缺檔。
      StoryPage('assets/scenes/timer/timer_day.webp', [
        '第一顆星亮起時，我還有點想睡。',
        '後來，你一天一天地回來。',
        '數到第七顆時，我就完全醒了。',
      ]),
    ],
  ),
  StoryEventSpec(
    id: 'comeback',
    title: '門再次打開的日子',
    label: '重新相遇',
    unlockHint: '離開一陣子後，再次回到{name}身邊',
    trigger: StoryTrigger.comeback,
    threshold: 7,
    pages: [
      // TODO(story-art): 正式回憶圖補回前，暫借現有場景圖避免缺檔。
      StoryPage('assets/scenes/water/water_day.webp', [
        '門安靜了一陣子。',
        '但我一直把這一頁留著。',
        '你回來了。',
        '嗯...我們就從今天，慢慢再走。',
      ]),
    ],
  ),
];

bool storyEventExists(String id) => storyCatalog.any((e) => e.id == id);

StoryEventSpec storyEventById(String id) => storyCatalog.firstWhere(
  (e) => e.id == id,
  orElse: () => storyCatalog.first,
);
