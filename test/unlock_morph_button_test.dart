// 音樂盒的解鎖演出（2026-08-06）。
//
// 原本兩個問題：尚未購買用的是 `lock_open_rounded`（**打開**的鎖，語意相反），
// 而且購買成功是瞬間換圖，沒有「東西被打開了」的過程。
//
// 這組測試釘住演出的語意順序與衝擊點，不驗像素：
// 闔鎖 → （搖晃）→ 開鎖＋音效 → 加入圖示。

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

  Future<void> pumpButton(
    WidgetTester tester, {
    bool reduceMotion = false,
  }) async {
    owned = false;
    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(disableAnimations: reduceMotion),
        child: MaterialApp(
          home: Scaffold(
            body: Center(
              child: StatefulBuilder(
                builder: (context, setState) {
                  setOuter = setState;
                  return UnlockMorphButton(
                    owned: owned,
                    lockedLabel: '解鎖 30',
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
    );
    await tester.pump();
  }

  void purchase() => setOuter(() => owned = true);

  /// 某個圖示是否**看得見**（疊圖是靠 Opacity 換的，所以要看 opacity）。
  bool visible(WidgetTester tester, IconData icon) {
    final finder = find.byIcon(icon);
    if (finder.evaluate().isEmpty) return false;
    final opacities = tester
        .widgetList<Opacity>(
          find.ancestor(of: finder.first, matching: find.byType(Opacity)),
        )
        .toList();
    if (opacities.isEmpty) return true; // 靜態鈕沒有包 Opacity
    return opacities.every((o) => o.opacity > 0.5);
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

    // 越過衝擊點：鎖彈開
    await tester.pump(kUnlockTotal * (kUnlockImpactAt + 0.05));
    expect(visible(tester, Icons.lock_open_rounded), isTrue);

    // 演完：化成加入圖示
    await tester.pump(kUnlockTotal);
    expect(find.byIcon(Icons.playlist_add_rounded), findsOneWidget);
    expect(find.byIcon(Icons.lock_rounded), findsNothing);
    expect(find.text('加入'), findsOneWidget);
  });

  testWidgets('解鎖音落在鎖彈開那一刻，而且只播一次', (tester) async {
    await pumpButton(tester);
    purchase();
    await tester.pump();

    // 衝擊點之前：還沒出聲
    await tester.pump(kUnlockTotal * (kUnlockImpactAt - 0.10));
    expect(cues, isEmpty, reason: '購買完成不是衝擊點，鎖真的彈開才是');

    await tester.pump(kUnlockTotal * 0.15);
    expect(cues, [SfxCue.unlock]);

    // 演完不會再補一次
    await tester.pump(kUnlockTotal);
    expect(cues, [SfxCue.unlock]);
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
    expect(cues, [SfxCue.unlock], reason: '音效是事實回饋，不隨動畫一起關掉');
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
