// 底部面板的把手必須**釘在頂端**，不能跟著內容捲走。
//
// 起因：改版時把 27 個手刻把手收斂成 `SheetDragHandle`，外觀與點擊都統一了，
// 但家庭的五個面板把它留在 `SingleChildScrollView` 的第一個 child——內容一捲
// 把手就消失，「可以往下拉關掉」的提示等於沒有。
//
// 這組測試釘兩件事：
// 1. 內容捲動時把手不動（`PinnedHandleSheet` 的存在理由）。
// 2. 在有界高度的面板裡不會因為 `Flexible` 丟版面例外。
//    ⚠️ 第 2 點在單純的 widget test 裡很容易漏掉——一定要**給一個會超出高度的
//    長內容**，短內容不會觸發 Flexible 的分配路徑。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:habit_app/widgets/sheet_drag_handle.dart';

void main() {
  /// 開一個和正式面板同樣設定的 bottom sheet（`isScrollControlled: true`）。
  Future<void> openSheet(WidgetTester tester, {required int rows}) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [
          ...GlobalMaterialLocalizationsStub.delegates,
        ],
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  builder: (ctx) => Padding(
                    padding: EdgeInsets.fromLTRB(
                      20,
                      16,
                      20,
                      MediaQuery.of(ctx).viewInsets.bottom + 32,
                    ),
                    child: PinnedHandleSheet(
                      tapToClose: false, // 不需要 l10n 的 Semantics label
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (var i = 0; i < rows; i++)
                            SizedBox(height: 56, child: Text('列 $i')),
                        ],
                      ),
                    ),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('內容捲動時把手不動', (tester) async {
    // 30 列 × 56 = 1680px，遠超過面板高度 → 一定會捲動
    await openSheet(tester, rows: 30);

    final handle = find.byType(SheetDragHandle);
    expect(handle, findsOneWidget);
    final before = tester.getRect(handle);
    expect(find.text('列 0'), findsOneWidget);

    await tester.drag(find.text('列 3'), const Offset(0, -400));
    await tester.pumpAndSettle();

    expect(tester.getRect(handle), before, reason: '把手跟著內容捲走了 → 它又被放回捲動區裡面');
    expect(
      tester.getRect(find.text('列 0')).top < before.top,
      isTrue,
      reason: '內容沒有真的捲動，這條測試就沒有意義',
    );
  });

  testWidgets('短內容：不撐滿、不丟版面例外', (tester) async {
    await openSheet(tester, rows: 2);
    expect(tester.takeException(), isNull);
    // 2 列 ×56 ＋ 把手 28 ＋ 間距 16 ＋ 內距 48 ≈ 204，遠小於畫面高度
    final h = tester.getRect(find.byType(PinnedHandleSheet)).height;
    expect(h, lessThan(400), reason: '短內容不該被撐到滿版');
  });

  testWidgets('長內容：撐到上限後改成捲動，不溢位', (tester) async {
    await openSheet(tester, rows: 30);
    expect(
      tester.takeException(),
      isNull,
      reason: 'Flexible 拿到無界高度就會丟例外——面板必須有上界',
    );
    final h = tester.getRect(find.byType(PinnedHandleSheet)).height;
    expect(h, greaterThan(400), reason: '長內容應該撐開到上限');
    expect(
      h,
      lessThanOrEqualTo(
        tester.view.physicalSize.height / tester.view.devicePixelRatio,
      ),
      reason: '超出畫面＝沒有被上界擋住，會溢位',
    );
  });
}

/// `showModalBottomSheet` 需要 Material localizations；測試裡用預設的就夠。
class GlobalMaterialLocalizationsStub {
  static const delegates = <LocalizationsDelegate<dynamic>>[
    DefaultMaterialLocalizations.delegate,
    DefaultWidgetsLocalizations.delegate,
  ];
}
