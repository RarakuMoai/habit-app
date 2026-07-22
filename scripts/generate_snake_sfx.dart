// 產生「菜園小蛇」第二版專用短音效。
//
// 音色方向：暖木質打擊＋柔和掌機三角波，不使用刺耳純方波。高頻動作保持
// 短促，升級／復活才留音樂尾韻，避免高頻收集與射擊互相蓋住。
// 執行：dart run scripts/generate_snake_sfx.dart

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

const _sampleRate = 48000;
const _twoPi = math.pi * 2;

enum _Wave { sine, triangle, softPulse }

final class _Track {
  _Track(double seconds)
    : samples = List<double>.filled((seconds * _sampleRate).round(), 0);

  final List<double> samples;

  void tone({
    required double start,
    required double duration,
    required double fromHz,
    double? toHz,
    double gain = 0.3,
    double attack = 0.004,
    double release = 0.07,
    double decay = 2.3,
    double warmth = 0.12,
    double vibratoHz = 0,
    double vibratoDepth = 0,
    _Wave wave = _Wave.sine,
  }) {
    final first = (start * _sampleRate).round();
    final count = (duration * _sampleRate).round();
    final endHz = toHz ?? fromHz;
    var phase = 0.0;
    for (var i = 0; i < count && first + i < samples.length; i++) {
      final t = i / _sampleRate;
      final progress = t / duration;
      final frequency =
          fromHz +
          (endHz - fromHz) * progress +
          math.sin(_twoPi * vibratoHz * t) * vibratoDepth;
      phase += _twoPi * frequency / _sampleRate;
      final envelope =
          _envelope(t, duration, attack, release) * math.exp(-decay * progress);
      final base = switch (wave) {
        _Wave.sine => math.sin(phase),
        _Wave.triangle => 2 / math.pi * math.asin(math.sin(phase)),
        _Wave.softPulse =>
          (math.sin(phase) +
                  0.30 * math.sin(phase * 3) +
                  0.10 * math.sin(phase * 5)) /
              1.40,
      };
      final value = base + warmth * math.sin(phase * 2);
      samples[first + i] += value * gain * envelope;
    }
  }

  void noise({
    required double start,
    required double duration,
    double gain = 0.16,
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
      state &= 0x7fffffff;
      final raw = state / 0x3fffffff - 1;
      smoothed += (raw - smoothed) * 0.12;
      final colored = highPass ? raw - smoothed : smoothed;
      final t = i / _sampleRate;
      final envelope =
          _envelope(t, duration, attack, release) *
          math.exp(-4.8 * t / duration);
      samples[first + i] += colored * gain * envelope;
    }
  }
}

double _envelope(double t, double duration, double attack, double release) {
  final fadeIn = attack <= 0 ? 1.0 : math.min(1.0, t / attack);
  final fadeOut = release <= 0 ? 1.0 : math.min(1.0, (duration - t) / release);
  return fadeIn * fadeOut;
}

void _arpeggio(
  _Track track,
  List<double> notes, {
  required double start,
  required double spacing,
  required double duration,
  double gain = 0.22,
  _Wave wave = _Wave.triangle,
}) {
  for (var i = 0; i < notes.length; i++) {
    track.tone(
      start: start + i * spacing,
      duration: duration,
      fromHz: notes[i],
      gain: gain,
      release: duration * 0.52,
      decay: 2.2,
      warmth: 0.08,
      wave: wave,
    );
  }
}

_Track _start() {
  final track = _Track(0.48)
    ..tone(
      start: 0,
      duration: 0.34,
      fromHz: 146.83,
      toHz: 196,
      gain: 0.13,
      release: 0.16,
      decay: 1.4,
      wave: _Wave.softPulse,
    );
  _arpeggio(
    track,
    const [293.66, 392, 493.88, 587.33],
    start: 0.02,
    spacing: 0.075,
    duration: 0.19,
    gain: 0.23,
  );
  return track;
}

_Track _collect() => _Track(0.11)
  ..noise(start: 0, duration: 0.026, gain: 0.07, highPass: true)
  ..tone(
    start: 0,
    duration: 0.10,
    fromHz: 610,
    toHz: 880,
    gain: 0.34,
    release: 0.035,
    decay: 5.0,
    warmth: 0.06,
    wave: _Wave.triangle,
  );

