import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:habit_app/pages/timer/game/dice_tray.dart';
import 'package:habit_app/utils/audio_settings_service.dart';
import 'package:habit_app/utils/prefs_keys.dart';
import 'package:shared_preferences/shared_preferences.dart';

Finder tappableForTooltip(String message) => find.descendant(
  of: find.byTooltip(message),
  matching: find.byType(InkWell),
);

Future<void> pumpDiceTray(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({PrefsKeys.gameTableDiceCount: 2});
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
      home: const DiceTrayPage(),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 16));
}

void main() {
  setUp(() => AudioSettingsService.sfxMuted.value = true);
  tearDown(() => AudioSettingsService.sfxMuted.value = false);

  testWidgets('390×844 放大字體下，骰子屋語意完整且按鈕至少 48px', (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      await pumpDiceTray(tester);

      expect(find.text('兔咪骰子屋'), findsOneWidget);
      expect(find.text('2 顆骰子'), findsOneWidget);
      expect(find.text('擲骰子'), findsOneWidget);
      expect(tester.takeException(), isNull);

      for (final label in [
        '回到遊戲，關閉骰子屋',
        '骰子顆數，目前 2 顆',
        '減少一顆骰子',
        '增加一顆骰子',
        '骰子遊戲區。可以按住骰子移動，放開手指甩出去。',
        '擲骰子，2 顆骰子',
      ]) {
        expect(
          find.bySemanticsLabel(RegExp(RegExp.escape(label))),
          findsWidgets,
        );
      }

      for (final tooltip in [
        '關閉骰子屋，回到遊戲',
        '減少一顆骰子',
        '增加一顆骰子',
        '擲骰子，擲出 2 顆骰子',
      ]) {
        final target = tappableForTooltip(tooltip);
        expect(target, findsOneWidget);
        expect(
          tester.getSize(target).shortestSide,
          greaterThanOrEqualTo(48),
          reason: '$tooltip 的觸控區至少要有 48px',
        );
      }
    } finally {
      semantics.dispose();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    }
  });
}
