import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:habit_app/pages/timer/game/dice_tray.dart';
import 'package:habit_app/pages/timer/game/party_face.dart';
import 'package:habit_app/pages/timer/game/table_stage_page.dart';
import 'package:habit_app/pages/timer/game/table_timer_models.dart';
import 'package:habit_app/utils/audio_settings_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> pumpPartyStage(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(1.3)),
        child: child ?? const SizedBox.shrink(),
      ),
      home: TableStagePage(config: TableTimerConfig.fallback()),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> unmountStage(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
}

void main() {
  setUp(() => AudioSettingsService.sfxMuted.value = true);
  tearDown(() => AudioSettingsService.sfxMuted.value = false);

  testWidgets('390×844 放大字體時，頂部骰子鈕不會壓到底部交棒 CTA', (tester) async {
    await pumpPartyStage(tester);

    final diceButton = find.byTooltip('骰子');
    final handoff = find.ancestor(
      of: find.text('點一下，開始遊戲'),
      matching: find.byType(AnimatedContainer),
    );
    expect(diceButton, findsOneWidget);
    expect(handoff, findsOneWidget);

    final diceRect = tester.getRect(diceButton);
    final handoffRect = tester.getRect(handoff);
    expect(diceRect.overlaps(handoffRect), isFalse);
    expect(diceRect.bottom, lessThanOrEqualTo(handoffRect.top));
    expect(tester.takeException(), isNull);

    await unmountStage(tester);
  });

  testWidgets('骰盤開啟時返回只收骰盤，不跳出結束確認', (tester) async {
    await pumpPartyStage(tester);

    await tester.tap(find.byTooltip('骰子'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 32));
    expect(find.byType(DiceTrayOverlay), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 32));

    expect(find.byType(DiceTrayOverlay), findsNothing);
    expect(find.byType(TableStagePage), findsOneWidget);
    expect(find.text('結束對局？'), findsNothing);
    expect(tester.takeException(), isNull);

    await unmountStage(tester);
  });

  testWidgets('準備畫面快速雙點只開始第一位，不會直接跳過玩家', (tester) async {
    await pumpPartyStage(tester);

    final passSurface = find.byType(PartyFace);
    await tester.tap(passSurface);
    await tester.tap(passSurface);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 32));

    expect(find.text('現在・玩家 1'), findsOneWidget);
    expect(find.text('現在・玩家 2'), findsNothing);
    expect(find.text('下一位：2 號 玩家 2'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await unmountStage(tester);
  });
}
