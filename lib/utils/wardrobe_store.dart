// 衣櫃 / 音樂盒的狀態單一真相來源（SSOT）。
//
// 擁有的造型/曲目、目前選用造型、播放清單都集中在這裡，並用 ValueNotifier
// 對外廣播：衣櫃頁、首頁兔咪（PersonaScene 套皮膚）、app 啟動決定播哪首
// BGM（main.dart）都讀這裡，避免各自讀 prefs 造成不同步。
//
// 純資料層：只負責「擁有/選用/清單/購買扣款」與持久化，不直接碰 BgmService。
// 播放副作用（切歌、試聽）由呼叫端（衣櫃頁）負責，保持低耦合。

import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'coin_service.dart';
import 'prefs_keys.dart';
import 'usage_stats.dart';
import 'wardrobe_catalog.dart';

/// 購買結果。
enum PurchaseResult { success, alreadyOwned, needCoins, needSubscription }

class WardrobeStore {
  WardrobeStore._();

  static Set<String> get _freeTrackIds => trackCatalog
      .where((track) => track.unlockType == UnlockType.free)
      .map((track) => track.id)
      .toSet();

  /// 目前選用的造型 id。
  static final ValueNotifier<String> selectedOutfit = ValueNotifier<String>(
    defaultOutfit.id,
  );

  /// 已擁有的造型 id 集合。
  static final ValueNotifier<Set<String>> ownedOutfits =
      ValueNotifier<Set<String>>({defaultOutfit.id});

  /// 播放清單（有序，使用者可拖曳排序）。順序穩定，不再用「第一首=目前」語意。
  static final ValueNotifier<List<String>> playlist =
      ValueNotifier<List<String>>([defaultTrack.id]);

  /// 目前播放曲的 id（指向 [playlist] 裡的某一首；與清單順序解耦）。
  static final ValueNotifier<String> currentTrackId = ValueNotifier<String>(
    defaultTrack.id,
  );

  /// 播放模式（單曲循環 / 列表循環 / 隨機）。
  static final ValueNotifier<PlayMode> playMode = ValueNotifier<PlayMode>(
    PlayMode.loopAll,
  );

  /// 已擁有的曲目 id 集合。
  static final ValueNotifier<Set<String>> ownedTracks =
      ValueNotifier<Set<String>>(_freeTrackIds);

  static bool _subscriber = false;
  static bool _loaded = false;
  static bool get loaded => _loaded;

  /// 是否為訂閱者（目前無金流，預設 false；接金流後讀真正狀態）。
  static bool get isSubscriber => _subscriber;

  /// 目前播放曲（依 [currentTrackId] 指標；指標無效時 fallback 到清單第一首）。
  static MusicTrackSpec get currentTrack {
    final list = playlist.value;
    final id = list.contains(currentTrackId.value)
        ? currentTrackId.value
        : (list.isEmpty ? defaultTrack.id : list.first);
    return trackById(id);
  }

  /// 目前播放曲的資產路徑（給啟動流程決定播哪首）。
  static String get currentTrackAsset => currentTrack.assetPath;

  /// 是否要在「自然播完」時換下一首：多軌的列表循環 / 隨機才需要；
  /// 單曲循環或只有一首時維持 gapless 單曲循環（不換歌）。
  static bool get shouldAdvanceOnComplete =>
      playMode.value != PlayMode.loopOne && playlist.value.length > 1;

  /// 目前選用造型。
  static OutfitSpec get currentOutfit => outfitById(selectedOutfit.value);

  /// 載入持久化狀態（冪等，可重複呼叫）。
  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final owned =
        (prefs.getStringList(PrefsKeys.bgmOwnedTracks) ?? const []).toSet()
          ..addAll(_freeTrackIds);
    final ownedFits =
        (prefs.getStringList(PrefsKeys.wardrobeOwnedOutfits) ?? const [])
            .toSet()
          ..add(defaultOutfit.id);
    final list = _safePlaylist(
      prefs.getStringList(PrefsKeys.bgmPlaylist),
      owned,
    );

