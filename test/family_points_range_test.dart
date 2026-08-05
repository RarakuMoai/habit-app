import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:habit_app/pages/family/family_models.dart';
import 'package:habit_app/pages/family/family_store.dart';
import 'package:habit_app/pages/family/family_widgets.dart';
import 'package:habit_app/pages/family/habit_sheets.dart';
import 'package:habit_app/pages/family/reward_sheets.dart';
import 'package:habit_app/pages/family_page.dart';
import 'package:habit_app/utils/prefs_keys.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'l10n_test_app.dart';

/// 分數上限的守門測試。
///
/// 這裡刻意測到接線層——真的把字打進面板、真的按儲存、再從 prefs 讀回來——
/// 而不是斷言 [kFamilyPointsMaxDigits] 等於幾。位數上限只是手段，要守住的事實是
/// 「家長設得出八位數的分數，而且它存得下來」。只驗常數的話，哪天欄位換成別的
/// formatter、或存檔路徑多一層 clamp，測試照樣全綠而功能是壞的。
///
/// 賺分與兌換價兩邊都測：分數是一整套互通的貨幣，只有一邊放寬等於沒放寬。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const bigPoints = 99999999; // 8 位數上限本身

  /// 面板裡唯一的數字欄位就是分數欄。
  final numberField = find.byWidgetPredicate(
    (widget) =>
        widget is TextField && widget.keyboardType == TextInputType.number,
  );

  /// 用一顆按鈕開面板：sheet 需要一個活著的 context，直接在 pumpWidget 裡呼叫
  /// 會拿到還沒掛上 Navigator 的那個。
  Future<void> openSheet(
    WidgetTester tester, {
    required String label,
    required void Function(BuildContext context) open,
  }) async {
    await tester.pumpWidget(
      l10nTestApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => open(context),
                child: Text(label),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
  }

  testWidgets('習慣分數存得下八位數', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final habit = ChildHabit(
      id: 'habit-1',
      childId: 'child-1',
      name: '整理書包',
      points: 10,
    );
    await saveHabits(prefs, [habit]);

    await openSheet(
      tester,
      label: '編輯習慣',
      open: (context) => unawaited(
        showEditHabitSheet(
          context,
          prefs: prefs,
          habit: habit,
          onSaved: () async {},
        ),
      ),
    );

    await tester.enterText(numberField, '$bigPoints');
    await tester.pumpAndSettle();
    await tester.tap(find.text('儲存'));
    await tester.pumpAndSettle();

    final saved = await loadHabits(prefs);
    expect(saved.single.points, bigPoints);
  });

  testWidgets('獎勵兌換價存得下八位數', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final reward = RewardItem(
      id: 'reward-1',
      name: '去動物園',
      pointsCost: 50,
      childIds: const ['child-1'],
    );
    await saveRewards(prefs, [reward]);

    await openSheet(
      tester,
      label: '編輯獎勵',
      open: (context) => unawaited(
        showEditRewardSheet(
          context,
          prefs: prefs,
          reward: reward,
          children: [ChildData(id: 'child-1', name: '小明', points: 0)],
          onSaved: () async {},
        ),
      ),
    );

    await tester.enterText(numberField, '$bigPoints');
    await tester.pumpAndSettle();
    await tester.tap(find.text('儲存'));
    await tester.pumpAndSettle();

    final saved = await loadRewards(prefs);
    expect(saved.single.pointsCost, bigPoints);
  });

  testWidgets('八位數分數在 SE 寬度的小孩卡不破版', (tester) async {
    SharedPreferences.setMockInitialValues({
      PrefsKeys.children: jsonEncode([
        {'id': 'child-1', 'name': '小兔', 'avatar': '🐰', 'points': bigPoints},
      ]),
    });
    tester.view.physicalSize = const Size(375, 667);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(l10nTestApp(home: const FamilyPage()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    // 放寬上限的代價要在最窄的機型上看得到：積分徽章是 Flexible + ellipsis，
    // 破版會以 RenderFlex overflow 例外出現，widget test 會直接判失敗。
    expect(find.text('$bigPoints'), findsOneWidget);
  });

  testWidgets('第九位數字打不進去：上限是真的存在，不是被拿掉了', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    await openSheet(
      tester,
      label: '編輯習慣',
      open: (context) => unawaited(
        showEditHabitSheet(
          context,
          prefs: prefs,
          habit: ChildHabit(
            id: 'habit-1',
            childId: 'child-1',
            name: '整理書包',
            points: 10,
          ),
          onSaved: () async {},
        ),
      ),
    );

    await tester.enterText(numberField, '999999999'); // 9 位
    await tester.pumpAndSettle();

    expect(
      tester.widget<TextField>(numberField).controller!.text.length,
      kFamilyPointsMaxDigits,
    );
  });
}
