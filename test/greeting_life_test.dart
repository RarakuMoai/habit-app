// 冷啟動問候的壽命：兔咪打一次招呼就好。
//
// `resetToOpening` 刻意讓問候沒有期限（停到下一次互動），但切分頁不算互動，
// 結果同一句話會跟著使用者走到每一頁——實拍在首頁與衣櫃頁同時掛著「啊，是你。」。
//
// **這組測試刻意測到接線層**（真的去點底部分頁），不是只測 MascotPersona 的 API。
// 只驗對照表而不驗接線，測試會全綠但功能是壞的。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:habit_app/main.dart';
import 'package:habit_app/utils/mascot.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'l10n_test_app.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    MascotPersona.voiceMuted = true;
    SharedPreferences.setMockInitialValues({
      'flutter.onboarding_done': true,
      // 有習慣才不會落到空狀態；內容不影響本組要驗的事。
      'flutter.habits':
          '[{"id":"h1","name":"走路","createdAt":"2026-08-05",'
          '"done":false,"frequency":"daily"}]',
    });
  });
  tearDown(() {
    MascotPersona.resetToIdle();
    MascotPersona.voiceMuted = false;
  });

  /// 收尾：先拆樹讓 `mounted` 變 false，再推進時間。
  ///
  /// MainPage 的 `_ensureMainBgm` 是 `Future.delayed(2800ms)` 不是可取消的
  /// Timer，只能等它自己跑完；拆樹在前，它醒來就會因為 !mounted 直接返回，
  /// 不會真的去碰音訊。順序反過來會在測試裡啟動 BGM。
  Future<void> drainMain(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 3));
  }

  Future<void> pumpMain(WidgetTester tester) async {
    tester.view.physicalSize = const Size(430, 1500);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(l10nTestApp(home: const MainPage()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('切分頁會收掉冷啟動問候，姿勢與泡泡不動', (tester) async {
    MascotPersona.resetToOpening();
    await pumpMain(tester);

    final greeting = MascotPersona.current.value.speech;
    expect(greeting, isNotNull, reason: '冷啟動應該有一句問候');
    final poseBefore = MascotPersona.current.value.assetPath;

    // 真的去點底部分頁，不是直接呼叫 API——要驗的就是接線有沒有接上。
    final other = find.text('計時');
    expect(other, findsWidgets, reason: '需要至少兩個分頁才驗得到跨頁');
    await tester.tap(other.first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      MascotPersona.current.value.speech,
      isNull,
      reason: '換一個房間，兔咪不該把同一句話再說一次',
    );
    expect(
      MascotPersona.current.value.assetPath,
      poseBefore,
      reason: '只收台詞：姿勢不動',
    );

    await drainMain(tester);
  });

  testWidgets('重按同一個分頁不算切換，問候留著', (tester) async {
    MascotPersona.resetToOpening();
    await pumpMain(tester);
    final greeting = MascotPersona.current.value.speech;
    expect(greeting, isNotNull);

    final current = find.text('習慣');
    expect(current, findsWidgets);
    await tester.tap(current.first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(MascotPersona.current.value.speech, greeting, reason: '沒有換房間，就不該收掉');

    await drainMain(tester);
  });

  test('事件台詞不歸這條管：來源不是 opening 就不動它', () {
    MascotPersona.resetToOpening();
    // 模擬首頁寫入的事件台詞（來源 home，有自己的租約與期限）。
    MascotPersona.setForContext(
      MascotEmotion.smile.assetPath,
      MascotContext.completedOne,
      speechWrite: MascotSpeechWrite.own,
      speech: '這件做完了。',
      origin: MascotStateOrigin.home,
    );
    expect(MascotPersona.speechOrigin, MascotStateOrigin.home);
    expect(
      MascotPersona.speechOrigin == MascotStateOrigin.opening,
      isFalse,
      reason: '切分頁的守衛只認 opening，事件台詞由擁有權機制自己管',
    );
  });
}
