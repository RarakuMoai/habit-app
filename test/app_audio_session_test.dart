import 'dart:async';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:habit_app/utils/app_audio_session.dart';

class _FailingSession extends Fake implements AudioSession {
  int configurations = 0;
  int activations = 0;

  @override
  Future<void> configure(AudioSessionConfiguration configuration) async {
    configurations++;
    if (configurations == 1) {
      throw PlatformException(code: 'native-session-unavailable');
    }
    expect(
      configuration.avAudioSessionCategory,
      AVAudioSessionCategory.ambient,
    );
  }

  @override
  Future<bool> setActive(
    bool active, {
    AVAudioSessionSetActiveOptions? avAudioSessionSetActiveOptions,
    AndroidAudioFocusGainType? androidAudioFocusGainType,
    AndroidAudioAttributes? androidAudioAttributes,
    bool? androidWillPauseWhenDucked,
    AudioSessionConfiguration fallbackConfiguration =
        const AudioSessionConfiguration.music(),
  }) async {
    activations++;
    return true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.ryanheise.audio_session');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  setUp(AppAudioSession.resetForTesting);
  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
    AppAudioSession.resetForTesting();
  });

  test(
    'delayed plugin configuration is shared by BGM, SFX and activation callers',
    () async {
      final started = Completer<void>();
      final release = Completer<void>();
      final configurations = <Map<dynamic, dynamic>>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'setConfiguration') {
          configurations.add((call.arguments as List).single as Map);
          if (!started.isCompleted) started.complete();
          await release.future;
        }
        return null;
      });
      final bgm = AppAudioSession.ensureConfigured();
      await started.future;
      final sfx = AppAudioSession.ensureConfigured();
      final activation = AppAudioSession.activate();
      await Future<void>.delayed(Duration.zero);
      expect(configurations, hasLength(1));
      release.complete();
      await Future.wait([bgm, sfx, activation]);
      await AppAudioSession.ensureConfigured();
      expect(configurations, hasLength(1));
      expect(
        configurations.single['avAudioSessionCategory'],
        AVAudioSessionCategory.ambient.rawValue,
      );
    },
  );

  test(
    'failed native configuration is retried before activation and never becomes a false success',
    () async {
      final session = _FailingSession();
      AppAudioSession.resetForTesting(session: session);
      await Future.wait([
        AppAudioSession.ensureConfigured(),
        AppAudioSession.ensureConfigured(),
      ]);
      expect(session.configurations, 1);
      expect(session.activations, 0);

      await AppAudioSession.activate();
      expect(session.configurations, 2);
      expect(session.activations, 1);
      await AppAudioSession.ensureConfigured();
      expect(session.configurations, 2);
      expect(session.activations, 2);
    },
  );
}
