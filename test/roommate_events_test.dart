import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:habit_app/l10n/app_localizations.dart';
import 'package:habit_app/utils/prefs_keys.dart';
import 'package:habit_app/utils/roommate_dialogue.dart';
import 'package:habit_app/utils/roommate_events.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('first conversation wins once and handling caps this logical day', () {
    const fresh = RoommateEventHistory();
    expect(
      fresh.eligible(day: '2026-09-10', completed: 0, total: 0),
      RoommateEvent.firstMeet,
    );
    final handled = fresh.handling(RoommateEvent.firstMeet, '2026-09-10');
    expect(handled.eligible(day: '2026-09-10', completed: 3, total: 3), isNull);
    expect(handled.eligible(day: '2026-09-11', completed: 0, total: 3), isNull);
    expect(
      handled.eligible(day: '2026-09-11', completed: 1, total: 3),
      RoommateEvent.smallWin,
    );
    expect(
      handled.eligible(day: '2026-09-11', completed: 3, total: 3),
      RoommateEvent.dayComplete,
    );
  });

  test(
    'opening or dismissing persists the cap without changing habit data',
    () async {
      SharedPreferences.setMockInitialValues({
        PrefsKeys.habits: 'existing-data',
      });
      final prefs = await SharedPreferences.getInstance();
      final handled = const RoommateEventHistory(
        firstMeetHandled: true,
      ).handling(RoommateEvent.smallWin, '2026-09-10');
      expect(await handled.save(prefs), isTrue);
      final restored = RoommateEventHistory.read(prefs);
      expect(
        restored.eligible(day: '2026-09-10', completed: 3, total: 3),
        isNull,
      );
      expect(
        restored.eligible(day: '2026-09-11', completed: 3, total: 3),
        RoommateEvent.dayComplete,
      );
      expect(prefs.getString(PrefsKeys.habits), 'existing-data');
      expect(jsonDecode(prefs.getString(PrefsKeys.roommateEventHistory)!), {
        'firstMeetHandled': true,
        'handledDay': '2026-09-10',
      });
    },
  );

  test(
    'malformed optional history falls back without breaking app loading',
    () async {
      for (final invalid in ['{broken', '[]', 2, '{"handledDay":3}']) {
        SharedPreferences.setMockInitialValues({
          PrefsKeys.roommateEventHistory: invalid,
        });
        final prefs = await SharedPreferences.getInstance();
        expect(RoommateEventHistory.read(prefs).firstMeetHandled, isFalse);
      }
    },
  );

  for (final event in [RoommateEvent.smallWin, RoommateEvent.dayComplete]) {
    test(
      '$event uses its own context and completes without a reward',
      () async {
        final l = await AppLocalizations.delegate.load(const Locale('zh'));
        final dialogue = RoommateDialogueController(
          initialNode: event.firstNode,
        );
        expect(dialogue.node, event.firstNode);
        dialogue.reveal();
        expect(
          dialogue.choose(
            dialogue.node.replies(l).first,
            expectedNode: dialogue.node,
            l10n: l,
          ),
          isTrue,
        );
        dialogue.reveal();
        expect(
          dialogue.choose(
            dialogue.node.replies(l).single,
            expectedNode: dialogue.node,
            l10n: l,
          ),
          isTrue,
        );
        expect(dialogue.finished, isTrue);
        dialogue.dispose();
      },
    );
  }
}
