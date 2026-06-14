import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
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

  // 等速節拍循環：用「一拍 = 音色 + 補到拍長的靜音」做成一小段 PCM，交給
  // just_audio 無縫循環（LoopMode.one）。發聲時間由音訊引擎的取樣時鐘決定，
  // 不靠 Dart timer 觸發，所以是取樣級等速（解決鼓聲忽快忽慢）。
  AudioPlayer? _loopPlayer;
  int _loopGen = 0;
  final Map<MetronomeTone, _Pcm> _pcmCache = {};

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
      final players = _players[tone];
      if (players == null || players.isEmpty) {
        // 尚未預載：補 init（含 ensureConfigured 已 setActive），但這拍可能略晚
        await init(tone: tone);
      }
      final ready = _players[tone];
      if (ready == null || ready.isEmpty) return;
      final cursor = _cursors[tone] ?? 0;
      final player = ready[cursor];
      _cursors[tone] = (cursor + 1) % ready.length;
      // session 在 init 時已 active；這裡不要 await activate（setActive 平台呼叫
      // 偶爾卡頓會把這拍拖慢、節奏聽起來忽快忽慢）。非阻塞補一刀確保仍 active。
      unawaited(AppAudioSession.activate());
      await player.setVolume(volume);
      await player.seek(Duration.zero);
      unawaited(player.play());
    } catch (e) {
      debugPrint('Metronome play failed: $e');
    }
  }

  // ── 等速節拍循環 ──

  /// 啟動或更新（改 BPM/音色/音量時呼叫）等速節拍循環。
  Future<void> startOrUpdateLoop({
    required int bpm,
    required MetronomeTone tone,
    required double volume,
  }) async {
    try {
      await AppAudioSession.ensureConfigured();
      final bytes = await _buildBeatLoopWav(tone, bpm.clamp(30, 240));
      final dir = Directory.systemTemp; // 免 path_provider，跨平台暫存目錄
      final gen = ++_loopGen;
      final file = File('${dir.path}/metro_loop_$gen.wav');
      await file.writeAsBytes(bytes, flush: true);
      _loopPlayer ??= AudioPlayer();
      final player = _loopPlayer!;
      await player.setAudioSource(AudioSource.file(file.path));
      await player.setLoopMode(LoopMode.one); // 無縫循環 = 取樣級等速
      await player.setVolume(volume.clamp(0.0, 1.0));
      unawaited(player.play()); // 不可 await（play future 播到停止才完成）
      _cleanupOldLoopFiles(dir, keep: file.path);
    } catch (e) {
      debugPrint('Metronome loop failed: $e');
    }
  }

  Future<void> setLoopVolume(double volume) async {
    try {
      await _loopPlayer?.setVolume(volume.clamp(0.0, 1.0));
    } catch (_) {}
  }

  Future<void> stopLoop() async {
    try {
      await _loopPlayer?.stop();
    } catch (_) {}
  }

  // 一拍循環 = 音色樣本 + 補到拍長的靜音；超過拍長則截斷音色（高 BPM）。
  Future<Uint8List> _buildBeatLoopWav(MetronomeTone tone, int bpm) async {
    final pcm = await _loadPcm(tone);
    final bytesPerFrame = 2 * pcm.channels; // 16-bit
    final beatFrames = (pcm.sampleRate * 60 / bpm).round();
    final totalBytes = beatFrames * bytesPerFrame;
    final out = Uint8List(totalBytes); // 預設全 0 = 靜音
    final copy = pcm.data.length < totalBytes ? pcm.data.length : totalBytes;
    out.setRange(0, copy, pcm.data);
    return _wrapWav(out, pcm.sampleRate, pcm.channels);
  }

  Future<_Pcm> _loadPcm(MetronomeTone tone) async {
    final cached = _pcmCache[tone];
    if (cached != null) return cached;
    final bd = await rootBundle.load(tone.assetPath);
    final pcm = _parseWav(bd.buffer.asUint8List());
    _pcmCache[tone] = pcm;
    return pcm;
  }

  _Pcm _parseWav(Uint8List b) {
    final bd = ByteData.sublistView(b);
    var pos = 12; // 跳過 'RIFF' size 'WAVE'
    var sampleRate = 44100, channels = 1;
    var data = Uint8List(0);
    while (pos + 8 <= b.length) {
      final id = String.fromCharCodes(b.sublist(pos, pos + 4));
      final size = bd.getUint32(pos + 4, Endian.little);
      final body = pos + 8;
      if (id == 'fmt ') {
        channels = bd.getUint16(body + 2, Endian.little);
        sampleRate = bd.getUint32(body + 4, Endian.little);
      } else if (id == 'data') {
        final end = (body + size <= b.length) ? body + size : b.length;
        data = Uint8List.sublistView(b, body, end);
      }
      pos = body + size + (size.isOdd ? 1 : 0);
    }
    return _Pcm(sampleRate: sampleRate, channels: channels, data: data);
  }

  Uint8List _wrapWav(Uint8List pcm, int sampleRate, int channels) {
    const bits = 16;
    final byteRate = sampleRate * channels * bits ~/ 8;
    final blockAlign = channels * bits ~/ 8;
    final out = BytesBuilder();
    void str(String s) => out.add(s.codeUnits);
    void u32(int v) => out.add(
      (ByteData(4)..setUint32(0, v, Endian.little)).buffer.asUint8List(),
    );
    void u16(int v) => out.add(
      (ByteData(2)..setUint16(0, v, Endian.little)).buffer.asUint8List(),
    );
    str('RIFF');
    u32(36 + pcm.length);
    str('WAVE');
    str('fmt ');
    u32(16);
    u16(1); // PCM
    u16(channels);
    u32(sampleRate);
    u32(byteRate);
    u16(blockAlign);
    u16(bits);
    str('data');
    u32(pcm.length);
    out.add(pcm);
    return out.toBytes();
  }

  void _cleanupOldLoopFiles(Directory dir, {required String keep}) {
    try {
      for (final f in dir.listSync()) {
        if (f is File && f.path.contains('metro_loop_') && f.path != keep) {
          try {
            f.deleteSync();
          } catch (_) {}
        }
      }
    } catch (_) {}
  }

  Future<void> dispose() async {
    for (final players in _players.values) {
      for (final player in players) {
        await player.dispose();
      }
    }
    _players.clear();
    _cursors.clear();
    await _loopPlayer?.dispose();
    _loopPlayer = null;
  }
}

// 解析後的 PCM（16-bit interleaved little-endian）
class _Pcm {
  final int sampleRate;
  final int channels;
  final Uint8List data;
  _Pcm({required this.sampleRate, required this.channels, required this.data});
}
