import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:habit_app/pages/timer_page.dart';
import 'package:habit_app/utils/mascot.dart';
import 'package:habit_app/utils/prefs_keys.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _NoopNotificationsPlatform extends FlutterLocalNotificationsPlatform {}

void main() {
  testWidgets('四種計時模式共用版型可切換且沒有版面例外', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MaterialApp(home: TimerPage()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('準備開始'), findsOneWidget);
    expect(find.text('設定'), findsOneWidget);
    expect(find.text('經典'), findsOneWidget);
    expect(find.text('深度'), findsOneWidget);
    expect(find.text('輕量'), findsOneWidget);
    expect(find.text('自訂'), findsOneWidget);
    expect(find.textContaining('番茄'), findsNothing);
    expect(find.text('今日完成'), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('深度'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('50:00'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.tune_rounded));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('專注計時設定'), findsOneWidget);
    expect(find.text('時間與回合'), findsOneWidget);
    expect(find.text('恢復「深度」初始值'), findsOneWidget);
    expect(find.textContaining('番茄'), findsNothing);

    await tester.tap(find.byIcon(Icons.add_rounded).first);
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('51 分'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '長讀');
    await tester.pump(const Duration(milliseconds: 250));
    await tester.ensureVisible(find.text('恢復「深度」初始值'));
    await tester.tap(find.text('恢復「深度」初始值'));
    await tester.pumpAndSettle();
    expect(find.text('恢復「深度」初始值？'), findsOneWidget);
    expect(find.textContaining('「長讀」的名稱'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(find.text('51 分'), findsOneWidget);

    await tester.ensureVisible(find.text('恢復「深度」初始值'));
    await tester.tap(find.text('恢復「深度」初始值'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('確認恢復'));
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('50 分'), findsOneWidget);

    tester.testTextInput.hide();
    await tester.pump();
    await tester.ensureVisible(find.text('完成'));
    await tester.tap(find.text('完成'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('深度'), findsOneWidget);
    expect(find.text('50:00'), findsOneWidget);

    await tester.tap(find.text('運動'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Tabata'), findsWidgets);
    expect(find.text('今天還沒動，選個模式開始吧'), findsNothing);
    expect(find.text('今日運動'), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('節拍器'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('準備節拍'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('遊戲'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('準備開局'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('專注與運動設定可在面板內直接切換要編輯的類別', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MaterialApp(home: TimerPage()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    Finder sheetText(String text) => find.descendant(
      of: find.byType(BottomSheet),
      matching: find.text(text),
    );
    Finder focusProfile(String text) => find.descendant(
      of: find.byKey(const ValueKey('focus-settings-profile-picker')),
      matching: find.text(text),
    );
    Finder exerciseKind(String text) => find.descendant(
      of: find.byKey(const ValueKey('exercise-settings-kind-picker')),
      matching: find.text(text),
    );

    await tester.tap(
      find.byKey(const ValueKey('timer-settings-action')).hitTestable(),
    );
    await tester.pumpAndSettle();
    expect(sheetText('專注方案'), findsOneWidget);
    for (final label in ['經典', '深度', '輕量', '自訂']) {
      expect(focusProfile(label), findsOneWidget);
    }

    await tester.tap(focusProfile('深度').hitTestable());
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('50 分'), findsOneWidget);
    await tester.tap(sheetText('完成').hitTestable());
    await tester.pumpAndSettle();
    expect(find.text('50:00'), findsOneWidget);

    await tester.tap(find.text('運動'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(
      find.byKey(const ValueKey('timer-settings-action')).hitTestable(),
    );
    await tester.pumpAndSettle();
    expect(sheetText('運動類別'), findsOneWidget);
    for (final label in ['Tabata', 'HIIT', 'EMOM', '重訓', '超慢跑']) {
      expect(exerciseKind(label), findsOneWidget);
    }

    await tester.tap(exerciseKind('HIIT').hitTestable());
    await tester.pump(const Duration(milliseconds: 300));
    expect(sheetText('HIIT 設定'), findsOneWidget);
    await tester.tap(sheetText('完成').hitTestable());
    await tester.pumpAndSettle();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt(PrefsKeys.timerSelectedPreset), 1);
    expect(prefs.getString(PrefsKeys.exerciseSubMode), 'hiit');
    expect(tester.takeException(), isNull);
  });

  testWidgets('四種計時模式的共用槽位維持同一垂直基準', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MaterialApp(home: TimerPage()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    double slotCenter(String name) {
      final slot = find.byKey(ValueKey('timer-mode-$name-slot'));
      expect(slot, findsOneWidget);
      return tester.getCenter(slot).dy;
    }

    final baseline = <String, double>{
      for (final name in ['status', 'progress', 'controls', 'quick-picker'])
        name: slotCenter(name),
    };

    for (final mode in ['運動', '節拍器', '遊戲']) {
      await tester.tap(find.text(mode));
      await tester.pump(const Duration(milliseconds: 300));
      for (final entry in baseline.entries) {
        expect(
          slotCenter(entry.key),
          closeTo(entry.value, 1.5),
          reason: '$mode 的 ${entry.key} 槽位應與專注對齊',
        );
      }
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('快捷方案可獨立改名與改時間', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MaterialApp(home: TimerPage()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    await tester.tap(find.byIcon(Icons.tune_rounded));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.enterText(find.byType(TextField), '閱讀');
    FocusManager.instance.primaryFocus?.unfocus();
    tester.testTextInput.hide();
    await tester.pumpAndSettle();
    final focusAdd = find.byIcon(Icons.add_rounded).first;
    await tester.scrollUntilVisible(
      focusAdd,
      120,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(focusAdd);
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('26 分'), findsOneWidget);
    final close = find.byIcon(Icons.close_rounded);
    await tester.ensureVisible(close);
    await tester.tap(close);
    await tester.pumpAndSettle();

    expect(find.text('閱讀'), findsOneWidget);
    expect(find.text('26:00'), findsOneWidget);

    await tester.tap(find.text('深度'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('50:00'), findsOneWidget);

    await tester.tap(find.text('閱讀'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('26:00'), findsOneWidget);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(PrefsKeys.timerFocusProfileName(0)), '閱讀');
    expect(prefs.getInt(PrefsKeys.timerFocusProfileFocus(0)), 26);
    expect(prefs.getInt(PrefsKeys.timerFocusProfileFocus(1)), 50);
    expect(tester.takeException(), isNull);
  });

  testWidgets('刪除方案名稱後以淡色顯示預設名稱', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MaterialApp(home: TimerPage()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.byIcon(Icons.tune_rounded));
    await tester.pump(const Duration(milliseconds: 500));

    final nameField = find.byType(TextFormField);
    await tester.enterText(find.byType(TextField), '');
    await tester.pump();

    final defaultHint = find.descendant(
      of: nameField,
      matching: find.text('經典'),
    );
    expect(defaultHint, findsOneWidget);
    expect(
      tester.widget<Text>(defaultHint).style?.color,
      const Color(0xFFD7CCC5),
    );
    expect(find.text('留空時會顯示預設名稱'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('三個計時設定以底緣霧化與箭頭引導捲動', (tester) async {
    SharedPreferences.setMockInitialValues({PrefsKeys.exerciseSubMode: 'jog'});
    tester.view.physicalSize = const Size(390, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MaterialApp(home: TimerPage()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.byIcon(Icons.tune_rounded));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    final continuation = find.byKey(const ValueKey('scroll-continuation-cue'));
    expect(find.byType(Scrollbar), findsNothing);
    expect(tester.widget<AnimatedOpacity>(continuation).opacity, 1);
    expect(find.byIcon(Icons.keyboard_arrow_down_rounded), findsOneWidget);
    expect(find.textContaining('往下滑'), findsNothing);

    await tester.drag(
      find.byKey(const ValueKey('scroll-continuation-view')),
      const Offset(0, -1600),
    );
    await tester.pump(const Duration(milliseconds: 300));

    expect(tester.widget<AnimatedOpacity>(continuation).opacity, 0);
    expect(find.textContaining('往下滑'), findsNothing);

    await tester.tap(find.text('完成').hitTestable());
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('運動'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byIcon(Icons.tune_rounded).hitTestable());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('超慢跑 設定'), findsOneWidget);
    expect(find.byType(Scrollbar), findsNothing);
    final exerciseScroll = tester.state<ScrollableState>(
      find.descendant(
        of: find.byKey(const ValueKey('scroll-continuation-view')),
        matching: find.byType(Scrollable),
      ),
    );
    expect(exerciseScroll.position.maxScrollExtent, greaterThan(0));
    expect(tester.widget<AnimatedOpacity>(continuation).opacity, 1);

    await tester.tap(find.text('完成').hitTestable());
    await tester.pumpAndSettle();
    tester.view.physicalSize = const Size(390, 844);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('節拍器'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(
      find.byKey(const ValueKey('timer-settings-action')).hitTestable(),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(Scrollbar), findsNothing);
    expect(tester.widget<AnimatedOpacity>(continuation).opacity, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('運動已有進度後重設不會出現破圖或殘留進度', (tester) async {
    SharedPreferences.setMockInitialValues({});
    FlutterLocalNotificationsPlatform.instance = _NoopNotificationsPlatform();
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MaterialApp(home: TimerPage()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    await tester.tap(find.text('運動'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byIcon(Icons.play_arrow_rounded).hitTestable());
    await tester.pump(const Duration(milliseconds: 100));

    // Tabata 預設為準備 → 運動 → 休息；跳過兩次後已有一組進度。
    await tester.tap(find.byIcon(Icons.skip_next_rounded).hitTestable());
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.byIcon(Icons.skip_next_rounded).hitTestable());
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.text('第 1 / 8 組'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('exercise-progress-0-filled')),
      findsOneWidget,
    );

    await tester.tap(find.byIcon(Icons.replay_rounded).hitTestable());
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Tabata'), findsWidgets);
    expect(
      find.byKey(const ValueKey('exercise-progress-0-empty')),
      findsOneWidget,
    );
    // 重設現在固定留在同一位置，待機時只停用，不再變回設定按鈕。
    expect(find.byIcon(Icons.replay_rounded), findsOneWidget);
    expect(tester.takeException(), isNull);
    MascotPersona.resetToOpening();
  });

  testWidgets('舊版自訂方案會遷移到第四個快捷方案', (tester) async {
    SharedPreferences.setMockInitialValues({
      PrefsKeys.timerSelectedPreset: 3,
      PrefsKeys.timerCustomSlot: 1,
      PrefsKeys.timerCustomName(1): '讀書',
      PrefsKeys.timerCustomFocus(1): 42,
      PrefsKeys.timerCustomShort(1): 7,
      PrefsKeys.timerCustomRounds(1): 2,
      PrefsKeys.timerLongBreakMinutes: 20,
      PrefsKeys.timerLongBreakEnabled: false,
    });
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MaterialApp(home: TimerPage()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('讀書'), findsOneWidget);
    expect(find.text('42:00'), findsOneWidget);
    expect(find.text('42/7 ×2'), findsOneWidget);
    expect(find.textContaining('番茄'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
