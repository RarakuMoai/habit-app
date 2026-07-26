// 衣櫃 / 音樂盒的「目錄」單一真相來源。
//
// 造型、曲目的靜態資料都集中在這裡，頁面、商店（WardrobeStore）、啟動流程
// （main.dart 決定播哪首 BGM）共用。之後要新增造型或音樂，只需要在
// [outfitCatalog] / [trackCatalog] 加一筆即可，其餘流程（擁有/選用/購買/
// 套用到兔咪）都會自動接上。

import 'package:flutter/painting.dart';

import '../l10n/app_localizations.dart';

const Color kWardrobeAccent = Color(0xFFB56CC7);
const Color kMusicAccent = Color(0xFF5A88D8);

// 情緒分類用色（卡片標籤/封面 fallback 的色調）。
const Color _kRelaxColor = Color(0xFF5A88D8); // 悠閒感：沉靜藍
const Color _kFocusColor = Color(0xFFE0894F); // 專注感：暖橙

/// 解鎖方式。
/// - [free]：預設擁有。
/// - [coin]：花金幣解鎖。
/// - [subscriberCoin]：需訂閱者身分，再花金幣解鎖。
enum UnlockType { free, coin, subscriberCoin }

/// 音樂情緒主分類。
enum MusicMood { relax, focus }

String moodLabel(AppLocalizations l10n, MusicMood mood) => switch (mood) {
  MusicMood.relax => l10n.moodRelax,
  MusicMood.focus => l10n.moodFocus,
};

/// 播放清單的循環模式。
/// - [loopOne]：單曲循環（gapless，預設氛圍曲就是這樣無縫接）。
/// - [loopAll]：列表循環，依清單順序播完接下一首，到底回第一首。
/// - [shuffle]：隨機，播完跳清單裡另一首。
enum PlayMode { loopOne, loopAll, shuffle }

String playModeLabel(AppLocalizations l10n, PlayMode mode) => switch (mode) {
  PlayMode.loopOne => l10n.playModeLoopOne,
  PlayMode.loopAll => l10n.playModeLoopAll,
  PlayMode.shuffle => l10n.playModeShuffle,
};

/// 持久化用字串（沿用舊 `bgm_mode` key；舊值 single/playlist 在 store 端遷移）。
String playModeKey(PlayMode mode) => switch (mode) {
  PlayMode.loopOne => 'loopOne',
  PlayMode.loopAll => 'loopAll',
  PlayMode.shuffle => 'shuffle',
};

/// 從持久化字串還原 [PlayMode]，含舊值遷移；無法辨識回傳 [fallback]。
PlayMode playModeFromKey(String? raw, {PlayMode fallback = PlayMode.loopAll}) =>
    switch (raw) {
      'loopOne' || 'single' => PlayMode.loopOne,
      'loopAll' || 'playlist' => PlayMode.loopAll,
      'shuffle' => PlayMode.shuffle,
      _ => fallback,
    };

class OutfitSpec {
  final String id;

  /// 預覽縮圖用的代表圖（通常是正面圖）。
  final String assetPath;

  /// 兔咪皮膚資料夾鍵：對應 `assets/mascot/<skinKey>/tumi_<emotion>.png`。
  /// 原始兔咪是 `core`；之後的造型放新資料夾、整組情緒圖補齊即可。
  final String skinKey;

  final UnlockType unlockType;
  final int coinPrice;

  const OutfitSpec({
    required this.id,
    required this.assetPath,
    required this.skinKey,
    required this.unlockType,
    required this.coinPrice,
  });
}

class MusicTrackSpec {
  final String id;
  final String title;
  final String artistName;
  final String channelName;
  final String sourceUrl;
  final String assetPath;

  /// 封面圖（`assets/...`）；null 則用色塊 + 音符 fallback。
  final String? coverAsset;

  final String durationLabel;
  final MusicMood mood;
  final Color color;
  final List<String> tags;
  final UnlockType unlockType;
  final int coinPrice;
  final String licenseNote;
  final String attributionText;

