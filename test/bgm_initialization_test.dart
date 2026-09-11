import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:habit_app/utils/bgm_service.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Delays the native volume acknowledgement, so a late initializer could mute
/// the destination after it has already raised its volume.
class _DelayedPlayer extends Fake implements AudioPlayer {
  final muteWrites = <Completer<void>>[];
  final volumes = <double>[];
  bool delayMute = false;
  bool failNextVolume = false;
  @override
  double volume = 1;

  @override
  Future<void> setLoopMode(LoopMode mode) async {}

  @override
  Future<void> setVolume(double next) async {
    volumes.add(next);
    if (failNextVolume) {
      failNextVolume = false;
      throw PlatformException(code: 'native-volume-failed');
    }
    if (next == 0 && delayMute) {
      final gate = Completer<void>();
      muteWrites.add(gate);
      await gate.future;
    }
    volume = next;
  }

  @override
  Stream<ProcessingState> get processingStateStream => const Stream.empty();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _DelayedPlayer player;
  late BgmService service;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    player = _DelayedPlayer();
    service = BgmService.forTesting(
      player: player,
      configureSession: () async {},
    );
  });
  tearDown(() {
    for (final gate in player.muteWrites) {
      if (!gate.isCompleted) gate.complete();
    }
    WidgetsBinding.instance.removeObserver(service);
  });

  test(
    'overlapping route initializers cannot mute the destination later',
    () async {
      player.delayMute = true;
      final entry = service.init();
      await Future<void>.delayed(Duration.zero);
      expect(player.muteWrites, hasLength(1));
      final home = service.init();
      await Future<void>.delayed(Duration.zero);

      player.muteWrites.first.complete();
      await entry;
      await player.setVolume(.25);
      for (final gate in player.muteWrites) {
        if (!gate.isCompleted) gate.complete();
      }
      await home;
      expect(player.volume, .25);
      expect(player.volumes, [0, .25]);

      await service.init();
      expect(player.volumes, [0, .25]);
    },
  );

  test(
    'native initialization failure reaches both callers and a retry can initialize',
    () async {
      player.failNextVolume = true;
      final first = service.init();
      final second = service.init();
      await Future.wait([
        expectLater(first, throwsA(isA<PlatformException>())),
        expectLater(second, throwsA(isA<PlatformException>())),
      ]);
      expect(player.volumes, [0]);

      await service.init();
      expect(player.volumes, [0, 0]);
      await player.setVolume(.25);
      await service.init();
      expect(player.volume, .25);
    },
  );
}
