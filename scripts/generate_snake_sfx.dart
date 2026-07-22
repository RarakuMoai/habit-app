// 產生「菜園小蛇」專用的短音效。
//
// 音色刻意使用柔和的正弦泛音與少量噪聲，不挪用棋鐘、骰子或一般 UI 聲。
// 執行：dart run scripts/generate_snake_sfx.dart

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

const _sampleRate = 48000;
const _twoPi = math.pi * 2;

final class _Track {
  _Track(double seconds)
    : samples = List<double>.filled((seconds * _sampleRate).round(), 0);

  final List<double> samples;

  void tone({
    required double start,
    required double duration,
    required double fromHz,
    double? toHz,
    double gain = 0.4,
    double attack = 0.004,
    double release = 0.06,
    double decay = 2.5,
    double warmth = 0.18,
  }) {
    final first = (start * _sampleRate).round();
    final count = (duration * _sampleRate).round();
    final endHz = toHz ?? fromHz;
    for (var i = 0; i < count && first + i < samples.length; i++) {
      final t = i / _sampleRate;
      final progress = t / duration;
      final frequencyDelta = endHz - fromHz;
      final phase =
          _twoPi * (fromHz * t + frequencyDelta * t * t / (2 * duration));
      final envelope =
          _envelope(t, duration, attack, release) * math.exp(-decay * progress);
      final value =
          math.sin(phase) +
          warmth * math.sin(phase * 2) +
          warmth * 0.35 * math.sin(phase * 3);
      samples[first + i] += value * gain * envelope;
    }
  }

  void noise({
    required double start,
    required double duration,
    double gain = 0.2,
    double attack = 0.001,
    double release = 0.04,
    bool highPass = false,
    int seed = 0x51A7,
  }) {
    final first = (start * _sampleRate).round();
    final count = (duration * _sampleRate).round();
    var state = seed;
    var smoothed = 0.0;
    for (var i = 0; i < count && first + i < samples.length; i++) {
      state ^= state << 13;
      state ^= state >> 17;
      state ^= state << 5;
      final raw = ((state & 0x7fffffff) / 0x3fffffff) - 1;
      smoothed += (raw - smoothed) * 0.16;
      final colored = highPass ? raw - smoothed : smoothed;
      final t = i / _sampleRate;
      final envelope =
          _envelope(t, duration, attack, release) *
          math.exp(-4.2 * t / duration);
      samples[first + i] += colored * gain * envelope;
    }
  }
}

double _envelope(double t, double duration, double attack, double release) {
  final fadeIn = attack <= 0 ? 1.0 : math.min(1.0, t / attack);
  final fadeOut = release <= 0 ? 1.0 : math.min(1.0, (duration - t) / release);
  return fadeIn * fadeOut;
}

_Track _start() {
  final t = _Track(0.34)
    ..tone(start: 0, duration: 0.2, fromHz: 294, toHz: 392, gain: 0.25)
    ..tone(start: 0.02, duration: 0.16, fromHz: 494, gain: 0.30)
    ..tone(start: 0.10, duration: 0.16, fromHz: 622, gain: 0.28)
    ..tone(start: 0.18, duration: 0.15, fromHz: 784, gain: 0.25);
  return t;
}

_Track _collect() => _Track(0.12)
  ..noise(start: 0, duration: 0.035, gain: 0.10, highPass: true)
  ..tone(
    start: 0,
    duration: 0.105,
    fromHz: 520,
    toHz: 850,
    gain: 0.48,
    release: 0.035,
    decay: 4.5,
  );

_Track _bonus() {
  final t = _Track(0.46);
  const notes = [523.25, 659.25, 783.99, 1046.50];
  for (var i = 0; i < notes.length; i++) {
    t.tone(
      start: i * 0.075,
      duration: 0.18,
      fromHz: notes[i],
      gain: 0.28,
      release: 0.10,
      decay: 2.8,
    );
  }
  return t;
}

_Track _power() => _Track(0.52)
  ..tone(
    start: 0,
    duration: 0.32,
    fromHz: 280,
    toHz: 760,
    gain: 0.24,
    release: 0.10,
    decay: 1.0,
  )
  ..tone(start: 0.14, duration: 0.24, fromHz: 523, gain: 0.24)
  ..tone(start: 0.23, duration: 0.24, fromHz: 659, gain: 0.23)
  ..tone(start: 0.31, duration: 0.20, fromHz: 880, gain: 0.22);

_Track _seed() => _Track(0.13)
  ..noise(start: 0, duration: 0.055, gain: 0.32, release: 0.03, highPass: true)
  ..tone(
    start: 0.006,
    duration: 0.10,
    fromHz: 1050,
    toHz: 420,
    gain: 0.32,
    release: 0.04,
    decay: 3.5,
  );

