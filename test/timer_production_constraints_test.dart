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
  testWidgets('320 英文大字超慢跑準備與運動中，BPM 操作固定 48pt 且保留即時調整', (tester) async {
    SharedPreferences.setMockInitialValues({PrefsKeys.exerciseSubMode: 'jog'});
    await load(tester, const Size(320, 667), 'en', false);
    await switchMode(tester, 'exercise');
    final faster = find.byKey(const ValueKey('jog-bpm-faster'));
    final slower = find.byKey(const ValueKey('jog-bpm-slower'));
    for (final phase in ['idle', 'work']) {
      await tester.ensureVisible(faster);
      await tester.pump();
      expect(tester.getSize(faster), const Size(48, 48));
      expect(tester.getSize(slower), const Size(48, 48));
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
          final status = tester.widget<TimerStatusPill>(
            find.byType(TimerStatusPill),
          );
          if (status.stateKey.toString().contains('work')) break;
          await tester.tap(find.byIcon(Icons.skip_next_rounded).hitTestable());
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(
          tester
              .widget<TimerStatusPill>(find.byType(TimerStatusPill))
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
