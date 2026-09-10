import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:habit_app/l10n/app_localizations.dart';
import 'package:habit_app/pages/timer/game/party_face.dart';
import 'package:habit_app/pages/timer/game/table_stage_page.dart';
import 'package:habit_app/pages/timer/game/table_timer_engine.dart';
import 'package:habit_app/pages/timer/game/table_timer_models.dart';
import 'package:habit_app/pages/timer_page.dart';
import 'package:habit_app/utils/app_feedback.dart';
import 'package:habit_app/utils/mascot.dart';
import 'package:habit_app/utils/prefs_keys.dart';
import 'package:habit_app/utils/tab_catalog.dart';
import 'package:habit_app/widgets/app_pressable.dart';
import 'package:habit_app/widgets/timer_mode_frame.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _NoopNotificationsPlatform extends FlutterLocalNotificationsPlatform {}

// Reproduces MainPage's extendBody + actual adaptive navigation height. TimerPage
// and MascotPageShell themselves remain production widgets, including both safe
// areas, AppBar, anchored room, toggle bar and mode selector.
Widget _productionApp(Size size, String language) {
  final top = size.width == 430 ? 59.0 : 20.0;
  final bottom = size.width == 430 ? 34.0 : 0.0;
  final twoRows = bottomNavUsesTwoRows(width: size.width - 24, itemCount: 6);
  return MaterialApp(
    locale: Locale(language),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    theme: ThemeData(fontFamily: 'Nunito'),
    builder: (context, child) => MediaQuery(
      data: MediaQueryData(
        size: size,
        viewInsets: MediaQuery.viewInsetsOf(context),
        padding: EdgeInsets.only(top: top, bottom: bottom),
        viewPadding: EdgeInsets.only(top: top, bottom: bottom),
        textScaler: const TextScaler.linear(1.3),
        disableAnimations: true,
      ),
      child: child!,
    ),
    home: Scaffold(
      extendBody: true,
      body: const Stack(children: [TimerPage()]),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: SizedBox(
            key: const ValueKey('production-navigation'),
            height: twoRows ? 96 : 60,
            child: const ColoredBox(color: Colors.white),
          ),
        ),
      ),
    ),
  );
}

