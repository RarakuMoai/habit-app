import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:habit_app/pages/home/room_scene_painters.dart';
import 'package:habit_app/pages/home_page.dart';
import 'package:habit_app/utils/logical_date.dart';
import 'package:habit_app/utils/logical_day_coordinator.dart';
import 'package:habit_app/utils/prefs_keys.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'l10n_test_app.dart';

void _paintRoomSceneEffects({
  required double progress,
  required double elapsedSeconds,
  required Size size,
}) {
  final time = ValueNotifier<double>(elapsedSeconds);
  final painter = RoomSceneEffectsPainter(
    accent: const Color(0xFF66BB6A),
    progress: progress,
    time: time,
  );
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  try {
    expect(() => painter.paint(canvas, size), returnsNormally);
  } finally {
    recorder.endRecording().dispose();
    time.dispose();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    LogicalDayCoordinator.debugInstance = LogicalDayCoordinator();
  });

  tearDown(() {
    LogicalDayCoordinator.debugInstance = null;
  });

  test('completion aura stops 與三個 colors 等長、合法且遞增', () {
    final stops = RoomSceneEffectsPainter.completionAuraStops;
    expect(stops, hasLength(3));
    expect(stops.first, 0.0);
    expect(stops.last, 1.0);
    for (var i = 0; i < stops.length; i++) {
      expect(stops[i], inInclusiveRange(0.0, 1.0));
      if (i > 0) expect(stops[i], greaterThan(stops[i - 1]));
    }
  });

  const states = <String, double>{
    'progress 0 edge': 0.0,
    'progress 1 all-done': 1.0,
  };
  const sizes = <String, Size>{'small': Size(48, 80), 'home': Size(390, 844)};
  const phases = <String, double>{'start': 0.0, 'middle': 6.0, 'tail': 11.999};

  for (final state in states.entries) {
    for (final size in sizes.entries) {
      for (final phase in phases.entries) {
        test(
          '${state.key} / ${size.key} / phase ${phase.key} 可完成 paint',
          () => _paintRoomSceneEffects(
            progress: state.value,
            elapsedSeconds: phase.value,
            size: size.value,
          ),
        );
      }
    }
  }

  for (final done in [false, true]) {
    testWidgets('Home ${done ? 'all-done' : '未完成'} 掛載條件正確', (tester) async {
      final today = LogicalDate.stringFor(
        DateTime.now(),
        LogicalDate.defaultHour,
      );
      SharedPreferences.setMockInitialValues({
        PrefsKeys.lastOpenDate: today,
        PrefsKeys.habits: jsonEncode([
          {
            'id': 'read',
            'name': '閱讀',
            'done': done,
            'frequency': 'daily',
            'createdAt': '2026-01-01',
          },
        ]),
      });

      await tester.pumpWidget(l10nTestApp(home: const HomePage()));
      await tester.pump();
      final state = tester.state(find.byType(HomePage)) as dynamic;
      await state.loadHabits();
      await tester.pump();

      expect(
        find.byType(RoomSceneEffects),
        done ? findsOneWidget : findsNothing,
      );
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 5));
    });
  }
}
