import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:habit_app/l10n/app_localizations.dart';
import 'package:habit_app/utils/app_style.dart';
import 'package:habit_app/utils/app_theme.dart';
import 'package:habit_app/widgets/mascot_app_bar.dart';

void main() {
  for (final width in [320.0, 430.0]) {
    for (final language in ['zh', 'en']) {
      testWidgets(
        'toolbar $width $language keeps three equal buttons and gaps',
        (tester) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = Size(width, 932);
          addTearDown(tester.view.resetDevicePixelRatio);
          addTearDown(tester.view.resetPhysicalSize);
          await tester.pumpWidget(
            MaterialApp(
              theme: buildAppTheme(),
              locale: Locale(language),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: const TextScaler.linear(1.3)),
                child: child!,
              ),
              home: const Scaffold(
                appBar: MascotAppBar(accent: AppPalette.brand),
              ),
            ),
          );
          await tester.pump();
          final rectangles = [
            for (final key in [
              'toolbar_coins',
              'toolbar_audio',
              'toolbar_settings',
            ])
              tester.getRect(find.byKey(ValueKey(key))),
          ];
          for (final rect in rectangles) {
            expect(rect.size, const Size(48, 48));
            expect(rect.center.dy, rectangles.first.center.dy);
          }
          expect(rectangles[1].left - rectangles[0].right, 8);
          expect(rectangles[2].left - rectangles[1].right, 8);
          expect(width - rectangles.last.right, 12);
          expect(
            tester.getRect(find.byType(MascotPill)).right,
            lessThanOrEqualTo(rectangles.first.left),
          );
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        },
      );
    }
  }
}