_Track _bonus() {
  final track = _Track(0.62);
  _arpeggio(
    track,
    const [293.66, 329.63, 392, 440, 587.33],
    start: 0,
    spacing: 0.072,
    duration: 0.27,
  );
  track
    ..tone(
      start: 0.30,
      duration: 0.30,
      fromHz: 880,
      gain: 0.13,
      release: 0.18,
      vibratoHz: 6,
      vibratoDepth: 3,
    )
    ..tone(
      start: 0.31,
      duration: 0.28,
      fromHz: 1174.66,
      gain: 0.10,
      release: 0.18,
      decay: 2.8,
    );
  return track;
}

_Track _power() => _Track(0.56)
  ..tone(
    start: 0,
    duration: 0.36,
    fromHz: 155,
    toHz: 440,
    gain: 0.19,
    release: 0.12,
    decay: 1.2,
    wave: _Wave.softPulse,
  )
  ..tone(start: 0.20, duration: 0.34, fromHz: 293.66, gain: 0.20)
  ..tone(start: 0.23, duration: 0.31, fromHz: 440, gain: 0.18)
  ..tone(start: 0.26, duration: 0.28, fromHz: 587.33, gain: 0.16);

_Track _seed() => _Track(0.10)
  ..noise(start: 0, duration: 0.045, release: 0.025, highPass: true)
  ..tone(
    start: 0.003,
    duration: 0.09,
    fromHz: 270,
    toHz: 145,
    gain: 0.27,
    release: 0.035,
    decay: 4.2,
    wave: _Wave.triangle,
  );

_Track _hit() => _Track(0.24)
  ..noise(start: 0, duration: 0.10, gain: 0.22, release: 0.065)
  ..tone(
    start: 0,
    duration: 0.19,
    fromHz: 175,
    toHz: 82,
    gain: 0.34,
    release: 0.09,
    decay: 2.1,
    wave: _Wave.softPulse,
  )
  ..tone(
    start: 0.035,
    duration: 0.16,
    fromHz: 310,
    toHz: 220,
    gain: 0.12,
    release: 0.08,
  );

_Track _hunt() {
  final track = _Track(0.72)
    ..noise(start: 0, duration: 0.16, gain: 0.17, release: 0.10)
    ..tone(
      start: 0,
      duration: 0.50,
      fromHz: 92,
      toHz: 220,
      gain: 0.19,
      release: 0.15,
      decay: 0.8,
      wave: _Wave.softPulse,
    );
  _arpeggio(
    track,
    const [146.83, 220, 293.66, 440],
    start: 0.10,
    spacing: 0.12,
    duration: 0.24,
    gain: 0.23,
    wave: _Wave.softPulse,
  );
  return track;
}

_Track _warning() => _Track(0.22)
  ..tone(
    start: 0,
    duration: 0.105,
    fromHz: 440,
    toHz: 392,
    gain: 0.27,
    release: 0.04,
    decay: 2.8,
    wave: _Wave.triangle,
  )
  ..tone(
    start: 0.105,
    duration: 0.105,
    fromHz: 392,
    toHz: 349.23,
    gain: 0.25,
    release: 0.05,
    decay: 2.8,
    wave: _Wave.triangle,
  );

_Track _gameOver() {
  final track = _Track(0.86);
  _arpeggio(
    track,
    const [587.33, 523.25, 440, 349.23, 293.66],
    start: 0,
    spacing: 0.125,
    duration: 0.30,
    wave: _Wave.softPulse,
  );
  track.tone(
    start: 0.49,
    duration: 0.35,
    fromHz: 146.83,
    toHz: 110,
    gain: 0.17,
    release: 0.17,
    decay: 1.7,
  );
  return track;
}

_Track _revive() {
  final track = _Track(0.80)
    ..tone(
      start: 0,
      duration: 0.48,
      fromHz: 110,
      toHz: 440,
      gain: 0.14,
      release: 0.17,
      decay: 0.8,
      wave: _Wave.softPulse,
    );
  _arpeggio(
    track,
    const [146.83, 220, 293.66, 369.99, 440, 587.33],
    start: 0.04,
    spacing: 0.09,
    duration: 0.28,
    gain: 0.19,
  );
  return track;
}

