import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:habit_app/l10n/app_localizations.dart';
import 'package:habit_app/pages/companion_dialogue_page.dart';
import 'package:habit_app/utils/app_theme.dart';
import 'package:habit_app/utils/companion_story_catalog.dart';
import 'package:habit_app/utils/companion_story_progress.dart';
import 'package:habit_app/utils/mascot.dart';
import 'package:habit_app/utils/scene_time.dart';
import 'package:habit_app/utils/wardrobe_store.dart';
import 'package:habit_app/widgets/mascot_scene.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _episode = CompanionEpisode(
  id: 'reader_test',
  day: 1,
  kind: CompanionStoryKind.main,
  title: CompanionText('一起坐一下', 'A little time together'),
  beats: [
    CompanionBeat(
      id: 'greeting',
      lines: [
        CompanionText('你來了。', 'You are here.'),
        CompanionText('今天，想聊些什麼？', 'What would you like to talk about?'),
      ],
      choices: [
        CompanionChoice(
          id: 'quiet',
          label: CompanionText(
            '今天有點累，想先安靜坐一會，晚一點再慢慢聊。',
            'I am a little tired today. Could we sit quietly together for a while '
                'and talk about everything when I have had some time to rest?',
          ),
          emotion: MascotEmotion.smile,
          replies: [CompanionText('好，一起休息一下。', 'Of course. Let us rest.')],
        ),
        CompanionChoice(
          id: 'share',
          label: CompanionText(
            '我有件事想跟你說。',
            'There is something I want to tell you.',
          ),
          replies: [CompanionText('我在聽。', 'I am listening.')],
        ),
      ],
    ),
    CompanionBeat(
      id: 'ending',
      emotion: MascotEmotion.smile,
      lines: [CompanionText('下次見。', 'See you next time.')],
    ),
  ],
);

Finder _key(String key) => find.byKey(ValueKey(key));

