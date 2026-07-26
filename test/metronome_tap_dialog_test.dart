// TAP 抓節奏：獨立視窗內預覽、按「套用」才改 BPM；取消完全不動設定。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:habit_app/pages/timer/metronome_timer.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'l10n_test_app.dart';

void main() {
  testWidgets('TAP 開獨立測速視窗，取消不改、套用才改 BPM', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      l10nTestApp(
        home: const Scaffold(
          body: Center(
            child: SizedBox(height: 620, width: 400, child: MetronomeTimer()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('120 BPM'), findsOneWidget); // 預設值

    // 開視窗：主畫面 BPM 不會被 TAP 直接洗掉。
    await tester.tap(find.text('TAP'));
    await tester.pumpAndSettle();
    expect(find.text('TAP 抓節奏'), findsOneWidget);
    expect(find.text('點我抓拍'), findsOneWidget);

    // 取消：什麼都不改。
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(find.text('TAP 抓節奏'), findsNothing);
    expect(find.text('120 BPM'), findsOneWidget);

    // 重開後連點三下（測試中壁鐘間隔極短 → 會夾到上限 240），
    // 預覽只顯示在視窗內，按「套用」才寫回主畫面。
    await tester.tap(find.text('TAP'));
    await tester.pumpAndSettle();
    final pad = find.byKey(const ValueKey('tap-tempo-pad'));
    await tester.tap(pad);
    await tester.pump();
    await tester.tap(pad);
    await tester.pump();
    await tester.tap(pad);
    await tester.pump();
    expect(find.text('套用 240 BPM'), findsOneWidget);
    expect(find.text('120 BPM'), findsOneWidget); // 主畫面還是舊值

    await tester.tap(find.text('套用 240 BPM'));
    await tester.pumpAndSettle();
    expect(find.text('TAP 抓節奏'), findsNothing);
    expect(find.text('240 BPM'), findsOneWidget);
    expect(find.text('120 BPM'), findsNothing);
  });
}
