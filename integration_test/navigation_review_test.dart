// Compare materials with the same production navigation, fixture and room state.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:habit_app/main.dart' as app;
import 'package:integration_test/integration_test.dart';

import 'review_fixture.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Native navigation material comparison', (tester) async {
    seedExperienceReview();
    app.main();
    for (var i = 0; i < 50; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    final nav = find.byKey(const ValueKey('main_navigation'));
    expect(nav, findsOneWidget);
    final directory = Directory(
      '${Directory.systemTemp.path}/experience-review',
    );
    await directory.create(recursive: true);
    for (final page in [
      ('習慣', 'nav-habits'),
      ('喝水', 'nav-water'),
      ('衣櫃', 'nav-wardrobe'),
    ]) {
      await tester.tap(find.descendant(of: nav, matching: find.text(page.$1)));
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      final bytes = await binding.takeScreenshot(page.$2);
      final file = File('${directory.path}/${page.$2}.png');
      await file.writeAsBytes(bytes);
      debugPrint('REVIEW_SCREENSHOT ${file.path}');
      expect(tester.takeException(), isNull);
    }
  });
}