void main() {
  setUpAll(() async {
    final nunito = FontLoader('Nunito');
    for (final weight in [
      'Regular',
      'Medium',
      'SemiBold',
      'Bold',
      'ExtraBold',
      'Black',
    ]) {
      nunito.addFont(rootBundle.load('assets/fonts/Nunito-$weight.ttf'));
    }
    await nunito.load();
    final digits = FontLoader('Baloo 2');
    digits.addFont(rootBundle.load('assets/fonts/Baloo2-ExtraBold.ttf'));
    await digits.load();
  });
  setUp(() {
    SharedPreferences.setMockInitialValues({
      PrefsKeys.timerFocusProfileFocus(0): 120,
    });
    MascotPanelPrefs.hintSeenValue.value = true;
    MascotPanelPrefs.settleRequest.value = null;
    FlutterLocalNotificationsPlatform.instance = _NoopNotificationsPlatform();
    debugFeedbackSink = (_, _) {};
  });
  tearDown(() {
    debugFeedbackSink = null;
    MascotPersona.resetToOpening();
  });

  Future<void> load(
    WidgetTester tester,
    Size size,
    String language,
    bool room,
  ) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    MascotPanelPrefs.openValue.value = room ? 1 : 0;
    await tester.pumpWidget(_productionApp(size, language));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<void> switchMode(WidgetTester tester, String mode) async {
    final target = find.byKey(ValueKey('timer-mode-$mode'));
    await tester.ensureVisible(target);
    await tester.tap(target);
    await tester.pump(const Duration(milliseconds: 300));
  }

  void expectOperable(WidgetTester tester, {required String reason}) {
    final frame = tester.getRect(find.byType(TimerModeFrame));
    final primary = find.byKey(const ValueKey('timer-primary-action'));
    expect(primary.hitTestable(), findsOneWidget, reason: reason);
    final mainRect = tester.getRect(primary);
    for (final label
        in find
            .descendant(of: primary, matching: find.byType(Text))
            .evaluate()) {
      final paragraph = label.renderObject! as RenderParagraph;
      expect(
        paragraph.didExceedMaxLines,
        isFalse,
        reason: '$reason primary label must remain readable',
      );
    }
    expect(mainRect.height, greaterThanOrEqualTo(52), reason: reason);
    expect(mainRect.width, greaterThanOrEqualTo(100), reason: reason);
    expect(
      mainRect.bottom,
      lessThanOrEqualTo(frame.bottom + 0.5),
      reason: reason,
    );
    final settings = find.byKey(const ValueKey('timer-settings-action'));
    expect(settings.hitTestable(), findsOneWidget, reason: reason);
    expect(
      tester.getSize(settings).height,
      greaterThanOrEqualTo(44),
      reason: reason,
    );
    final actions = find.descendant(
      of: find.byKey(const ValueKey('timer-mode-controls-slot')),
      matching: find.byType(AppPressable),
    );
    for (final action in actions.evaluate()) {
      final rect = tester.getRect(find.byWidget(action.widget));
      expect(rect.height, greaterThanOrEqualTo(44), reason: reason);
      expect(rect.width, greaterThanOrEqualTo(44), reason: reason);
      expect(
        rect.bottom,
        lessThanOrEqualTo(frame.bottom + 0.5),
        reason: reason,
      );
    }
    expect(tester.takeException(), isNull, reason: reason);
  }

  Rect contentBounds(WidgetTester tester, Finder tile) {
    final content = find.descendant(
      of: tile,
      matching: find.byWidgetPredicate(
        (widget) => widget is Icon || widget is Text,
      ),
    );
    return content
        .evaluate()
        .map((element) => tester.getRect(find.byWidget(element.widget)))
        .reduce((a, b) => a.expandToInclude(b));
  }

  void expectCenteredOption(WidgetTester tester, Finder tile) {
    final rect = tester.getRect(tile);
    final content = contentBounds(tester, tile);
    expect(
      content.center.dx,
      closeTo(rect.center.dx, 0.5),
      reason: 'option content horizontal center',
    );
    expect(
      content.center.dy,
      closeTo(rect.center.dy, 0.5),
      reason: 'option content vertical center',
    );
  }

  for (final language in ['zh', 'en']) {
    for (final room in [true, false]) {
      testWidgets('430 $language ${room ? "收合" : "展開"} 五種運動框內置中且操作欄位置穩定', (
        tester,
      ) async {
        await load(tester, const Size(430, 932), language, room);
        await switchMode(tester, 'exercise');
        Rect? initialPrimary;
        double? initialHeroCenter;
        for (final kind in ['tabata', 'hiit', 'emom', 'gym', 'jog']) {
          final tile = find.byKey(ValueKey('exercise-kind-$kind'));
          if (!room) await tester.ensureVisible(tile);
          await tester.tap(tile);
          await tester.pump(const Duration(milliseconds: 300));
          for (final option in ['tabata', 'hiit', 'emom', 'gym', 'jog']) {
            expectCenteredOption(
              tester,
              find.byKey(ValueKey('exercise-kind-$option')),
            );
          }
          final primary = tester.getRect(
            find.byKey(const ValueKey('timer-primary-action')),
          );
          final hero = tester.getRect(find.byKey(const ValueKey('timer-hero')));
          initialPrimary ??= primary;
          initialHeroCenter ??= hero.center.dx;
          expect(primary.left, closeTo(initialPrimary.left, 0.5));
          expect(primary.width, closeTo(initialPrimary.width, 0.5));
          expect(hero.center.dx, closeTo(initialHeroCenter, 0.5));
          if (room) {
            expect(
              hero.width,
              greaterThanOrEqualTo(148),
              reason: 'jog must retain a readable hero',
            );
            final frame = tester.getRect(find.byType(TimerModeFrame));
            expect(
              tester.getRect(tile).bottom,
              lessThanOrEqualTo(frame.bottom - 16),
              reason: 'exercise presets reserve a distinct navigation gap',
            );
            expectOperable(tester, reason: '$language/$kind');
          }
          if (kind == 'jog') {
            final speed = tester.getRect(
              find.byKey(const ValueKey('jog-bpm-control')),
            );
            final settings = tester.getRect(
              find.byKey(const ValueKey('timer-settings-action')),
            );
            if (room) {
              expect(speed.top, closeTo(primary.bottom, 0.5));
              expect(speed.left, closeTo(primary.left, 0.5));
              expect(speed.width, closeTo(primary.width, 0.5));
              expect(
                find.byKey(const ValueKey('timer-joined-adjustment')),
                findsOneWidget,
              );
            } else {
              expect(speed.center.dy, closeTo(settings.center.dy, 0.5));
              expect(speed.right, lessThan(settings.left));
            }
            for (final id in ['slower', 'faster']) {
              expect(
                tester.getSize(find.byKey(ValueKey('jog-bpm-$id'))).height,
                greaterThanOrEqualTo(44),
              );
            }
          }
          expect(tester.takeException(), isNull);
        }
        await tester.pumpWidget(const SizedBox());
      });
    }
    testWidgets('430 $language 四種快捷列左右留白對稱、圖文在框內置中', (tester) async {
      await load(tester, const Size(430, 932), language, true);
      for (final mode in ['focus', 'exercise', 'game', 'metronome']) {
        await switchMode(tester, mode);
        final frame = tester.getRect(find.byType(TimerModeFrame));
        final keys = switch (mode) {
          'focus' => [for (var i = 0; i < 4; i++) 'focus-profile-$i'],
          'exercise' => [
            for (final id in ['tabata', 'hiit', 'emom', 'gym', 'jog'])
              'exercise-kind-$id',
          ],
          'game' => [
            for (final id in ['party', 'chess', 'free']) 'game-quick-$id',
          ],
          _ => <String>[],
        };
        final tiles = mode == 'metronome'
            ? find
                  .descendant(
                    of: find.byKey(const ValueKey('metronome-quick-settings')),
                    matching: find.byType(InkWell),
                  )
                  .evaluate()
                  .map((e) => find.byWidget(e.widget))
                  .toList()
            : keys.map((key) => find.byKey(ValueKey(key))).toList();
        final first = tester.getRect(tiles.first);
        final last = tester.getRect(tiles.last);
        expect(first.left - frame.left, closeTo(frame.right - last.right, 0.5));
        for (final tile in tiles) {
          expect(tester.getRect(tile).height, closeTo(first.height, 0.5));
          if (mode != 'metronome') expectCenteredOption(tester, tile);
        }
        expect(tester.takeException(), isNull);
      }
      await tester.pumpWidget(const SizedBox());
    });
  }

  for (final language in ['zh', 'en']) {
    for (final size in [const Size(320, 667), const Size(430, 932)]) {
      testWidgets('${size.width.toInt()} $language BPM 精準輸入、範圍驗證與取消，鍵盤不遮確認', (
        tester,
      ) async {
        SharedPreferences.setMockInitialValues({
          PrefsKeys.exerciseSubMode: 'jog',
        });
        await load(tester, size, language, size.width == 430);
        await switchMode(tester, 'exercise');
        final prefs = await SharedPreferences.getInstance();
        final l10n = AppLocalizations.of(
          tester.element(find.byType(TimerModeFrame)),
        );
        final edit = find.byKey(const ValueKey('jog-bpm-edit'));
        await tester.ensureVisible(edit);
        await tester.tap(edit);
        await tester.pumpAndSettle();
        tester.view.viewInsets = const FakeViewPadding(bottom: 300);
        addTearDown(tester.view.resetViewInsets);
        // Dialog animates its padding as the native keyboard changes insets.
        await tester.pumpAndSettle();
        final input = find.byKey(const ValueKey('jog-bpm-input'));
        final save = find.byKey(const ValueKey('jog-bpm-save'));
        await tester.enterText(input, '241');
        await tester.tap(save);
        await tester.pump();
        expect(
          find.text(l10n.valRangeWithUnit(30, 240, 'BPM')),
          findsOneWidget,
        );
        expect(save.hitTestable(), findsOneWidget);
        expect(
          tester.getRect(save).bottom,
          lessThanOrEqualTo(size.height - 300),
        );
        expect(prefs.getInt(PrefsKeys.exerciseBpm('jog')), isNull);
        await tester.enterText(input, '160');
        await tester.tap(find.text(l10n.commonCancel));
        await tester.pumpAndSettle();
        expect(prefs.getInt(PrefsKeys.exerciseBpm('jog')), isNull);
        tester.view.resetViewInsets();
        await tester.pump();
        await tester.ensureVisible(edit);
        await tester.tap(edit);
        await tester.pumpAndSettle();
        await tester.enterText(input, '200');
        // Keep the keyboard open while confirming. On the real page it switches
        // a room layout to a summary and unmounts the original header control.
        tester.view.viewInsets = const FakeViewPadding(bottom: 300);
        await tester.pumpAndSettle();
        await tester.tap(save);
        await tester.pumpAndSettle();
        expect(prefs.getInt(PrefsKeys.exerciseBpm('jog')), 200);
        expect(find.byType(AlertDialog), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      });
    }
  }

  testWidgets('BPM 標題膠囊長按連發、放開停止且上下限維持30到240', (tester) async {
    SharedPreferences.setMockInitialValues({
      PrefsKeys.exerciseSubMode: 'jog',
      PrefsKeys.exerciseBpm('jog'): 237,
    });
    await load(tester, const Size(430, 932), 'zh', true);
    await switchMode(tester, 'exercise');
    final prefs = await SharedPreferences.getInstance();
    final faster = find.byKey(const ValueKey('jog-bpm-faster'));
    final touch = await tester.startGesture(tester.getCenter(faster));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 360));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 110));
    }
    await touch.up();
    await tester.pump();
    expect(prefs.getInt(PrefsKeys.exerciseBpm('jog')), 240);
    final slower = find.byKey(const ValueKey('jog-bpm-slower'));
    await tester.tap(slower);
    await tester.pump();
    expect(prefs.getInt(PrefsKeys.exerciseBpm('jog')), 239);
    await tester.pump(const Duration(milliseconds: 700));
    expect(prefs.getInt(PrefsKeys.exerciseBpm('jog')), 239);
    await tester.tap(find.byKey(const ValueKey('jog-bpm-edit')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('jog-bpm-input')), '30');
    await tester.tap(find.byKey(const ValueKey('jog-bpm-save')));
    await tester.pumpAndSettle();
    await tester.tap(slower);
    await tester.pump();
    expect(prefs.getInt(PrefsKeys.exerciseBpm('jog')), 30);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('430 收合超慢跑即時 BPM 與五種運動快選均在可見區', (tester) async {
    SharedPreferences.setMockInitialValues({PrefsKeys.exerciseSubMode: 'jog'});
    await load(tester, const Size(430, 932), 'zh', true);
    await switchMode(tester, 'exercise');
    final frame = tester.getRect(find.byType(TimerModeFrame));
    for (final key in [
      'jog-bpm-slower',
      'jog-bpm-faster',
      'exercise-kind-tabata',
      'exercise-kind-hiit',
      'exercise-kind-emom',
      'exercise-kind-gym',
      'exercise-kind-jog',
    ]) {
      final target = find.byKey(ValueKey(key));
      expect(target.hitTestable(), findsOneWidget);
      expect(tester.getRect(target).bottom, lessThanOrEqualTo(frame.bottom));
      expect(tester.getSize(target).height, greaterThanOrEqualTo(44));
    }
    final prefs = await SharedPreferences.getInstance();
    final before = prefs.getInt(PrefsKeys.exerciseBpm('jog')) ?? 180;
    await tester.tap(find.byKey(const ValueKey('jog-bpm-faster')));
    await tester.pump();
    expect(prefs.getInt(PrefsKeys.exerciseBpm('jog')), before + 1);
    await tester.tap(find.byKey(const ValueKey('exercise-kind-hiit')));
    await tester.pump();
    expect(prefs.getString(PrefsKeys.exerciseSubMode), 'hiit');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  for (final size in [const Size(320, 667), const Size(430, 932)]) {
    for (final language in ['zh', 'en']) {
      for (final room in [true, false]) {
        testWidgets(
          '${size.width.toInt()} $language 1.3 ${room ? '房間' : '展開'} 四模式初始操作可讀好按',
          (tester) async {
            await load(tester, size, language, room);
            for (final mode in ['focus', 'exercise', 'metronome', 'game']) {
              await switchMode(tester, mode);
              expectOperable(tester, reason: '$size/$language/$room/$mode');
              if (size.width == 430 && room) {
                final frameRect = tester.getRect(find.byType(TimerModeFrame));
                final quick = find.byKey(
                  const ValueKey('timer-mode-quick-picker-slot'),
                );
                final quickRect = tester.getRect(quick);
                expect(
                  quickRect.bottom,
                  lessThanOrEqualTo(frameRect.bottom),
                  reason:
                      '$mode quick actions must be visible without vertical scrolling',
                );
                final keys = switch (mode) {
                  'focus' => [for (var i = 0; i < 4; i++) 'focus-profile-$i'],
                  'exercise' => [
                    'exercise-kind-tabata',
                    'exercise-kind-hiit',
                    'exercise-kind-emom',
                    'exercise-kind-gym',
                    'exercise-kind-jog',
                  ],
                  'game' => [
                    'game-quick-party',
                    'game-quick-chess',
                    'game-quick-free',
                  ],
                  _ => <String>[],
                };
                for (final key in keys) {
                  final target = find.byKey(ValueKey(key));
                  final rect = tester.getRect(target);
                  expect(target.hitTestable(), findsOneWidget, reason: key);
                  expect(rect.height, greaterThanOrEqualTo(44), reason: key);
                  expect(
                    rect.left,
                    greaterThanOrEqualTo(frameRect.left),
                    reason: key,
                  );
                  expect(
                    rect.right,
                    lessThanOrEqualTo(frameRect.right),
                    reason: key,
                  );
                  expect(
                    rect.bottom,
                    lessThanOrEqualTo(frameRect.bottom),
                    reason: key,
                  );
                }
              }
              if (mode == 'focus') {
                final frame = tester.getSize(find.byType(TimerModeFrame));
                final primary = tester.getSize(
                  find.byKey(const ValueKey('timer-primary-action')),
                );
                final hero = find.byKey(const ValueKey('timer-hero'));
                debugPrint(
                  'TIMER METRICS $size $language room=$room frame=$frame primary=$primary hero=${hero.evaluate().isEmpty ? 'summary' : tester.getSize(hero)}',
                );
              }
            }
            // Secondary detail content stays reachable after the primary stage.
            final detail = find.byKey(
              const ValueKey('timer-mode-quick-picker-slot'),
            );
            await tester.ensureVisible(detail);
            await tester.pump();
            expect(detail.hitTestable(), findsOneWidget);
            expect(tester.takeException(), isNull);
            MascotPersona.resetToOpening();
            await tester.pumpWidget(const SizedBox());
          },
        );
      }
    }
  }

  for (final room in [true, false]) {
    testWidgets('320 英文大字 ${room ? '房間' : '展開'} 專注運動休息暫停、節拍啟停維持主操作', (
      tester,
    ) async {
      await load(tester, const Size(320, 667), 'en', room);
      Finder primary() => find.byKey(const ValueKey('timer-primary-action'));
      String phase() => tester
          .widget<TimerStatusPill>(find.byType(TimerStatusPill))
          .stateKey
          .toString();
      await tester.tap(primary());
      await tester.pump(const Duration(milliseconds: 100));
      expect(phase(), contains('focus'));
      expectOperable(tester, reason: 'focus running');
      await tester.tap(find.byIcon(Icons.skip_next_rounded).hitTestable());
      await tester.pump(const Duration(milliseconds: 100));
      expect(phase(), contains('shortBreak'));
      expectOperable(tester, reason: 'focus rest');
      await tester.tap(primary());
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        find.byIcon(Icons.play_arrow_rounded).hitTestable(),
        findsOneWidget,
      );
      expectOperable(tester, reason: 'focus paused');

      await switchMode(tester, 'exercise');
      await tester.tap(primary());
      await tester.pump(const Duration(milliseconds: 100));
      expect(phase(), contains('prep'));
      await tester.tap(find.byIcon(Icons.skip_next_rounded).hitTestable());
      await tester.pump(const Duration(milliseconds: 100));
      expect(phase(), contains('work'));
      expectOperable(tester, reason: 'exercise work');
      await tester.tap(find.byIcon(Icons.skip_next_rounded).hitTestable());
      await tester.pump(const Duration(milliseconds: 100));
      expect(phase(), contains('rest'));
      expectOperable(tester, reason: 'exercise rest');
      await tester.tap(primary());
      await tester.pump(const Duration(milliseconds: 100));
      expectOperable(tester, reason: 'exercise paused');

      await switchMode(tester, 'metronome');
      await tester.tap(primary());
      await tester.pump(const Duration(milliseconds: 100));
      expect(phase(), 'true');
      expectOperable(tester, reason: 'metronome running');
      await tester.tap(primary());
      await tester.pump(const Duration(milliseconds: 100));
      expect(phase(), 'false');
      expectOperable(tester, reason: 'metronome stopped');
      MascotPersona.resetToOpening();
      await tester.pumpWidget(const SizedBox());
    });
  }
  testWidgets('320 英文大字超慢跑準備與運動中，BPM 操作固定 44pt 且保留即時調整', (tester) async {
    SharedPreferences.setMockInitialValues({PrefsKeys.exerciseSubMode: 'jog'});
    await load(tester, const Size(320, 667), 'en', false);
    await switchMode(tester, 'exercise');
    final faster = find.byKey(const ValueKey('jog-bpm-faster'));
    final slower = find.byKey(const ValueKey('jog-bpm-slower'));
    for (final phase in ['idle', 'work']) {
      await tester.ensureVisible(faster);
      await tester.pump();
      expect(tester.getSize(faster), const Size(44, 44));
      expect(tester.getSize(slower), const Size(44, 44));
      final prefs = await SharedPreferences.getInstance();
      final before = prefs.getInt(PrefsKeys.exerciseBpm('jog')) ?? 180;
      await tester.tap(faster);
      await tester.pump(const Duration(milliseconds: 100));
      expect(prefs.getInt(PrefsKeys.exerciseBpm('jog')), before + 1);
      expect(tester.takeException(), isNull, reason: phase);
      if (phase == 'idle') {
        final primary = find.byKey(const ValueKey('timer-primary-action'));
        await tester.ensureVisible(primary);
        await tester.tap(primary);
        await tester.pump(const Duration(milliseconds: 100));
        for (var i = 0; i < 3; i++) {
          final status =
              tester.widget<TimerModeFrame>(find.byType(TimerModeFrame)).status
                  as TimerStatusPill;
          if (status.stateKey.toString().contains('work')) break;
          await tester.tap(find.byIcon(Icons.skip_next_rounded).hitTestable());
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(
          (tester.widget<TimerModeFrame>(find.byType(TimerModeFrame)).status
                  as TimerStatusPill)
              .stateKey
              .toString(),
          contains('work'),
        );
      }
    }
    MascotPersona.resetToOpening();
    await tester.pumpWidget(const SizedBox());
  });

  for (final size in [const Size(320, 667), const Size(430, 932)]) {
    for (final language in ['zh', 'en']) {
      testWidgets('${size.width.toInt()} $language 大字遊戲桌操作完整可讀、可換人及修正', (
        tester,
      ) async {
        SharedPreferences.setMockInitialValues({
          PrefsKeys.gameTableConfig: TableTimerConfig.fallback()
              .copyWith(
                players: const [
                  TablePlayer(name: 'Avery Rose', colorIndex: 0),
                  TablePlayer(name: 'Noah James', colorIndex: 1),
                ],
              )
              .encode(),
        });
        await load(tester, size, language, true);
        await switchMode(tester, 'game');
        await tester.tap(find.byKey(const ValueKey('timer-primary-action')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        expect(find.byType(TableStagePage), findsOneWidget);
        final face = find.byType(PartyFace);
        final engine = tester.widget<PartyFace>(face).engine;
        final l = AppLocalizations.of(tester.element(face));

        Future<void> expectButton(String label) async {
          final text = find.text(label).last;
          await tester.ensureVisible(text);
          await tester.pump();
          expect(text.hitTestable(), findsOneWidget);
          final button = find
              .ancestor(of: text, matching: find.byType(InkWell))
              .first;
          final bounds = tester.getRect(button);
          final labelBounds = tester.getRect(text);
          expect(bounds.width, greaterThanOrEqualTo(44));
          expect(bounds.height, greaterThanOrEqualTo(44));
          expect(labelBounds.left, greaterThanOrEqualTo(bounds.left));
          expect(labelBounds.right, lessThanOrEqualTo(bounds.right));
          expect(labelBounds.bottom, lessThanOrEqualTo(bounds.bottom));
          expect(
            (text.evaluate().single.renderObject! as RenderParagraph)
                .didExceedMaxLines,
            isFalse,
          );
        }

        expect(engine.phase, TablePhase.ready);
        await expectButton(l.stgLeave);
        await expectButton(l.gtDiceLabel);
        final toolbar = tester.getRect(
          find.byKey(const ValueKey('table-stage-actions')),
        );
        expect(toolbar.bottom, lessThanOrEqualTo(tester.getTopLeft(face).dy));
        // These are the actual translated seat tokens, including the upper seat.
        for (final seat
            in find
                .descendant(of: face, matching: find.byType(AnimatedScale))
                .evaluate()) {
          expect(
            tester.getTopLeft(find.byWidget(seat.widget)).dy,
            greaterThan(toolbar.bottom),
            reason: 'the wrapped actions must not cover the seating ring',
          );
        }
        await tester.tapAt(tester.getCenter(face));
        await tester.pump(const Duration(milliseconds: 100));
        expect(engine.phase, TablePhase.running);
        await expectButton(l.stgPause);
        await tester.tapAt(tester.getCenter(face));
        await tester.pump(const Duration(milliseconds: 100));
        expect(engine.currentIndex, 1);
        await tester.tap(find.text(l.stgPause).hitTestable());
        await tester.pump(const Duration(milliseconds: 100));
        expect(engine.phase, TablePhase.paused);
        for (final label in [
          l.stgResume,
          l.stgPrevPlayer,
          l.stgRestartTurn,
          l.stgEndGame,
        ]) {
          await expectButton(label);
        }
        await tester.ensureVisible(find.text(l.stgPrevPlayer));
        await tester.tap(find.text(l.stgPrevPlayer).hitTestable());
        await tester.pump(const Duration(milliseconds: 100));
        expect(engine.currentIndex, 0);
        expect(engine.phase, TablePhase.running);

        await tester.tap(find.text(l.stgPause).hitTestable());
        await tester.pump(const Duration(milliseconds: 100));
        await tester.ensureVisible(find.text(l.stgRestartTurn));
        await tester.tap(find.text(l.stgRestartTurn).hitTestable());
        await tester.pump(const Duration(milliseconds: 100));
        expect(engine.currentIndex, 0);
        expect(engine.phase, TablePhase.running);

        await tester.tap(find.text(l.stgPause).hitTestable());
        await tester.pump(const Duration(milliseconds: 100));
        await tester.ensureVisible(find.text(l.stgResume));
        await tester.tap(find.text(l.stgResume).hitTestable());
        await tester.pump(const Duration(milliseconds: 100));
        expect(engine.phase, TablePhase.running);
        expect(tester.takeException(), isNull);
        MascotPersona.resetToOpening();
        await tester.pumpWidget(const SizedBox());
      });
    }
  }
}
