import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import 'audio_settings_service.dart';

enum SfxCue {
  tap('assets/sounds/sfx_tap.wav', 0.46),
  success('assets/sounds/sfx_success.wav', 0.58),
  complete('assets/sounds/sfx_complete.wav', 0.64),
  cancel('assets/sounds/sfx_cancel.wav', 0.46);

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
    await _activateSession();
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
      await _activateSession();
      await player.stop();
      await player.seek(Duration.zero);
      await player.setVolume(cue.volume);
      await player.play();
    } catch (e) {
      debugPrint('SFX play failed: $e');
    }
  }

  Future<void> _activateSession() async {
    try {
      final session = await AudioSession.instance;
      await session.configure(
        const AudioSessionConfiguration(
          avAudioSessionCategory: AVAudioSessionCategory.ambient,
        ),
      );
      await session.setActive(true);
    } catch (e) {
      debugPrint('SFX: audio session activate failed: $e');
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
