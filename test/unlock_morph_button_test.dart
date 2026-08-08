// 音樂盒的解鎖演出（2026-08-06）。
//
// 原本兩個問題：尚未購買用的是 `lock_open_rounded`（**打開**的鎖，語意相反），
// 而且購買成功是瞬間換圖，沒有「東西被打開了」的過程。
//
// 這組測試釘住演出的語意順序與衝擊點，不驗像素：
// 闔鎖 → （搖晃）→ 開鎖＋音效 → 加入圖示。

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:habit_app/utils/app_feedback.dart';
import 'package:habit_app/utils/sfx_service.dart';
import 'package:habit_app/widgets/unlock_morph_button.dart';

void main() {
  final cues = <SfxCue?>[];

  setUp(() {
    cues.clear();
    debugFeedbackSink = (cue, _) => cues.add(cue);
  });
  tearDown(() => debugFeedbackSink = null);

  /// 把 owned 掛在外部，模擬 store 的 ValueNotifier 翻面。
  late StateSetter setOuter;
  var owned = false;

  /// 音樂盒小卡上這顆鈕的實際寬度（14PM，兩欄格線 + 卡片內距 + 兩鈕平分）。
  ///
  /// ⚠️ **測試一定要給這個寬度，不能讓它自由伸展。** 在寬鬆的版面裡
  /// 「解鎖 30」放得下、`FittedBox` 不縮放，位移的 bug 就整個消失——上一輪
  /// 就是這樣被騙過去：測試綠燈、實機仍在滑。真正會出事的是**放不下**的情況。
  const kRealButtonWidth = 84.75;

  Future<void> pumpButton(
    WidgetTester tester, {
    bool reduceMotion = false,
    String lockedLabel = '解鎖 30',
  }) async {
    owned = false;
    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(disableAnimations: reduceMotion),
        child: MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: kRealButtonWidth,
                child: StatefulBuilder(
                  builder: (context, setState) {
                    setOuter = setState;
                    return UnlockMorphButton(
                      owned: owned,
                      lockedLabel: lockedLabel,
                      unlockedLabel: '加入',
                      unlockedIcon: Icons.playlist_add_rounded,
                      color: const Color(0xFF7A5C46),
                      onLockedTap: () {},
                      onUnlockedTap: () {},
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  void purchase() => setOuter(() => owned = true);

  /// 某個 widget 這一幀的實際不透明度。
  ///
  /// ⚠️ 兩組內容是用 `FadeTransition` 換的，**不是 `Opacity`**（為了只重畫不
  /// 重建，見元件裡的說明）。所以要往上找 FadeTransition 並讀它的 animation，
  /// 不能 `find.byType(Opacity)`——那樣永遠找不到，測試會假綠。
  double alphaOf(WidgetTester tester, Finder finder) {
    if (finder.evaluate().isEmpty) return 0;
    return tester
        .widgetList<FadeTransition>(
          find.ancestor(of: finder.first, matching: find.byType(FadeTransition)),
        )
        .fold<double>(1, (a, f) => a * f.opacity.value);
  }

  /// 某個圖示是否看得見（靜態鈕沒有包 FadeTransition，一律視為看得見）。
  bool visible(WidgetTester tester, IconData icon) {
    final finder = find.byIcon(icon);
    if (finder.evaluate().isEmpty) return false;
    return alphaOf(tester, finder) > 0.5;
  }

  testWidgets('尚未購買顯示「闔上」的鎖，不是打開的鎖', (tester) async {
    await pumpButton(tester);

    expect(find.byIcon(Icons.lock_rounded), findsOneWidget);
    expect(
      find.byIcon(Icons.lock_open_rounded),
      findsNothing,
      reason: '開著的鎖代表「已解鎖」，用在尚未購買上語意相反',
    );
    expect(find.text('解鎖 30'), findsOneWidget);
  });

  testWidgets('購買後照順序演：闔鎖 → 開鎖 → 加入', (tester) async {
    await pumpButton(tester);
    purchase();
    await tester.pump();

    // 蓄力＋搖晃期間：鎖還是闔著的，還沒開
    await tester.pump(kUnlockAnticipate);
    expect(
      visible(tester, Icons.lock_rounded),
      isTrue,
      reason: '搖晃是「還沒掙脫」，這時不能已經開了',
    );

    // 剛越過衝擊點：鎖彈開。
    // ⚠️ 只能往前跨一點點——淡出從衝擊點那一幀就開始了，跨太多鎖已經半透明，
    // 這條測的是「有沒有換成開著的鎖」，不該被淡出干擾。
    await tester.pump(
      kUnlockTotal * kUnlockImpactAt -
          kUnlockAnticipate +
          const Duration(milliseconds: 30),
    );
    expect(visible(tester, Icons.lock_open_rounded), isTrue);

    // 演完：化成加入圖示
    await tester.pump(kUnlockTotal);
    expect(find.byIcon(Icons.playlist_add_rounded), findsOneWidget);
    expect(find.byIcon(Icons.lock_rounded), findsNothing);
    expect(find.text('加入'), findsOneWidget);
  });

  testWidgets('兩聲各自落在自己的動作上，而且都只播一次', (tester) async {
    await pumpButton(tester);
    purchase();
    await tester.pump();

    // 搖晃開始 → 搖晃音；此時解鎖音還不能出現
    await tester.pump(kUnlockTotal * (kUnlockShakeAt + 0.02));
    expect(cues, [SfxCue.lockRattle], reason: '鎖開始掙扎才出這一聲');

    // 衝擊點之前：解鎖音還沒響
    await tester.pump(kUnlockTotal * (kUnlockImpactAt - kUnlockShakeAt - 0.10));
    expect(
      cues,
      isNot(contains(SfxCue.unlock)),
      reason: '購買完成不是衝擊點，鎖真的彈開才是',
    );

    await tester.pump(kUnlockTotal * 0.15);
    expect(cues, [SfxCue.lockRattle, SfxCue.unlock]);

    // 演完不會再補
    await tester.pump(kUnlockTotal);
    expect(cues, [SfxCue.lockRattle, SfxCue.unlock]);
  });

  testWidgets('Reduce Motion：不搖不縮放，但語意與音效都留著', (tester) async {
    await pumpButton(tester, reduceMotion: true);
    expect(find.byIcon(Icons.lock_rounded), findsOneWidget);

    purchase();
    await tester.pump();

    // 演出期間完全不該建出 Transform：搖晃與縮放正是要拿掉的那兩樣。
    await tester.pump(kUnlockTotalReduced * 0.5);
    expect(
      find.descendant(
        of: find.byType(UnlockMorphButton),
        matching: find.byType(Transform),
      ),
      findsNothing,
      reason: 'Reduce Motion 不該有搖晃或縮放',
    );

    await tester.pump(kUnlockTotalReduced);
    expect(find.byIcon(Icons.playlist_add_rounded), findsOneWidget);
    expect(
      cues,
      [SfxCue.unlock],
      reason: '解鎖音是事實回饋要留著；搖晃音描述的是不會發生的動作，該省略',
    );
  });

  testWidgets('淡出從鎖彈開那一幀就開始；不會疊字鬼影，也不會空出白膠囊', (tester) async {
    // 使用者定的節奏：「鑰匙鎖打開特效的那個時間點就要進入淡出」——不能等光都
    // 放完了畫面才開始變。
    //
    // 兩段幾乎不重疊（理由見 kUnlockMorph：同時淡入淡出時兩組內容互相穿插，
    // 實錄有約 280ms 讀成「≡+50 加入幣」），但也不能完全首尾相接——那樣交界
    // 處會空一顆膠囊出來。這條測試同時釘住這兩端。
    await pumpButton(tester, lockedLabel: '50 足跡幣');
    purchase();
    await tester.pump();

    double alpha(String text) => alphaOf(tester, find.text(text));

    var sawFadeOutStart = false;
    var blankMs = 0;
    var elapsed = 0;
    while (elapsed < kUnlockTotal.inMilliseconds) {
      await tester.pump(const Duration(milliseconds: 20));
      elapsed += 20;
      final out = alpha('50 足跡幣');
      final into = alpha('加入');

      if (elapsed <= 880) {
        expect(out, 1.0, reason: '彈開之前舊內容必須全不透明（${elapsed}ms）');
      }
      if (elapsed >= 1000 && elapsed <= 1300) {
        // 彈開後 100~400ms：淡出必須已經在走，但還沒走完
        expect(
          out,
          allOf(lessThan(1.0), greaterThan(0.0)),
          reason: '淡出沒有跟著彈開一起開始（${elapsed}ms，alpha=$out）',
        );
        sawFadeOutStart = true;
      }
      // 不能同時看得見——那正是同時淡入淡出被否決的原因（會讀成疊字鬼影）。
      expect(
        out > 0.02 && into > 0.02,
        isFalse,
        reason: '${elapsed}ms 兩組同時看得見（舊 $out／新 $into）→ 疊字鬼影',
      );
      // 也不能空太久。線性淡化首尾相接時，交界處兩邊同時趨近 0，會空出一顆
      // 白膠囊（實錄 1977ms 整顆是空的）；靠 easeIn／easeOut 快速通過低透明度
      // 的區間，空白才會縮到一幀以內。
      if (math.max(out, into) < 0.05) {
        blankMs += 20;
      } else {
        blankMs = 0;
      }
      expect(blankMs, lessThanOrEqualTo(40), reason: '${elapsed}ms 膠囊空了太久');
    }
    expect(sawFadeOutStart, isTrue);
  });

  testWidgets('演出全程沒有位移或縮放，而且淡入的就是最終樣貌', (tester) async {
    // 使用者實機回報兩次：先是「交界處文字縮排」，再是「加入的圖案往右滑才完成
    // 最終樣貌，我希望不要有滑動，單純最終樣貌淡入就好」。
    //
    // 根因是兩組內容共用一份版面：標籤從「解鎖 30」換成「加入」時內容變窄，
    // FittedBox 的 scaleDown 倍率跟著變（85pt 的鈕上是 0.70 → 1.00），整組
    // 連圖示帶文字放大 43%。改成兩組各排各的版之後，每一組都待在它靜態時的
    // 位置與大小上，只有透明度在動。
    //
    // 這條測試釘死兩件事：演出中每個元素的 Rect 恆定，且淡入那一組的 Rect
    // 等於演出結束後靜態鈕的 Rect（否則收尾會跳一下）。
    await pumpButton(tester, lockedLabel: '50 足跡幣');
    purchase();
    await tester.pump();

    final seen = <String, Rect>{};
    void track(String name, Finder finder, int ms) {
      if (finder.evaluate().isEmpty) return;
      final rect = tester.getRect(finder.first);
      final before = seen[name];
      if (before == null) {
        seen[name] = rect;
      } else {
        expect(rect, before, reason: '$name 在 ${ms}ms 動了：$before → $rect');
      }
    }

    for (var ms = 20; ms < kUnlockTotal.inMilliseconds; ms += 20) {
      await tester.pump(const Duration(milliseconds: 20));
      track('舊標籤', find.text('50 足跡幣'), ms);
      track('新標籤', find.text('加入'), ms);
      track('加入圖示', find.byIcon(Icons.playlist_add_rounded), ms);
    }
    expect(seen.keys, containsAll(['舊標籤', '新標籤', '加入圖示']));

    // 演完 → 靜態鈕。淡入時待的位置必須就是這裡。
    await tester.pump(kUnlockTotal);
    expect(
      tester.getRect(find.text('加入')),
      seen['新標籤'],
      reason: '淡入的位置不等於最終位置 → 收尾會跳一下',
    );
    expect(
      tester.getRect(find.byIcon(Icons.playlist_add_rounded)),
      seen['加入圖示'],
      reason: '淡入的圖示不等於最終圖示的位置與大小 → 就是使用者說的「往右滑」',
    );
  });

  testWidgets('一開始就已擁有 → 靜態加入鈕，不演出、不出聲', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: UnlockMorphButton(
              owned: true,
              lockedLabel: '解鎖 30',
              unlockedLabel: '加入',
              unlockedIcon: Icons.playlist_add_rounded,
              color: const Color(0xFF7A5C46),
              onLockedTap: () {},
              onUnlockedTap: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pump(kUnlockTotal);

    expect(find.byIcon(Icons.playlist_add_rounded), findsOneWidget);
    expect(cues, isEmpty, reason: '重新進頁面不該重播解鎖音');
  });
}
