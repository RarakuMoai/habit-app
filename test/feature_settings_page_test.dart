import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:habit_app/pages/feature_settings_page.dart';
import 'package:habit_app/utils/prefs_keys.dart';
import 'package:habit_app/utils/tab_catalog.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'l10n_test_app.dart';

void main() {
  test('底部導覽與設定預覽共用同一個換排門檻', () {
    expect(bottomNavUsesTwoRows(width: 390, itemCount: 6), isFalse);
    expect(bottomNavUsesTwoRows(width: 360, itemCount: 6), isFalse);
    expect(bottomNavUsesTwoRows(width: 320, itemCount: 6), isTrue);
    expect(bottomNavUsesTwoRows(width: 300, itemCount: 5), isFalse);
  });

  testWidgets('一般手機的六個分頁在設定預覽維持同一排', (tester) async {
    SharedPreferences.setMockInitialValues({
      PrefsKeys.timerEnabled: true,
      PrefsKeys.waterEnabled: true,
      PrefsKeys.weightTrackingEnabled: true,
      PrefsKeys.familyEnabled: true,
    });
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(l10nTestApp(home: const FeatureSettingsPage()));
    await tester.pumpAndSettle();

    final labels = ['習慣', '計時', '喝水', '體重', '家庭', '衣櫃'];
    final centers = [
      for (final label in labels) tester.getCenter(find.text(label).first),
    ];
    final minY = centers.map((p) => p.dy).reduce((a, b) => a < b ? a : b);
    final maxY = centers.map((p) => p.dy).reduce((a, b) => a > b ? a : b);

    expect(maxY - minY, lessThan(1));
    expect(tester.takeException(), isNull);
  });
}
