import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:just_audio/just_audio.dart';

import 'app_audio_session.dart';

enum MetronomeTone {
  // gain：把各音色的峰值正規化到相近響度（原檔 kick/bell 峰值偏低，聽起來小聲）。
  // 量過原始波形峰值後反推：目標峰值 ~0.85 滿格。
  wood('wood', '木魚', 'assets/sounds/metronome_wood.wav', 1.05),
  kick('kick', '溫和鼓聲', 'assets/sounds/metronome_kick.wav', 1.85),
  lowWood('low_wood', '低木', 'assets/sounds/metronome_lowwood.wav', 1.25),
  bell('bell', '柔鈴', 'assets/sounds/metronome_bell.wav', 2.0);

  const MetronomeTone(this.id, this.label, this.assetPath, this.gain);
  final String id;
  final String label;
  final String assetPath;
  final double gain;

  static MetronomeTone fromId(String? id) => MetronomeTone.values.firstWhere(
    (tone) => tone.id == id,
    orElse: () => MetronomeTone.wood,
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
  final Map<MetronomeTone, String> _gainedPaths = {}; // 響度正規化後的暫存檔

  Future<void> init({MetronomeTone tone = MetronomeTone.wood}) async {
    if (_players.containsKey(tone)) return;
    await AppAudioSession.ensureConfigured();
    // 用「響度正規化後」的音檔（不是原始 asset），預覽/點按也會比照循環變大聲。
    final path = await _gainedFile(tone);
    final players = <AudioPlayer>[];
    for (var i = 0; i < 4; i++) {
      final player = AudioPlayer();
      await player.setAudioSource(AudioSource.file(path));
      await player.setVolume(0.75);
      players.add(player);
    }
    _players[tone] = players;
    _cursors[tone] = 0;
  }

  // 產生（並快取）一份響度正規化後的音檔，供預覽 player 使用。
  Future<String> _gainedFile(MetronomeTone tone) async {
    final cached = _gainedPaths[tone];
    if (cached != null) return cached;
    final pcm = await _loadPcm(tone); // 已套 gain
    final wav = _wrapWav(pcm.data, pcm.sampleRate, pcm.channels);
    final file = File('${Directory.systemTemp.path}/metro_tone_${tone.id}.wav');
    await file.writeAsBytes(wav, flush: true);
    _gainedPaths[tone] = file.path;
    return file.path;
  }

  void play({required double volume, MetronomeTone tone = MetronomeTone.wood}) {
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

  /// 啟動或更新（改 BPM/音色/音量/拍號時呼叫）等速節拍循環。
  ///
  /// [beatsPerBar] >= 2 時循環長度 = 一整個小節；[accentFirst] 為真則把第一拍以
  /// 全振幅、其餘拍以較小振幅烤進 PCM，做出「第一拍重音」。beatsPerBar=1 時退化成
  /// 原本的單拍循環（與舊行為一致）。
  Future<void> startOrUpdateLoop({
    required int bpm,
    required MetronomeTone tone,
    required double volume,
    int beatsPerBar = 1,
    bool accentFirst = true,
  }) async {
    try {
      await AppAudioSession.ensureConfigured();
      final bytes = await _buildBarLoopWav(
        tone,
        bpm.clamp(30, 240),
        beatsPerBar.clamp(1, 12),
        accentFirst,
      );
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

  // 一小節循環 = beatsPerBar 拍，每拍 = 音色樣本 + 補到拍長的靜音；超過拍長則截斷
  // 音色（高 BPM）。第一拍重音改用「升高音高」（pitch-shift）做出明顯不同的咔聲，
  // 比單純放大音量更容易分辨（古典節拍器第一拍就是較高的滴答）。
  Future<Uint8List> _buildBarLoopWav(
    MetronomeTone tone,
    int bpm,
    int beatsPerBar,
    bool accentFirst,
  ) async {
    final pcm = await _loadPcm(tone);
    final bytesPerFrame = 2 * pcm.channels; // 16-bit
    final beatFrames = (pcm.sampleRate * 60 / bpm).round();
    final beatBytes = beatFrames * bytesPerFrame;
    final out = Uint8List(beatBytes * beatsPerBar); // 預設全 0 = 靜音
    for (var b = 0; b < beatsPerBar; b++) {
      final accent = accentFirst && beatsPerBar > 1 && b == 0;
      _writeBeat(out, b * beatBytes, beatBytes, pcm, pitch: accent ? 1.5 : 1.0);
    }
    return _wrapWav(out, pcm.sampleRate, pcm.channels);
  }

  // 把音色樣本寫進 out 的某一拍槽。pitch>1：線性重採樣升高音高（重音用），
  // 樣本變短、頻率變高；pitch==1 直接複製。樣本比拍長長則截斷（高 BPM）。
  void _writeBeat(
    Uint8List out,
    int offset,
    int beatBytes,
    _Pcm pcm, {
    double pitch = 1.0,
  }) {
    if (pitch == 1.0 || pcm.channels != 1) {
      final copy = pcm.data.length < beatBytes ? pcm.data.length : beatBytes;
      out.setRange(offset, offset + copy, pcm.data);
      return;
    }
    final src = ByteData.sublistView(pcm.data);
    final dst = ByteData.sublistView(out);
    final srcSamples = pcm.data.length ~/ 2; // mono 16-bit
    final maxDst = beatBytes ~/ 2;
    var i = 0;
    var pos = 0.0;
    while (i < maxDst) {
      final si = pos.floor();
      if (si >= srcSamples) break;
      final s0 = src.getInt16(si * 2, Endian.little);
      final s1 = (si + 1 < srcSamples)
          ? src.getInt16((si + 1) * 2, Endian.little)
          : s0;
      final v = (s0 + (s1 - s0) * (pos - si)).round().clamp(-32768, 32767);
      dst.setInt16(offset + i * 2, v, Endian.little);
      i++;
      pos += pitch;
    }
  }

  Future<_Pcm> _loadPcm(MetronomeTone tone) async {
    final cached = _pcmCache[tone];
    if (cached != null) return cached;
    final bd = await rootBundle.load(tone.assetPath);
    final pcm = _applyGain(_parseWav(bd.buffer.asUint8List()), tone.gain);
    _pcmCache[tone] = pcm;
    return pcm;
  }

  // 把 16-bit PCM 整體乘上 gain（響度正規化），clamp 防爆音。
  _Pcm _applyGain(_Pcm pcm, double gain) {
    if (gain == 1.0) return pcm;
    final out = Uint8List(pcm.data.length);
    final src = ByteData.sublistView(pcm.data);
    final dst = ByteData.sublistView(out);
    for (var i = 0; i + 1 < pcm.data.length; i += 2) {
      final v = (src.getInt16(i, Endian.little) * gain).round();
      dst.setInt16(i, v.clamp(-32768, 32767), Endian.little);
    }
    return _Pcm(
      sampleRate: pcm.sampleRate,
      channels: pcm.channels,
      data: out,
    );
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
    _pcmCache.clear();
    _gainedPaths.clear();
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
