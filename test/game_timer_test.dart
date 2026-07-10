import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:habit_app/pages/timer/game_timer.dart';
import 'package:habit_app/utils/audio_settings_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> pumpGameTimer(
  WidgetTester tester, {
  required Size size,
  double textScale = 1,
}) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child ?? const SizedBox.shrink(),
      ),
      home: const Scaffold(body: GameTimer()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => AudioSettingsService.sfxMuted.value = true);
  tearDown(() => AudioSettingsService.sfxMuted.value = false);

  testWidgets('快速入口在窄高度仍清楚且有核心 Semantics', (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      await pumpGameTimer(tester, size: const Size(390, 360), textScale: 1.3);

      expect(tester.takeException(), isNull);
      expect(find.text('兔咪遊戲桌'), findsOneWidget);
      expect(find.text('開始遊戲'), findsOneWidget);
      expect(find.text('只骰骰子'), findsOneWidget);
      expect(find.text('調整設定'), findsWidgets);
      expect(find.bySemanticsLabel('用目前設定開始遊戲'), findsWidgets);
      expect(find.bySemanticsLabel('只骰骰子'), findsWidgets);
      expect(find.bySemanticsLabel('調整玩法、人數和時間'), findsWidgets);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('390×844 放大字體時完整設定與底部操作列不 overflow', (tester) async {
    await pumpGameTimer(tester, size: const Size(390, 844), textScale: 1.3);

    expect(tester.takeException(), isNull);
    expect(find.text('收好設定'), findsOneWidget);
    expect(find.text('骰子'), findsOneWidget);
    expect(find.text('開始遊戲'), findsOneWidget);

    final setupList = find.byType(ListView).first;
    for (var i = 0; i < 8; i++) {
      await tester.drag(setupList, const Offset(0, -360));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
    expect(find.text('收藏這組玩法'), findsOneWidget);
  });
}