void _surface(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _open(
  WidgetTester tester, {
  CompanionEpisode episode = _episode,
  CompanionCursor? cursor,
  bool preview = false,
  bool replay = false,
  bool reduce = true,
  double textScale = 1,
  String locale = 'zh',
  Future<bool> Function(CompanionCursor)? save,
  Future<bool> Function(bool)? finish,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(),
      locale: Locale(locale),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          disableAnimations: reduce,
          textScaler: TextScaler.linear(textScale),
          padding: const EdgeInsets.only(top: 24, bottom: 34),
        ),
        child: child!,
      ),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => Navigator.of(context).push<bool>(
                MaterialPageRoute(
                  builder: (_) => CompanionDialoguePage(
                    episode: episode,
                    initialCursor: cursor,
                    preview: preview,
                    replay: replay,
                    onSave: save,
                    onFinish: finish,
                  ),
                ),
              ),
              child: const Text('open reader'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open reader'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pump();
}

Future<void> _tap(WidgetTester tester, String key) async {
  final finder = _key(key);
  await Scrollable.ensureVisible(tester.element(finder), alignment: 0.5);
  await tester.pump();
  await tester.tap(finder);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pump();
}

Future<void> _dispose(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 25));
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({'untouched': 'saved record'});
    WardrobeStore.reset();
    SceneTimeController.debugInstance = SceneTimeController(
      clock: () => DateTime(2026, 9, 12, 13),
    );
  });
  tearDown(() {
    WardrobeStore.reset();
    SceneTimeController.instance.dispose();
    SceneTimeController.debugInstance = null;
  });

  testWidgets(
    'developer preview never calls save or finish, including restart',
    (tester) async {
      _surface(tester, const Size(390, 844));
      var saves = 0;
      var finishes = 0;
      await _open(
        tester,
        preview: true,
        save: (_) async {
          saves++;
          return true;
        },
        finish: (_) async {
          finishes++;
          return true;
        },
      );
      expect(_key('companion_mode'), findsOneWidget);
      expect(_key('companion_skip'), findsNothing);
      await _tap(tester, 'companion_next');
      await _tap(tester, 'companion_choice_quiet');
      expect(find.text('好，一起休息一下。'), findsOneWidget);
      await _tap(tester, 'companion_restart');
      expect(find.text('你來了。'), findsOneWidget);
      await _tap(tester, 'companion_next');
      await _tap(tester, 'companion_choice_share');
      await _tap(tester, 'companion_next');
      await _tap(tester, 'companion_next');
      expect(_key('companion_dialogue_page'), findsNothing);
      expect(saves, 0);
      expect(finishes, 0);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getKeys(), {'untouched'});
      expect(prefs.getString('untouched'), 'saved record');
      await _dispose(tester);
    },
  );

  testWidgets('archive replay is local until finish marks read without skip', (
    tester,
  ) async {
    _surface(tester, const Size(390, 844));
    var saves = 0;
    final finishes = <bool>[];
    await _open(
      tester,
      replay: true,
      save: (_) async {
        saves++;
        return true;
      },
      finish: (skipped) async {
        finishes.add(skipped);
        return true;
      },
    );
    expect(_key('companion_skip'), findsNothing);
    await _tap(tester, 'companion_next');
    await _tap(tester, 'companion_choice_quiet');
    await _tap(tester, 'companion_next');
    await _tap(tester, 'companion_next');
    expect(saves, 0);
    expect(finishes, [false]);
    await _dispose(tester);
  });

  testWidgets(
    'closing saves the visible cursor but does not finish the story',
    (tester) async {
      _surface(tester, const Size(390, 844));
      final cursors = <CompanionCursor>[];
      final finishes = <bool>[];
      await _open(
        tester,
        save: (cursor) async {
          cursors.add(cursor);
          return true;
        },
        finish: (skipped) async {
          finishes.add(skipped);
          return true;
        },
      );
      await _tap(tester, 'companion_next');
      expect(cursors.single.lineIndex, 1);
      await _tap(tester, 'companion_close');
      expect(_key('companion_dialogue_page'), findsNothing);
      expect(finishes, isEmpty);
      await _dispose(tester);
    },
  );

  testWidgets('system back does not complete or skip', (tester) async {
    _surface(tester, const Size(390, 844));
    var finished = false;
    await _open(
      tester,
      finish: (_) async {
        finished = true;
        return true;
      },
    );
    await tester.binding.handlePopRoute();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
    expect(finished, isFalse);
    expect(_key('companion_dialogue_page'), findsNothing);
    await _dispose(tester);
  });

  testWidgets(
    'explicit skip finishes with true and never synthesizes a choice',
    (tester) async {
      _surface(tester, const Size(390, 844));
      final finishes = <bool>[];
      final cursors = <CompanionCursor>[];
      await _open(
        tester,
        save: (cursor) async {
          cursors.add(cursor);
          return true;
        },
        finish: (skipped) async {
          finishes.add(skipped);
          return true;
        },
      );
      await _tap(tester, 'companion_skip');
      expect(finishes, [true]);
      expect(cursors, isEmpty);
      expect(_key('companion_dialogue_page'), findsNothing);
      await _dispose(tester);
    },
  );

  testWidgets('failed cursor save keeps line and choices and can retry', (
    tester,
  ) async {
    _surface(tester, const Size(390, 844));
    var attempts = 0;
    await _open(
      tester,
      cursor: CompanionCursor(episodeId: _episode.id, lineIndex: 1),
      save: (_) async => ++attempts > 1,
    );
    await _tap(tester, 'companion_choice_quiet');
    expect(find.text('今天，想聊些什麼？'), findsOneWidget);
    expect(find.text('好，一起休息一下。'), findsNothing);
    expect(_key('companion_choice_quiet'), findsOneWidget);
    expect(_key('companion_save_error'), findsOneWidget);
    await _tap(tester, 'companion_retry');
    expect(attempts, 2);
    expect(find.text('好，一起休息一下。'), findsOneWidget);
    expect(_key('companion_save_error'), findsNothing);
    await _dispose(tester);
  });

  testWidgets('thrown finish stays on last line until retry succeeds', (
    tester,
  ) async {
    _surface(tester, const Size(390, 844));
    var attempts = 0;
    await _open(
      tester,
      cursor: CompanionCursor(episodeId: _episode.id, beatIndex: 1),
      finish: (_) async {
        if (++attempts == 1) throw StateError('write failed');
        return true;
      },
    );
    await _tap(tester, 'companion_next');
    expect(find.text('下次見。'), findsOneWidget);
    expect(_key('companion_save_error'), findsOneWidget);
    await _tap(tester, 'companion_retry');
    expect(attempts, 2);
    expect(_key('companion_dialogue_page'), findsNothing);
    await _dispose(tester);
  });

  testWidgets('pending save blocks double tap and back until cursor commits', (
    tester,
  ) async {
    _surface(tester, const Size(390, 844));
    final pending = Completer<bool>();
    var saves = 0;
    await _open(
      tester,
      save: (_) {
        saves++;
        return pending.future;
      },
    );
    await _tap(tester, 'companion_next');
    await tester.tap(_key('companion_next'));
    await tester.pump();
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(saves, 1);
    expect(find.text('你來了。'), findsOneWidget);
    expect(_key('companion_dialogue_page'), findsOneWidget);
    pending.complete(true);
    await tester.pump();
    await tester.pump();
    expect(find.text('今天，想聊些什麼？'), findsOneWidget);
    await _dispose(tester);
  });

  for (final locale in ['zh', 'en']) {
    testWidgets(
      '320x568, text 2x, $locale choices remain scrollable and tappable',
      (tester) async {
        _surface(tester, const Size(320, 568));
        await _open(
          tester,
          preview: true,
          locale: locale,
          textScale: 2,
          cursor: CompanionCursor(episodeId: _episode.id, lineIndex: 1),
        );
        expect(tester.takeException(), isNull);
        final closeSize = tester.getSize(_key('companion_close'));
        expect(closeSize.width, greaterThanOrEqualTo(48));
        expect(closeSize.height, greaterThanOrEqualTo(48));
        final choiceSize = tester.getSize(_key('companion_choice_quiet'));
        expect(choiceSize.height, greaterThanOrEqualTo(48));
        await _tap(tester, 'companion_choice_quiet');
        expect(
          find.text(locale == 'en' ? 'Of course. Let us rest.' : '好，一起休息一下。'),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        await _tap(tester, 'companion_next');
        await _tap(tester, 'companion_next');
        expect(_key('companion_dialogue_page'), findsNothing);
        expect(tester.takeException(), isNull);
        await _dispose(tester);
      },
    );
  }

  testWidgets('reduce motion shows full subtitle and disables scene motion', (
    tester,
  ) async {
    _surface(tester, const Size(390, 844));
    await _open(tester, preview: true);
    expect(find.text('你來了。'), findsOneWidget);
    final scene = tester.widget<MascotScene>(find.byType(MascotScene));
    expect(scene.reduceMotion, isTrue);
    expect(scene.poseTransition, MascotPoseTransition.cut);
    await _tap(tester, 'companion_next');
    expect(find.text('今天，想聊些什麼？'), findsOneWidget);
    await _dispose(tester);
  });
}
