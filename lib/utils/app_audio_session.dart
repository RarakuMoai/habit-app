// 全 app 唯一的 AVAudioSession 設定點。
//
// 為什麼要有這個檔：iOS 上 `session.configure()` 只能在啟動時設「一次」。
// 重複 configure（尤其多個 audio plugin / service 各自 configure）會讓 iOS
// 把 audio session 拆掉重建，輸出路由在重建空窗期就會「狀態在播但沒聲音」——
// 這正是冷啟動 BGM 沒聲、要手動切靜音(pause→play)才出聲的主因。
//
// 規則：
//   - configure() 只跑一次（第一個呼叫 ensureConfigured 的 service 負責）。
//   - 之後任何要確保 session active 的場合，只呼叫 setActive(true)。
//     setActive 是 idempotent，不會重設路由，重複呼叫安全。
//
// category 用 ambient：跟其他 app 共存 + 尊重實體靜音鍵（跟原神一樣的行為）。

import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';

class AppAudioSession {
  AppAudioSession._();

  static bool _configured = false;
  static AudioSession? _session;

  // 目前生效的 category。預設 ambient（與其他 app 共存、尊重實體靜音鍵）。
  // 超慢跑節拍器要在靜音模式也聽得到時，會暫時切到 playback（見 setLoudCategory）。
  static bool _loud = false;

  // 切 category 必須 reconfigure，會重設輸出路由 → 正在播的 BGM 可能瞬間沒聲。
  // BgmService.init 會把自己的「重新 engage」掛這裡，category 變更後主動救回。
  static Future<void> Function()? onCategoryChanged;

  static AudioSessionConfiguration get _config => AudioSessionConfiguration(
    avAudioSessionCategory: _loud
        ? AVAudioSessionCategory.playback
        : AVAudioSessionCategory.ambient,
    // playback 預設會打斷其他 app 的音樂；mixWithOthers 讓節拍器疊在使用者
    // 自己的播放清單之上，而不是把它停掉。
    avAudioSessionCategoryOptions: _loud
        ? AVAudioSessionCategoryOptions.mixWithOthers
        : AVAudioSessionCategoryOptions.none,
  );

  /// 第一次呼叫會 configure + setActive；之後只會 setActive。
  /// BgmService / SfxService 的 init 都呼叫這個，誰先到誰負責 configure。
  static Future<void> ensureConfigured() async {
    if (_configured) {
      await activate();
      return;
    }
    try {
      final session = await AudioSession.instance;
      await session.configure(_config);
      _session = session;
      _configured = true;
      await session.setActive(true);
    } catch (e) {
      debugPrint('AppAudioSession: configure failed: $e');
    }
  }

  /// 切換「響度 category」：true=playback（忽略靜音鍵，給節拍器）、
  /// false=ambient（尊重靜音鍵，平時狀態）。
  ///
  /// 只在真的需要變更時 reconfigure（reconfigure 會重設路由，盡量少做）。
  /// 變更後呼叫 [onCategoryChanged] 讓 BGM 重新 engage，避免路由重設後沒聲。
  static Future<void> setLoudCategory(bool loud) async {
    if (_loud == loud) {
      await activate();
      return;
    }
    _loud = loud;
    if (!_configured) {
      await ensureConfigured();
      await onCategoryChanged?.call();
      return;
    }
    try {
      final session = _session ?? await AudioSession.instance;
      _session = session;
      // 先 deactivate 再 configure：部分 iOS 版本在 session active 時 configure
      // 不會真的切換靜音鍵行為，要 deactivate→configure→activate 才生效。
      // deactivate 自成一個 try：失敗（例如還有音源在播）也不擋下面的 configure。
      try {
        await session.setActive(false);
      } catch (e) {
        debugPrint('AppAudioSession: deactivate before reconfigure failed: $e');
      }
      await session.configure(_config);
      await session.setActive(true);
      debugPrint(
        'AppAudioSession: category -> ${loud ? "playback(loud)" : "ambient"}',
      );
    } catch (e) {
      debugPrint('AppAudioSession: setLoudCategory failed: $e');
    }
    await onCategoryChanged?.call();
  }

  /// 只確保 session active，不重新 configure。
  /// 播放前 / 救援前用這個，避免重設輸出路由把聲音弄沒。
  static Future<void> activate() async {
    try {
      final session = _session ?? await AudioSession.instance;
      _session = session;
      await session.setActive(true);
    } catch (e) {
      debugPrint('AppAudioSession: setActive failed: $e');
    }
  }
}
