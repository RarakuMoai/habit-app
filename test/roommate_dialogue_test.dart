import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:habit_app/l10n/app_localizations.dart';
import 'package:habit_app/main.dart';
import 'package:habit_app/pages/companion_dialogue_page.dart';
import 'package:habit_app/pages/home/home_speech_owner.dart';
import 'package:habit_app/pages/home_page.dart';
import 'package:habit_app/utils/audio_settings_service.dart';
import 'package:habit_app/utils/companion_story_progress.dart';
import 'package:habit_app/utils/logical_date.dart';
import 'package:habit_app/utils/mascot.dart';
import 'package:habit_app/utils/prefs_keys.dart';
import 'package:habit_app/utils/roommate_dialogue.dart';
import 'package:habit_app/utils/roommate_voice.dart';
import 'package:habit_app/utils/sfx_service.dart';
import 'package:habit_app/utils/story_store.dart';
import 'package:habit_app/utils/wardrobe_store.dart';
import 'package:habit_app/widgets/mascot_page_shell.dart';
import 'package:habit_app/widgets/mascot_scene.dart';
import 'package:habit_app/widgets/roommate_dialogue.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'shared_preferences_delay_test_helper.dart';

class _Voice implements RoommateVoiceOutput {
  final cues = <SfxCue>[];
  int stops = 0;
  bool disposed = false;
  @override
  Future<void> play(SfxCue cue) async => cues.add(cue);
  @override
  void stop() => stops++;
  @override
  void dispose() => disposed = true;
}

void _surface(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Widget _app(
  _Voice voice, {
  VoidCallback? close,
  bool reduced = false,
  bool visible = true,
  String locale = 'zh',
  double scale = 1,
}) => MaterialApp(
  locale: Locale(locale),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Builder(
    builder: (context) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        disableAnimations: reduced,
        textScaler: TextScaler.linear(scale),
        padding: const EdgeInsets.only(top: 59, bottom: 34),
      ),
      child: Scaffold(
        body: Scaffold(
          appBar: AppBar(),
          body: TickerMode(
            enabled: visible,
            child: MascotPageShell(
              accent: Colors.orange,
              scene: const SizedBox(),
              interactionBuilder: (height) => RoommateDialogue(
                sceneHeight: height,
                accent: Colors.orange,
                onClose: close ?? () {},
                voice: voice,
              ),
              child: const SizedBox(),
            ),
          ),
        ),
      ),
    ),
  ),
);

Finder _reply(String id) => find.byKey(ValueKey('roommate_reply_$id'));
Future<void> _choose(WidgetTester tester, String id) async {
  await tester.tap(find.byKey(const ValueKey('roommate_subtitle')));
  await tester.pump();
  await tester.ensureVisible(_reply(id));
  await tester.tap(_reply(id));
  await tester.pump();
}

Future<void> _dispose(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 25));
  await CompanionStoryProgress.instance.resetForTesting();
}

