import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:habit_app/l10n/app_localizations.dart';
import 'package:habit_app/pages/settings_page.dart';
import 'package:habit_app/utils/app_theme.dart';
import 'package:habit_app/widgets/settings_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUpAll(() async {
    final font = FontLoader('Nunito');
    for (final weight in [
      'Regular',
      'Medium',
      'SemiBold',
      'Bold',
      'ExtraBold',
      'Black',
    ]) {
      font.addFont(rootBundle.load('assets/fonts/Nunito-$weight.ttf'));
    }
    await font.load();
  });
  for (final width in [320.0, 430.0]) {
    for (final language in ['zh', 'en']) {
      testWidgets('$width $language 大字設定圖示與整組標題說明置中', (tester) async {
        SharedPreferences.setMockInitialValues({});
        tester.view.physicalSize = Size(width, 932);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          MaterialApp(
            locale: Locale(language),
            theme: buildAppTheme(),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: const TextScaler.linear(1.3),
                disableAnimations: true,
              ),
              child: child!,
            ),
            home: const SettingsPage(),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        final l10n = AppLocalizations.of(
          tester.element(find.byType(SettingsPage)),
        );
        for (final titleText in [
          l10n.settingsEditProfileTitle,
          l10n.settingsManageFeaturesTitle,
          l10n.pinSettingsTitle,
          l10n.settingsAdvancedTitle,
        ]) {
          final target = find.byWidgetPredicate(
            (widget) => widget is SettingsTileCard && widget.title == titleText,
          );
          await tester.scrollUntilVisible(
            target,
            300,
            scrollable: find
                .descendant(
                  of: find.byType(SettingsPage),
                  matching: find.byType(Scrollable),
                )
                .first,
          );
          await tester.ensureVisible(target);
          await tester.pump();
          final tile = tester.widget<SettingsTileCard>(target);
          final icon = tester.getRect(
            find.byKey(ValueKey('settings-icon-${tile.title}')),
          );
          final copy = tester.getRect(
            find.byKey(ValueKey('settings-copy-${tile.title}')),
          );
          final bounds = tester.getRect(target);
          expect(icon.center.dy, closeTo(copy.center.dy, 0.5));
          expect(copy.left, greaterThan(icon.right));
          expect(copy.right, lessThan(bounds.right));
          expect(copy.bottom, lessThan(bounds.bottom));
          final title = find.descendant(
            of: target,
            matching: find.text(tile.title),
          );
          final subtitle = find.descendant(
            of: target,
            matching: find.text(tile.subtitle!),
          );
          expect(tester.getTopLeft(title).dx, tester.getTopLeft(subtitle).dx);
          expect(tester.takeException(), isNull, reason: tile.title);
        }
        await tester.pumpWidget(const SizedBox());
      });
    }
  }
}
