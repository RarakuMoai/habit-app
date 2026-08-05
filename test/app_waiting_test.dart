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
/// 要守的事實有三件：真的跑起來時畫面上出現的是那條共用的燈；**快的載入從頭到尾
/// 不亮**（一閃而過讀起來就是故障感，正好與這個 milestone 想要的相反）；
/// 以及之後沒有人再各自寫一顆裸 spinner。
///
/// 最後那條靠原始碼掃描，不是多此一舉：只有行為測試的話，新頁面照樣可以偷偷
/// 長出第十七種等待，而且全部測試都會是綠的。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// 讀出等待條**實際畫出來**的不透明度。
  ///
  /// 不能讀 `AnimatedOpacity.opacity`：那是目標值，淡入還沒跑完就已經是 1，
  /// 會把「正在亮」誤判成「亮完了」。要看它內部 FadeTransition 的當下值。
  double renderedOpacity(WidgetTester tester) {
    return tester
        .widget<FadeTransition>(
          find.descendant(
            of: find.byType(AppPageWaiting),
            matching: find.byType(FadeTransition),
          ),
        )
        .opacity
        .value;
  }

  group('慢到值得說一聲時才亮', () {
    testWidgets('門檻前完全不亮', (tester) async {
      await tester.pumpWidget(
        l10nTestApp(home: const Scaffold(body: AppPageWaiting())),
      );

      expect(renderedOpacity(tester), 0);
      await tester.pump(const Duration(milliseconds: 199));
      expect(renderedOpacity(tester), 0, reason: '門檻沒到就不該開始亮');

      await tester.pumpWidget(const SizedBox()); // 收掉待處理的 timer
    });

    testWidgets('過了門檻才淡入，而且是漸亮不是硬切', (tester) async {
      await tester.pumpWidget(
        l10nTestApp(home: const Scaffold(body: AppPageWaiting())),
      );

      await tester.pump(const Duration(milliseconds: 210));
      expect(renderedOpacity(tester), 0, reason: '剛過門檻，淡入才要開始');

      await tester.pump(const Duration(milliseconds: 90));
      final mid = renderedOpacity(tester);
      expect(mid, greaterThan(0));
      expect(mid, lessThan(1), reason: '硬切一樣是閃，只是慢了 200ms 才閃');

      await tester.pump(const Duration(milliseconds: 200));
      expect(renderedOpacity(tester), 1);

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('Reduce Motion 拿掉淡入，但門檻照舊', (tester) async {
      await tester.pumpWidget(
        l10nTestApp(
          home: const MediaQuery(
            data: MediaQueryData(disableAnimations: true),
            child: Scaffold(body: AppPageWaiting()),
          ),
        ),
      );

      await tester.pump(const Duration(milliseconds: 199));
      expect(renderedOpacity(tester), 0, reason: '門檻是語意，不是裝飾，不該被拿掉');

      await tester.pump(const Duration(milliseconds: 10));
      await tester.pump();
      expect(renderedOpacity(tester), 1, reason: '不淡入，過門檻就到位');

      await tester.pumpWidget(const SizedBox());
    });
  });

  group('跑起來時用的是共用的等待條', () {
    // 這兩頁讀的是本機 prefs，實測**只等一幀**就載完——正是門檻要擋掉的那種。
    // 所以斷言的重點不是「有沒有這個 widget」，而是「它從頭到尾沒有亮過」。
    testWidgets('家庭頁載得夠快，燈從頭到尾不亮', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(l10nTestApp(home: const FamilyPage()));

      expect(find.byType(AppPageWaiting), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(renderedOpacity(tester), 0);

      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(AppPageWaiting), findsNothing); // 載完就收掉
    });

    testWidgets('設定頁同理', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(l10nTestApp(home: const SettingsPage()));

      expect(find.byType(AppPageWaiting), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(renderedOpacity(tester), 0);

      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(AppPageWaiting), findsNothing);
    });

    testWidgets('等待條有無障礙標籤，不是一個沒有語意的色塊', (tester) async {
      await tester.pumpWidget(
        l10nTestApp(home: const Scaffold(body: AppPageWaiting())),
      );
      await tester.pump(const Duration(milliseconds: 400));

      final indicator = tester.widget<LinearProgressIndicator>(
        find.byType(LinearProgressIndicator),
      );
      expect(indicator.semanticsLabel, isNotEmpty);
      expect(indicator.color, AppWaiting.bar);

      await tester.pumpWidget(const SizedBox());
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
