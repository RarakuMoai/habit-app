import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:habit_app/pages/profile_edit_page.dart';
import 'package:habit_app/utils/prefs_keys.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'l10n_test_app.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('基本資料以彩色大字分區呈現，SE 尺寸可完整捲動', (tester) async {
    SharedPreferences.setMockInitialValues({
      PrefsKeys.userNickname: '小優',
      PrefsKeys.mascotName: '小白',
      PrefsKeys.userHeight: 165.0,
      PrefsKeys.userWeight: 55.0,
    });
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(l10nTestApp(home: const ProfileEditPage()));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('profile-edit-intro')), findsOneWidget);
    expect(find.text('讓小白更認識你'), findsOneWidget);
    expect(find.text('稱呼'), findsOneWidget);
    expect(find.text('你和小白想怎麼被叫'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('關於你'),
      160,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('關於你'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('身體數據'),
      160,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('身體數據'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('一週大概運動幾天？'),
      180,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump();

    expect(find.text('活動量'), findsOneWidget);
    expect(find.text('一週大概運動幾天？'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
