// 骰子對決彩蛋：兩指長按偵測、像素窗簾進出場、root overlay 掛載。
// 物理擲骰的公平性/收斂已由 dice_world_test.dart 覆蓋，這裡不重測。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:habit_app/utils/mascot.dart';
import 'package:habit_app/widgets/dice_duel_panel.dart';
import 'package:habit_app/widgets/mascot_page_shell.dart';
import 'package:habit_app/widgets/mascot_scene.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _detectorHarness({
  required bool enabled,
  required VoidCallback onTrigger,
}) {
  return MaterialApp(
    home: TwoFingerEggDetector(
      enabled: enabled,
      onTrigger: onTrigger,
      child: const ColoredBox(color: Colors.white, child: SizedBox.expand()),
    ),
  );
}

/// 走完像素窗簾的「蓋滿 → 換景 → 退去」一段（0.55s + 0.55s）。
Future<void> _pumpCurtainCycle(WidgetTester tester) async {
  await tester.pump(); // 窗簾動畫 t0
  await tester.pump(const Duration(milliseconds: 600)); // 蓋滿、換景
  await tester.pump(); // 退簾 t0
  await tester.pump(const Duration(milliseconds: 600)); // 退完
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    MascotScenePointers.count.value = 0;
    MascotPanelPrefs.openValue.value = 1.0;
  });

  testWidgets('兩指靜止按滿 1.8 秒才觸發；單指不觸發、同一次觸控只觸發一次', (tester) async {
    var fired = 0;
    await tester.pumpWidget(_detectorHarness(enabled: true, onTrigger: () => fired++));

    // 單指按滿不觸發。
    final single = await tester.createGesture(pointer: 7);
    await single.down(const Offset(100, 100));
    await tester.pump(const Duration(seconds: 2));
    expect(fired, 0);
    await single.up();

    // 兩指按住：指數同步、滿 1.8 秒觸發一次。
    final a = await tester.createGesture(pointer: 8);
    final b = await tester.createGesture(pointer: 9);
    await a.down(const Offset(120, 100));
    await b.down(const Offset(240, 100));
    expect(MascotScenePointers.count.value, 2);
    await tester.pump(const Duration(milliseconds: 1700));
    expect(fired, 0); // 還沒按滿
    await tester.pump(const Duration(milliseconds: 200));
    expect(fired, 1);
    // 手指沒放開不重複觸發。
    await tester.pump(const Duration(seconds: 2));
    expect(fired, 1);
    await a.up();
    await b.up();
    expect(MascotScenePointers.count.value, 0);
  });

  testWidgets('手指滑動或第三指落下都取消觸發', (tester) async {
    var fired = 0;
    await tester.pumpWidget(_detectorHarness(enabled: true, onTrigger: () => fired++));

    // 一指滑走超過容忍值 → 失格。
    final a = await tester.createGesture(pointer: 8);
    final b = await tester.createGesture(pointer: 9);
    await a.down(const Offset(120, 100));
    await b.down(const Offset(240, 100));
    await a.moveBy(const Offset(40, 0));
    await tester.pump(const Duration(seconds: 2));
    expect(fired, 0);
    await a.up();
    await b.up();

    // 第三指落下 → 取消。
    final c = await tester.createGesture(pointer: 10);
    final d = await tester.createGesture(pointer: 11);
    final e = await tester.createGesture(pointer: 12);
    await c.down(const Offset(100, 100));
    await d.down(const Offset(200, 100));
    await tester.pump(const Duration(milliseconds: 900));
    await e.down(const Offset(300, 100));
    await tester.pump(const Duration(seconds: 2));
    expect(fired, 0);
    await c.up();
    await d.up();
    await e.up();
  });

  testWidgets('enabled=false 時不觸發，但指數仍同步（充電互讓不失效）', (tester) async {
    var fired = 0;
    await tester.pumpWidget(_detectorHarness(enabled: false, onTrigger: () => fired++));

    final a = await tester.createGesture(pointer: 8);
    final b = await tester.createGesture(pointer: 9);
    await a.down(const Offset(120, 100));
    await b.down(const Offset(240, 100));
    expect(MascotScenePointers.count.value, 2);
    await tester.pump(const Duration(seconds: 2));
    expect(fired, 0);
    await a.up();
    await b.up();
    expect(MascotScenePointers.count.value, 0);
  });

  testWidgets('彩蛋演出：窗簾蓋滿才換景，無擲骰鈕與教學文字，結束遊戲跑完退場才回呼', (tester) async {
    var closed = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: DiceDuelEgg(onClosed: () => closed = true)),
      ),
    );

    // 窗簾蓋滿前骰盤還沒掛上。
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(DiceDuelPanel), findsNothing);
    await tester.pump(const Duration(milliseconds: 300)); // 蓋滿、換景
    expect(find.byType(DiceDuelPanel), findsOneWidget);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600)); // 退簾

    // 極簡 HUD：只有功能按鍵，沒有擲骰鈕、沒有教學文字。
    expect(find.text('結束遊戲'), findsOneWidget);
    expect(find.text('擲骰子'), findsNothing);
    expect(find.textContaining('甩'), findsNothing);

    await tester.tap(find.text('結束遊戲'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600)); // 蓋滿、卸下骰盤
    expect(find.byType(DiceDuelPanel), findsNothing);
    expect(closed, isFalse); // 窗簾還沒退完
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600)); // 退完
    expect(closed, isTrue);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('shell：兩指長按場景把彩蛋掛上 root overlay，結束遊戲後移除', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MascotPageShell(
          accent: Colors.orange,
          scene: const SizedBox.expand(),
          child: const Text('功能卡'),
        ),
      ),
    );

    final origin = tester.getTopLeft(find.byType(MascotPageShell));
    final a = await tester.createGesture(pointer: 21);
    final b = await tester.createGesture(pointer: 22);
    await a.down(origin + const Offset(150, 60));
    await b.down(origin + const Offset(300, 60));
    await tester.pump(const Duration(milliseconds: 1900));
    await a.up();
    await b.up();
    await tester.pump();
    expect(find.byType(DiceDuelEgg), findsOneWidget);

    // 走完開場窗簾後收掉。
    await _pumpCurtainCycle(tester);
    await tester.tap(find.text('結束遊戲'));
    await _pumpCurtainCycle(tester);
    expect(find.byType(DiceDuelEgg), findsNothing);

    await tester.pumpWidget(const SizedBox());
  });
}