  const MusicTrackSpec({
    required this.id,
    required this.title,
    required this.artistName,
    required this.channelName,
    required this.sourceUrl,
    required this.assetPath,
    required this.coverAsset,
    required this.durationLabel,
    required this.mood,
    required this.color,
    required this.tags,
    required this.unlockType,
    required this.coinPrice,
    required this.licenseNote,
    required this.attributionText,
  });
}

/// 造型的顯示名／說明：id 才是穩定識別（存進 prefs 的是 id），
/// 文案一律走 l10n，不放在 catalog 裡。
String outfitName(AppLocalizations l10n, OutfitSpec o) => switch (o.id) {
  'tumi_original' => l10n.outfitOriginalName,
  _ => o.id,
};

String outfitSubtitle(AppLocalizations l10n, OutfitSpec o) => switch (o.id) {
  'tumi_original' => l10n.outfitOriginalSub,
  _ => '',
};

const List<OutfitSpec> outfitCatalog = [
  OutfitSpec(
    id: 'tumi_original',
    assetPath: 'assets/mascot/core/tumi_neutral_front.png',
    skinKey: 'core',
    unlockType: UnlockType.free,
    coinPrice: 0,
  ),
];

// 免費 BGM 的授權與感謝說明（各曲共用，來源連結逐曲不同）。
// 授權與感謝說明改由 l10n 提供；catalog 只留哨兵值，顯示時解析
// （見 licenseText / attributionText）。
const String _kFreeLicense = 'freeLicense';
const String _kFreeAttribution = 'freeAttribution';

String licenseText(AppLocalizations l10n, String note) =>
    note == 'freeLicense' ? l10n.bgmFreeLicense : note;

String attributionText(AppLocalizations l10n, String note) =>
    note == 'freeAttribution' ? l10n.bgmFreeAttribution : note;

const int _kTrackPrice = 50; // 新曲統一單價

