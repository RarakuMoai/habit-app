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
  tumiSleepy('assets/sounds/tumi_mi_sleepy.wav', 0.44);

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

  Future<void> play(SfxCue cue) async {
    if (AudioSettingsService.sfxMuted.value) return;
    try {
      if (!_initialized) await init();
      final player = _players[cue];
      if (player == null) return;
      await AppAudioSession.activate();
      await player.stop();
      await player.seek(Duration.zero);
      await player.setVolume(cue.volume);
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
