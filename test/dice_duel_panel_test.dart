// 骰子對決彩蛋：兩指長按偵測與面板基本行為。
// 物理擲骰的公平性/收斂已由 dice_world_test.dart 覆蓋，這裡不重測。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:habit_app/widgets/dice_duel_panel.dart';
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

void main() {
  setUp(() {
    MascotScenePointers.count.value = 0;
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

  testWidgets('對決面板：進場是玩家回合，收起跑完退場動畫回呼 onClosed', (tester) async {
    SharedPreferences.setMockInitialValues({});
    var closed = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: DiceDuelPanel(onClosed: () => closed = true)),
      ),
    );
    await tester.pump(const Duration(milliseconds: 350)); // 進場動畫

    expect(find.textContaining('換你'), findsOneWidget);
    expect(find.text('擲骰子'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pump(); // 退場動畫起跑（第一幀只建立動畫起始時間）
    await tester.pump(const Duration(milliseconds: 200));
    expect(closed, isFalse); // 退場動畫還在跑
    await tester.pump(const Duration(milliseconds: 200));
    expect(closed, isTrue);

    // 卸載後 ticker / timer 不殘留（flutter_test 會自動驗證）。
    await tester.pumpWidget(const SizedBox());
  });
}