const List<MusicTrackSpec> trackCatalog = [
  // ── 預設（免費）─────────────────────────────────────────
  MusicTrackSpec(
    id: 'bgm_main',
    title: 'Sleeping star',
    artistName: 'えだまめ88',
    channelName: 'えだまめ88',
    sourceUrl: 'https://www.youtube.com/watch?v=DUMfWYq7bmg',
    assetPath: 'sounds/bgm_main.m4a',
    coverAsset: 'assets/music/covers/bgm_main.png',
    durationLabel: 'loop',
    mood: MusicMood.relax,
    color: _kRelaxColor,
    tags: ['預設', '慢'],
    unlockType: UnlockType.free,
    coinPrice: 0,
    licenseNote: _kFreeLicense,
    attributionText: _kFreeAttribution,
  ),
  MusicTrackSpec(
    id: 'bgm_onboarding',
    title: 'cotton bear',
    artistName: '茶葉のぎか',
    channelName: '茶葉のぎか',
    sourceUrl: 'https://www.youtube.com/watch?v=tEPLpqIqU4I',
    assetPath: 'sounds/bgm_onboarding.m4a',
    coverAsset: 'assets/music/covers/bgm_onboarding.png',
    durationLabel: '1:51',
    mood: MusicMood.relax,
    color: _kRelaxColor,
    tags: ['前導', '慢'],
    unlockType: UnlockType.free,
    coinPrice: 0,
    licenseNote: _kFreeLicense,
    attributionText: _kFreeAttribution,
  ),

  // ── 悠閒感 ─────────────────────────────────────────────
  MusicTrackSpec(
    id: 'bgm_aquamarine',
    title: 'Aquamarine',
    artistName: '茶葉のぎか',
    channelName: '茶葉のぎか',
    sourceUrl: 'https://www.youtube.com/watch?v=AptgkZKbbzk',
    assetPath: 'sounds/bgm_aquamarine.m4a',
    coverAsset: 'assets/music/covers/bgm_aquamarine.png',
    durationLabel: '2:12',
    mood: MusicMood.relax,
    color: _kRelaxColor,
    tags: ['快'],
    unlockType: UnlockType.coin,
    coinPrice: _kTrackPrice,
    licenseNote: _kFreeLicense,
    attributionText: _kFreeAttribution,
  ),
  MusicTrackSpec(
    id: 'bgm_bed_merry',
    title: 'bed merry',
    artistName: '茶葉のぎか',
    channelName: '茶葉のぎか',
    sourceUrl: 'https://www.youtube.com/watch?v=eiqm5oVRekA',
    assetPath: 'sounds/bgm_bed_merry.m4a',
    coverAsset: 'assets/music/covers/bgm_bed_merry.png',
    durationLabel: '2:16',
    mood: MusicMood.relax,
    color: _kRelaxColor,
    tags: ['中'],
    unlockType: UnlockType.coin,
    coinPrice: _kTrackPrice,
    licenseNote: _kFreeLicense,
    attributionText: _kFreeAttribution,
  ),
  MusicTrackSpec(
    id: 'bgm_lonely_town',
    title: 'Lonely Town',
    artistName: 'Kyatto',
    channelName: 'Kyatto',
    sourceUrl: 'https://www.youtube.com/watch?v=l18f4SmS0_k',
    assetPath: 'sounds/bgm_lonely_town.m4a',
    coverAsset: 'assets/music/covers/bgm_lonely_town.png',
    durationLabel: '2:10',
    mood: MusicMood.relax,
    color: _kRelaxColor,
    tags: ['慢'],
    unlockType: UnlockType.coin,
    coinPrice: _kTrackPrice,
    licenseNote: _kFreeLicense,
    attributionText: _kFreeAttribution,
  ),
  MusicTrackSpec(
    id: 'bgm_nothing',
    title: 'Nothing',
    artistName: 'えだまめ88',
    channelName: 'えだまめ88',
    sourceUrl: 'https://www.youtube.com/watch?v=Eip3IytYqIk',
    assetPath: 'sounds/bgm_nothing.m4a',
    coverAsset: 'assets/music/covers/bgm_nothing.png',
    durationLabel: '1:51',
    mood: MusicMood.relax,
    color: _kRelaxColor,
    tags: ['中'],
    unlockType: UnlockType.coin,
    coinPrice: _kTrackPrice,
    licenseNote: _kFreeLicense,
    attributionText: _kFreeAttribution,
  ),
  MusicTrackSpec(
    id: 'bgm_sleeping_world',
    title: 'Sleeping World',
    artistName: 'Kyatto',
    channelName: 'Kyatto',
    sourceUrl: 'https://www.youtube.com/watch?v=BqftENqrgkw',
    assetPath: 'sounds/bgm_sleeping_world.m4a',
    coverAsset: 'assets/music/covers/bgm_sleeping_world.png',
    durationLabel: '3:16',
    mood: MusicMood.relax,
    color: _kRelaxColor,
    tags: ['中'],
    unlockType: UnlockType.coin,
    coinPrice: _kTrackPrice,
    licenseNote: _kFreeLicense,
    attributionText: _kFreeAttribution,
  ),
  MusicTrackSpec(
    id: 'bgm_snowdrop',
    title: 'Snowdrop',
    artistName: 'Kyatto',
    channelName: 'Kyatto',
    sourceUrl: 'https://www.youtube.com/watch?v=7xxzDpZ4AJM',
    assetPath: 'sounds/bgm_snowdrop.m4a',
    coverAsset: 'assets/music/covers/bgm_snowdrop.png',
    durationLabel: '2:33',
    mood: MusicMood.relax,
    color: _kRelaxColor,
    tags: ['中'],
    unlockType: UnlockType.coin,
    coinPrice: _kTrackPrice,
    licenseNote: _kFreeLicense,
    attributionText: _kFreeAttribution,
  ),

  // ── 專注感 ─────────────────────────────────────────────
  MusicTrackSpec(
    id: 'bgm_fried_egg',
    title: 'Fried Egg',
    artistName: 'Kyatto',
    channelName: 'Kyatto',
    sourceUrl: 'https://www.youtube.com/watch?v=EJ-AEvikvP4',
    assetPath: 'sounds/bgm_fried_egg.m4a',
    coverAsset: 'assets/music/covers/bgm_fried_egg.png',
    durationLabel: '2:12',
    mood: MusicMood.focus,
    color: _kFocusColor,
    tags: ['慢'],
    unlockType: UnlockType.coin,
    coinPrice: _kTrackPrice,
    licenseNote: _kFreeLicense,
    attributionText: _kFreeAttribution,
  ),
  MusicTrackSpec(
    id: 'bgm_kyatto_shower',
    title: 'Kyatto - Shower',
    artistName: 'Kyatto',
    channelName: 'Kyatto',
    sourceUrl: 'https://www.youtube.com/watch?v=qAABwnWqFCI',
    assetPath: 'sounds/bgm_kyatto_shower.m4a',
    coverAsset: 'assets/music/covers/bgm_kyatto_shower.png',
    durationLabel: '2:12',
    mood: MusicMood.focus,
    color: _kFocusColor,
    tags: ['快'],
    unlockType: UnlockType.coin,
    coinPrice: _kTrackPrice,
    licenseNote: _kFreeLicense,
    attributionText: _kFreeAttribution,
  ),
  MusicTrackSpec(
    id: 'bgm_makeup_time',
    title: 'makeup time',
    artistName: '茶葉のぎか',
    channelName: '茶葉のぎか',
    sourceUrl: 'https://www.youtube.com/watch?v=sNksZDu_IZk',
    assetPath: 'sounds/bgm_makeup_time.m4a',
    coverAsset: 'assets/music/covers/bgm_makeup_time.png',
    durationLabel: '2:11',
    mood: MusicMood.focus,
    color: _kFocusColor,
    tags: ['快'],
    unlockType: UnlockType.coin,
    coinPrice: _kTrackPrice,
    licenseNote: _kFreeLicense,
    attributionText: _kFreeAttribution,
  ),
  MusicTrackSpec(
    id: 'bgm_matsurinohi',
    title: 'matsurinohi',
    artistName: '茶葉のぎか',
    channelName: '茶葉のぎか',
    sourceUrl: 'https://www.youtube.com/watch?v=e6V01KwdAVQ',
    assetPath: 'sounds/bgm_matsurinohi.m4a',
    coverAsset: 'assets/music/covers/bgm_matsurinohi.png',
    durationLabel: '2:26',
    mood: MusicMood.focus,
    color: _kFocusColor,
    tags: ['中'],
    unlockType: UnlockType.coin,
    coinPrice: _kTrackPrice,
    licenseNote: _kFreeLicense,
    attributionText: _kFreeAttribution,
  ),
  MusicTrackSpec(
    id: 'bgm_pyon_pyon_pink',
    title: 'PYON PYON PINK!',
    artistName: '茶葉のぎか',
    channelName: '茶葉のぎか',
    sourceUrl: 'https://www.youtube.com/watch?v=BF1QiZLy4sA',
    assetPath: 'sounds/bgm_pyon_pyon_pink.m4a',
    coverAsset: 'assets/music/covers/bgm_pyon_pyon_pink.png',
    durationLabel: '2:17',
    mood: MusicMood.focus,
    color: _kFocusColor,
    tags: ['中'],
    unlockType: UnlockType.coin,
    coinPrice: _kTrackPrice,
    licenseNote: _kFreeLicense,
    attributionText: _kFreeAttribution,
  ),
  MusicTrackSpec(
    id: 'bgm_roadside',
    title: 'Roadside',
    artistName: 'Kyatto',
    channelName: 'Kyatto',
    sourceUrl: 'https://www.youtube.com/watch?v=iBArD9P6qRE',
    assetPath: 'sounds/bgm_roadside.m4a',
    coverAsset: 'assets/music/covers/bgm_roadside.png',
    durationLabel: '2:20',
    mood: MusicMood.focus,
    color: _kFocusColor,
    tags: ['快'],
    unlockType: UnlockType.coin,
    coinPrice: _kTrackPrice,
    licenseNote: _kFreeLicense,
    attributionText: _kFreeAttribution,
  ),
  MusicTrackSpec(
    id: 'bgm_see_you_at_christmas',
    title: 'See you at Christmas！',
    artistName: 'えだまめ88',
    channelName: 'えだまめ88',
    sourceUrl: 'https://www.youtube.com/watch?v=Wn_Q1dgME3I',
    assetPath: 'sounds/bgm_see_you_at_christmas.m4a',
    coverAsset: 'assets/music/covers/bgm_see_you_at_christmas.png',
    durationLabel: '3:50',
    mood: MusicMood.focus,
    color: _kFocusColor,
    tags: ['快'],
    unlockType: UnlockType.coin,
    coinPrice: _kTrackPrice,
    licenseNote: _kFreeLicense,
    attributionText: _kFreeAttribution,
  ),
  MusicTrackSpec(
    id: 'bgm_soda_soda',
    title: 'Soda Soda',
    artistName: '茶葉のぎか',
    channelName: '茶葉のぎか',
    sourceUrl: 'https://www.youtube.com/watch?v=vlyuDNdYpmY',
    assetPath: 'sounds/bgm_soda_soda.m4a',
    coverAsset: 'assets/music/covers/bgm_soda_soda.png',
    durationLabel: '2:02',
    mood: MusicMood.focus,
    color: _kFocusColor,
    tags: ['快'],
    unlockType: UnlockType.coin,
    coinPrice: _kTrackPrice,
    licenseNote: _kFreeLicense,
    attributionText: _kFreeAttribution,
  ),
  MusicTrackSpec(
    id: 'bgm_swimmer',
    title: 'Swimmer',
    artistName: 'Kyatto',
    channelName: 'Kyatto',
    sourceUrl: 'https://www.youtube.com/watch?v=pK3ps9Z4MFE',
    assetPath: 'sounds/bgm_swimmer.m4a',
    coverAsset: 'assets/music/covers/bgm_swimmer.png',
    durationLabel: '1:48',
    mood: MusicMood.focus,
    color: _kFocusColor,
    tags: ['快'],
    unlockType: UnlockType.coin,
    coinPrice: _kTrackPrice,
    licenseNote: _kFreeLicense,
    attributionText: _kFreeAttribution,
  ),
];

