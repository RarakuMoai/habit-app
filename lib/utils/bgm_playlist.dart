// 播放清單 ↔ BGM 的唯一協調點。
//
// 兩件事：
//   1. 「目前曲自然播完 → 換下一首」：把 BgmService 的 onTrackCompleted 接到
//      WardrobeStore.advanceToNext()，再用既有 play() 切到下一首（復用全部冷啟動救援）。
//   2. 隨「播放模式 / 清單長度」同步 BgmService 的 loop 行為：多軌列表循環 / 隨機
//      → advance（LoopMode.off）；單曲循環或只有一首 → 單曲 gapless（LoopMode.one）。
//
// 不負責「使用者手動選播 / 試聽」的即時切歌——那由衣櫃頁直接呼叫 BgmService.play()，
// 避免兩邊同時播放。這裡只處理「背景自動輪播」與「loop 行為同步」。

import 'dart:async';

import 'bgm_service.dart';
import 'wardrobe_store.dart';

class BgmPlaylist {
  BgmPlaylist._();

  static bool _wired = false;

  /// 接線（冪等）。需在 WardrobeStore.load() 與 BgmService.init() 之後、
  /// 啟動首播之前呼叫，讓多軌使用者的冷啟動首曲就帶正確 loop 行為。
  static void init() {
    if (_wired) return;
    _wired = true;
    BgmService.instance.onTrackCompleted = _onTrackCompleted;
    _syncAdvanceMode();
    WardrobeStore.playMode.addListener(_syncAdvanceMode);
    WardrobeStore.playlist.addListener(_syncAdvanceMode);
  }

  // 只調 BgmService 的 loop 行為，不觸發重播（重播交給頁面/啟動流程）。
  static void _syncAdvanceMode() {
    unawaited(
      BgmService.instance.setAdvanceMode(WardrobeStore.shouldAdvanceOnComplete),
    );
  }

  static void _onTrackCompleted() => unawaited(_advance());

  static Future<void> _advance() async {
    final asset = await WardrobeStore.advanceToNext();
    await BgmService.instance.setAdvanceMode(
      WardrobeStore.shouldAdvanceOnComplete,
    );
    await BgmService.instance.play(asset);
  }
}
