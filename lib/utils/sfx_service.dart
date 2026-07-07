import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import 'app_audio_session.dart';
import 'audio_settings_service.dart';

enum SfxCue {
  tap('assets/sounds/sfx_tap.wav', 0.88),
  success('assets/sounds/sfx_success.wav', 0.95),
  complete('assets/sounds/sfx_complete.wav', 1.0),
  cancel('assets/sounds/sfx_cancel.wav', 0.9),
  tumiNeutral('assets/sounds/tumi_mi_neutral.wav', 0.52),
  tumiQuestion('assets/sounds/tumi_mi_question.wav', 0.54),
  tumiHappy('assets/sounds/tumi_mi_happy.wav', 0.56),
  tumiSad('assets/sounds/tumi_mi_sad.wav', 0.50),
  tumiSleepy('assets/sounds/tumi_mi_sleepy.wav', 0.44),
  // 桌遊計時器專屬（ElevenLabs 生成、剪裁後 peak 對齊上面同類音效）
  gamePass('assets/sounds/sfx_game_pass.wav', 0.9), // 棋鐘喀噠：換人/擲骰
  gameWarn('assets/sounds/sfx_game_warn.wav', 0.85), // 木質 tick：倒數警示
  gameFlag('assets/sounds/sfx_game_flag.wav', 1.0); // 沉鑼：超時/旗倒

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
