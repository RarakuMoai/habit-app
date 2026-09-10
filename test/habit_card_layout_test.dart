// 完成與未完成保留相同的掃讀高度；兩行名稱及連動副標也必須讓打卡圓圈置中。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:habit_app/l10n/app_localizations.dart';
import 'package:habit_app/pages/home/habit_card.dart';
import 'package:habit_app/utils/app_theme.dart';

void main() {
  for (final width in [320.0, 430.0]) {
    for (final linked in [false, true]) {
      for (final done in [false, true]) {
        testWidgets('打卡圓圈垂直置中 width=$width linked=$linked done=$done', (
          tester,
        ) async {
          tester.view.physicalSize = Size(width, 667);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          await tester.pumpWidget(
            MaterialApp(
              locale: const Locale('zh', 'TW'),
              theme: buildAppTheme(),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: Scaffold(
                body: Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: HabitCard(
                      habit: {
                        'name': '測試習慣',
                        'done': done,
                        'frequency': 'daily',
                      },
                      onToggle: () {},
                      onEdit: () {},
                      onDelete: () {},
                      isLinked: linked,
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final circle = tester.getRect(
            find
                .descendant(
                  of: find.byType(ListTile),
                  matching: find.byWidgetPredicate(
                    (w) => w is AnimatedContainer,
                  ),
                )
                .first,
          );
          final tile = tester.getRect(find.byType(ListTile));
          expect(circle.height, 32);
          expect(tile.height, greaterThanOrEqualTo(72));
          expect(
            (circle.center.dy - tile.center.dy).abs(),
            lessThan(1),
            reason: '完成、未完成與連動卡都應對齊實際卡片中心',
          );
          expect(tester.takeException(), isNull);
        });
      }
    }
  }
}