Future<void> _waitForFeedback(WidgetTester tester) async {
  for (var i = 0; i < 140; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<String> _pumpCompletionInvitation(
  WidgetTester tester, {
  int habitCount = 3,
}) async {
  _surface(tester, const Size(430, 932));
  final today = LogicalDate.stringFor(DateTime.now(), LogicalDate.defaultHour);
  SharedPreferences.setMockInitialValues({
    PrefsKeys.lastOpenDate: today,
    PrefsKeys.coinLastLoginDate: today,
    PrefsKeys.sfxMuted: true,
    PrefsKeys.mascotPanelHintSeen: true,
    PrefsKeys.habits: jsonEncode([
      for (var i = 0; i < habitCount; i++)
        {
          'id': 'pending_h$i',
          'name': '小日常$i',
          'createdAt': today,
          'frequency': 'daily',
          'done': i == 0,
        },
    ]),
  });
  StoryEvents.debugCatalog = [];
  addTearDown(() => StoryEvents.debugCatalog = null);
  AudioSettingsService.sfxMuted.value = true;
  addTearDown(() => AudioSettingsService.sfxMuted.value = false);
  await tester.pumpWidget(const MyApp(startAtHome: true));
  await tester.pump();
  await tester.pump(const Duration(seconds: 6));
  expect(find.byKey(const ValueKey('roommate_entry')), findsOneWidget);
  return today;
}

Future<DelayFirstWriteStore> _holdInvitationWrite(WidgetTester tester) async {
  final store = installDelayFirstWriteStore(
    'flutter.${PrefsKeys.companionStoryProgress}',
  );
  addTearDown(store.restore);
  final invitation = tester.widget<InkWell>(
    find.byKey(const ValueKey('roommate_entry')),
  );
  await tester.tap(find.byKey(const ValueKey('roommate_entry')));
  await tester.pump();
  expect(store.didDelay, isTrue);
  // A second queued callback while the native write is pending cannot re-enter.
  invitation.onTap!();
  await tester.pump();
  expect(find.byType(CompanionDialoguePage), findsNothing);
  return store;
}

Future<void> _expectInvitationPersisted(String day) async {
  final prefs = await SharedPreferences.getInstance();
  // Reload checks the platform store, not only legacy setString's early cache.
  await prefs.reload();
  final progress = CompanionProgressState.fromJson(
    jsonDecode(prefs.getString(PrefsKeys.companionStoryProgress)!)
        as Map<String, dynamic>,
  );
  expect(progress.active?.episodeId, 'story_01');
  expect(progress.days, 0);
  expect(progress.creditedDayKeys, isNot(contains(day)));
  expect(progress.completed, isEmpty);
}

void main() {
  setUp(() async {
    await CompanionStoryProgress.instance.resetForTesting();
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('室友對話即時套用睡衣，回覆換姿勢後仍保持造型', (tester) async {
    _surface(tester, const Size(430, 932));
    WardrobeStore.reset();
    await WardrobeStore.load();
    addTearDown(WardrobeStore.reset);
    await tester.pumpWidget(_app(_Voice()));
    await tester.pump();
    final original = tester.widget<MascotScene>(find.byType(MascotScene)).asset;
    expect(original, contains('/mascot/core/'));

    await WardrobeStore.setOutfit('tumi_moon_pajamas');
    await tester.pump();
    expect(
      tester.widget<MascotScene>(find.byType(MascotScene)).asset,
      original.replaceFirst('/core/', '/moon_pajamas/'),
    );
    await _choose(tester, 'continue');
    expect(
      tester.widget<MascotScene>(find.byType(MascotScene)).asset,
      'assets/mascot/moon_pajamas/tumi_question.png',
    );
    await _choose(tester, 'begin');
    expect(
      tester.widget<MascotScene>(find.byType(MascotScene)).asset,
      'assets/mascot/moon_pajamas/tumi_happy.png',
    );
    expect(tester.takeException(), isNull);
    await _dispose(tester);
  });

  testWidgets('選項按住有回饋；取消不換句、不改版面；降低動態不縮放', (tester) async {
    _surface(tester, const Size(430, 932));
    final voice = _Voice();
    await tester.pumpWidget(_app(voice));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('roommate_subtitle')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    final feedback = find.byKey(const ValueKey('reply_press_hello_continue'));
    final size = tester.getSize(feedback);
    final position = tester.getTopLeft(feedback);
    Transform transform() => tester.widget<Transform>(
      find.descendant(of: feedback, matching: find.byType(Transform)).first,
    );
    final gesture = await tester.startGesture(
      tester.getCenter(_reply('continue')),
    );
    await tester.pump(const Duration(milliseconds: 120));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(transform().transform.storage[0], lessThan(1));
    expect(transform().transformHitTests, isFalse);
    expect(tester.getSize(feedback), size);
    expect(tester.getTopLeft(feedback), position);
    expect(voice.cues, hasLength(1), reason: '按住不提早選取或額外發聲');
    await gesture.cancel();
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(transform().transform.storage[0], 1);
    expect(_reply('begin'), findsNothing);

    final reducedGesture = await tester.startGesture(
      tester.getCenter(_reply('continue')),
    );
    await tester.pump(const Duration(milliseconds: 120));
    await tester.pump();
    await tester.pumpWidget(_app(voice, reduced: true));
    await tester.pump();
    expect(transform().transform.storage[0], 1);
    await reducedGesture.up();
    await tester.pump();
    expect(_reply('begin'), findsOneWidget);
    expect(voice.cues, hasLength(2));
    expect(tester.takeException(), isNull);
    await _dispose(tester);
  });

  testWidgets('字幕完成才接受選項；連點不能跳兩句；等候不逾時', (tester) async {
    _surface(tester, const Size(430, 932));
    final voice = _Voice();
    await tester.pumpWidget(_app(voice));
    expect(tester.widget<OutlinedButton>(_reply('continue')).onPressed, isNull);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(voice.cues, [SfxCue.tumiConfirm]);
    await tester.tap(find.byKey(const ValueKey('roommate_subtitle')));
    await tester.pump();
    final stale = tester.widget<OutlinedButton>(_reply('continue')).onPressed!;
    stale();
    stale();
    await tester.pump();
    expect(_reply('begin'), findsOneWidget);
    expect(tester.widget<OutlinedButton>(_reply('begin')).onPressed, isNull);
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 25));
    expect(_reply('begin'), findsOneWidget);
    expect(voice.cues, [SfxCue.tumiConfirm, SfxCue.tumiQuestion]);
    await _dispose(tester);
    expect(voice.disposed, isTrue);
  });

  for (final path in [
    ['continue', 'begin', 'finish'],
    ['continue', 'rest', 'home', 'together', 'finish'],
    ['continue', 'rest', 'quiet', 'finish'],
  ]) {
    testWidgets('可完成分支 ${path.join(' → ')}', (tester) async {
      _surface(tester, const Size(430, 932));
      final voice = _Voice();
      var closed = 0;
      await tester.pumpWidget(_app(voice, close: () => closed++));
      for (final id in path) {
        await _choose(tester, id);
      }
      expect(closed, 1);
      expect(voice.cues.length, path.length);
      await _dispose(tester);
    });
  }

  testWidgets('切分頁與背景暫停，返回不補播同句 MI', (tester) async {
    _surface(tester, const Size(430, 932));
    final voice = _Voice();
    await tester.pumpWidget(_app(voice));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pumpWidget(_app(voice, visible: false));
    await tester.pump(const Duration(seconds: 5));
    expect(tester.widget<OutlinedButton>(_reply('continue')).onPressed, isNull);
    expect(voice.cues.length, 1);
    expect(voice.stops, greaterThan(0));
    await tester.pumpWidget(_app(voice));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump(const Duration(seconds: 5));
    expect(voice.cues.length, 1);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    expect(
      tester.widget<OutlinedButton>(_reply('continue')).onPressed,
      isNotNull,
    );
    expect(voice.cues.length, 1);
    await _dispose(tester);
  });

  for (final spec in [
    (const Size(375, 667), 'zh', 1.0),
    (const Size(430, 932), 'en', 1.3),
    (const Size(375, 667), 'en', 2.0),
  ]) {
    testWidgets('正式 shell 約束、減少動態與長字 ${spec.$1} ${spec.$2} ${spec.$3}', (
      tester,
    ) async {
      _surface(tester, spec.$1);
      final voice = _Voice();
      await tester.pumpWidget(
        _app(voice, reduced: true, locale: spec.$2, scale: spec.$3),
      );
      await tester.pump();
      expect(
        tester.widget<OutlinedButton>(_reply('continue')).onPressed,
        isNotNull,
      );
      await _choose(tester, 'continue');
      await tester.pump();
      expect(
        tester.widget<OutlinedButton>(_reply('rest')).onPressed,
        isNotNull,
      );
      await _choose(tester, 'rest');
      await _choose(tester, 'home');
      expect(tester.takeException(), isNull);
      await _dispose(tester);
    });
  }

  for (final size in [const Size(430, 932), const Size(375, 667)]) {
    testWidgets('MainPage $size 導覽恢復、背景接縫與資料保留', (tester) async {
      _surface(tester, size);
      tester.view.padding = FakeViewPadding(
        top: size.width == 375 ? 20 : 59,
        bottom: size.width == 375 ? 0 : 34,
      );
      addTearDown(tester.view.resetPadding);
      final today = LogicalDate.stringFor(
        DateTime.now(),
        LogicalDate.defaultHour,
      );
      final saved = jsonEncode([
        {
          'id': 'read',
          'name': '讀兩頁書',
          'createdAt': today,
          'frequency': 'daily',
          'done': false,
        },
      ]);
      SharedPreferences.setMockInitialValues({
        'last_open_date': today,
        'habits': saved,
        'sfx_muted': true,
        'coin_last_login_date': today,
      });
      StoryEvents.debugCatalog = [];
      addTearDown(() => StoryEvents.debugCatalog = null);
      AudioSettingsService.sfxMuted.value = true;
      await tester.pumpWidget(const MyApp(startAtHome: true));
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      for (var i = 0; i < 15; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      final home = tester.state(find.byType(HomePage)) as dynamic;
      await home.loadHabits();
      await tester.pump();
      await tester.pump(const Duration(seconds: 5));
      final original = find.text('讀兩頁書').evaluate().single;
      final nav = find.byKey(const ValueKey('main_navigation'));
      final originalNav = nav.evaluate().single;
      await tester.tap(find.byKey(const ValueKey('roommate_entry')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump();
      expect(find.byType(CompanionDialoguePage), findsOneWidget);
      expect(
        find.byType(CompanionDialoguePage, skipOffstage: false),
        findsOneWidget,
        reason: '首頁導覽只推入一個閱讀器',
      );
      final roomRect = tester.getRect(
        find.byKey(const ValueKey('companion_room')),
      );
      final textRect = tester.getRect(
        find.byKey(const ValueKey('companion_reading_scroll')),
      );
      expect(
        roomRect.bottom,
        closeTo(textRect.top, 0.1),
        reason: '房間漸層與可捲動紙面共用同一條邊，不能留下水平空隙',
      );
      expect(textRect.bottom, lessThanOrEqualTo(size.height));
      expect(nav, findsNothing);
      expect(
        find.byKey(const ValueKey('main_navigation'), skipOffstage: false),
        findsOneWidget,
      );
      expect(find.text('讀兩頁書'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('companion_next')));
      await tester.pump();
      final savedCursor = CompanionStoryProgress.instance.state.active!
          .toJson();
      await tester.tap(find.byKey(const ValueKey('companion_close')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump();
      expect(find.text('讀兩頁書').evaluate().single, same(original));
      expect(nav.evaluate().single, same(originalNav));
      expect(CompanionStoryProgress.instance.state.days, 0);
      expect(find.byKey(const ValueKey('roommate_entry')), findsOneWidget);
      await home.loadHabits();
      await tester.pump();
      expect(find.byType(CompanionDialoguePage), findsNothing);
      expect(find.byKey(const ValueKey('roommate_entry')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('roommate_entry')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(
        tester
            .widget<CompanionDialoguePage>(find.byType(CompanionDialoguePage))
            .initialCursor!
            .toJson(),
        savedCursor,
      );
      await tester.tap(find.byKey(const ValueKey('companion_skip')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump();
      expect(CompanionStoryProgress.instance.state.days, 1);
      expect(find.byKey(const ValueKey('roommate_entry')), findsNothing);
      await home.loadHabits();
      await tester.pump();
      expect(find.byType(CompanionDialoguePage), findsNothing);
      expect(find.byKey(const ValueKey('roommate_entry')), findsNothing);
      expect(nav, findsOneWidget);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('habits'), saved);
      expect(tester.takeException(), isNull);
      await _dispose(tester);
      AudioSettingsService.sfxMuted.value = false;
    });
  }

  testWidgets(
    'daily story invitation yields to completion feedback and never auto-opens',
    (tester) async {
      _surface(tester, const Size(430, 932));
      final today = LogicalDate.stringFor(
        DateTime.now(),
        LogicalDate.defaultHour,
      );
      SharedPreferences.setMockInitialValues({
        PrefsKeys.lastOpenDate: today,
        PrefsKeys.coinLastLoginDate: today,
        PrefsKeys.sfxMuted: true,
        PrefsKeys.mascotPanelHintSeen: true,
        PrefsKeys.habits: jsonEncode([
          for (var i = 0; i < 2; i++)
            {
              'id': 'h$i',
              'name': '小日常$i',
              'createdAt': today,
              'frequency': 'daily',
              'done': false,
            },
        ]),
      });
      StoryEvents.debugCatalog = [];
      addTearDown(() => StoryEvents.debugCatalog = null);
      AudioSettingsService.sfxMuted.value = true;
      await tester.pumpWidget(const MyApp(startAtHome: true));
      await tester.pump();
      await tester.pump(const Duration(seconds: 6));
      final home = tester.state(find.byType(HomePage)) as dynamic;
      expect(find.byKey(const ValueKey('roommate_entry')), findsOneWidget);
      home.toggleHabit(0);
      await tester.pump();
      expect(find.byKey(const ValueKey('roommate_entry')), findsNothing);
      for (var i = 0; i < 140; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.byType(CompanionDialoguePage), findsNothing);
      expect(find.byKey(const ValueKey('roommate_entry')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('roommate_entry')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(
        tester
            .widget<CompanionDialoguePage>(find.byType(CompanionDialoguePage))
            .episode
            .id,
        'story_01',
      );
      await tester.tap(find.byKey(const ValueKey('companion_skip')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump();
      home.toggleHabit(1);
      for (var i = 0; i < 140; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.byKey(const ValueKey('roommate_entry')), findsNothing);
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      final progress = CompanionProgressState.fromJson(
        jsonDecode(prefs.getString(PrefsKeys.companionStoryProgress)!)
            as Map<String, dynamic>,
      );
      expect(progress.days, 1);
      expect(progress.creditedDayKeys, {today});
      expect(progress.completed['story_01']!.skipped, isTrue);
      expect(
        (jsonDecode(prefs.getString(PrefsKeys.habits)!) as List).every(
          (h) => h['done'] == true,
        ),
        isTrue,
      );
      expect(tester.takeException(), isNull);
      await _dispose(tester);
      AudioSettingsService.sfxMuted.value = false;
    },
  );

  for (final waitForFeedback in [false, true]) {
    testWidgets(
      'pending invitation yields to a new check, even after feedback: $waitForFeedback',
      (tester) async {
        final today = await _pumpCompletionInvitation(tester);
        final home = tester.state(find.byType(HomePage)) as dynamic;
        final store = await _holdInvitationWrite(tester);

        home.toggleHabit(1);
        await tester.pump();
        expect(home.debugPresentationActive, isTrue);
        final eventId = home.debugCompletionEventId;
        if (waitForFeedback) await _waitForFeedback(tester);
        store.release();
        await tester.pump();

        expect(find.byType(CompanionDialoguePage), findsNothing);
        expect(home.debugCompletionEventId, eventId);
        expect(home.debugPresentationActive, !waitForFeedback);
        expect(find.byKey(const ValueKey('main_navigation')), findsOneWidget);
        await _expectInvitationPersisted(today);
        final prefs = await SharedPreferences.getInstance();
        final saved = jsonDecode(prefs.getString(PrefsKeys.habits)!) as List;
        expect(saved.where((h) => h['done'] == true), hasLength(2));
        expect(
          find.byKey(const ValueKey('roommate_entry')),
          waitForFeedback ? findsOneWidget : findsNothing,
        );
        expect(tester.takeException(), isNull);
        await _dispose(tester);
      },
    );
  }

  testWidgets('pending story cannot replace a newer all-complete reaction', (
    tester,
  ) async {
    final today = await _pumpCompletionInvitation(tester, habitCount: 2);
    final home = tester.state(find.byType(HomePage)) as dynamic;
    final store = await _holdInvitationWrite(tester);
    home.toggleHabit(1);
    await tester.pump();
    expect(home.allDone0, isTrue);
    expect(home.debugSpeechOwnerSource, HomeSpeechSource.milestone);
    store.release();
    await tester.pump();

    expect(find.byType(CompanionDialoguePage), findsNothing);
    expect(home.debugSpeechOwnerSource, HomeSpeechSource.milestone);
    await _expectInvitationPersisted(today);
    final prefs = await SharedPreferences.getInstance();
    final saved = jsonDecode(prefs.getString(PrefsKeys.habits)!) as List;
    expect(saved.every((h) => h['done'] == true), isTrue);
    expect(tester.takeException(), isNull);
    await _dispose(tester);
  });

  testWidgets(
    'reload cancels pending entry even when the same event still fits',
    (tester) async {
      final today = await _pumpCompletionInvitation(tester);
      final home = tester.state(find.byType(HomePage)) as dynamic;
      final store = await _holdInvitationWrite(tester);
      await home.loadHabits();
      await tester.pump();
      store.release();
      await tester.pump();

      expect(find.byType(CompanionDialoguePage), findsNothing);
      expect(find.byKey(const ValueKey('main_navigation')), findsOneWidget);
      await _expectInvitationPersisted(today);
      expect(tester.takeException(), isNull);
      await _dispose(tester);
    },
  );

  testWidgets('toolbar action cancels entry before the dialogue has opened', (
    tester,
  ) async {
    final today = await _pumpCompletionInvitation(tester);
    final store = await _holdInvitationWrite(tester);
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('toolbar_audio')),
        matching: find.byType(IconButton),
      ),
    );
    await tester.pump();
    store.release();
    await tester.pump();

    expect(find.byType(CompanionDialoguePage), findsNothing);
    expect(find.byKey(const ValueKey('main_navigation')), findsOneWidget);
    await _expectInvitationPersisted(today);
    expect(tester.takeException(), isNull);
    await _dispose(tester);
  });

  testWidgets('closing and restoring the room cancels its pending invitation', (
    tester,
  ) async {
    final today = await _pumpCompletionInvitation(tester);
    final store = await _holdInvitationWrite(tester);
    MascotPanelPrefs.openValue.value = 0;
    await tester.pump();
    MascotPanelPrefs.openValue.value = 1;
    await tester.pump();
    store.release();
    await tester.pump();

    expect(find.byType(CompanionDialoguePage), findsNothing);
    await _expectInvitationPersisted(today);
    expect(tester.takeException(), isNull);
    await _dispose(tester);
  });

  testWidgets('leaving and returning to the route cancels pending entry', (
    tester,
  ) async {
    final today = await _pumpCompletionInvitation(tester);
    final store = await _holdInvitationWrite(tester);
    final navigator = Navigator.of(tester.element(find.byType(HomePage)));
    final routeClosed = navigator.push<void>(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('another route')),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    navigator.pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await routeClosed;
    store.release();
    await tester.pump();

    expect(find.byType(CompanionDialoguePage), findsNothing);
    expect(find.byKey(const ValueKey('main_navigation')), findsOneWidget);
    await _expectInvitationPersisted(today);
    expect(tester.takeException(), isNull);
    await _dispose(tester);
  });

  test('控制器拒绝偽造選項與上一句 callback', () async {
    final l = await AppLocalizations.delegate.load(const Locale('zh'));
    final dialogue = RoommateDialogueController();
    final first = dialogue.node.replies(l).single;
    expect(
      dialogue.choose(first, expectedNode: RoommateNode.hello, l10n: l),
      isFalse,
    );
    dialogue.reveal();
    expect(
      dialogue.choose(
        const RoommateReply('continue', '', RoommateNode.quiet),
        expectedNode: RoommateNode.hello,
        l10n: l,
      ),
      isFalse,
    );
    expect(
      dialogue.choose(first, expectedNode: RoommateNode.hello, l10n: l),
      isTrue,
    );
    dialogue.reveal();
    expect(
      dialogue.choose(first, expectedNode: RoommateNode.hello, l10n: l),
      isFalse,
    );
    expect(dialogue.node, RoommateNode.invitation);
    dialogue.dispose();
  });
}
