import 'package:flutter_test/flutter_test.dart';
import 'package:habit_app/utils/coin_service.dart';
import 'package:habit_app/utils/prefs_keys.dart';
import 'package:habit_app/utils/wardrobe_catalog.dart';
import 'package:habit_app/utils/wardrobe_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

// 測試常用的三首（皆存在於 catalog）。
const _a = 'bgm_main'; // = defaultTrack.id
const _b = 'bgm_aquamarine';
const _c = 'bgm_nothing';
const _onboarding = 'bgm_onboarding';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({
      PrefsKeys.coinBalance: 500,
      PrefsKeys.bgmOwnedTracks: [defaultTrack.id],
      PrefsKeys.bgmPlaylist: [defaultTrack.id],
      PrefsKeys.bgmSelectedTrack: defaultTrack.id,
    });
    CoinService.notifier.value = 500;
    WardrobeStore.reset();
  });

  // 用三首已擁有曲 seed 一份清單＋指定目前曲＋模式，再 load。
  Future<void> seed({
    List<String> playlist = const [_a, _b, _c],
    String? current,
    String? mode,
  }) async {
    SharedPreferences.setMockInitialValues({
      PrefsKeys.coinBalance: 500,
      PrefsKeys.bgmOwnedTracks: [_a, _b, _c],
      PrefsKeys.bgmPlaylist: playlist,
      PrefsKeys.bgmSelectedTrack: current ?? playlist.first,
      PrefsKeys.bgmMode: ?mode,
    });
    WardrobeStore.reset();
    await WardrobeStore.load();
  }

  test('purchaseTrack 只解鎖曲目，不自動加入清單', () async {
    final track = trackById(_b);

    await WardrobeStore.load();
    final result = await WardrobeStore.purchaseTrack(track.id, 'test');

    expect(result, PurchaseResult.success);
    expect(WardrobeStore.ownedTracks.value, contains(track.id));
    expect(WardrobeStore.playlist.value, [defaultTrack.id]);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList(PrefsKeys.bgmPlaylist), [defaultTrack.id]);
    expect(prefs.getString(PrefsKeys.bgmSelectedTrack), defaultTrack.id);
  });

  test('免費內建曲會自動進入已擁有曲庫，但不自動加入清單', () async {
    await WardrobeStore.load();

    expect(WardrobeStore.ownedTracks.value, contains(_onboarding));
    expect(WardrobeStore.playlist.value, [defaultTrack.id]);
  });

  test('addTrack 把已解鎖曲目加到清單尾端、不動目前曲', () async {
    await WardrobeStore.load();
    expect(
      await WardrobeStore.purchaseTrack(_b, 'test'),
      PurchaseResult.success,
    );
    await WardrobeStore.addTrack(_b);

    expect(WardrobeStore.playlist.value, [_a, _b]);
    expect(WardrobeStore.currentTrackId.value, _a); // 目前曲不變
  });

  test('setCurrentTrack 只移動指標、不重排清單', () async {
    await seed(current: _a);

    final changed = await WardrobeStore.setCurrentTrack(_c);

    expect(changed, true);
    expect(WardrobeStore.currentTrackId.value, _c);
    expect(WardrobeStore.playlist.value, [_a, _b, _c]); // 順序不動

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(PrefsKeys.bgmSelectedTrack), _c);
    expect(prefs.getStringList(PrefsKeys.bgmPlaylist), [_a, _b, _c]);
  });

  test('setCurrentTrack 設成同一首回傳 false', () async {
    await seed(current: _b);
    expect(await WardrobeStore.setCurrentTrack(_b), false);
  });

  test('reorder 同步發布新順序再持久化、指標不變', () async {
    await seed(current: _b);

    final persistence = WardrobeStore.reorder(2, 0); // 把 _c 移到最前
    // ReorderableList drop callback 結束前，畫面資料就必須是新順序；若等 prefs
    // 寫完才發布，拖曳 proxy 會先回舊位置再瞬間交換。
    expect(WardrobeStore.playlist.value, [_c, _a, _b]);
    expect(WardrobeStore.currentTrackId.value, _b); // 指標跟著 id，不受位置影響

    await persistence;
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList(PrefsKeys.bgmPlaylist), [_c, _a, _b]);
  });

  test('removeTrack 移除目前曲 → 指標前進到下一首', () async {
    await seed(current: _b);

    final changed = await WardrobeStore.removeTrack(_b);

    expect(changed, true);
    expect(WardrobeStore.playlist.value, [_a, _c]);
    expect(WardrobeStore.currentTrackId.value, _c); // _b 後面那首
  });

  test('removeTrack 移除最後一首（目前曲）→ wrap 回第一首', () async {
    await seed(current: _c);

    final changed = await WardrobeStore.removeTrack(_c);

    expect(changed, true);
    expect(WardrobeStore.playlist.value, [_a, _b]);
    expect(WardrobeStore.currentTrackId.value, _a); // wrap
  });

  test('removeTrack 移除非目前曲 → 指標不變、回傳 false', () async {
    await seed(current: _a);

    final changed = await WardrobeStore.removeTrack(_b);

    expect(changed, false);
    expect(WardrobeStore.playlist.value, [_a, _c]);
    expect(WardrobeStore.currentTrackId.value, _a);
  });

  test('removeTrack 最後一首不可移除', () async {
    await seed(playlist: [_a], current: _a);
    expect(await WardrobeStore.removeTrack(_a), false);
    expect(WardrobeStore.playlist.value, [_a]);
  });

  test('nextTrackId：loopOne 回同一首', () async {
    await seed(current: _b, mode: 'loopOne');
    expect(WardrobeStore.nextTrackId(), _b);
  });

  test('nextTrackId：loopAll 依序前進並 wrap', () async {
    await seed(current: _b, mode: 'loopAll');
    expect(WardrobeStore.nextTrackId(), _c);

    await seed(current: _c, mode: 'loopAll');
    expect(WardrobeStore.nextTrackId(), _a); // wrap 回第一首
  });

  test('nextTrackId：shuffle 不會回到目前這首', () async {
    await seed(current: _a, mode: 'shuffle');
    for (var i = 0; i < 30; i++) {
      expect(WardrobeStore.nextTrackId(), isNot(_a));
    }
  });

  test('advanceToNext 更新指標並回傳新曲 asset', () async {
    await seed(current: _b, mode: 'loopAll');
    final asset = await WardrobeStore.advanceToNext();
    expect(WardrobeStore.currentTrackId.value, _c);
    expect(asset, trackById(_c).assetPath);
  });

  test('shouldAdvanceOnComplete：多軌列表/隨機才為 true', () async {
    await seed(playlist: [_a], mode: 'loopAll'); // 單軌
    expect(WardrobeStore.shouldAdvanceOnComplete, false);

    await seed(mode: 'loopAll'); // 多軌列表循環
    expect(WardrobeStore.shouldAdvanceOnComplete, true);

    await seed(mode: 'loopOne'); // 多軌但單曲循環
    expect(WardrobeStore.shouldAdvanceOnComplete, false);

    await seed(mode: 'shuffle');
    expect(WardrobeStore.shouldAdvanceOnComplete, true);
  });

  test('setPlayMode 持久化', () async {
    await seed();
    await WardrobeStore.setPlayMode(PlayMode.shuffle);
    expect(WardrobeStore.playMode.value, PlayMode.shuffle);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(PrefsKeys.bgmMode), 'shuffle');
  });

  test('載入遷移：bgm_mode 舊值映射 + 無值預設 loopAll', () async {
    await seed(mode: 'single');
    expect(WardrobeStore.playMode.value, PlayMode.loopOne);

    await seed(mode: 'playlist');
    expect(WardrobeStore.playMode.value, PlayMode.loopAll);

    await seed(); // 無 bgm_mode
    expect(WardrobeStore.playMode.value, PlayMode.loopAll);
  });

  test('載入：目前曲指標不在清單內 → clamp 回第一首', () async {
    await seed(playlist: [_a, _b], current: _c); // _c 不在清單
    expect(WardrobeStore.currentTrackId.value, _a);
  });
}
