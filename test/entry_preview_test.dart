import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:habit_app/dev/entry_preview/app.dart';
import 'package:habit_app/dev/entry_preview/model.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('new, returning and credential-only have distinct entry decisions', () {
    for (final scenario in EntryScenario.values) {
      final m = EntryPreviewModel(scenario: scenario);
      m.initialized(m.epoch);
      if (scenario == EntryScenario.initializationFailed) {
        expect(m.stage, EntryStage.initializationFailed);
        m.coldLaunch(retry: true);
        m.initialized(m.epoch);
        expect(m.stage, EntryStage.cover);
      }
      if (m.hasJourney) {
        m.continueJourney();
        expect(m.stage, EntryStage.room);
      } else if (m.hasCredential) {
        m.openRestore();
        expect(m.stage, EntryStage.restore);
      } else if (m.stage == EntryStage.cover) {
        m.startGuest();
        expect(m.stage, EntryStage.meeting);
      }
      m.dispose();
    }
  });
  test('cancel/failure and late auth callbacks never create a journey', () {
    for (final result in [
      PreviewAuthResult.canceled,
      PreviewAuthResult.failed,
      PreviewAuthResult.offline,
    ]) {
      final m = EntryPreviewModel();
      m.initialized(m.epoch);
      final operation = m.beginAuth('Apple')!;
      m.completeAuth(operation, result);
      expect(m.hasJourney, isFalse);
      expect(m.hasCredential, isFalse);
      expect(m.stage, EntryStage.cover);
      m.completeAuth(operation, PreviewAuthResult.successNew);
      expect(m.hasJourney, isFalse);
      m.dispose();
    }
    final m = EntryPreviewModel();
    m.initialized(m.epoch);
    final operation = m.beginAuth('Google')!;
    m.selectScenario(EntryScenario.returningGuest);
    m.completeAuth(operation, PreviewAuthResult.successExisting);
    expect(m.hasCredential, isFalse);
    expect(m.stage, EntryStage.initializing);
    m.dispose();
  });
  test(
    'restore failure is unknown remote data, success skips first meeting',
    () {
      final m = EntryPreviewModel(scenario: EntryScenario.credentialsOnly);
      m.initialized(m.epoch);
      m.openRestore();
      m.restore(success: false);
      expect(m.stage, EntryStage.restore);
      expect(m.hasJourney, isFalse);
      expect(m.notice, PreviewNotice.restoreFailed);
      m.restore(success: true);
      expect(m.stage, EntryStage.room);
      expect(m.firstMeetingDone, isTrue);
      m.dispose();
    },
  );
  test('skip creates only preview continuity; cold start retains cover', () {
    final m = EntryPreviewModel();
    m.initialized(m.epoch);
    m.startGuest();
    m.finishMeeting(skip: true);
    expect(m.stage, EntryStage.room);
    m.coldLaunch();
    m.initialized(m.epoch);
    expect(m.stage, EntryStage.cover);
    m.continueJourney();
    expect(m.stage, EntryStage.room);
    m.dispose();
  });
  test(
    'offline returning journey continues and auth success has explicit paths',
    () {
      final returning = EntryPreviewModel(
        scenario: EntryScenario.returningGuest,
      )..offline = true;
      returning.initialized(returning.epoch);
      returning.continueJourney();
      expect(returning.stage, EntryStage.room);
      returning.dispose();
      for (final result in [
        PreviewAuthResult.successNew,
        PreviewAuthResult.successExisting,
      ]) {
        final m = EntryPreviewModel();
        m.initialized(m.epoch);
        m.completeAuth(m.beginAuth('Google')!, result);
        expect(m.hasCredential, isTrue);
        expect(
          m.stage,
          result == PreviewAuthResult.successNew
              ? EntryStage.meeting
              : EntryStage.restore,
        );
        expect(m.hasJourney, result == PreviewAuthResult.successNew);
        m.dispose();
      }
    },
  );
  test('runtime production entry does not import any preview or OAuth', () {
    expect(
      File('lib/main.dart').readAsStringSync(),
      isNot(contains('entry_preview')),
    );
    for (final f in Directory(
      'lib/dev/entry_preview',
    ).listSync().whereType<File>()) {
      final text = f.readAsStringSync();
      expect(text, isNot(contains('shared_preferences')));
      expect(text, isNot(contains('firebase')));
      expect(text, isNot(contains('onboardingDone')));
      expect(text, isNot(contains('main.dart')));
    }
  });
  Future<void> show(WidgetTester tester, EntryPreviewModel m, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    m.initialized(m.epoch);
    await tester.pumpWidget(EntryPreviewApp(model: m));
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, String key) async {
    final finder = find.byKey(ValueKey(key));
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  for (final size in [const Size(375, 667), const Size(430, 932)]) {
    for (final language in ['zh', 'en']) {
      for (final large in [false, true]) {
        testWidgets(
          'layout $size $language large=$large and accessible skip flow',
          (tester) async {
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);
            final m = EntryPreviewModel()
              ..language = language
              ..textScale = large ? 2 : null
              ..reduceMotion = large;
            addTearDown(m.dispose);
            SharedPreferences.setMockInitialValues({
              'onboardingDone': true,
              'userBirthday': '1990-02-03',
              'sentinel': 'untouched',
            });
            final prefs = await SharedPreferences.getInstance();
            final before = {
              for (final key in prefs.getKeys()) key: prefs.get(key),
            };
            await show(tester, m, size);
            final coverTop = tester
                .getTopLeft(find.byKey(const ValueKey('cover-art')))
                .dy;
            m.selectScenario(EntryScenario.returningGuest);
            m.initialized(m.epoch);
            await tester.pumpAndSettle();
            expect(
              tester.getTopLeft(find.byKey(const ValueKey('cover-art'))).dy,
              coverTop,
              reason:
                  'Short returning panel must not recenter the cover artwork',
            );
            m.selectScenario(EntryScenario.firstUse);
            m.initialized(m.epoch);
            await tester.pumpAndSettle();
            expect(
              tester
                  .getRect(find.byKey(const ValueKey('cover-branding')))
                  .overlaps(
                    tester.getRect(find.byKey(const ValueKey('cover-mascot'))),
                  ),
              isFalse,
            );
            expect(
              tester
                  .getRect(find.byKey(const ValueKey('preview-toolbar')))
                  .bottom,
              lessThanOrEqualTo(
                tester.getRect(find.byKey(const ValueKey('cover-scroll'))).top,
              ),
            );
            expect(find.byKey(const ValueKey('apple')), findsOneWidget);
            expect(find.byKey(const ValueKey('google')), findsOneWidget);
            expect(find.byKey(const ValueKey('guest')), findsOneWidget);
            await tap(tester, 'apple');
            await tap(tester, 'auth-cancel');
            expect(m.hasJourney, isFalse);
            final notice = tester.getRect(find.byKey(const ValueKey('notice')));
            expect(
              notice.top,
              greaterThanOrEqualTo(
                tester
                    .getRect(find.byKey(const ValueKey('preview-toolbar')))
                    .bottom,
              ),
            );
            expect(notice.bottom, lessThanOrEqualTo(size.height));
            await tap(tester, 'guest');
            await tap(tester, 'skip-meeting');
            expect(m.stage, EntryStage.room);
            final scroll = tester.widget<SingleChildScrollView>(
              find.byKey(const ValueKey('inside-scroll')),
            );
            expect(
              scroll.controller!.offset,
              0,
              reason:
                  'Room landing resets first-meeting scroll, including large text',
            );
            expect(tester.takeException(), isNull);
            expect({
              for (final key in prefs.getKeys()) key: prefs.get(key),
            }, before);
            await tester.pumpWidget(const SizedBox());
          },
        );
      }
    }
  }
  testWidgets(
    'warm lifecycle retains room; manual language preserves journey',
    (tester) async {
      final m = EntryPreviewModel(scenario: EntryScenario.returningGuest)
        ..language = 'zh';
      addTearDown(m.dispose);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await show(tester, m, const Size(430, 932));
      await tap(tester, 'continue');
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(m.stage, EntryStage.room);
      await tap(tester, 'language');
      await tap(tester, 'locale-en');
      expect(m.hasJourney, isTrue);
      expect(m.stage, EntryStage.room);
      expect(find.text('Our little everyday'), findsOneWidget);
    },
  );
}
