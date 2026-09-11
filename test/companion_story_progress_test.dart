import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:habit_app/utils/companion_story_catalog.dart';
import 'package:habit_app/utils/companion_story_progress.dart';
import 'package:habit_app/utils/prefs_keys.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'shared_preferences_failure_test_helper.dart';

CompanionSession _readToEnd(
  CompanionEpisode episode, [
  CompanionCursor? cursor,
]) {
  var session = CompanionSession(episode, cursor);
  for (var guard = 0; guard < 500 && !session.atEnd; guard++) {
    session = CompanionSession(
      episode,
      session.choices.isEmpty
          ? session.advance()
          : session.choose(session.choices.first.id),
    );
  }
  expect(session.atEnd, isTrue, reason: '${episode.id} must terminate');
  return session;
}

String _day(int index) => DateTime(
  2026,
).add(Duration(days: index)).toIso8601String().substring(0, 10);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('CompanionSession', () {
    test('every localized catalog branch has stable IDs and terminates', () {
      for (final episode in companionEpisodes) {
        final initial = CompanionSession(episode);
        final finished = _readToEnd(episode);
        expect(initial.cursor.beatIndex, 0);
        expect(initial.cursor.choices, isEmpty);
        expect(finished.text.resolve('zh'), isNotEmpty);
        expect(finished.text.resolve('en'), isNotEmpty);
        expect(finished.advance().toJson(), finished.cursor.toJson());
        for (var beatIndex = 0; beatIndex < episode.beats.length; beatIndex++) {
          final beat = episode.beats[beatIndex];
          for (final choice in beat.choices) {
            final question = CompanionSession(
              episode,
              CompanionCursor(
                episodeId: episode.id,
                beatIndex: beatIndex,
                lineIndex: beat.lines.length - 1,
              ),
            );
            expect(question.advance().toJson(), question.cursor.toJson());
            final response = CompanionSession(
              episode,
              question.choose(choice.id),
            );
            expect(response.cursor.choices[beat.id], choice.id);
            expect(
              response.text.resolve('en'),
              choice.replies.first.resolve('en'),
            );
            expect(question.cursor.choices, isEmpty);
            _readToEnd(episode, response.cursor);
          }
        }
      }
    });

    test(
      'stale positions and removed choices are safe without made-up answers',
      () {
        final episode = companionEpisodes.first;
        final stale = CompanionSession(
          episode,
          CompanionCursor(
            episodeId: episode.id,
            beatIndex: 999,
            lineIndex: -1,
            choiceId: 'removed',
            replyIndex: 999,
            choices: const {'old_beat': 'old_choice'},
          ),
        );
        expect(stale.cursor.beatIndex, 0);
        expect(stale.cursor.lineIndex, 0);
        expect(stale.cursor.choiceId, isNull);
        expect(stale.cursor.choices, {'old_beat': 'old_choice'});
        expect(stale.choose('not-a-choice').toJson(), stale.cursor.toJson());
        final other = CompanionSession(
          episode,
          CompanionCursor(episodeId: 'another'),
        );
        expect(other.cursor.choices, isEmpty);
        expect(other.cursor.episodeId, episode.id);
      },
    );
  });

  group('CompanionStoryProgress', () {
    test('daily double taps are serialized and grant only one day', () async {
      final store = CompanionStoryProgress();
      await store.load();
      final episode = store.nextEpisode(_day(0))!;
      await store.begin(episode.id);
      var notifications = 0;
      store.addListener(() => notifications++);
      final result = await Future.wait(
        List.generate(
          12,
          (_) => store.finish(episode.id, dayKey: _day(0), skipped: true),
        ),
      );
      expect(result, everyElement(isTrue));
      expect(store.state.days, 1);
      expect(store.state.completed.length, 1);
      expect(store.state.completed[episode.id]!.firstCompletedAt, _day(0));
      expect(store.state.completed[episode.id]!.read, isFalse);
      expect(store.state.active, isNull);
      expect(notifications, 1);
      expect(store.nextEpisode(_day(0)), isNull);
    });

    test(
      'awaits a successful write before exposing a choice or notifying',
      () async {
        final prefs = await SharedPreferences.getInstance();
        Completer<bool>? pending;
        String? pendingValue;
        final store = CompanionStoryProgress(
          prefs: prefs,
          writeString: (key, value) {
            if (pending == null) return prefs.setString(key, value);
            pendingValue = value;
            return pending.future;
          },
        );
        await store.load();
        final episode = store.nextEpisode(_day(0))!;
        await store.begin(episode.id);
        final initial = store.state.active!.toJson();
        final candidate = _readToEnd(episode).cursor;
        var notifications = 0;
        store.addListener(() => notifications++);
        pending = Completer<bool>();
        final writing = store.saveCursor(candidate);
        await Future<void>.delayed(Duration.zero);
        expect(store.state.active!.toJson(), initial);
        expect(notifications, 0);
        await prefs.setString(PrefsKeys.companionStoryProgress, pendingValue!);
        pending.complete(true);
        expect(await writing, isTrue);
        expect(store.state.active!.toJson(), candidate.toJson());
        expect(notifications, 1);
      },
    );

    for (final throwSynchronously in [false, true]) {
      test(
        'failed ${throwSynchronously ? 'throw' : 'false'} write preserves state, native save and retry',
        () async {
          final prefs = await SharedPreferences.getInstance();
          final store = CompanionStoryProgress(prefs: prefs);
          await store.load();
          final episode = store.nextEpisode(_day(0))!;
          await store.begin(episode.id);
          final before = prefs.getString(PrefsKeys.companionStoryProgress);
          final stateBefore = store.state;
          var notifications = 0;
          store.addListener(() => notifications++);
          installFailFirstWriteStore(
            'flutter.${PrefsKeys.companionStoryProgress}',
            throwSynchronously: throwSynchronously,
          );
          expect(
            await store.finish(episode.id, dayKey: _day(0), skipped: true),
            isFalse,
          );
          expect(identical(store.state, stateBefore), isTrue);
          expect(notifications, 0);
          expect(prefs.getString(PrefsKeys.companionStoryProgress), before);
          final reloaded = CompanionStoryProgress(prefs: prefs);
          expect(await reloaded.load(), isTrue);
          expect(reloaded.state.days, 0);
          expect(reloaded.state.active!.episodeId, episode.id);
          expect(
            await store.finish(episode.id, dayKey: _day(0), skipped: true),
            isTrue,
          );
          expect(store.state.days, 1);
        },
      );
    }

    test(
      'reload resumes an actual response; skip stores selected answers only',
      () async {
        final store = CompanionStoryProgress();
        await store.load();
        final episode = store.nextEpisode(_day(0))!;
        await store.begin(episode.id);
        var session = CompanionSession(episode);
        while (session.choices.isEmpty && !session.atEnd) {
          session = CompanionSession(episode, session.advance());
        }
        expect(session.choices, isNotEmpty);
        final selected = session.choices.last;
        session = CompanionSession(episode, session.choose(selected.id));
        await store.saveCursor(session.cursor);
        final resumed = CompanionStoryProgress();
        await resumed.load();
        expect(resumed.state.days, 0);
        expect(resumed.state.completed, isEmpty);
        expect(resumed.state.active!.toJson(), session.cursor.toJson());
        expect(
          CompanionSession(episode, resumed.state.active).text.resolve('en'),
          selected.replies.first.resolve('en'),
        );
        await resumed.finish(episode.id, dayKey: _day(0), skipped: true);
        final record = resumed.state.completed[episode.id]!;
        expect(record.choices, session.cursor.choices);
        expect(record.skipped, isTrue);
        expect(record.read, isFalse);
        expect(resumed.state.days, 1);
      },
    );

    test(
      'normal completion requires final line; replay only clears unread',
      () async {
        final store = CompanionStoryProgress();
        await store.load();
        final episode = store.nextEpisode(_day(0))!;
        await store.begin(episode.id);
        expect(
          await store.finish(episode.id, dayKey: _day(0), skipped: false),
          isFalse,
        );
        await store.finish(episode.id, dayKey: _day(0), skipped: true);
        final before = store.state.toJson();
        final savedAnswers = store.state.completed[episode.id]!.choices;
        // The pure reader is the entirety of a developer preview, including choice.
        _readToEnd(episode);
        expect(store.state.toJson(), before);
        expect(await store.begin(episode.id), isFalse);
        await store.markRead(episode.id);
        expect(store.state.days, 1);
        expect(store.state.completed[episode.id]!.firstCompletedAt, _day(0));
        expect(store.state.completed[episode.id]!.choices, savedAnswers);
        expect(store.state.completed[episode.id]!.skipped, isTrue);
        expect(store.state.completed[episode.id]!.read, isTrue);
        expect(await store.markRead('unknown'), isFalse);
      },
    );

    test(
      'completed normal reading is read and keeps real chosen answers',
      () async {
        final store = CompanionStoryProgress();
        await store.load();
        final episode = store.nextEpisode(_day(0))!;
        await store.begin(episode.id);
        final end = _readToEnd(episode);
        await store.saveCursor(end.cursor);
        expect(
          await store.finish(episode.id, dayKey: _day(0), skipped: false),
          isTrue,
        );
        expect(store.state.completed[episode.id]!.read, isTrue);
        expect(store.state.completed[episode.id]!.skipped, isFalse);
        expect(store.state.completed[episode.id]!.choices, end.cursor.choices);
      },
    );

    test(
      'distinct eligible stories may unlock on same day without extra credit',
      () async {
        final store = CompanionStoryProgress();
        await store.load();
        final first = store.nextEpisode(_day(0))!;
        await store.begin(first.id);
        await store.finish(first.id, dayKey: _day(0), skipped: true);
        final second = companionEpisodeById('daily_02')!;
        expect(await store.begin(second.id), isTrue);
        expect(
          await store.finish(second.id, dayKey: _day(0), skipped: true),
          isTrue,
        );
        expect(store.state.days, 1);
        expect(store.state.completed.keys, containsAll([first.id, second.id]));
        expect(await store.begin(companionEpisodes.last.id), isFalse);
      },
    );

    test(
      'all 90 days remain reachable through daily gaps, then growth is capped',
      () async {
        final store = CompanionStoryProgress();
        await store.load();
        final firstDates = <String, String>{};
        var repeatedDaily = false;
        for (var day = 0; day < 95; day++) {
          final episode = store.nextEpisode(_day(day));
          expect(
            episode,
            isNotNull,
            reason: 'Companionship must not stall on day $day',
          );
          if (store.state.completed.containsKey(episode!.id)) {
            expect(episode.kind, CompanionStoryKind.daily);
            repeatedDaily = true;
          }
          firstDates.putIfAbsent(episode.id, () => _day(day));
          expect(await store.begin(episode.id), isTrue);
          expect(
            await store.finish(episode.id, dayKey: _day(day), skipped: true),
            isTrue,
          );
          expect(store.state.days, (day + 1).clamp(0, 90));
          expect(
            store.state.completed[episode.id]!.firstCompletedAt,
            firstDates[episode.id],
          );
          expect(store.nextEpisode(_day(day)), isNull);
        }
        expect(repeatedDaily, isTrue);
        expect(
          store.state.completed.keys,
          containsAll(companionEpisodes.map((e) => e.id)),
        );
        // Switching back to a previously credited logical day is not a new day.
        expect(store.nextEpisode(_day(2)), isNull);
        expect(store.nextEpisode(_day(140)), isNotNull);
        expect(store.state.days, 90);
      },
    );

    test(
      'reload after clearing preferences does not resurrect cached progress',
      () async {
        final prefs = await SharedPreferences.getInstance();
        final store = CompanionStoryProgress(prefs: prefs);
        await store.load();
        final first = store.nextEpisode(_day(0))!;
        await store.begin(first.id);
        await store.finish(first.id, dayKey: _day(0), skipped: true);
        await store.begin('daily_02');
        expect(store.state.days, 1);
        expect(store.state.active, isNotNull);

        await store.settleWrites();
        await prefs.clear();
        expect(await store.reload(), isTrue);
        expect(store.loaded, isTrue);
        expect(store.loadError, isNull);
        expect(store.state.days, 0);
        expect(store.state.completed, isEmpty);
        expect(store.state.creditedDayKeys, isEmpty);
        expect(store.state.active, isNull);
        expect(prefs.containsKey(PrefsKeys.companionStoryProgress), isFalse);
        expect(store.nextEpisode(_day(0))!.id, first.id);
        // The previously credited logical day is available in the genuinely new
        // save, and the old daily cursor cannot write itself back after reset.
        expect(
          await store.saveCursor(CompanionCursor(episodeId: 'daily_02')),
          isFalse,
        );
        expect(prefs.containsKey(PrefsKeys.companionStoryProgress), isFalse);
        await store.begin(first.id);
        await store.finish(first.id, dayKey: _day(0), skipped: true);
        expect(store.state.days, 1);
        expect(store.state.completed.keys, [first.id]);
      },
    );

    test(
      'reload adopts a restored snapshot and clears an earlier load error',
      () async {
        final prefs = await SharedPreferences.getInstance();
        final store = CompanionStoryProgress(prefs: prefs);
        await store.load();
        final first = store.nextEpisode(_day(0))!;
        await store.begin(first.id);
        await store.finish(first.id, dayKey: _day(0), skipped: true);
        final restoredCursor = _readToEnd(
          companionEpisodeById('daily_03')!,
        ).cursor;
        final restored = CompanionProgressState(
          days: 12,
          creditedDayKeys: {for (var day = 0; day < 12; day++) _day(day)},
          completed: {
            first.id: CompanionCompletion(
              firstCompletedAt: '2025-12-20',
              skipped: false,
              read: true,
              choices: const {'preserved_beat': 'preserved_choice'},
            ),
          },
          active: restoredCursor,
          extra: const {
            'restored_metadata': {'keep': true},
          },
        );
        // A failed reload must not leave the old one-day save looking usable.
        await prefs.setString(
          PrefsKeys.companionStoryProgress,
          '{"version": 2}',
        );
        expect(await store.reload(), isFalse);
        expect(store.loadError, isNotNull);
        expect(store.nextEpisode(_day(20)), isNull);
        await prefs.setString(
          PrefsKeys.companionStoryProgress,
          jsonEncode(restored.toJson()),
        );
        expect(await store.reload(), isTrue);
        expect(store.loadError, isNull);
        expect(store.state.toJson(), restored.toJson());
        expect(store.nextEpisode(_day(20))!.id, restoredCursor.episodeId);
        expect(store.state.completed[first.id]!.firstCompletedAt, '2025-12-20');
      },
    );

    test(
      'settleWrites drains pending and queued writes before clear and reload',
      () async {
        final prefs = await SharedPreferences.getInstance();
        final gate = Completer<void>();
        var holdWrites = false;
        final store = CompanionStoryProgress(
          prefs: prefs,
          writeString: (key, value) async {
            if (holdWrites) await gate.future;
            return prefs.setString(key, value);
          },
        );
        await store.load();
        final first = store.nextEpisode(_day(0))!;
        await store.begin(first.id);
        holdWrites = true;
        final finishing = store.finish(
          first.id,
          dayKey: _day(0),
          skipped: true,
        );
        final queuedBegin = store.begin('daily_02');
        var cleared = false;
        final resetting = () async {
          await store.settleWrites();
          await prefs.clear();
          cleared = true;
          expect(await store.reload(), isTrue);
        }();
        await Future<void>.delayed(Duration.zero);
        expect(cleared, isFalse);
        expect(store.state.days, 0);
        expect(store.state.active!.episodeId, first.id);
        gate.complete();
        expect(await finishing, isTrue);
        expect(await queuedBegin, isTrue);
        await resetting;
        expect(cleared, isTrue);
        await prefs.reload();
        expect(prefs.containsKey(PrefsKeys.companionStoryProgress), isFalse);
        expect(store.state.days, 0);
        expect(store.state.completed, isEmpty);
        expect(store.state.active, isNull);
        expect(store.state.creditedDayKeys, isEmpty);
      },
    );

    test('absence does not consume, erase or penalize progress', () async {
      final store = CompanionStoryProgress();
      await store.load();
      final episode = store.nextEpisode(_day(0))!;
      await store.begin(episode.id);
      await store.finish(episode.id, dayKey: _day(0), skipped: true);
      expect(store.nextEpisode(_day(60))!.day, 2);
      expect(store.state.days, 1);
      expect(store.nextEpisode('2026-02-30'), isNull);
      expect(
        await store.finish('unknown', dayKey: _day(60), skipped: true),
        isFalse,
      );
    });

    for (final raw in [
      'not json',
      '',
      '{"version":2}',
      '{"version":1,"days":"bad"}',
    ]) {
      test(
        'unrecognized/corrupt save remains byte-for-byte intact: $raw',
        () async {
          SharedPreferences.setMockInitialValues({
            PrefsKeys.companionStoryProgress: raw,
          });
          final prefs = await SharedPreferences.getInstance();
          final store = CompanionStoryProgress(prefs: prefs);
          expect(await store.load(), isFalse);
          expect(store.loadError, isNotNull);
          expect(store.nextEpisode(_day(0)), isNull);
          expect(await store.begin(companionEpisodes.first.id), isFalse);
          expect(
            await store.saveCursor(
              CompanionCursor(episodeId: companionEpisodes.first.id),
            ),
            isFalse,
          );
          expect(
            await store.finish(
              companionEpisodes.first.id,
              dayKey: _day(0),
              skipped: true,
            ),
            isFalse,
          );
          expect(await store.markRead(companionEpisodes.first.id), isFalse);
          expect(prefs.getString(PrefsKeys.companionStoryProgress), raw);
        },
      );
    }

    test('unknown records and metadata survive normal writes', () async {
      final seed = CompanionProgressState(
        completed: {
          'future_event': CompanionCompletion(
            firstCompletedAt: _day(0),
            skipped: true,
            read: false,
            choices: const {'future_beat': 'future_choice'},
            extra: const {'future_flag': 17},
          ),
        },
        extra: const {
          'future_root': {'id': 'keep'},
        },
      ).toJson();
      SharedPreferences.setMockInitialValues({
        PrefsKeys.companionStoryProgress: jsonEncode(seed),
      });
      final store = CompanionStoryProgress();
      expect(await store.load(), isTrue);
      final episode = store.nextEpisode(_day(1))!;
      await store.begin(episode.id);
      await store.finish(episode.id, dayKey: _day(1), skipped: true);
      final output = store.state.toJson();
      expect(output['future_root'], seed['future_root']);
      expect(
        (output['completed'] as Map)['future_event'],
        (seed['completed'] as Map)['future_event'],
      );
    });

    test(
      'unknown active story is retained and cannot be overwritten by begin',
      () async {
        final original = jsonEncode(
          CompanionProgressState(
            active: CompanionCursor(
              episodeId: 'future_episode',
              beatIndex: 12,
              lineIndex: 3,
              choices: const {'future_beat': 'future_choice'},
              extra: const {'future_cursor': 'keep'},
            ),
          ).toJson(),
        );
        SharedPreferences.setMockInitialValues({
          PrefsKeys.companionStoryProgress: original,
        });
        final prefs = await SharedPreferences.getInstance();
        final store = CompanionStoryProgress(prefs: prefs);
        expect(await store.load(), isTrue);
        expect(store.state.active!.episodeId, 'future_episode');
        expect(store.nextEpisode(_day(0)), isNull);
        expect(await store.begin(companionEpisodes.first.id), isFalse);
        expect(prefs.getString(PrefsKeys.companionStoryProgress), original);
      },
    );

    test(
      'public maps and sets cannot mutate persisted state behind the store',
      () async {
        final store = CompanionStoryProgress();
        await store.load();
        expect(
          () => store.state.creditedDayKeys.add(_day(0)),
          throwsUnsupportedError,
        );
        expect(() => store.state.completed.clear(), throwsUnsupportedError);
        await store.begin(companionEpisodes.first.id);
        expect(
          () => store.state.active!.choices['a'] = 'b',
          throwsUnsupportedError,
        );
      },
    );
  });
}