    ownedTracks.value = owned;
    ownedOutfits.value = ownedFits;
    selectedOutfit.value = _safeOutfitId(
      prefs.getString(PrefsKeys.wardrobeSelectedOutfit),
      ownedFits,
    );
    playlist.value = list;
    // 目前曲指標：取舊的 selectedTrack，clamp 進清單（否則退回第一首）。
    final rawCurrent = prefs.getString(PrefsKeys.bgmSelectedTrack);
    currentTrackId.value = (rawCurrent != null && list.contains(rawCurrent))
        ? rawCurrent
        : list.first;
    playMode.value = playModeFromKey(prefs.getString(PrefsKeys.bgmMode));
    _subscriber = prefs.getBool(PrefsKeys.subscriptionActive) ?? false;
    _loaded = true;
  }

  /// 給啟動流程：確保已載入並回傳目前曲資產。
  static Future<String> loadCurrentTrackAsset() async {
    if (!_loaded) await load();
    return currentTrackAsset;
  }

  /// 資料全部刪除時呼叫：把記憶體狀態歸零回預設，
  /// 避免清空 prefs 後仍殘留已不擁有的造型/曲目。
  static void reset() {
    ownedTracks.value = _freeTrackIds;
    ownedOutfits.value = {defaultOutfit.id};
    selectedOutfit.value = defaultOutfit.id;
    playlist.value = [defaultTrack.id];
    currentTrackId.value = defaultTrack.id;
    playMode.value = PlayMode.loopAll;
    _subscriber = false;
  }

  // ── 造型 ───────────────────────────────────────────────
  static Future<void> setOutfit(String id) async {
    if (!ownedOutfits.value.contains(id) || !outfitExists(id)) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(PrefsKeys.wardrobeSelectedOutfit, id);
    selectedOutfit.value = id;
    // 匿名統計：套用造型（衣櫃是否帶動回訪的核心指標之一）。
    unawaited(UsageStats.bump(UsageEvents.wardrobeApply));
  }

  // ── 播放清單 ───────────────────────────────────────────
  // 清單順序與「目前曲指標」分離持久化：清單寫 bgmPlaylist，指標寫 bgmSelectedTrack。
  static Future<void> _persistPlaylist(List<String> next) async {
    final safe = next.isEmpty ? [defaultTrack.id] : next;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(PrefsKeys.bgmPlaylist, safe);
    playlist.value = List<String>.from(safe);
  }

  static Future<void> _persistCurrent(String id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(PrefsKeys.bgmSelectedTrack, id);
    currentTrackId.value = id;
  }

  /// 加入清單尾端（不改動目前曲）。
  static Future<void> addTrack(String id) async {
    if (!ownedTracks.value.contains(id) || playlist.value.contains(id)) return;
    await _persistPlaylist([...playlist.value, id]);
  }

  /// 拖曳重排清單（plain move：移除 [oldIndex] 後插入 [newIndex]）。
  /// 呼叫端負責套用 ReorderableListView 的 newIndex 調整。目前曲指標不受影響。
  static Future<void> reorder(int oldIndex, int newIndex) async {
    final list = [...playlist.value];
    if (oldIndex < 0 || oldIndex >= list.length) return;
    final clamped = newIndex.clamp(0, list.length - 1);
    if (clamped == oldIndex) return;
    final item = list.removeAt(oldIndex);
    list.insert(clamped, item);
    await _persistPlaylist(list);
  }

  /// 從清單移除；回傳目前曲是否改變。最後一首不可移除。
  /// 若移除的正是目前曲，指標接續到「原位置的下一首」（wrap 回第一首）。
  static Future<bool> removeTrack(String id) async {
    final list = playlist.value;
    if (!list.contains(id) || list.length == 1) return false;
    final removingCurrent = currentTrackId.value == id;
    final idx = list.indexOf(id);
    final remaining = list.where((t) => t != id).toList();
    await _persistPlaylist(remaining);
    if (removingCurrent) {
      await _persistCurrent(remaining[idx % remaining.length]);
      return true;
    }
    return false;
  }

  /// 設為目前播放（只移動指標，不重排清單）；回傳目前曲是否改變。
  /// 若是已擁有但還不在清單裡的曲目（從曲庫詳情設目前），先加入清單尾端。
  static Future<bool> setCurrentTrack(String id) async {
    if (!ownedTracks.value.contains(id)) return false;
    if (!playlist.value.contains(id)) {
      await _persistPlaylist([...playlist.value, id]);
    }
    if (currentTrackId.value == id) return false;
    await _persistCurrent(id);
    return true;
  }

  /// 切換播放模式並持久化。
  static Future<void> setPlayMode(PlayMode mode) async {
    if (playMode.value == mode) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(PrefsKeys.bgmMode, playModeKey(mode));
    playMode.value = mode;
  }

  /// 依目前模式算「下一首」的 id（純函式，不改狀態）。
  static String nextTrackId() {
    final list = playlist.value;
    if (list.isEmpty) return defaultTrack.id;
    final cur = currentTrackId.value;
    switch (playMode.value) {
      case PlayMode.loopOne:
        return cur;
      case PlayMode.loopAll:
        final i = list.indexOf(cur);
        return i == -1 ? list.first : list[(i + 1) % list.length];
      case PlayMode.shuffle:
        if (list.length <= 1) return list.first;
        final others = list.where((t) => t != cur).toList();
        return others[Random().nextInt(others.length)];
    }
  }

  /// 前進到下一首（更新指標並持久化），回傳新曲的資產路徑。
  static Future<String> advanceToNext() async {
    final next = nextTrackId();
    if (next != currentTrackId.value) {
      await _persistCurrent(next);
    }
    return trackById(next).assetPath;
  }

  // ── 購買 ───────────────────────────────────────────────
  static Future<PurchaseResult> purchaseOutfit(String id) async {
    if (ownedOutfits.value.contains(id)) return PurchaseResult.alreadyOwned;
    final spec = outfitById(id);
    final paid = await _charge(
      spec.unlockType,
      spec.coinPrice,
      '購買造型：${spec.name}',
    );
    if (paid != PurchaseResult.success) return paid;
    final prefs = await SharedPreferences.getInstance();
    final next = {...ownedOutfits.value, id};
    await prefs.setStringList(PrefsKeys.wardrobeOwnedOutfits, next.toList());
    ownedOutfits.value = next;
    unawaited(UsageStats.bump(UsageEvents.wardrobeBuy));
    return PurchaseResult.success;
  }

  static Future<PurchaseResult> purchaseTrack(String id) async {
    if (ownedTracks.value.contains(id)) return PurchaseResult.alreadyOwned;
    final spec = trackById(id);
    final paid = await _charge(
      spec.unlockType,
      spec.coinPrice,
      '購買音樂：${spec.title}',
    );
    if (paid != PurchaseResult.success) return paid;
    final prefs = await SharedPreferences.getInstance();
    final next = {...ownedTracks.value, id};
    await prefs.setStringList(PrefsKeys.bgmOwnedTracks, next.toList());
    ownedTracks.value = next;
    unawaited(UsageStats.bump(UsageEvents.wardrobeBuy));
    return PurchaseResult.success;
  }

  static Future<PurchaseResult> _charge(
    UnlockType type,
    int price,
    String note,
  ) async {
    if (type == UnlockType.free) return PurchaseResult.success;
    if (type == UnlockType.subscriberCoin && !isSubscriber) {
      return PurchaseResult.needSubscription;
    }
    final ok = await CoinService.spend(price, note: note);
    return ok ? PurchaseResult.success : PurchaseResult.needCoins;
  }

  // ── 安全 fallback ──────────────────────────────────────
  static String _safeOutfitId(String? id, Set<String> owned) =>
      (id != null && owned.contains(id) && outfitExists(id))
      ? id
      : defaultOutfit.id;

  static List<String> _safePlaylist(List<String>? ids, Set<String> owned) {
    final safe = (ids ?? const <String>[])
        .where((id) => owned.contains(id) && trackExists(id))
        .toList();
    return safe.isEmpty ? [defaultTrack.id] : safe;
  }
}