OutfitSpec get defaultOutfit => outfitCatalog.first;
MusicTrackSpec get defaultTrack => trackCatalog.first;

bool outfitExists(String id) => outfitCatalog.any((o) => o.id == id);

bool trackExists(String id) => trackCatalog.any((t) => t.id == id);

OutfitSpec outfitById(String id) => outfitCatalog.firstWhere(
  (o) => o.id == id,
  orElse: () => outfitCatalog.first,
);

MusicTrackSpec trackById(String id) => trackCatalog.firstWhere(
  (t) => t.id == id,
  orElse: () => trackCatalog.first,
);

/// 曲目長度的顯示字：'loop' 是無縫循環的哨兵值，其餘直接是 m:ss。
String durationText(AppLocalizations l10n, String durationLabel) =>
    durationLabel == 'loop' ? l10n.bgmDurationLoop : durationLabel;

List<MusicTrackSpec> tracksOfMood(MusicMood mood) =>
    trackCatalog.where((t) => t.mood == mood).toList();

String unlockLabel(AppLocalizations l10n, UnlockType type, int coinPrice) =>
    switch (type) {
      UnlockType.free => l10n.unlockOwned,
      UnlockType.coin => l10n.unlockCoinPrice(coinPrice),
      UnlockType.subscriberCoin => l10n.unlockSubscriberCoin(coinPrice),
    };

/// 曲目標籤的顯示字。標籤本身是穩定識別字串（存在 catalog 裡、不做比對
/// 以外的用途），只在顯示時翻譯。
String bgmTagLabel(AppLocalizations l10n, String tag) => switch (tag) {
  '預設' => l10n.bgmTagDefault,
  '前導' => l10n.bgmTagIntro,
  '慢' => l10n.bgmTagSlow,
  '中' => l10n.bgmTagMedium,
  '快' => l10n.bgmTagFast,
  _ => tag,
};

/// 把一個「core 兔咪資產路徑」換成目前造型的皮膚版本。
/// 例：`assets/mascot/core/tumi_happy.png` + skinKey `spring`
///   → `assets/mascot/spring/tumi_happy.png`。
/// 找不到對應皮膚資料夾段就原樣返回（安全 fallback）。
String skinnedMascotAsset(String coreAsset, String skinKey) {
  if (skinKey == 'core') return coreAsset;
  const marker = '/mascot/core/';
  final idx = coreAsset.indexOf(marker);
  if (idx == -1) return coreAsset;
  return coreAsset.replaceFirst(marker, '/mascot/$skinKey/');
}
