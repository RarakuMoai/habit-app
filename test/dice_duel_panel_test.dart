// 骰子對決彩蛋：兩指長按偵測、像素窗簾進出場、root overlay 掛載。
// 物理擲骰的公平性/收斂已由 dice_world_test.dart 覆蓋，這裡不重測。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:habit_app/pages/timer/game/dice_tray.dart'
    show DiceWorldPainter;
import 'package:habit_app/pages/timer/game/dice_world.dart';
import 'package:habit_app/utils/mascot.dart';
import 'package:habit_app/widgets/dice_duel_panel.dart';
import 'package:habit_app/widgets/mascot_page_shell.dart';
import 'package:habit_app/widgets/mascot_scene.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'l10n_test_app.dart';

Widget _detectorHarness({
  required bool enabled,
  required VoidCallback onTrigger,
  bool threeFingerEnabled = true,
  VoidCallback? onThreeFingerTrigger,
}) {
  return l10nTestApp(
    home: TwoFingerEggDetector(
      enabled: enabled,
      onTrigger: onTrigger,
      threeFingerEnabled: threeFingerEnabled,
      onThreeFingerTrigger: onThreeFingerTrigger,
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

DiceWorld _diceWorld(WidgetTester tester) {
  final paint = find.byWidgetPredicate(
    (widget) => widget is CustomPaint && widget.painter is DiceWorldPainter,
  );
  final painter =
      tester.widget<CustomPaint>(paint).painter! as DiceWorldPainter;
  return painter.world;
}

void _makeCurrentDieSettle(DiceWorld world) {
  final die = world.dice.single;
  world.hasBeenThrown = true;
  world.wake();
  die
    ..vel = Offset.zero
    ..q = DiceQuat.identity()
    ..wx = 0
    ..wy = 0
    ..wz = 0
    ..tiltT = 0
    ..popT = 0;
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    MascotScenePointers.count.value = 0;
    MascotPanelPrefs.openValue.value = 1.0;
    MascotPersona.voiceMuted = true;
  });

  tearDown(() {
    MascotPersona.resetToOpening();
    MascotPersona.voiceMuted = false;
  });

  test('本次戰績只累加已結算局數，三種結果分開計算', () {
    final score = const DiceDuelSessionScore()
        .record(DiceDuelOutcome.playerWin)
        .record(DiceDuelOutcome.mascotWin)
        .record(DiceDuelOutcome.tie)
        .record(DiceDuelOutcome.playerWin);

    expect(
      score,
      const DiceDuelSessionScore(
        rounds: 4,
        playerWins: 2,
        mascotWins: 1,
        ties: 1,
      ),
    );
  });

  testWidgets('兩指靜止按滿 1.8 秒才觸發；單指不觸發、同一次觸控只觸發一次', (tester) async {
    var fired = 0;
    await tester.pumpWidget(
      _detectorHarness(enabled: true, onTrigger: () => fired++),
    );

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
    await tester.pumpWidget(
      _detectorHarness(enabled: true, onTrigger: () => fired++),
    );

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

  testWidgets('第三指落下改算三指長按，不沿用二指已累積時間', (tester) async {
    var twoFingerFired = 0;
    var threeFingerFired = 0;
    await tester.pumpWidget(
      _detectorHarness(
        enabled: true,
        onTrigger: () => twoFingerFired++,
        onThreeFingerTrigger: () => threeFingerFired++,
      ),
    );

    final a = await tester.createGesture(pointer: 31);
    final b = await tester.createGesture(pointer: 32);
    final c = await tester.createGesture(pointer: 33);
    await a.down(const Offset(100, 100));
    await b.down(const Offset(200, 100));
    await tester.pump(const Duration(milliseconds: 900));
    await c.down(const Offset(300, 100));

    // 從第三指落下重新起算；不會在原二指的 1.8 秒點觸發。
    await tester.pump(const Duration(milliseconds: 1000));
    expect(twoFingerFired, 0);
    expect(threeFingerFired, 0);
    await tester.pump(const Duration(milliseconds: 900));
    expect(twoFingerFired, 0);
    expect(threeFingerFired, 1);

    // 三指已觸發後即使放開一指，同 session 也不會再觸發二指。
    await c.up();
    await tester.pump(const Duration(seconds: 2));
    expect(twoFingerFired, 0);
    expect(threeFingerFired, 1);
    await a.up();
    await b.up();

    // 第四指會讓三指失格：彩蛋只接受 exact count。
    final d = await tester.createGesture(pointer: 34);
    final e = await tester.createGesture(pointer: 35);
    final f = await tester.createGesture(pointer: 36);
    final g = await tester.createGesture(pointer: 37);
    await d.down(const Offset(80, 100));
    await e.down(const Offset(160, 100));
    await f.down(const Offset(240, 100));
    await tester.pump(const Duration(milliseconds: 900));
    await g.down(const Offset(320, 100));
    await tester.pump(const Duration(seconds: 2));
    expect(twoFingerFired, 0);
    expect(threeFingerFired, 1);
    await d.up();
    await e.up();
    await f.up();
    await g.up();
  });

  testWidgets('二指已觸發後加入第三指，同 session 不再觸發三指', (tester) async {
    var twoFingerFired = 0;
    var threeFingerFired = 0;
    await tester.pumpWidget(
      _detectorHarness(
        enabled: true,
        onTrigger: () => twoFingerFired++,
        onThreeFingerTrigger: () => threeFingerFired++,
      ),
    );

    final a = await tester.createGesture(pointer: 41);
    final b = await tester.createGesture(pointer: 42);
    final c = await tester.createGesture(pointer: 43);
    await a.down(const Offset(100, 100));
    await b.down(const Offset(200, 100));
    await tester.pump(const Duration(milliseconds: 1900));
    expect(twoFingerFired, 1);

    await c.down(const Offset(300, 100));
    await tester.pump(const Duration(seconds: 2));
    expect(twoFingerFired, 1);
    expect(threeFingerFired, 0);
    await a.up();
    await b.up();
    await c.up();
  });

  testWidgets('enabled=false 時不觸發，但指數仍同步（充電互讓不失效）', (tester) async {
    var fired = 0;
    await tester.pumpWidget(
      _detectorHarness(enabled: false, onTrigger: () => fired++),
    );

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
      l10nTestApp(
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

    // 極簡 HUD：常駐本次戰績與唯一退出入口，沒有擲骰鈕或另開一局按鈕。
    expect(find.text('結束遊戲'), findsOneWidget);
    expect(find.text('本次 0 局'), findsOneWidget);
    expect(find.text('再來一場'), findsNothing);
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

  testWidgets('結果摘要使用改名後名稱，12 字長名稱在窄螢幕維持單行', (tester) async {
    const mascotName = '超級無敵可愛棉花糖兔兔寶';
    await tester.binding.setSurfaceSize(const Size(240, 180));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      l10nTestApp(
        home: const Scaffold(
          body: Padding(
            padding: EdgeInsets.all(20),
            child: DiceDuelResultSummary(
              outcome: DiceDuelOutcome.mascotWin,
              mascotName: mascotName,
              playerValue: 3,
              mascotValue: 6,
            ),
          ),
        ),
      ),
    );

    expect(find.text('$mascotName贏了！'), findsOneWidget);
    expect(find.text('你 3・$mascotName 6'), findsOneWidget);
    expect(find.text('兔咪贏了！'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('本次戰績支援改名與窄寬度，不把結束入口擠出畫面', (tester) async {
    const mascotName = '超級無敵可愛棉花糖兔兔寶';
    await tester.binding.setSurfaceSize(const Size(250, 120));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      l10nTestApp(
        home: const Scaffold(
          body: Padding(
            padding: EdgeInsets.all(12),
            child: DiceDuelScoreboard(
              score: DiceDuelSessionScore(
                rounds: 12,
                playerWins: 5,
                mascotWins: 4,
                ties: 3,
              ),
              mascotName: mascotName,
            ),
          ),
        ),
      ),
    );

    expect(find.text('本次 12 局'), findsOneWidget);
    expect(find.text('你 5 勝・$mascotName 4 勝・平手 3'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('結果後抓同一顆骰子無縫進下一局，保留落點朝向與本次戰績', (tester) async {
    await tester.pumpWidget(
      l10nTestApp(
        home: Scaffold(
          body: SizedBox(
            width: 390,
            height: 520,
            child: DiceDuelPanel(onClose: () {}),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(); // 初次取得骰盤 bounds 後置中。

    final world = _diceWorld(tester);
    _makeCurrentDieSettle(world);
    await tester.pump(const Duration(milliseconds: 40)); // 使用者點數定格。
    await tester.pump(const Duration(milliseconds: 1100)); // 角色開始擲。
    await tester.pump(const Duration(milliseconds: 40)); // 先讓 settle gate 重新武裝。
    _makeCurrentDieSettle(world);
    await tester.pump(const Duration(milliseconds: 40)); // 角色點數定格、完成一局。

    expect(find.byType(DiceDuelResultSummary), findsOneWidget);
    expect(find.text('本次 1 局'), findsOneWidget);
    expect(find.text('再來一場'), findsNothing);

    final dieBefore = world.dice.single;
    final positionBefore = dieBefore.pos;
    final orientationBefore = dieBefore.q.clone();
    final field = find.byKey(const ValueKey('dice-duel-physics-field'));
    final gesture = await tester.createGesture(pointer: 91);
    await gesture.down(tester.getTopLeft(field) + positionBefore);

    expect(
      identical(world.dice.single, dieBefore),
      isTrue,
      reason: '下一局必須沿用同一顆骰子',
    );
    expect(world.dice.single.pos, positionBefore, reason: '按下開始下一局時不能跳回中央');
    expect(world.dice.single.q.w, orientationBefore.w);
    expect(world.dice.single.q.x, orientationBefore.x);
    expect(world.dice.single.q.y, orientationBefore.y);
    expect(world.dice.single.q.z, orientationBefore.z);

    await tester.pump();
    expect(find.byType(DiceDuelResultSummary), findsNothing);
    expect(find.text('本次 1 局'), findsOneWidget, reason: '開始下一局不會先清空本次戰績');
    await gesture.up();
    await tester.pump();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getKeys(), isEmpty, reason: '骰子戰績只活在本次彩蛋，不得寫入偏好設定');

    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    await tester.pumpWidget(
      l10nTestApp(
        home: Scaffold(body: DiceDuelPanel(onClose: () {})),
      ),
    );
    await tester.pump();
    expect(find.text('本次 0 局'), findsOneWidget, reason: '關閉再進入後應從零開始');
    await tester.pumpWidget(const SizedBox());
    MascotPersona.resetToIdle(); // 結算台詞的 10 秒回神 timer 不應洩漏出測試。
  });

  testWidgets('shell：兩指長按場景把彩蛋掛上 root overlay，結束遊戲後移除', (tester) async {
    await tester.pumpWidget(
      l10nTestApp(
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

  testWidgets('shell：三指長按走獨立 callback，不會開啟骰子 overlay', (tester) async {
    var threeFingerFired = 0;
    await tester.pumpWidget(
      l10nTestApp(
        home: MascotPageShell(
          accent: Colors.orange,
          scene: const SizedBox.expand(),
          onThreeFingerEggTrigger: () => threeFingerFired++,
          child: const Text('功能卡'),
        ),
      ),
    );

    final origin = tester.getTopLeft(find.byType(MascotPageShell));
    final a = await tester.createGesture(pointer: 51);
    final b = await tester.createGesture(pointer: 52);
    final c = await tester.createGesture(pointer: 53);
    await a.down(origin + const Offset(100, 60));
    await b.down(origin + const Offset(200, 60));
    await tester.pump(const Duration(milliseconds: 900));
    await c.down(origin + const Offset(300, 60));
    await tester.pump(const Duration(milliseconds: 1900));

    expect(threeFingerFired, 1);
    expect(find.byType(DiceDuelEgg), findsNothing);
    await a.up();
    await b.up();
    await c.up();
    await tester.pumpWidget(const SizedBox());
  });
}
