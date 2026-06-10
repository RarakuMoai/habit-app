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

  /// 第一次呼叫會 configure + setActive；之後只會 setActive。
  /// BgmService / SfxService 的 init 都呼叫這個，誰先到誰負責 configure。
  static Future<void> ensureConfigured() async {
    if (_configured) {
      await activate();
      return;
    }
    try {
      final session = await AudioSession.instance;
      await session.configure(
        const AudioSessionConfiguration(
          avAudioSessionCategory: AVAudioSessionCategory.ambient,
        ),
      );
      _session = session;
      _configured = true;
      await session.setActive(true);
    } catch (e) {
      debugPrint('AppAudioSession: configure failed: $e');
    }
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
