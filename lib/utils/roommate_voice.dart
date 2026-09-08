import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import 'app_audio_session.dart';
import 'audio_settings_service.dart';
import 'sfx_service.dart';

abstract interface class RoommateVoiceOutput {
  Future<void> play(SfxCue cue);
  void stop();
  void dispose();
}

/// 對話擁有自己的播放器；停止對話不會切掉計時提示或其他角色回饋。
/// 每次 await 後核對世代，首次載入期間退出也不會在背景突然補播 MI。
class RoommateVoice implements RoommateVoiceOutput {
  AudioPlayer? _player;
  Future<void> _tail = Future<void>.value();
  int _epoch = 0;
  bool _disposed = false;

  RoommateVoice() {
    AudioSettingsService.sfxMuted.addListener(_onMute);
  }

  void _onMute() {
    if (AudioSettingsService.sfxMuted.value) stop();
  }

  @override
  Future<void> play(SfxCue cue) {
    final epoch = ++_epoch;
    bool current() =>
        !_disposed && epoch == _epoch && !AudioSettingsService.sfxMuted.value;
    final operation = _tail.then((_) async {
      if (!current()) return;
      await AudioSettingsService.instance.init();
      if (!current()) return;
      await AppAudioSession.ensureConfigured();
      if (!current()) return;
      final player = _player ??= AudioPlayer();
      await player.stop();
      if (!current()) return;
      await player.setAudioSource(AudioSource.asset(cue.assetPath));
      if (!current()) return;
      await player.setVolume(cue.volume);
      if (!current()) return;
      await AppAudioSession.activate();
      if (!current()) return;
      unawaited(
        player.play().catchError((Object e) {
          debugPrint('Roommate voice playback failed: $e');
        }),
      );
    });
    _tail = operation.catchError((Object e) {
      debugPrint('Roommate voice preparation failed: $e');
    });
    return _tail;
  }

  @override
  void stop() {
    _epoch++;
    final player = _player;
    if (player != null) {
      unawaited(
        player.stop().catchError((Object e) {
          debugPrint('Roommate voice stop failed: $e');
        }),
      );
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _epoch++;
    AudioSettingsService.sfxMuted.removeListener(_onMute);
    final player = _player;
    _player = null;
    if (player != null) {
      unawaited(
        player.dispose().catchError((Object e) {
          debugPrint('Roommate voice dispose failed: $e');
        }),
      );
    }
  }
}
