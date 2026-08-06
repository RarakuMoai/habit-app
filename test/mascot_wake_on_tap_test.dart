// 有動作就醒來（2026-08-06）。
//
// 回報：「我點兔咪，兔咪變成睡覺圖案」。
//
// 成因：點擊的反應演出收尾會 `_applyPersona(_baselineMascotContext, force: true)`，
// 而零進度白天的 baseline 立繪是 `sleep`。所以點一下、三秒後兔咪就睡著——
// 使用者做了動作，角色卻睡回去。
//
// 規則見 `docs/tumi_dialogue_catalog.md` §互動之後回到哪：碰過之後零進度改用
// 中性臉，**只換立繪不換情境**（台詞仍是 notStarted 那組），夜晚不受影響，
// 跨日重置會清掉。
//
// ⚠️ 場景時間要固定住：不固定的話，測試在 22:00–06:00 執行會走 night 分支，
// 變成假綠燈。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:habit_app/main.dart';
import 'package:habit_app/pages/home_page.dart';
import 'package:habit_app/utils/mascot.dart';
import 'package:habit_app/utils/scene_time.dart';
import 'package:habit_app/widgets/mascot_scene.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'l10n_test_app.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    MascotPersona.voiceMuted = true;
    SharedPreferences.setMockInitialValues({
      'flutter.onboarding_done': true,
      // 一個沒完成的習慣 → 零進度，baseline 才會落到 notStarted。
      'flutter.habits':
          '[{"id":"h1","name":"走路","createdAt":"2026-08-06",'
          '"done":false,"frequency":"daily"}]',
    });
  });

  tearDown(() {
    MascotPersona.resetToIdle();
    MascotPersona.voiceMuted = false;
    SceneTimeController.debugInstance = null;
  });

  void fixSceneHour(int hour) {
    SceneTimeController.debugInstance = SceneTimeController(
      clock: () => DateTime(2026, 8, 6, hour),
    );
  }

  Future<void> drainMain(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 3));
  }

  Future<dynamic> pumpHome(WidgetTester tester) async {
    tester.view.physicalSize = const Size(430, 1500);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(l10nTestApp(home: const MainPage()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    return tester.state(find.byType(HomePage)) as dynamic;
  }

  testWidgets('白天零進度、還沒碰過 → baseline 是打瞌睡', (tester) async {
    fixSceneHour(13);
    final home = await pumpHome(tester);

    expect(
      home.debugBaselineMascotAsset,
      MascotEmotion.sleep.assetPath,
      reason: '「懶懶等你」是這一天還沒被碰過時的姿勢',
    );

    await drainMain(tester);
  });

  testWidgets('點兔咪之後 baseline 不再是睡覺', (tester) async {
    fixSceneHour(13);
    final home = await pumpHome(tester);
    expect(home.debugBaselineMascotAsset, MascotEmotion.sleep.assetPath);

    // 先 pump 一次再點：MascotStage 的手勢要等第一幀掛上去。
    await tester.pump();
    await tester.tap(find.byType(MascotStage));
    await tester.pump();
    // 撐過點擊台詞那條 3 秒 expiry——原本就是它把兔咪送回睡覺的。
    await tester.pump(const Duration(seconds: 4));

    expect(
      home.debugBaselineMascotAsset,
      isNot(MascotEmotion.sleep.assetPath),
      reason: '使用者做了動作，角色不該睡回去',
    );
    expect(
      home.debugBaselineMascotAsset,
      MascotEmotion.neutralFront.assetPath,
      reason: '醒來用會眨眼的中性臉',
    );

    await drainMain(tester);
  });

  testWidgets('只換立繪，情境仍是 notStarted（台詞不變）', (tester) async {
    fixSceneHour(13);
    final home = await pumpHome(tester);

    await tester.pump();
    await tester.tap(find.byType(MascotStage));
    await tester.pump();
    await tester.pump(const Duration(seconds: 4));

    expect(
      home.debugBaselineMascotContext,
      MascotContext.notStarted,
      reason: '「還沒開始也沒關係」那組台詞照舊，醒來只影響立繪',
    );

    await drainMain(tester);
  });

  testWidgets('夜晚不受影響，仍是 night', (tester) async {
    fixSceneHour(23);
    final home = await pumpHome(tester);
    expect(home.debugBaselineMascotAsset, MascotEmotion.night.assetPath);

    await tester.pump();
    await tester.tap(find.byType(MascotStage));
    await tester.pump();
    await tester.pump(const Duration(seconds: 4));

    expect(
      home.debugBaselineMascotAsset,
      MascotEmotion.night.assetPath,
      reason: '夜晚是「真的該睡了」，碰一下不該把它變成白天的中性臉',
    );

    await drainMain(tester);
  });
}
