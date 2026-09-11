import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:habit_app/l10n/app_localizations.dart';
import 'package:habit_app/pages/onboarding_page.dart';
import 'package:habit_app/utils/entry_audio.dart';
import 'package:habit_app/utils/prefs_keys.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Audio extends EntryAudioBackend {
  @override
  String? loadedAsset = 'sounds/previous.m4a';
  @override
  String get selectedAsset => 'sounds/selected.m4a';
  bool entry = false;
  @override
  Future<void> prepare() async {}
  @override
  Future<void> setEntryActive(bool active) async => entry = active;
  @override
  Future<void> play(String asset, {required bool deferFade}) async {
    loadedAsset = asset;
  }
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pump();
  expect(tester.takeException(), isNull);
}

void main() {
  late _Audio backend;
  setUp(() {
    SharedPreferences.setMockInitialValues({PrefsKeys.musicMuted: true});
    backend = _Audio();
    EntryAudio.debugInstance = EntryAudio(backend: backend);
  });
  tearDown(() => EntryAudio.debugInstance = null);

  for (final replay in [false, true]) {
    testWidgets(
      'opening ${replay ? 'memory replay' : 'developer preview'} owns music and restores on close',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            locale: const Locale('zh', 'TW'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => Navigator.of(context).push<void>(
                    MaterialPageRoute(
                      builder: (_) => OnboardingPage(
                        preview: !replay,
                        onReplayFinished: replay ? (_) async => true : null,
                      ),
                    ),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('open'));
        await _settle(tester);
        expect(backend.loadedAsset, EntryAudio.introAsset);
        expect(backend.entry, isTrue);
        await tester.tap(find.byKey(const ValueKey('onboarding-back')));
        await _settle(tester);
        expect(backend.loadedAsset, 'sounds/previous.m4a');
        expect(backend.entry, isFalse);
        expect(
          (await SharedPreferences.getInstance()).getBool(PrefsKeys.musicMuted),
          isTrue,
        );
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
