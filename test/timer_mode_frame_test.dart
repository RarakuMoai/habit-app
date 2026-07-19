import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:habit_app/widgets/timer_mode_frame.dart';

void main() {
  Widget harness(ValueNotifier<double> height) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: ValueListenableBuilder<double>(
            valueListenable: height,
            builder: (context, value, _) => SizedBox(
              width: 400,
              height: value,
              child: TimerModeFrame(
                heroBuilder: (_, size) => SizedBox.square(
                  key: const ValueKey('hero'),
                  dimension: size,
                  child: const ColoredBox(color: Colors.orange),
                ),
                status: const Text('狀態'),
                progress: const Text('進度'),
                controls: const Text('控制'),
                quickPicker: const Text('快速設定'),
                statusLine: const Text('摘要'),
                footer: const Text('統計'),
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
  }

  testWidgets('完整、緊湊、超緊湊版維持一致資訊層級且不溢出', (tester) async {
    final height = ValueNotifier<double>(600);
    addTearDown(height.dispose);

    await tester.pumpWidget(harness(height));
    expect(find.text('摘要'), findsOneWidget);
    expect(find.text('快速設定'), findsOneWidget);
    expect(find.text('統計'), findsOneWidget);
    expect(find.byKey(const ValueKey('timer-settings-action')), findsOneWidget);
    expect(tester.takeException(), isNull);

    height.value = 340;
    await tester.pumpAndSettle();
    expect(find.text('快速設定'), findsOneWidget);
    expect(find.text('摘要'), findsNothing);
    expect(find.text('統計'), findsNothing);
    expect(find.byKey(const ValueKey('timer-settings-action')), findsOneWidget);
    expect(tester.takeException(), isNull);

    height.value = 180;
    await tester.pumpAndSettle();
    expect(find.text('狀態'), findsOneWidget);
    expect(find.text('進度'), findsOneWidget);
    expect(find.text('控制'), findsOneWidget);
    expect(find.text('快速設定'), findsNothing);
    expect(find.text('統計'), findsNothing);
    expect(find.byKey(const ValueKey('timer-settings-action')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('完整版的共用槽位使用固定高度', (tester) async {
    final height = ValueNotifier<double>(600);
    addTearDown(height.dispose);

    await tester.pumpWidget(harness(height));

    double slotHeight(String name) =>
        tester.getSize(find.byKey(ValueKey('timer-mode-$name-slot'))).height;

    expect(slotHeight('status'), TimerModeMetrics.statusHeight);
    expect(slotHeight('progress'), TimerModeMetrics.progressHeight);
    expect(slotHeight('controls'), TimerModeMetrics.controlsHeight);
    expect(slotHeight('status-line'), TimerModeMetrics.statusLineHeight);
    expect(slotHeight('quick-picker'), TimerModeMetrics.quickPickerHeight);
    expect(slotHeight('footer'), TimerModeMetrics.footerHeight);
  });

  testWidgets('不同文字長度的狀態膠囊維持同尺寸', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Row(
            children: [
              TimerStatusPill(
                stateKey: 'short',
                color: Colors.orange,
                icon: Icons.timer_rounded,
                label: '準備',
              ),
              TimerStatusPill(
                stateKey: 'long',
                color: Colors.purple,
                icon: Icons.graphic_eq_rounded,
                label: '節拍播放中',
              ),
            ],
          ),
        ),
      ),
    );

    final pills = tester.widgetList<SizedBox>(
      find.descendant(
        of: find.byType(TimerStatusPill),
        matching: find.byType(SizedBox),
      ),
    );
    final fixed = pills.where(
      (pill) => pill.width == TimerModeMetrics.statusWidth,
    );
    expect(fixed.length, 2);
    expect(fixed.every((pill) => pill.height == 34), isTrue);
  });
}
