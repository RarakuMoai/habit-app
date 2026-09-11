import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:habit_app/l10n/app_localizations.dart';
import 'package:habit_app/pages/onboarding_page.dart';
import 'package:habit_app/utils/app_theme.dart';
import 'package:habit_app/utils/entry_audio.dart';
import 'package:habit_app/utils/prefs_keys.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _SilentAudio extends EntryAudioBackend {
  @override
  String? get loadedAsset => null;
  @override
  String get selectedAsset => 'sounds/bgm_main.m4a';
  @override
  Future<void> prepare() async {}
  @override
  Future<void> setEntryActive(bool active) async {}
  @override
  Future<void> play(String asset, {required bool deferFade}) async {}
}

Finder _key(String key) => find.byKey(ValueKey(key));

void main() {
  const output = String.fromEnvironment('ONBOARDING_REVIEW_OUTPUT');
  const cjkFont = String.fromEnvironment('ONBOARDING_REVIEW_CJK_FONT');
  setUpAll(() async {
    await (FontLoader(
      'Nunito',
    )..addFont(rootBundle.load('assets/fonts/Nunito-Regular.ttf'))).load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    if (cjkFont.isNotEmpty) {
      final bytes = await File(cjkFont).readAsBytes();
      await (FontLoader(
        'ReviewCJK',
      )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
    }
  });

  for (final size in [const Size(320, 568), const Size(430, 932)]) {
    testWidgets('full-screen sky and stable Tumi stage at $size', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      SharedPreferences.setMockInitialValues({PrefsKeys.musicMuted: true});
      EntryAudio.debugInstance = EntryAudio(backend: _SilentAudio());
      addTearDown(() => EntryAudio.debugInstance = null);
      final keyboard = ValueNotifier(0.0);
      addTearDown(keyboard.dispose);
      final boundary = GlobalKey();
      var theme = buildAppTheme();
      if (cjkFont.isNotEmpty) {
        theme = theme.copyWith(
          textTheme: theme.textTheme.apply(fontFamilyFallback: ['ReviewCJK']),
          filledButtonTheme: FilledButtonThemeData(
            style: theme.filledButtonTheme.style!.copyWith(
              textStyle: WidgetStatePropertyAll(
                theme.filledButtonTheme.style!.textStyle!
                    .resolve({})!
                    .copyWith(fontFamilyFallback: ['ReviewCJK']),
              ),
            ),
          ),
        );
      }
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: theme,
            locale: const Locale('zh', 'TW'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            builder: (context, child) => ValueListenableBuilder(
              valueListenable: keyboard,
              builder: (context, bottom, _) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  padding: EdgeInsets.only(
                    top: size.height > 800 ? 59 : 20,
                    bottom: bottom > 0
                        ? 0
                        : size.height > 800
                        ? 34
                        : 0,
                  ),
                  viewInsets: EdgeInsets.only(bottom: bottom),
                  disableAnimations: true,
                ),
                child: child!,
              ),
            ),
            home: const OnboardingPage(preview: true),
          ),
        ),
      );
      Future<void> settle() async {
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        await tester.pump();
        expect(tester.takeException(), isNull);
      }

      Future<void> next() async {
        await tester.tap(_key('onboarding-primary'));
        await settle();
      }

      Future<void> capture(String name) async {
        if (output.isEmpty) return;
        await tester.runAsync(() async {
          final render =
              boundary.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary;
          final image = await render.toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final target = File('$output/${size.width.toInt()}-$name.png');
          await target.parent.create(recursive: true);
          await target.writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }

      await settle();
      final fullSky = tester.getRect(_key('onboarding-sky'));
      expect(fullSky, Offset.zero & size);
      expect(_key('onboarding-portrait'), findsNothing);
      await capture('arrival');
      await next();
      final portrait = tester.getRect(_key('onboarding-portrait'));
      expect(portrait.width, closeTo(portrait.height, 0.01));
      expect(portrait.center.dx, closeTo(size.width / 2, 0.01));
      expect(
        portrait.width,
        closeTo((size.width * 0.58).clamp(156, 252), 0.01),
      );
      expect(
        tester.getRect(_key('onboarding-dialogue')).top,
        greaterThanOrEqualTo(portrait.bottom),
      );
      await capture('hello');
      await next();
      expect(tester.getRect(_key('onboarding-portrait')), portrait);
      await next();
      expect(tester.getRect(_key('onboarding-portrait')), portrait);
      await capture('name');
      keyboard.value = 300;
      await settle();
      expect(tester.getRect(_key('onboarding-sky')), fullSky);
      expect(_key('onboarding-portrait'), findsNothing);
      final field = _key('onboarding-mascot-name');
      await Scrollable.ensureVisible(tester.element(field), alignment: 0.5);
      await settle();
      expect(field.hitTestable(), findsOneWidget);
      expect(_key('onboarding-primary').hitTestable(), findsOneWidget);
      expect(
        tester.getRect(_key('onboarding-primary')).bottom,
        lessThanOrEqualTo(size.height - 300),
      );
      await capture('keyboard');
      await tester.pumpWidget(const SizedBox.shrink());
      await settle();
    });
  }
}
