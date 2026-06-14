import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import 'app_audio_session.dart';

enum MetronomeTone {
  wood('wood', '木魚', 'assets/sounds/metronome_wood.wav'),
  kick('kick', '溫和鼓聲', 'assets/sounds/metronome_kick.wav'),
  lowWood('low_wood', '低木', 'assets/sounds/metronome_lowwood.wav'),
  bell('bell', '柔鈴', 'assets/sounds/metronome_bell.wav'),
  clap('clap', '拍手', 'assets/sounds/metronome_clap.wav');

  const MetronomeTone(this.id, this.label, this.assetPath);
  final String id;
  final String label;
  final String assetPath;

  static MetronomeTone fromId(String? id) => MetronomeTone.values.firstWhere(
    (tone) => tone.id == id,
    orElse: () => MetronomeTone.kick,
  );
}

class MetronomeService {
  MetronomeService._();
  static final MetronomeService instance = MetronomeService._();

  final Map<MetronomeTone, List<AudioPlayer>> _players = {};
  final Map<MetronomeTone, int> _cursors = {};

  Future<void> init({MetronomeTone tone = MetronomeTone.kick}) async {
    if (_players.containsKey(tone)) return;
    await AppAudioSession.ensureConfigured();
    final players = <AudioPlayer>[];
    for (var i = 0; i < 4; i++) {
      final player = AudioPlayer();
      await player.setAudioSource(AudioSource.asset(tone.assetPath));
      await player.setVolume(0.75);
      players.add(player);
    }
    _players[tone] = players;
    _cursors[tone] = 0;
  }

  void play({required double volume, MetronomeTone tone = MetronomeTone.kick}) {
    if (volume <= 0) return;
    unawaited(_play(volume.clamp(0.0, 1.0), tone));
  }

  Future<void> _play(double volume, MetronomeTone tone) async {
    try {
      await init(tone: tone);
      final players = _players[tone];
      if (players == null || players.isEmpty) return;
      final cursor = _cursors[tone] ?? 0;
      final player = players[cursor];
      _cursors[tone] = (cursor + 1) % players.length;
      await AppAudioSession.activate();
      await player.seek(Duration.zero);
      await player.setVolume(volume);
      unawaited(player.play());
    } catch (e) {
      debugPrint('Metronome play failed: $e');
    }
  }

  Future<void> dispose() async {
    for (final players in _players.values) {
      for (final player in players) {
        await player.dispose();
      }
    }
    _players.clear();
    _cursors.clear();
  }
}
