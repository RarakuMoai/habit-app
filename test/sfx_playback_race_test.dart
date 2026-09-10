import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:habit_app/utils/audio_settings_service.dart';
import 'package:habit_app/utils/sfx_service.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeVoice extends Fake implements AudioPlayer {
  bool isPlaying = false;
  int playCount = 0;
  Completer<void>? nextStopGate;
  Completer<void>? _playback;

  @override
  Future<Duration?> setAudioSource(
    AudioSource audioSource, {
    bool preload = true,
    int? initialIndex,
    Duration? initialPosition,
  }) async => const Duration(seconds: 1);
  @override
  Future<void> setVolume(double volume) async {}
  @override
  Future<void> setLoopMode(LoopMode mode) async {}
  @override
  Future<void> seek(Duration? position, {int? index}) async {}
  @override
  Future<void> setSpeed(double speed) async {}
  @override
  Future<void> setPitch(double pitch) async {}
  @override
  Future<void> play() {
    isPlaying = true;
    playCount++;
    _playback = Completer<void>();
    return _playback!.future;
  }

  @override
  Future<void> stop() async {
    final gate = nextStopGate;
    nextStopGate = null;
    if (gate != null) await gate.future;
    isPlaying = false;
    final playback = _playback;
    if (playback != null && !playback.isCompleted) playback.complete();
  }

  @override
  Future<void> dispose() => stop();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SfxService service;
  late List<_FakeVoice> voices;
  Completer<void>? configurationGate;
  Completer<void>? activationGate;

  // 等所有立即完成的平台 Future 跑完，保留刻意卡住的測試 gate。
  Future<void> flush() => Future<void>.delayed(Duration.zero);
  _FakeVoice voiceFor(SfxCue cue) {
    var index = 0;
    for (final candidate in SfxCue.values) {
      if (candidate == cue) return voices[index];
      index += candidate == SfxCue.footprintCoinTick ? 4 : 1;
    }
    throw StateError('missing cue');
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AudioSettingsService.instance.init();
    AudioSettingsService.sfxMuted.value = false;
    voices = [];
    configurationGate = null;
    activationGate = null;
    service = SfxService.forTesting(
      playerFactory: () {
        final voice = _FakeVoice();
        voices.add(voice);
        return voice;
      },
      configureSession: () async {
        if (configurationGate != null) await configurationGate!.future;
      },
      activateSession: () async {
        if (activationGate != null) await activationGate!.future;
      },
    );
  });
  tearDown(() async {
    await service.dispose();
    AudioSettingsService.sfxMuted.value = false;
  });

  test('首次載入途中放開，延遲載入完成也不能重新播放 loop', () async {
    configurationGate = Completer<void>();
    final start = service.playLoop(SfxCue.tumiPet);
    await flush();
    final stop = service.stop(SfxCue.tumiPet);
    configurationGate!.complete();
    await Future.wait([start, stop]);
    expect(voiceFor(SfxCue.tumiPet).playCount, 0);
  });

  test('播放準備中先靜音再開啟，舊請求仍失效', () async {
    await service.init();
    activationGate = Completer<void>();
    final start = service.play(SfxCue.success);
    await flush();
    await AudioSettingsService.instance.setSfxMuted(true);
    await AudioSettingsService.instance.setSfxMuted(false);
    activationGate!.complete();
    await start;
    await flush();
    expect(voiceFor(SfxCue.success).playCount, 0);
    await service.play(SfxCue.success);
    expect(voiceFor(SfxCue.success).playCount, 1);
  });

  test('靜音停止現有 loop，重新開啟不復活', () async {
    await service.playLoop(SfxCue.tumiPet);
    final voice = voiceFor(SfxCue.tumiPet);
    expect(voice.isPlaying, isTrue);
    await AudioSettingsService.instance.setSfxMuted(true);
    await flush();
    expect(voice.isPlaying, isFalse);
    await AudioSettingsService.instance.setSfxMuted(false);
    await flush();
    expect(voice.playCount, 1);
    expect(voice.isPlaying, isFalse);
  });

  test('session activation 卡住時，靜音仍立刻停止現播 loop', () async {
    await service.playLoop(SfxCue.tumiPet);
    final voice = voiceFor(SfxCue.tumiPet);
    activationGate = Completer<void>();
    final queued = service.playLoop(SfxCue.tumiPet);
    await flush();
    await AudioSettingsService.instance.setSfxMuted(true);
    await flush();
    expect(voice.isPlaying, isFalse);
    activationGate!.complete();
    await queued;
    expect(voice.playCount, 1);
  });

  test('晚回來的 native stop 不會停掉使用者的新一次播放', () async {
    await service.playLoop(SfxCue.tumiPet);
    final voice = voiceFor(SfxCue.tumiPet);
    final gate = Completer<void>();
    voice.nextStopGate = gate;
    final stop = service.stop(SfxCue.tumiPet);
    await flush();
    final restart = service.playLoop(SfxCue.tumiPet);
    await flush();
    expect(voice.playCount, 1);
    gate.complete();
    await Future.wait([stop, restart]);
    expect(voice.playCount, 2);
    expect(voice.isPlaying, isTrue);
  });

  test('九次金幣聲仍保留四聲道與每次觸發', () async {
    await service.init();
    await Future.wait(
      List.generate(9, (_) => service.playPolyphonic(SfxCue.footprintCoinTick)),
    );
    final playing = voices.where((voice) => voice.playCount > 0).toList();
    expect(playing.length, 4);
    expect(playing.map((voice) => voice.playCount).reduce((a, b) => a + b), 9);
    expect(playing.every((voice) => voice.isPlaying), isTrue);
  });
}
