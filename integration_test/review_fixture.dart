import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:habit_app/utils/logical_date.dart';
import 'package:habit_app/utils/prefs_keys.dart';
import 'package:habit_app/utils/story_catalog.dart';
import 'package:shared_preferences/shared_preferences.dart';

void seedExperienceReview() {
  if (!kDebugMode) throw StateError('Review fixtures are debug-only.');
  WidgetsFlutterBinding.ensureInitialized();
  final today = LogicalDate.stringFor(DateTime.now(), LogicalDate.defaultHour);
  final calendar = DateTime.now().toIso8601String().split('T').first;
  SharedPreferences.setMockInitialValues({
    PrefsKeys.onboardingDone: true,
    PrefsKeys.sfxMuted: true,
    PrefsKeys.legacyBgmMuted: true,
    PrefsKeys.storyUnlocked: jsonEncode([
      for (final e in storyCatalog)
        {'id': e.id, 'date': DateTime.now().toIso8601String()},
    ]),
    PrefsKeys.lastOpenDate: today,
    PrefsKeys.coinLastLoginDate: calendar,
    PrefsKeys.coinBalance: 128,
    PrefsKeys.mascotPanelHintSeen: true,
    PrefsKeys.userNickname: '小日',
    PrefsKeys.userHeight: 168.0,
    PrefsKeys.userWeight: 60.4,
    PrefsKeys.targetWeight: 58.0,
    PrefsKeys.userGender: '女',
    PrefsKeys.userBirthday: '1995-06-15',
    PrefsKeys.userActivityLevel: '輕度',
    PrefsKeys.timerEnabled: true,
    PrefsKeys.waterEnabled: true,
    PrefsKeys.weightTrackingEnabled: true,
    PrefsKeys.familyEnabled: true,
    PrefsKeys.waterCupMl: 250,
    PrefsKeys.waterGoalMl: 2000,
    PrefsKeys.waterGoalDate: today,
    PrefsKeys.waterDay(today): 4,
    PrefsKeys.habits: jsonEncode([
      {
        'id': 'review-read',
        'name': '閱讀 20 分鐘',
        'createdAt': '2026-01-01',
        'frequency': 'daily',
        'done': false,
      },
      {
        'id': 'review-tidy',
        'name': '整理一個小角落',
        'createdAt': '2026-01-01',
        'frequency': 'daily',
        'done': true,
      },
      {
        'id': 'review-water',
        'name': '喝足夠的水',
        'createdAt': '2026-01-01',
        'frequency': 'daily',
        'done': false,
      },
      {
        'id': 'review-walk',
        'name': '散步，留一點時間給自己',
        'createdAt': '2026-01-01',
        'frequency': 'weekly',
        'weeklyTarget': 3,
        'weeklyDates': <String>[],
        'done': false,
      },
    ]),
    PrefsKeys.weightRecords: jsonEncode([
      for (var i = 13; i >= 0; i--)
        {
          'date': LogicalDate.stringFor(
            DateTime.now().subtract(Duration(days: i)),
            LogicalDate.defaultHour,
          ),
          'weight': 60.4 + i * 0.08,
          'height': 168.0,
          'time': '08:30',
        },
    ]),
    PrefsKeys.children: jsonEncode([
      {'id': 'review-child', 'name': '小樂', 'avatar': '🐰', 'points': 80},
      {'id': 'review-child2', 'name': '小星', 'avatar': '🐱', 'points': 45},
    ]),
    PrefsKeys.childHabits: jsonEncode([
      {
        'id': 'review-ch1',
        'childId': 'review-child',
        'name': '把玩具送回家',
        'points': 10,
        'done': false,
      },
      {
        'id': 'review-ch2',
        'childId': 'review-child',
        'name': '刷牙',
        'points': 10,
        'done': true,
      },
    ]),
  });
}
