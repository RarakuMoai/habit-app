// 衣櫃 / 音樂盒的狀態單一真相來源（SSOT）。
//
// 擁有的造型/曲目、目前選用造型、播放清單都集中在這裡，並用 ValueNotifier
// 對外廣播：衣櫃頁、首頁兔咪（PersonaScene 套皮膚）、app 啟動決定播哪首
// BGM（main.dart）都讀這裡，避免各自讀 prefs 造成不同步。
//
// 純資料層：只負責「擁有/選用/清單/購買扣款」與持久化，不直接碰 BgmService。
// 播放副作用（切歌、試聽）由呼叫端（衣櫃頁）負責，保持低耦合。

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'coin_service.dart';
import 'prefs_keys.dart';
import 'wardrobe_catalog.dart';

/// 購買結果。
enum PurchaseResult { success, alreadyOwned, needCoins, needSubscription }

class WardrobeStore {
  WardrobeStore._();

  /// 目前選用的造型 id。
  static final ValueNotifier<String> selectedOutfit = ValueNotifier<String>(
    defaultOutfit.id,
  );

  /// 已擁有的造型 id 集合。
  static final ValueNotifier<Set<String>> ownedOutfits =
      ValueNotifier<Set<String>>({defaultOutfit.id});

  /// 播放清單（有序）；第一首為「目前播放」。
  static final ValueNotifier<List<String>> playlist =
      ValueNotifier<List<String>>([defaultTrack.id]);

  /// 已擁有的曲目 id 集合。
  static final ValueNotifier<Set<String>> ownedTracks =
      ValueNotifier<Set<String>>({defaultTrack.id});

  static bool _subscriber = false;
  static bool _loaded = false;
  static bool get loaded => _loaded;

  /// 是否為訂閱者（目前無金流，預設 false；接金流後讀真正狀態）。
  static bool get isSubscriber => _subscriber;

  /// 目前播放曲（清單第一首）。
  static MusicTrackSpec get currentTrack => trackById(
    playlist.value.isEmpty ? defaultTrack.id : playlist.value.first,
  );

  /// 目前播放曲的資產路徑（給啟動流程決定播哪首）。
  static String get currentTrackAsset => currentTrack.assetPath;

  /// 目前選用造型。
  static OutfitSpec get currentOutfit => outfitById(selectedOutfit.value);

  /// 載入持久化狀態（冪等，可重複呼叫）。
  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final owned = (prefs.getStringList(PrefsKeys.bgmOwnedTracks) ?? const [])
        .toSet()
      ..add(defaultTrack.id);
    final ownedFits =
        (prefs.getStringList(PrefsKeys.wardrobeOwnedOutfits) ?? const [])
            .toSet()
          ..add(defaultOutfit.id);
    final fallbackTrack = _safeTrackId(
      prefs.getString(PrefsKeys.bgmSelectedTrack),
      owned,
    );

    ownedTracks.value = owned;
    ownedOutfits.value = ownedFits;
    selectedOutfit.value = _safeOutfitId(
      prefs.getString(PrefsKeys.wardrobeSelectedOutfit),
      ownedFits,
    );
    playlist.value = _safePlaylist(
      prefs.getStringList(PrefsKeys.bgmPlaylist),
      owned,
      fallbackTrack,
    );
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
    ownedTracks.value = {defaultTrack.id};
    ownedOutfits.value = {defaultOutfit.id};
    selectedOutfit.value = defaultOutfit.id;
    playlist.value = [defaultTrack.id];
    _subscriber = false;
  }

  // ── 造型 ───────────────────────────────────────────────
  static Future<void> setOutfit(String id) async {
    if (!ownedOutfits.value.contains(id) || !outfitExists(id)) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(PrefsKeys.wardrobeSelectedOutfit, id);
    selectedOutfit.value = id;
  }

  // ── 播放清單 ───────────────────────────────────────────
  // 寫入清單並持久化；回傳「目前曲（第一首）是否改變」，
  // 呼叫端據此決定要不要實際切換 BGM。
  static Future<bool> _writePlaylist(List<String> next) async {
    final safe = next.isEmpty ? [defaultTrack.id] : next;
    final prevCurrent = currentTrack.id;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(PrefsKeys.bgmPlaylist, safe);
    await prefs.setString(PrefsKeys.bgmSelectedTrack, safe.first);
    playlist.value = List<String>.from(safe);
    return prevCurrent != safe.first;
  }

  static Future<void> addTrack(String id) async {
    if (!ownedTracks.value.contains(id) || playlist.value.contains(id)) return;
    await _writePlaylist([...playlist.value, id]);
  }

  /// 從清單移除；回傳目前曲是否改變。最後一首不可移除。
  static Future<bool> removeTrack(String id) async {
    if (!playlist.value.contains(id) || playlist.value.length == 1) {
      return false;
    }
    return _writePlaylist(playlist.value.where((t) => t != id).toList());
  }

  /// 設為目前播放（移到清單最前）；回傳目前曲是否改變。
  static Future<bool> setCurrentTrack(String id) async {
    if (!ownedTracks.value.contains(id)) return false;
    if (playlist.value.isNotEmpty && playlist.value.first == id) return false;
    return _writePlaylist([id, ...playlist.value.where((t) => t != id)]);
  }

  // ── 購買 ───────────────────────────────────────────────
  static Future<PurchaseResult> purchaseOutfit(String id) async {
    if (ownedOutfits.value.contains(id)) return PurchaseResult.alreadyOwned;
    final spec = outfitById(id);
    final paid = await _charge(spec.unlockType, spec.coinPrice, '購買造型：${spec.name}');
    if (paid != PurchaseResult.success) return paid;
    final prefs = await SharedPreferences.getInstance();
    final next = {...ownedOutfits.value, id};
    await prefs.setStringList(
      PrefsKeys.wardrobeOwnedOutfits,
      next.toList(),
    );
    ownedOutfits.value = next;
    return PurchaseResult.success;
  }

  static Future<PurchaseResult> purchaseTrack(String id) async {
    if (ownedTracks.value.contains(id)) return PurchaseResult.alreadyOwned;
    final spec = trackById(id);
    final paid = await _charge(spec.unlockType, spec.coinPrice, '購買音樂：${spec.title}');
    if (paid != PurchaseResult.success) return paid;
    final prefs = await SharedPreferences.getInstance();
    final next = {...ownedTracks.value, id};
    await prefs.setStringList(PrefsKeys.bgmOwnedTracks, next.toList());
    ownedTracks.value = next;
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

  static String _safeTrackId(String? id, Set<String> owned) =>
      (id != null && owned.contains(id) && trackExists(id))
      ? id
      : defaultTrack.id;

  static List<String> _safePlaylist(
    List<String>? ids,
    Set<String> owned,
    String fallback,
  ) {
    final safe = (ids ?? const <String>[])
        .where((id) => owned.contains(id) && trackExists(id))
        .toList();
    return safe.isEmpty ? [fallback] : safe;
  }
}