_Track _hit() => _Track(0.22)
  ..noise(start: 0, duration: 0.09, gain: 0.36, release: 0.055)
  ..tone(
    start: 0,
    duration: 0.15,
    fromHz: 155,
    toHz: 82,
    gain: 0.44,
    release: 0.07,
    decay: 2.0,
  )
  ..tone(start: 0.035, duration: 0.16, fromHz: 360, toHz: 290, gain: 0.18);

_Track _hunt() => _Track(0.52)
  ..tone(start: 0, duration: 0.19, fromHz: 330, gain: 0.28)
  ..tone(start: 0.10, duration: 0.20, fromHz: 494, gain: 0.30)
  ..tone(start: 0.22, duration: 0.25, fromHz: 659, gain: 0.29)
  ..tone(start: 0.22, duration: 0.28, fromHz: 165, toHz: 220, gain: 0.18);

_Track _warning() => _Track(0.16)
  ..tone(
    start: 0,
    duration: 0.13,
    fromHz: 720,
    toHz: 520,
    gain: 0.38,
    release: 0.045,
    decay: 2.0,
  )
  ..tone(start: 0, duration: 0.10, fromHz: 180, gain: 0.18);

_Track _gameOver() => _Track(0.66)
  ..tone(start: 0, duration: 0.23, fromHz: 494, gain: 0.27)
  ..tone(start: 0.11, duration: 0.23, fromHz: 415, gain: 0.27)
  ..tone(start: 0.22, duration: 0.25, fromHz: 330, gain: 0.28)
  ..tone(start: 0.35, duration: 0.29, fromHz: 247, toHz: 210, gain: 0.30)
  ..tone(start: 0.34, duration: 0.26, fromHz: 105, toHz: 62, gain: 0.22)
  ..noise(start: 0.34, duration: 0.13, gain: 0.16, release: 0.09);

_Track _revive() {
  final t = _Track(0.70)
    ..tone(
      start: 0,
      duration: 0.42,
      fromHz: 220,
      toHz: 660,
      gain: 0.18,
      release: 0.10,
      decay: 0.8,
    );
  const notes = [294.0, 392.0, 494.0, 659.0, 880.0];
  for (var i = 0; i < notes.length; i++) {
    t.tone(
      start: 0.04 + i * 0.085,
      duration: 0.25,
      fromHz: notes[i],
      gain: 0.21,
      release: 0.13,
      decay: 2.2,
    );
  }
  return t;
}

void _writeWav(File file, _Track track, {double targetPeak = 0.78}) {
  final peak = track.samples.fold<double>(0, (p, s) => math.max(p, s.abs()));
  final scale = peak == 0 ? 1.0 : targetPeak / peak;
  final dataBytes = track.samples.length * 2;
  final bytes = ByteData(44 + dataBytes);
  void ascii(int offset, String text) {
    for (var i = 0; i < text.length; i++) {
      bytes.setUint8(offset + i, text.codeUnitAt(i));
    }
  }

  ascii(0, 'RIFF');
  bytes.setUint32(4, 36 + dataBytes, Endian.little);
  ascii(8, 'WAVE');
  ascii(12, 'fmt ');
  bytes.setUint32(16, 16, Endian.little);
  bytes.setUint16(20, 1, Endian.little); // PCM
  bytes.setUint16(22, 1, Endian.little); // mono
  bytes.setUint32(24, _sampleRate, Endian.little);
  bytes.setUint32(28, _sampleRate * 2, Endian.little);
  bytes.setUint16(32, 2, Endian.little);
  bytes.setUint16(34, 16, Endian.little);
  ascii(36, 'data');
  bytes.setUint32(40, dataBytes, Endian.little);
  for (var i = 0; i < track.samples.length; i++) {
    final sample = (track.samples[i] * scale).clamp(-1.0, 1.0);
    bytes.setInt16(44 + i * 2, (sample * 32767).round(), Endian.little);
  }
  file.writeAsBytesSync(bytes.buffer.asUint8List(), flush: true);
}

void main(List<String> args) {
  final output = Directory(args.isEmpty ? 'assets/sounds' : args.single);
  output.createSync(recursive: true);
  final sounds = <String, _Track>{
    'sfx_snake_start.wav': _start(),
    'sfx_snake_collect.wav': _collect(),
    'sfx_snake_bonus.wav': _bonus(),
    'sfx_snake_power.wav': _power(),
    'sfx_snake_seed.wav': _seed(),
    'sfx_snake_hit.wav': _hit(),
    'sfx_snake_hunt.wav': _hunt(),
    'sfx_snake_warning.wav': _warning(),
    'sfx_snake_game_over.wav': _gameOver(),
    'sfx_snake_revive.wav': _revive(),
  };

  for (final entry in sounds.entries) {
    final file = File('${output.path}/${entry.key}');
    _writeWav(file, entry.value);
    stdout.writeln(
      '${entry.key}: ${(entry.value.samples.length / _sampleRate).toStringAsFixed(2)}s',
    );
  }
}
