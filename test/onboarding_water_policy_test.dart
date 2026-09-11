import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:habit_app/utils/prefs_keys.dart';
import 'package:habit_app/utils/water_habit_link.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'story onboarding opens water without creating the first habit',
    () async {
      SharedPreferences.setMockInitialValues({
        PrefsKeys.waterEnabled: true,
        PrefsKeys.onboardingStoryVersion: 1,
      });
      final prefs = await SharedPreferences.getInstance();
      expect(await WaterHabitLink.reconcile(prefs), isFalse);
      expect(prefs.getString(PrefsKeys.habits), isNull);
      expect(prefs.getBool(PrefsKeys.waterEnabled), isTrue);
      // Explicit feature actions can still create the linked habit.
      expect(await WaterHabitLink.ensureHabit(prefs), isTrue);
      expect(await WaterHabitLink.reconcile(prefs), isFalse);
      expect(
        jsonDecode(prefs.getString(PrefsKeys.habits)!) as List,
        hasLength(1),
      );
    },
  );

  test(
    'legacy enabled tools and existing linked habits still reconcile',
    () async {
      SharedPreferences.setMockInitialValues({PrefsKeys.waterEnabled: true});
      final prefs = await SharedPreferences.getInstance();
      expect(await WaterHabitLink.reconcile(prefs), isTrue);
      expect(WaterHabitLink.hasHabit(prefs), isTrue);
      await prefs.setInt(PrefsKeys.onboardingStoryVersion, 1);
      await prefs.setBool(PrefsKeys.waterEnabled, false);
      expect(await WaterHabitLink.reconcile(prefs), isTrue);
      expect(prefs.getBool(PrefsKeys.waterEnabled), isTrue);
    },
  );
}