_Track _magnetSpawn() => _Track(0.42)
  ..tone(
    start: 0,
    duration: 0.38,
    fromHz: 392,
    toHz: 587.33,
    gain: 0.19,
    release: 0.18,
    decay: 1.8,
    vibratoHz: 7,
    vibratoDepth: 4,
  )
  ..tone(
    start: 0.05,
    duration: 0.34,
    fromHz: 783.99,
    toHz: 1174.66,
    gain: 0.11,
    release: 0.18,
    decay: 2.4,
  );

_Track _magnetVacuum() {
  final track = _Track(0.72)
    ..tone(
      start: 0,
      duration: 0.50,
      fromHz: 130,
      toHz: 760,
      gain: 0.20,
      release: 0.14,
      decay: 0.5,
      wave: _Wave.softPulse,
    )
    ..noise(
      start: 0.02,
      duration: 0.38,
      gain: 0.09,
      release: 0.12,
      highPass: true,
    );
  _arpeggio(
    track,
    const [392, 493.88, 587.33, 783.99],
    start: 0.28,
    spacing: 0.075,
    duration: 0.25,
    gain: 0.17,
  );
  return track;
}

_Track _laserCharge() => _Track(0.56)
  ..tone(
    start: 0,
    duration: 0.48,
    fromHz: 95,
    toHz: 760,
    gain: 0.20,
    release: 0.08,
    decay: 0.3,
    wave: _Wave.softPulse,
  )
  ..tone(
    start: 0.28,
    duration: 0.26,
    fromHz: 440,
    toHz: 880,
    gain: 0.13,
    release: 0.10,
    vibratoHz: 12,
    vibratoDepth: 8,
  );

_Track _laserShot() => _Track(0.18)
  ..noise(start: 0, duration: 0.11, gain: 0.17, release: 0.06, highPass: true)
  ..tone(
    start: 0,
    duration: 0.17,
    fromHz: 930,
    toHz: 170,
    gain: 0.24,
    decay: 1.8,
    wave: _Wave.softPulse,
  )
  ..tone(
    start: 0.008,
    duration: 0.15,
    fromHz: 760,
    toHz: 140,
    gain: 0.18,
    decay: 1.8,
    wave: _Wave.triangle,
  );

_Track _moleRise() => _Track(0.32)
  ..noise(start: 0, duration: 0.18, gain: 0.20, release: 0.11)
  ..tone(
    start: 0,
    duration: 0.28,
    fromHz: 82,
    toHz: 165,
    gain: 0.27,
    release: 0.10,
    decay: 1.7,
    wave: _Wave.softPulse,
  )
  ..tone(
    start: 0.10,
    duration: 0.18,
    fromHz: 220,
    toHz: 185,
    gain: 0.11,
    release: 0.09,
  );

void _writeWav(File file, _Track track, {double targetPeak = 0.68}) {
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
  bytes.setUint16(20, 1, Endian.little);
  bytes.setUint16(22, 1, Endian.little);
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
  final sounds = <String, (_Track, double)>{
    'sfx_snake_start.wav': (_start(), 0.66),
    'sfx_snake_collect.wav': (_collect(), 0.58),
    'sfx_snake_bonus.wav': (_bonus(), 0.66),
    'sfx_snake_power.wav': (_power(), 0.64),
    'sfx_snake_seed.wav': (_seed(), 0.52),
    'sfx_snake_hit.wav': (_hit(), 0.66),
    'sfx_snake_hunt.wav': (_hunt(), 0.68),
    'sfx_snake_warning.wav': (_warning(), 0.56),
    'sfx_snake_game_over.wav': (_gameOver(), 0.66),
    'sfx_snake_revive.wav': (_revive(), 0.68),
    'sfx_snake_magnet_spawn.wav': (_magnetSpawn(), 0.58),
    'sfx_snake_magnet_vacuum.wav': (_magnetVacuum(), 0.68),
    'sfx_snake_laser_charge.wav': (_laserCharge(), 0.62),
    'sfx_snake_laser_shot.wav': (_laserShot(), 0.58),
    'sfx_snake_mole_rise.wav': (_moleRise(), 0.62),
  };

  for (final entry in sounds.entries) {
    final file = File('${output.path}/${entry.key}');
    _writeWav(file, entry.value.$1, targetPeak: entry.value.$2);
    stdout.writeln(
      '${entry.key}: '
      '${(entry.value.$1.samples.length / _sampleRate).toStringAsFixed(2)}s',
    );
  }
}
