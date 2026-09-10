import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:habit_app/l10n/app_localizations.dart';
import 'package:habit_app/pages/family_page.dart';
import 'package:habit_app/pages/timer_page.dart';
import 'package:habit_app/utils/app_style.dart';
import 'package:habit_app/utils/prefs_keys.dart';
import 'package:habit_app/widgets/app_pressable.dart';
import 'package:habit_app/widgets/timer_mode_frame.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'l10n_test_app.dart';

void main() {
  testWidgets('計時窄槽以分行保留 44pt 操作範圍，降低動態仍可操作', (tester) async {
    var started = 0;
    var reset = 0;
    await tester.pumpWidget(
      l10nTestApp(
        home: MediaQuery(
          data: const MediaQueryData(
            disableAnimations: true,
            textScaler: TextScaler.linear(1.3),
          ),
          child: Scaffold(
            body: Center(
              child: SizedBox(
                width: 144,
                height: TimerModeMetrics.controlsHeight,
                child: TimerControlCluster(
                  accent: AppPalette.focus,
                  primaryIcon: Icons.play_arrow_rounded,
                  onPrimary: () => started++,
                  leading: TimerSecondaryAction(
                    icon: Icons.replay_rounded,
                    label: '重設',
                    onTap: () => reset++,
                  ),
                  trailing: TimerSecondaryAction(
                    icon: Icons.skip_next_rounded,
                    label: '跳過',
                    onTap: () {},
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    for (final pressable in find.byType(AppPressable).evaluate()) {
      expect(
        tester.getSize(find.byWidget(pressable.widget)).height,
        greaterThanOrEqualTo(44),
      );
    }
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('開始')),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(
      tester
          .widgetList<AnimatedScale>(find.byType(AnimatedScale))
          .every((scale) => scale.scale == 1),
      isTrue,
    );
    await gesture.up();
    await tester.pump();
    await tester.tap(find.text('重設'));
    expect(started, 1);
    expect(reset, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('英文 320pt 大字四模式與 120 分鐘保持清楚且不重疊', (tester) async {
    SharedPreferences.setMockInitialValues({
      PrefsKeys.timerFocusProfileFocus(0): 120,
    });
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const MediaQuery(
          data: MediaQueryData(
            size: Size(320, 700),
            textScaler: TextScaler.linear(1.3),
            disableAnimations: true,
          ),
          child: TimerPage(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('120:00'), findsOneWidget);
    for (final mode in ['Focus', 'Workout', 'Metronome', 'Games']) {
      await tester.tap(find.text(mode));
      await tester.pump(const Duration(milliseconds: 300));
      final status = tester.getRect(find.byType(TimerStatusPill));
      final settings = tester.getRect(
        find.byKey(const ValueKey('timer-settings-action')),
      );
      expect(status.overlaps(settings), isFalse, reason: mode);
      expect(tester.takeException(), isNull, reason: mode);
    }
  });

  testWidgets('家庭名冊與子頁在 320pt、大字及八位積分仍可切換', (tester) async {
    const childName = '喜歡閱讀與畫畫的小朋友';
    SharedPreferences.setMockInitialValues({
      PrefsKeys.children: jsonEncode([
        {
          'id': 'child-long',
          'name': childName,
          'avatar': '🐰',
          'points': 99999999,
        },
      ]),
    });
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      l10nTestApp(
        home: const MediaQuery(
          data: MediaQueryData(
            size: Size(320, 700),
            disableAnimations: true,
            textScaler: TextScaler.linear(1.3),
          ),
          child: FamilyPage(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('99999999'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text(childName));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('99999999'), findsOneWidget);
    expect(find.text('積分紀錄'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('獎勵'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
  });
}
