// 導覽與確認的回饋語言。
//
// 守的是「什麼該出聲、什麼只該震、什麼要安靜」這條規則，不是某個 cue 的音量：
// 高頻導覽只給觸覺（一天按幾十次，出聲會變噪音）、app 主動擋在前面的確認框
// 開啟時提醒一次、取消走統一的收回語彙、確認刻意不發（讓真正發生的那件事出聲，
// 避免同一個動作連響兩聲）。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:habit_app/utils/app_feedback.dart';
import 'package:habit_app/utils/sfx_service.dart';
import 'package:habit_app/widgets/app_dialogs.dart';

import 'l10n_test_app.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<(SfxCue?, HapticLevel)> events;

  setUp(() {
    events = [];
    debugResetFeedbackClock();
    debugFeedbackSink = (cue, haptic) => events.add((cue, haptic));
  });
  tearDown(() {
    debugFeedbackSink = null;
    debugResetFeedbackClock();
  });

  group('確認框', () {
    Future<void> openConfirm(
      WidgetTester tester, {
      required void Function(bool) onResult,
    }) async {
      await tester.pumpWidget(
        l10nTestApp(
          navigatorObservers: [PopupFeedbackObserver()],
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () async {
                    final ok = await showAppConfirmDialog(
                      context,
                      title: '刪除',
                      message: '確定要刪除嗎？',
                    );
                    onResult(ok);
                  },
                  child: const Text('開啟'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('開啟'));
      await tester.pumpAndSettle();
    }

    testWidgets('開啟時只給一次 selection 觸覺，不出聲', (tester) async {
      await openConfirm(tester, onResult: (_) {});
      expect(events, [(null, HapticLevel.selection)]);
    });

    testWidgets('觸發按鈕剛出過回饋時，開啟不再重複震一次', (tester) async {
      await tester.pumpWidget(
        l10nTestApp(
          navigatorObservers: [PopupFeedbackObserver()],
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () {
                    // 很多面板是這樣打開的：按鈕自己先播一次 tap。
                    playFeedback(SfxCue.tap);
                    showAppConfirmDialog(
                      context,
                      title: '刪除',
                      message: '確定要刪除嗎？',
                    );
                  },
                  child: const Text('開啟'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('開啟'));
      await tester.pumpAndSettle();

      expect(
        events,
        [(SfxCue.tap, HapticLevel.light)],
        reason: '只留按鈕自己那一次，observer 不再疊上去',
      );
    });

    testWidgets('引擎逐拍的觸覺不會吃掉面板的浮出觸覺', (tester) async {
      // 節拍器由節拍迴圈逐拍發觸覺，跟使用者按了什麼無關。它若蓋掉「最近有
      // 回饋」的時戳，observer 就會誤判成「這個面板是某個按鈕打開的」而跳過
      // ——BPM 273 以上拍距小於 220ms，浮出觸覺會永遠消失。
      playHaptic(HapticLevel.selection, fromUserAction: false);
      events.clear();

      await openConfirm(tester, onResult: (_) {});

      expect(
        events,
        [(null, HapticLevel.selection)],
        reason: '引擎發的那一下不算「使用者剛按過按鈕」，observer 照樣要發',
      );
    });

    testWidgets('取消走 cancel 的收回語彙', (tester) async {
      bool? result;
      await openConfirm(tester, onResult: (r) => result = r);
      events.clear();

      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();

      expect(result, isFalse);
      expect(events, [(SfxCue.cancel, HapticLevel.selection)]);
    });

    testWidgets('確認刻意不發：讓真正發生的那件事自己出聲', (tester) async {
      bool? result;
      await openConfirm(tester, onResult: (r) => result = r);
      events.clear();

      await tester.tap(find.text('確定'));
      await tester.pumpAndSettle();

      expect(result, isTrue);
      expect(
        events,
        isEmpty,
        reason: '在這裡先響一次，會讓同一個動作連響兩聲',
      );
    });
  });

  group('回饋語言的分工', () {
    test('高頻導覽用 selection：它是觸覺裡最輕的一級', () {
      // 分頁切換用的就是這一級。比 light／medium 輕，一天按幾十次才不會累。
      expect(
        HapticLevel.values.indexOf(HapticLevel.selection),
        lessThan(HapticLevel.values.indexOf(HapticLevel.light)),
      );
      expect(
        HapticLevel.values.indexOf(HapticLevel.light),
        lessThan(HapticLevel.values.indexOf(HapticLevel.medium)),
      );
    });

    test('playHaptic 不帶任何音效', () {
      playHaptic(HapticLevel.selection);
      expect(events, [(null, HapticLevel.selection)]);
    });
  });
}
