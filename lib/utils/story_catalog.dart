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
    title: '第一個小習慣',
    trigger: StoryTrigger.firstHabit,
    pages: [
      StoryPage('assets/story/first_habit.png', [
        '這是第一個小小的開始。',
        '不用急，我會慢慢陪你。',
        '兔咪把這一天收進書裡。',
      ]),
    ],
  ),
  StoryEventSpec(
    id: 'first_all_done',
    title: '第一次全部完成',
    trigger: StoryTrigger.firstAllDone,
    pages: [
      StoryPage('assets/story/first_all_done.png', [
        '今天的事情，都被你溫柔地完成了。',
        '我有看到喔。',
        '這一頁，想留給努力過的你。',
      ]),
    ],
  ),
  StoryEventSpec(
    id: 'streak_7',
    title: '連續第七天',
    trigger: StoryTrigger.habitStreak,
    threshold: 7,
    pages: [
      StoryPage('assets/story/streak_7.png', [
        '你已經連續七天了。',
        '我每天都有等到你。',
        '兔咪偷偷記了下來。',
        '這個，想留給你。',
      ]),
    ],
  ),
  StoryEventSpec(
    id: 'comeback',
    title: '你回來的這天',
    trigger: StoryTrigger.comeback,
    threshold: 7,
    pages: [
      StoryPage('assets/story/comeback.png', [
        '有一陣子沒見了。',
        '但你回來的時候，我還是在這裡。',
        '今天，也可以從很小的一步開始。',
      ]),
    ],
  ),
];

bool storyEventExists(String id) => storyCatalog.any((e) => e.id == id);

StoryEventSpec storyEventById(String id) => storyCatalog.firstWhere(
  (e) => e.id == id,
  orElse: () => storyCatalog.first,
);
