import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:habit_app/pages/family_page.dart';
import 'package:habit_app/pages/settings_page.dart';
import 'package:habit_app/utils/app_style.dart';
import 'package:habit_app/widgets/app_waiting.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'l10n_test_app.dart';

/// U3「等待的樣子」的守門測試。
///
/// 要守的事實是「全 app 的等待是同一盞燈」。這件事有兩面：真的跑起來時畫面上
/// 出現的是那條共用的燈（行為測試），以及**之後沒有人再各自寫一顆裸 spinner**
/// （原始碼掃描）。只有前者的話，新頁面照樣可以偷偷長出第十七種等待，
/// 而且全部測試都會是綠的。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('跑起來時出現的是共用的等待條', () {
    // ⚠️ 斷言的位置是「pumpWidget 之後、下一個 pump 之前」，不是隨便挑的：
    // 這些頁讀的是本機 prefs，等待狀態實際上**只存在第一幀**，再 pump 一次
    // 就已經載完了。多 pump 一次就會抓到 findsNothing 而誤以為壞掉。
    testWidgets('家庭頁載入中', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(l10nTestApp(home: const FamilyPage()));

      expect(find.byType(AppLoadingBar), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);

      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(AppLoadingBar), findsNothing); // 載完就收掉
    });

    testWidgets('設定頁載入中', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(l10nTestApp(home: const SettingsPage()));

      expect(find.byType(AppLoadingBar), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);

      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(AppLoadingBar), findsNothing);
    });

    testWidgets('等待條有無障礙標籤，不是一個沒有語意的色塊', (tester) async {
      await tester.pumpWidget(
        l10nTestApp(home: const Scaffold(body: AppPageWaiting())),
      );
      await tester.pump();

      final indicator = tester.widget<LinearProgressIndicator>(
        find.byType(LinearProgressIndicator),
      );
      expect(indicator.semanticsLabel, isNotEmpty);
      expect(indicator.color, AppWaiting.bar);
    });
  });

  test('lib/ 底下沒有新的裸 CircularProgressIndicator', () {
    // 兩個刻意的例外，各自有理由：
    const allowed = <String, String>{
      // 開發者工具頁不在品牌範圍內（visual_spec 的 grey/黑歸零也排除 lib/dev）。
      'lib/pages/dev_test_page.dart': '開發者測試頁，不面向使用者',
      // 控制項上的忙碌指示不是整頁等待：它要跟著按鈕的前景色走，換成整頁用的
      // 橫條會變成「按鈕裡塞一條進度條」。這一顆維持 spinner 是刻意的。
      'lib/pages/family/habit_tab.dart': '按鈕內的 14×14 忙碌指示，非整頁等待',
    };

    final offenders = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final path = entity.path;
      if (allowed.containsKey(path)) continue;
      final lines = entity.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (lines[i].contains('CircularProgressIndicator')) {
          offenders.add('$path:${i + 1}');
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          '整頁／整個分頁的等待請用 AppPageWaiting，不要各自寫 spinner。'
          '若這一處真的是控制項上的忙碌指示，把檔案加進本測試的 allowed 並寫明理由。',
    );
  });
}
