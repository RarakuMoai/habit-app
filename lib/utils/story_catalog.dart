// 回憶本（特殊事件 / 劇情）的「目錄」單一真相來源。
//
// 事件的靜態資料都集中在這裡，衣櫃的「回憶」分區、繪本閱讀器（MemoryBookReader）、
// 觸發判定（StoryEvents）共用。之後要新增事件只要在 [storyCatalog] 加一筆、
// 把對應繪本圖丟進 assets/story/ 即可，解鎖/翻閱流程都會自動接上。
//
// 事件「自己來」：不靠按鈕隨時觸發，而是掛在連勝、久違回來、節日等既有時刻上
// （見 story_store.dart 的 StoryEvents）。一個事件 = 一頁單圖繪本。

import 'package:flutter/painting.dart';

/// 回憶本主題色（暖棕／書頁感；與造型紫 kWardrobeAccent、音樂藍 kMusicAccent 區分）。
const Color kMemoryAccent = Color(0xFFC08552);

/// 事件觸發來源。判定邏輯在 StoryEvents，掛在 app 裡本來就會發生的時刻。
enum StoryTrigger { habitStreak, loginStreak, firstHabit, comeback, season }

/// 事件層級。免費事件直接解鎖；訂閱事件（未來「劇情包」）等接金流再開。
enum EventTier { free, subscriber }

/// 一個特殊事件 = 一頁繪本（單圖 + 兔咪旁白幾句）。
class StoryEventSpec {
  final String id;

  /// 書籤 / 目錄顯示用的事件名。
  final String title;

  /// 繪本圖（`assets/story/<id>.png`）；缺檔時閱讀器有柔和 fallback。
  final String image;

  /// 兔咪旁白，一句一行，翻到該頁時逐句呈現。短、溫柔，照角色人設。
  final List<String> captions;

  final StoryTrigger trigger;

  /// 觸發門檻（連勝天數等）；不需要的事件填 0。
  final int threshold;

  final EventTier tier;

  const StoryEventSpec({
    required this.id,
    required this.title,
    required this.image,
    required this.captions,
    required this.trigger,
    required this.threshold,
    required this.tier,
  });
}

const List<StoryEventSpec> storyCatalog = [
  StoryEventSpec(
    id: 'streak_7',
    title: '連續第七天',
    image: 'assets/story/streak_7.png',
    captions: [
      '你已經連續七天了。',
      '我每天都有等到你。',
      '兔咪偷偷記了下來。',
      '這個，想留給你。',
    ],
    trigger: StoryTrigger.habitStreak,
    threshold: 7,
    tier: EventTier.free,
  ),
];

bool storyEventExists(String id) => storyCatalog.any((e) => e.id == id);

StoryEventSpec storyEventById(String id) => storyCatalog.firstWhere(
  (e) => e.id == id,
  orElse: () => storyCatalog.first,
);
