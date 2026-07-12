import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import 'app_audio_session.dart';
import 'audio_settings_service.dart';

enum SfxCue {
  tap('assets/sounds/sfx_tap.wav', 0.88),
  success('assets/sounds/sfx_success.wav', 0.95),
  complete('assets/sounds/sfx_complete.wav', 1.0),
  cancel('assets/sounds/sfx_cancel.wav', 0.9),
  // 衣櫃購買／回憶揭曉：溫暖木質起音＋短促星光尾音。
  unlock('assets/sounds/sfx_unlock.wav', 0.85),
  // 每日足跡幣：先用柔軟吸入聲，命中時再疊一個短落袋聲。
  footprintCoinAbsorb('assets/sounds/sfx_footprint_coin_absorb.wav', 0.72),
  footprintCoinLandSoft('assets/sounds/sfx_footprint_coin_land_1.wav', 0.68),
  // 保留第二個 ElevenLabs 候選，成品實機聽感不合時可直接切換。
  footprintCoinLandAlt('assets/sounds/sfx_footprint_coin_land_2.wav', 0.68),
  // 兔咪語音（2026-07 新錄音組，取代舊 tumi_mi_*）。
  // 各檔原始響度不齊（RMS -20.8 ~ -28.3 dBFS），用音量係數拉齊到
  // 「輕聲陪伴」水準；歡呼是大事件慶祝，刻意比日常亮一點。
  tumiCheer('assets/sounds/tumi_voice_cheer.wav', 0.95),
  tumiConfirm('assets/sounds/tumi_voice_confirm.wav', 0.45),
  tumiHappy('assets/sounds/tumi_voice_happy.wav', 0.50),
  tumiQuestion('assets/sounds/tumi_voice_question.wav', 0.58),
  tumiSad('assets/sounds/tumi_voice_sad.wav', 0.85),
  // 桌遊計時器專屬（ElevenLabs 生成、剪裁後 peak 對齊上面同類音效）
  gamePass('assets/sounds/sfx_game_pass.wav', 0.9), // 棋鐘喀噠：換人
  gameWarn('assets/sounds/sfx_game_warn.wav', 0.85), // 木質 tick：倒數警示
  gameFlag('assets/sounds/sfx_game_flag.wav', 1.0), // 沉鑼：超時/旗倒
  gameDice('assets/sounds/sfx_game_dice.wav', 0.9); // 骰子喀啦：擲骰/碰撞

  const SfxCue(this.assetPath, this.volume);
  final String assetPath;
  final double volume;
}

class SfxService {
  SfxService._();
  static final SfxService instance = SfxService._();

  final Map<SfxCue, AudioPlayer> _players = {};
  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;
    await AudioSettingsService.instance.init();
    await AppAudioSession.ensureConfigured();
    for (final cue in SfxCue.values) {
      final player = AudioPlayer();
      await player.setAudioSource(AudioSource.asset(cue.assetPath));
      await player.setVolume(cue.volume);
      _players[cue] = player;
    }
    _initialized = true;
  }

  /// [volumeScale] 疊在 cue 預設音量上（0–1），碰撞聲隨力道縮放用。
  Future<void> play(SfxCue cue, {double volumeScale = 1}) async {
    if (AudioSettingsService.sfxMuted.value) return;
    try {
      if (!_initialized) await init();
      final player = _players[cue];
      if (player == null) return;
      await AppAudioSession.activate();
      await player.stop();
      await player.seek(Duration.zero);
      await player.setVolume(cue.volume * volumeScale.clamp(0.0, 1.0));
      await player.play();
    } catch (e) {
      debugPrint('SFX play failed: $e');
    }
  }

  Future<void> dispose() async {
    for (final player in _players.values) {
      await player.dispose();
    }
    _players.clear();
    _initialized = false;
  }
}
