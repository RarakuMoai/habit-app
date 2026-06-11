// 迴歸測試：每日習慣卡的打卡圓圈必須垂直置中。
// ListTile 對 leading 的置中是用內部算出的內容高度（單行=56），不是被
// 外層撐開後的實際高度（68）；沒設 minTileHeight 時，無副標的卡圓圈會
// 偏上 ~6px、有副標（連動喝水）的卡反而剛好置中，造成不一致。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:habit_app/pages/home/habit_card.dart';

void main() {
  Future<void> pumpCard(
    WidgetTester tester, {
    required bool isLinked,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: HabitCard(
              habit: {'name': '測試習慣', 'done': false, 'frequency': 'daily'},
              onToggle: () {},
              onEdit: () {},
              onDelete: () {},
              isLinked: isLinked,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  // 打卡圓圈 = ListTile leading 裡的 34x34 AnimatedContainer
  Rect circleRect(WidgetTester tester) {
    final finder = find.descendant(
      of: find.byType(ListTile),
      matching: find.byWidgetPredicate(
        (w) => w is AnimatedContainer,
      ),
    );
    return tester.getRect(finder.first);
  }

  Rect tileRect(WidgetTester tester) => tester.getRect(find.byType(ListTile));

  for (final linked in [false, true]) {
    testWidgets('打卡圓圈垂直置中（isLinked=$linked）', (tester) async {
      await pumpCard(tester, isLinked: linked);
      final circle = circleRect(tester);
      final tile = tileRect(tester);
      expect(circle.height, 34);
      expect(
        (circle.center.dy - tile.center.dy).abs(),
        lessThan(1.0),
        reason:
            '圓圈中心 ${circle.center.dy} 應對齊卡片中心 ${tile.center.dy}'
            '（tile 高 ${tile.height}）',
      );
    });
  }
}
