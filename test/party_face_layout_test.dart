// 多人對局面是「手機平放在桌上」的遠距閱讀情境：
// 目前玩家與下一位不能回歸一般手持 UI 的小字級。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:habit_app/pages/timer/game/party_face.dart';
import 'package:habit_app/pages/timer/game/table_timer_engine.dart';
import 'package:habit_app/pages/timer/game/table_timer_models.dart';

import 'l10n_test_app.dart';

TableTimerConfig _config({List<TablePlayer>? players}) => TableTimerConfig(
  mode: TableGameMode.party,
  players:
      players ??
      const [
        TablePlayer(name: '小兔', colorIndex: 0),
        TablePlayer(name: '阿嬤', colorIndex: 1),
        TablePlayer(name: '小美', colorIndex: 2),
      ],
  turnSeconds: 60,
  warnSeconds: 10,
  autoAdvance: false,
);

Future<void> _pumpFace(
  WidgetTester tester,
  TableTimerEngine engine, {
  Size size = const Size(390, 844),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    l10nTestApp(home: Scaffold(body: PartyFace(engine: engine))),
  );
  await tester.pump();
}

void main() {
  testWidgets('桌上模式清楚標示目前與下一位玩家', (tester) async {
    final engine = TableTimerEngine(_config(), autoTick: false);
    addTearDown(engine.dispose);
    await _pumpFace(tester, engine);

    expect(find.text('第一位'), findsOneWidget);
    expect(find.text('下一位'), findsOneWidget);
    expect(find.text('小兔'), findsOneWidget);
    expect(find.text('阿嬤'), findsOneWidget);

    final currentName = tester.widget<Text>(
      find.byKey(const ValueKey('game-current-player-name')),
    );
    final nextName = tester.widget<Text>(
      find.byKey(const ValueKey('game-next-player-name')),
    );
    expect(currentName.style!.fontSize, greaterThanOrEqualTo(30));
    expect(nextName.style!.fontSize, greaterThanOrEqualTo(23));

    engine.start();
    await tester.pump();
    expect(find.text('現在輪到'), findsOneWidget);

    engine.advance();
    await tester.pump();
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('game-current-player-name')))
          .data,
      '阿嬤',
    );
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('game-next-player-name')))
          .data,
      '小美',
    );
  });

  testWidgets('小螢幕與十二字玩家名不會撐破對局面', (tester) async {
    final engine = TableTimerEngine(
      _config(
        players: const [
          TablePlayer(name: '這是一位名字很長玩家', colorIndex: 0),
          TablePlayer(name: '下一位名字也很長呢', colorIndex: 1),
        ],
      ),
      autoTick: false,
    );
    addTearDown(engine.dispose);
    await _pumpFace(tester, engine, size: const Size(320, 568));

    expect(tester.takeException(), isNull);
    expect(
      find.byKey(const ValueKey('game-current-player-name')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('game-next-player-name')), findsOneWidget);
  });
}
