// Explicit debug target only. Not imported by production main.dart or routes.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/audio_settings_service.dart';
import '../utils/bgm_service.dart';
import '../utils/sfx_service.dart';
import 'entry_preview/app.dart';
import 'entry_preview/model.dart';

void main() {
  if (!kDebugMode) {
    throw StateError('Entry preview is debug-only; never ship this target.');
  }
  final binding = WidgetsFlutterBinding.ensureInitialized();
  // Existing audio services may use preferences: replace the entire legacy
  // platform store BEFORE constructing them. No native preferences are read.
  // Deliberate debug-only isolation for the legacy audio services.
  // ignore: invalid_use_of_visible_for_testing_member
  SharedPreferences.setMockInitialValues({});
  const initial = String.fromEnvironment(
    'ENTRY_SCENARIO',
    defaultValue: 'firstUse',
  );
  final model = EntryPreviewModel(
    scenario: EntryScenario.values.firstWhere(
      (v) => v.name == initial,
      orElse: () => EntryScenario.firstUse,
    ),
  );
  final audio = _PreviewAudio();
  binding.deferFirstFrame();
  runApp(_LaunchBridge(model: model, audio: audio));
}

class _LaunchBridge extends StatefulWidget {
  const _LaunchBridge({required this.model, required this.audio});
  final EntryPreviewModel model;
  final _PreviewAudio audio;
  @override
  State<_LaunchBridge> createState() => _LaunchBridgeState();
}

class _LaunchBridgeState extends State<_LaunchBridge> {
  bool _prepared = false;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_prepared) return;
    _prepared = true;
    // Same unmodified raster and BoxFit as the native launch storyboard.
    // Allow the engine frame when decode is ready, with no minimum delay.
    precacheImage(
      const AssetImage('assets/scenes/onboarding/entry_preview_launch.png'),
      context,
    ).whenComplete(() => WidgetsBinding.instance.allowFirstFrame());
  }

  @override
  Widget build(BuildContext context) => EntryPreviewApp(
    model: widget.model,
    onAudio: widget.audio.set,
    onVoice: widget.audio.voice,
  );
}

class _PreviewAudio {
  Future<void>? _preparing;
  Future<void> _tail = Future.value();
  bool _enabled = false;
  Future<void> set(bool enabled, bool room) {
    _enabled = enabled;
    // Preserve service ownership and ordering without changing production audio.
    return _tail = _tail
        .then((_) async {
          _preparing ??= Future.wait([
            BgmService.instance.init(),
            SfxService.instance.init(),
          ]).then((_) {});
          await _preparing;
          await AudioSettingsService.instance.setAllMuted(!_enabled);
          if (_enabled) {
            await BgmService.instance.play(
              room ? 'sounds/bgm_main.m4a' : 'sounds/bgm_onboarding.m4a',
            );
          }
        })
        .catchError((Object error) {
          debugPrint('Preview audio unavailable: ${error.runtimeType}');
        });
  }

  void voice() {
    if (_enabled) SfxService.instance.play(SfxCue.tumiConfirm);
  }
}
