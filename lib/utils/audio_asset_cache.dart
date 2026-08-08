import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'prefs_keys.dart';

/// 讓 just_audio 抽出的本機音訊快取和 App bundle 保持同步。
///
/// just_audio 以 asset 路徑當快取鍵；若內容換了但檔名沒變，App 更新後仍可能
/// 播到舊檔。每次原地替換任何音訊資產時，遞增 [currentVersion]，新版第一次
/// 冷啟動便會清一次音訊快取。成功後才記錄版本，失敗時下次啟動會再重試。
class AudioAssetCache {
  static const int currentVersion = 8; // 2026-08-08 換掉 sfx_unlock.wav

  static Future<bool> ensureCurrent(
    SharedPreferences prefs, {
    Future<void> Function()? clearCache,
  }) async {
    final storedVersion = prefs.getInt(PrefsKeys.audioAssetCacheVersion) ?? 0;
    if (storedVersion >= currentVersion) return false;

    await (clearCache ?? AudioPlayer.clearAssetCache)();
    await prefs.setInt(PrefsKeys.audioAssetCacheVersion, currentVersion);
    return true;
  }

  const AudioAssetCache._();
}
