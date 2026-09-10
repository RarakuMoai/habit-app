import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:habit_app/widgets/app_pressable.dart';
import 'package:habit_app/widgets/timer_mode_frame.dart';

import 'l10n_test_app.dart';

void main() {
  Widget harness(Size size) => l10nTestApp(
    home: MediaQuery(
      data: const MediaQueryData(
        textScaler: TextScaler.linear(1.3),
        disableAnimations: true,
      ),
      child: Scaffold(
        body: Center(
          child: SizedBox.fromSize(
            size: size,
            child: TimerModeFrame(
              compactReadout: const TimerCompactReadout(
                value: '120:00',
                color: Colors.orange,
              ),
              heroBuilder: (_, size) => SizedBox.square(
                key: const ValueKey('hero'),
                dimension: size,
                child: const ColoredBox(color: Colors.orange),
              ),
              status: const TimerStatusPill(
                stateKey: 'ready',
                color: Colors.orange,
                icon: Icons.timer_rounded,
                label: '準備開始',
              ),
              progress: const SizedBox(height: 12, child: Text('進度')),
              controls: TimerControlCluster(
                accent: Colors.orange,
                primaryIcon: Icons.play_arrow_rounded,
                onPrimary: () {},
                leading: TimerSecondaryAction(
                  icon: Icons.replay_rounded,
                  label: '重設',
                  onTap: () {},
                ),
                trailing: TimerSecondaryAction(
                  icon: Icons.skip_next_rounded,
                  label: '跳過',
                  onTap: () {},
                ),
              ),
              quickPicker: const SizedBox(
                height: 64,
                child: Center(child: Text('快速設定')),
              ),
              statusLine: const Text('這一段是真實高度的摘要，可以換行呈現，不再被固定高度裁切。'),
              footer: const SizedBox(height: 50, child: Text('統計')),
              topAction: TimerSettingsAction(
                color: Colors.orange,
                onTap: () {},
              ),
            ),
          ),
        ),
      ),
    ),
  );

  for (final (size, summary) in [
    (const Size(320, 123), true),
    (const Size(430, 278), false),
    (const Size(320, 353), false),
    (const Size(430, 581), false),
    (const Size(360, 250), true),
    (const Size(390, 240), true),
  ]) {
    testWidgets('$size 主要操作維持尺寸，次要內容可捲至', (tester) async {
      await tester.pumpWidget(harness(size));
      final primary = find.byKey(const ValueKey('timer-primary-action'));
      final frameRect = tester.getRect(find.byType(TimerModeFrame));
      expect(primary.hitTestable(), findsOneWidget);
      expect(tester.getSize(primary).height, greaterThanOrEqualTo(52));
      expect(
        tester.getRect(primary).bottom,
        lessThanOrEqualTo(frameRect.bottom),
      );
      expect(
        find.byKey(const ValueKey('timer-settings-action')).hitTestable(),
        findsOneWidget,
      );
      for (final element in find.byType(AppPressable).evaluate()) {
        expect(
          tester.getSize(find.byWidget(element.widget)).height,
          greaterThanOrEqualTo(44),
        );
      }
      if (summary) {
        expect(find.byKey(const ValueKey('hero')), findsNothing);
        expect(find.text('120:00'), findsOneWidget);
      } else {
        final hero = tester.getRect(find.byKey(const ValueKey('hero')));
        expect(hero.width, greaterThanOrEqualTo(size.height < 350 ? 104 : 176));
        if (size.width == 430 && size.height == 278) {
          final quick = tester.getRect(
            find.byKey(const ValueKey('timer-mode-quick-picker-slot')),
          );
          expect(quick.bottom, lessThanOrEqualTo(frameRect.bottom));
        }
        expect(hero.left, greaterThanOrEqualTo(frameRect.left + 18));
      }
      final footer = find.text('統計');
      await tester.ensureVisible(footer);
      await tester.pump();
      expect(footer.hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('狀態依真實可用寬度排版，不與設定重疊也不縮小字型', (tester) async {
    await tester.pumpWidget(harness(const Size(320, 353)));
    final status = tester.getRect(find.byType(TimerStatusPill));
    final settings = tester.getRect(
      find.byKey(const ValueKey('timer-settings-action')),
    );
    expect(status.overlaps(settings), isFalse);
    expect(status.height, 44);
    expect(
      find.descendant(
        of: find.byType(TimerStatusPill),
        matching: find.byType(FittedBox),
      ),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });
}
