// 「完成一件普通每日習慣、今天還沒做完」這個時刻的語意與時序。
//
// 守住的不是「有動畫」，而是：
//   - 一次 input 一個語意事件，清 transient／過期都不再算一次
//   - 打卡是 completedOne，不是 tapReaction（不冒問號、不播疑問聲）
//   - 觸覺／音效／泡泡／語音各只發生一次，而且在該發生的那一拍
//   - 連打共用一條 MI 反應；撤銷能中斷還沒播的正向裝飾
//   - Reduce Motion 拿掉位移演出但保留全部語意
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:habit_app/pages/home/completion_presentation_controller.dart';
import 'package:habit_app/pages/home/habit_card.dart';
import 'package:habit_app/pages/home/room_scene_painters.dart';
import 'package:habit_app/pages/home_page.dart';
import 'package:habit_app/utils/app_feedback.dart';
import 'package:habit_app/utils/logical_date.dart';
import 'package:habit_app/utils/logical_day_coordinator.dart';
import 'package:habit_app/utils/mascot.dart';
import 'package:habit_app/utils/prefs_keys.dart';
import 'package:habit_app/utils/sfx_service.dart';
import 'package:habit_app/widgets/mascot_scene.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'l10n_test_app.dart';

Map<String, dynamic> _habit(String name, {bool done = false}) => {
  'id': 'id_$name',
  'createdAt': '2026-01-01',
  'name': name,
  'done': done,
  'frequency': 'daily',
};

String _todayString() =>
    LogicalDate.stringFor(DateTime.now(), LogicalDate.defaultHour);

void _seed(int count) {
  SharedPreferences.setMockInitialValues({
    PrefsKeys.lastOpenDate: _todayString(),
    PrefsKeys.habits: jsonEncode([
      for (var i = 1; i <= count; i++) _habit('習慣$i'),
    ]),
  });
}

/// 這次演出實際發出的所有回饋（音效 / 觸覺 / 兔咪語音）。
class _FeedbackLog {
  final List<SfxCue> cues = [];
  final List<HapticLevel> haptics = [];
  final List<SfxCue> voices = [];

  /// 實際冒出來的頭頂泡泡（每一次 persona 帶著非 null 泡泡送出算一次）。
  final List<EmotionBubble> bubbles = [];
  int _lastBubbleTick = 0;

  void _onPersona() {
    final state = MascotPersona.current.value;
    final bubble = state.bubble;
    if (bubble == null || state.bubbleTick == _lastBubbleTick) return;
    _lastBubbleTick = state.bubbleTick;
    bubbles.add(bubble);
  }

  void install() {
    debugFeedbackSink = (cue, haptic) {
      if (cue != null) cues.add(cue);
      if (haptic != HapticLevel.none) haptics.add(haptic);
    };
    MascotPersona.debugVoiceSink = voices.add;
    _lastBubbleTick = MascotPersona.current.value.bubbleTick;
    MascotPersona.current.addListener(_onPersona);
  }

  void clear() {
    cues.clear();
    haptics.clear();
    voices.clear();
    bubbles.clear();
  }

  void uninstall() {
    debugFeedbackSink = null;
    MascotPersona.debugVoiceSink = null;
    MascotPersona.current.removeListener(_onPersona);
  }
}

/// 首頁上半部是兔咪場景，800×600 的預設測試畫布會把習慣卡擠出畫面外。
/// 用 14PM 的邏輯尺寸（校準基準機型）讓卡片真的點得到。
void _setSurface(WidgetTester tester, {double height = 932}) {
  tester.view.physicalSize = Size(430, height);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<dynamic> _pumpHome(
  WidgetTester tester, {
  bool reduceMotion = false,
  double height = 932,
}) async {
  _setSurface(tester, height: height);
  await tester.pumpWidget(
    l10nTestApp(
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(disableAnimations: reduceMotion),
          child: const HomePage(),
        ),
      ),
    ),
  );
  await tester.pump();
  final state = tester.state(find.byType(HomePage)) as dynamic;
  await state.loadHabits();
  await tester.pump();
  return state;
}

/// 收掉整棵樹並把所有 timer 跑完，避免殘留到下一個測試。
Future<void> _tearDownHome(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 12));
}

PersonaScene _persona(WidgetTester tester) =>
    tester.widget<PersonaScene>(find.byType(PersonaScene));

/// 第一張習慣卡裡的勾勾描繪 painter（沒開始描就回 null）。
CustomPainter? _checkPainter(WidgetTester tester) {
  final paints = tester.widgetList<CustomPaint>(
    find.descendant(
      of: find.byType(HabitCard).first,
      matching: find.byType(CustomPaint),
    ),
  );
  for (final paint in paints) {
    final painter = paint.painter;
    if (painter != null &&
        painter.runtimeType.toString().contains('CheckDraw')) {
      return painter;
    }
  }
  return null;
}

Future<void> _tapHabit(WidgetTester tester, String name) async {
  await tester.tap(find.text(name));
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FeedbackLog log;

  setUp(() {
    LogicalDayCoordinator.debugInstance = LogicalDayCoordinator();
    MascotPersona.resetToIdle();
    MascotPersona.debugResetVoiceCooldowns();
    log = _FeedbackLog()..install();
  });

  tearDown(() {
    log.uninstall();
    MascotPersona.idleBaseline = null;
    LogicalDayCoordinator.debugInstance = null;
  });

  // ── 20.1 語意事件 ───────────────────────────────────────────

  group('語意', () {
    testWidgets('今天第一件走 completedOne：不冒問號泡泡、不播疑問聲', (tester) async {
      _seed(3);
      await _pumpHome(tester);
      log.clear();

      await _tapHabit(tester, '習慣1');
      // 走完整段演出
      await tester.pump(CompletionPresentationController.kSpeakDelay);

      final state = MascotPersona.current.value;
      expect(
        state.bubble,
        EmotionBubble.note,
        reason: '打卡是 completedOne 的音符，不是點兔咪的問號',
      );
      expect(state.bubble, isNot(EmotionBubble.question));
      expect(
        log.voices,
        isNot(contains(SfxCue.tumiQuestion)),
        reason: '普通完成不得播疑問聲',
      );
      expect(log.voices, [SfxCue.tumiConfirm]);
      expect(state.speech, '今天第一件。');

      await _tearDownHome(tester);
    });

    testWidgets('一次 input 只建立一個語意事件；清 transient 不再建立第二個', (tester) async {
      _seed(3);
      final home = await _pumpHome(tester);
      expect(home.debugCompletionEventId, 0);

      await _tapHabit(tester, '習慣1');
      expect(home.debugCompletionEventId, 1);

      // 跑完整條時間線（含清台詞的 quiet）
      await tester.pump(CompletionPresentationController.kQuietDelay);
      expect(
        home.debugCompletionEventId,
        1,
        reason: '過期／收尾都不是新的完成事件',
      );
      expect(MascotPersona.current.value.speech, isNull);

      await _tearDownHome(tester);
    });

    testWidgets('尾韻收乾淨時不再播第二次泡泡、語音或音效', (tester) async {
      _seed(3);
      await _pumpHome(tester);

      await _tapHabit(tester, '習慣1');
      await tester.pump(CompletionPresentationController.kSpeakDelay);
      expect(log.bubbles, [EmotionBubble.note]);
      log.clear();

      await tester.pump(const Duration(seconds: 3));

      expect(log.cues, isEmpty, reason: '收尾不得再發音效');
      expect(log.voices, isEmpty, reason: '收尾不得再叫一次');
      expect(log.haptics, isEmpty);
      expect(log.bubbles, isEmpty, reason: '收尾不得再冒一顆泡泡');

      await _tearDownHome(tester);
    });

    testWidgets('演出結束回到目前進度的 baseline，不是開 app 的中性臉', (tester) async {
      _seed(3);
      final home = await _pumpHome(tester);

      await _tapHabit(tester, '習慣1');
      await tester.pump(CompletionPresentationController.kRecoverDelay);

      expect(home.debugBaselineMascotContext, MascotContext.completedOne);
      expect(
        MascotPersona.current.value.assetPath,
        MascotEmotion.expect.assetPath,
        reason: '1/3 完成的 baseline 是 expect，不是 neutral_front',
      );
      expect(
        MascotPersona.current.value.assetPath,
        isNot(MascotEmotion.neutralFront.assetPath),
      );

      await _tearDownHome(tester);
    });

    testWidgets('persona 過期回神也走進度 baseline', (tester) async {
      _seed(3);
      await _pumpHome(tester);

      await _tapHabit(tester, '習慣1');
      // MascotPersona 的 _revertAfter 是 10 秒
      await tester.pump(const Duration(seconds: 11));

      expect(
        MascotPersona.current.value.assetPath,
        MascotEmotion.expect.assetPath,
        reason: '過期不得固定回 openApp neutral',
      );
      expect(MascotPersona.current.value.speech, isNull);

      await _tearDownHome(tester);
    });

    testWidgets('同一天的第二件不再重複播語音', (tester) async {
      _seed(4);
      await _pumpHome(tester);

      await _tapHabit(tester, '習慣1');
      await tester.pump(CompletionPresentationController.kQuietDelay);
      log.clear();

      await _tapHabit(tester, '習慣2');
      await tester.pump(CompletionPresentationController.kSpeakDelay);

      expect(log.voices, isEmpty, reason: '非首件保持安靜，只留符號＋音效');
      expect(
        MascotPersona.current.value.speech,
        isNull,
        reason: '非首件不冒文字',
      );
      expect(MascotPersona.current.value.bubble, EmotionBubble.note);

      await _tearDownHome(tester);
    });

    testWidgets('打卡不會把兔咪原本正在說的話砍掉', (tester) async {
      _seed(4);
      await _pumpHome(tester);
      // 兔咪剛講了一句（例如開場問候）還沒講完
      MascotPersona.setForContext(
        MascotEmotion.neutralFront.assetPath,
        MascotContext.openApp,
        speech: '嗯...你來了。',
        force: true,
      );
      await tester.pump();

      await _tapHabit(tester, '習慣2'); // 非首件語意（第一件仍是這件，改用首件也一樣）
      await tester.pump(CompletionPresentationController.kImpactDelay);
      expect(
        MascotPersona.current.value.speech,
        '嗯...你來了。',
        reason: '換姿勢那一拍不該讓還在講的話憑空消失',
      );

      await tester.pump(
        CompletionPresentationController.kSpeakDelay -
            CompletionPresentationController.kImpactDelay,
      );
      expect(MascotPersona.current.value.speech, '今天第一件。');

      await _tearDownHome(tester);
    });

    testWidgets('一次完成只有一次觸覺與一次音效', (tester) async {
      _seed(3);
      await _pumpHome(tester);
      log.clear();

      await _tapHabit(tester, '習慣1');
      await tester.pump(const Duration(seconds: 3));

      expect(log.cues, [SfxCue.success]);
      expect(log.haptics, [HapticLevel.light]);

      await _tearDownHome(tester);
    });
  });

  // ── 20.2 演出時序 ───────────────────────────────────────────

  group('時序', () {
    testWidgets('第一個 pump 就完成：資料、卡片、勾勾同時起跑，但還沒有聲音', (tester) async {
      _seed(3);
      final home = await _pumpHome(tester);
      log.clear();

      await _tapHabit(tester, '習慣1');

      expect((home.habits as List)[0]['done'], isTrue);
      expect(home.dailyDoneCount, 1);
      expect(
        log.cues,
        isEmpty,
        reason: '按下去的第一拍只該有 ink 與勾，不該同拍就發聲',
      );
      expect(log.haptics, isEmpty);
      expect(
        MascotPersona.current.value.bubble,
        isNot(EmotionBubble.note),
        reason: '泡泡不得與 input 同拍',
      );

      // 勾勾正在描：同一個 painter 在下一拍會回報需要重畫（t 有前進）。
      final atInput = _checkPainter(tester);
      expect(atInput, isNotNull, reason: '完成的卡要立刻開始描勾');
      await tester.pump(const Duration(milliseconds: 150));
      expect(
        _checkPainter(tester)!.shouldRepaint(atInput!),
        isTrue,
        reason: '勾勾必須是「畫出來」的，不是一次到位',
      );

      await _tearDownHome(tester);
    });

    testWidgets('MI 先察覺、再蹲跳；泡泡最後才出現', (tester) async {
      _seed(3);
      await _pumpHome(tester);

      final noticeBefore = _persona(tester).noticeTick;
      final reactionBefore = _persona(tester).reactionTick;

      await _tapHabit(tester, '習慣1');
      expect(_persona(tester).noticeTick, noticeBefore, reason: '輸入當拍還沒察覺');
      expect(_persona(tester).reactionTick, reactionBefore);

      await tester.pump(CompletionPresentationController.kNoticeDelay);
      expect(
        _persona(tester).noticeTick,
        noticeBefore + 1,
        reason: '察覺要早於蹲跳',
      );
      expect(_persona(tester).reactionTick, reactionBefore);

      await tester.pump(
        CompletionPresentationController.kAnticipateDelay -
            CompletionPresentationController.kNoticeDelay,
      );
      expect(_persona(tester).reactionTick, reactionBefore + 1);
      expect(
        _persona(tester).reactionStrength,
        lessThan(1.0),
        reason: '打卡的小跳要比直接點兔咪克制',
      );
      expect(
        MascotPersona.current.value.speech,
        isNull,
        reason: 'MI 還在動，泡泡不該搶先',
      );

      await tester.pump(
        CompletionPresentationController.kSpeakDelay -
            CompletionPresentationController.kAnticipateDelay,
      );
      expect(MascotPersona.current.value.speech, '今天第一件。');

      await _tearDownHome(tester);
    });

    testWidgets('觸覺與音效落在勾勾觸底那一拍，不在輸入當拍', (tester) async {
      _seed(3);
      await _pumpHome(tester);
      log.clear();

      await _tapHabit(tester, '習慣1');
      await tester.pump(
        CompletionPresentationController.kImpactDelay -
            const Duration(milliseconds: 20),
      );
      expect(log.cues, isEmpty);
      expect(log.haptics, isEmpty);

      await tester.pump(const Duration(milliseconds: 40));
      expect(log.cues, [SfxCue.success]);
      expect(log.haptics, [HapticLevel.light]);

      await _tearDownHome(tester);
    });

    testWidgets('勾勾描完的長度＝主衝擊點', (tester) async {
      expect(
        kHabitCheckDrawDuration,
        CompletionPresentationController.kImpactDelay,
        reason: '勾勾畫完與觸覺／音效必須同一刻，否則會聽到「後補」的聲音',
      );
    });

    testWidgets('進度條先按住舊值，衝擊點才放開', (tester) async {
      _seed(4);
      await _pumpHome(tester);

      await _tapHabit(tester, '習慣1');
      // 數字是事實，立刻更新
      expect(find.text('1 / 4'), findsWidgets);

      final builder = tester.widget<TweenAnimationBuilder<double>>(
        find.byType(TweenAnimationBuilder<double>).first,
      );
      expect(
        builder.tween.end,
        0.0,
        reason: '進度條在衝擊點之前維持舊值',
      );

      await tester.pump(CompletionPresentationController.kImpactDelay);
      final released = tester.widget<TweenAnimationBuilder<double>>(
        find.byType(TweenAnimationBuilder<double>).first,
      );
      expect(released.tween.end, closeTo(0.25, 0.001));

      await _tearDownHome(tester);
    });

    testWidgets('切走分頁不補播還沒發生的完成演出', (tester) async {
      _seed(3);
      _setSurface(tester);
      final visible = ValueNotifier<bool>(true);
      await tester.pumpWidget(
        l10nTestApp(
          home: ValueListenableBuilder<bool>(
            valueListenable: visible,
            builder: (_, v, _) =>
                TickerMode(enabled: v, child: const HomePage()),
          ),
        ),
      );
      await tester.pump();
      final home = tester.state(find.byType(HomePage)) as dynamic;
      await home.loadHabits();
      await tester.pump();
      log.clear();

      await _tapHabit(tester, '習慣1');
      visible.value = false;
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(seconds: 4));

      expect(
        log.cues,
        isEmpty,
        reason: '看不到兔咪就不該聽到打卡演出繼續播完',
      );
      expect(log.voices, isEmpty);
      expect(home.debugCompletionArcActive, isFalse);
      expect(
        (home.habits as List)[0]['done'],
        isTrue,
        reason: '取消演出不得回滾已提交的資料',
      );

      visible.dispose();
      await _tearDownHome(tester);
    });

    testWidgets('演出途中把整棵樹拆掉：不丟例外、也不再發聲', (tester) async {
      _seed(3);
      await _pumpHome(tester);

      await _tapHabit(tester, '習慣1');
      await tester.pump(const Duration(milliseconds: 100));
      log.clear();

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 5));

      expect(tester.takeException(), isNull);
      expect(log.cues, isEmpty);
      expect(log.voices, isEmpty);
    });
  });

  // ── 20.2 無障礙 ─────────────────────────────────────────────

  group('無障礙', () {
    testWidgets('一次完成只有一個節點宣告「已完成」', (tester) async {
      final handle = tester.ensureSemantics();
      _seed(3);
      await _pumpHome(tester);

      await _tapHabit(tester, '習慣1');
      await tester.pump(CompletionPresentationController.kSpeakDelay);

      // 節點 label 會併入卡片上看得到的名稱，所以用 pattern 比對狀態那段。
      expect(find.bySemanticsLabel(RegExp('習慣1，已完成')), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('，已完成')), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('習慣2，已完成')), findsNothing);
      // 台詞泡泡不得被讀成第二次完成確認
      final speech = MascotPersona.current.value.speech;
      expect(speech, isNotNull);
      expect(speech, isNot(contains('完成')));

      await _tearDownHome(tester);
      handle.dispose();
    });

    testWidgets('撤銷後 Semantics 回到未完成', (tester) async {
      final handle = tester.ensureSemantics();
      _seed(3);
      await _pumpHome(tester);

      await _tapHabit(tester, '習慣1');
      await tester.pump(const Duration(milliseconds: 100));
      await _tapHabit(tester, '習慣1');
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.bySemanticsLabel(RegExp('習慣1，未完成')), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('，已完成')), findsNothing);

      await _tearDownHome(tester);
      handle.dispose();
    });
  });

  // ── 20.3 連打 ───────────────────────────────────────────────

  group('連打', () {
    testWidgets('六件完成五件：資料全對、不進 all-done、MI 只反應一次', (tester) async {
      _seed(6);
      final home = await _pumpHome(tester, height: 1180);
      log.clear();
      final reactionBefore = _persona(tester).reactionTick;
      final noticeBefore = _persona(tester).noticeTick;

      for (var i = 1; i <= 5; i++) {
        await tester.tap(find.text('習慣$i'));
        await tester.pump(const Duration(milliseconds: 60));
      }

      expect(home.dailyDoneCount, 5);
      expect(home.allDone0, isFalse);
      expect(
        home.debugCompletionEventId,
        5,
        reason: '每一件都是自己的 domain 事件，不能被演出合併吃掉',
      );
      expect(
        _persona(tester).reactionTick,
        reactionBefore + 1,
        reason: 'MI 不得每一件都從第 0 幀重蹲一次',
      );
      expect(_persona(tester).noticeTick, noticeBefore + 1);

      await tester.pump(const Duration(seconds: 4));
      expect(log.voices.length, lessThanOrEqualTo(1));
      expect(log.cues, List.filled(5, SfxCue.success));
      expect(log.haptics, List.filled(5, HapticLevel.light));
      expect(
        log.cues,
        isNot(contains(SfxCue.complete)),
        reason: '沒完成最後一件就不該觸發全完成音',
      );
      expect(find.byType(RoomSceneEffects), findsNothing);

      final prefs = await SharedPreferences.getInstance();
      final stored =
          (jsonDecode(prefs.getString(PrefsKeys.habits)!) as List)
              .cast<Map<String, dynamic>>();
      expect(stored.where((h) => h['done'] == true).length, 5);
      expect(
        prefs.getString(PrefsKeys.habitDoneDay(_todayString())),
        isNotNull,
        reason: '五件都要進今天的歷史',
      );

      await _tearDownHome(tester);
    });

    testWidgets('連打的泡泡不疊層：整段只換過一次泡泡事件', (tester) async {
      _seed(6);
      await _pumpHome(tester, height: 1180);

      for (var i = 1; i <= 4; i++) {
        await tester.tap(find.text('習慣$i'));
        await tester.pump(const Duration(milliseconds: 50));
      }
      await tester.pump(CompletionPresentationController.kSpeakDelay);
      expect(
        log.bubbles,
        [EmotionBubble.note],
        reason: '連打四件只該冒一顆泡泡，不是疊四層',
      );

      await tester.pump(const Duration(seconds: 3));
      expect(log.bubbles.length, 1, reason: '尾韻不得再補冒泡泡');

      await _tearDownHome(tester);
    });

    testWidgets('跨過一半門檻不另外再演一次里程碑', (tester) async {
      _seed(4);
      final home = await _pumpHome(tester);
      log.clear();

      for (var i = 1; i <= 2; i++) {
        await tester.tap(find.text('習慣$i'));
        await tester.pump(const Duration(milliseconds: 60));
      }
      await tester.pump(const Duration(seconds: 4));

      expect(home.debugBaselineMascotContext, MascotContext.halfDone);
      expect(
        log.voices.length,
        lessThanOrEqualTo(1),
        reason: '不得同時播普通完成與 halfDone 兩套反應',
      );
      expect(
        MascotPersona.current.value.assetPath,
        MascotEmotion.smile.assetPath,
        reason: '收尾要安靜交棒給較高層級的 baseline',
      );

      await _tearDownHome(tester);
    });
  });

  // ── 20.4 撤銷 ───────────────────────────────────────────────

  group('撤銷', () {
    testWidgets('正向尾韻還沒播完就撤銷：不再播過時的語音與音效', (tester) async {
      _seed(3);
      final home = await _pumpHome(tester);

      await _tapHabit(tester, '習慣1');
      await tester.pump(const Duration(milliseconds: 120));
      log.clear();

      await _tapHabit(tester, '習慣1'); // 撤銷
      await tester.pump(const Duration(seconds: 4));

      expect((home.habits as List)[0]['done'], isFalse);
      expect(
        log.cues,
        [SfxCue.cancel],
        reason: '過時的成功音不得補播',
      );
      expect(
        log.voices,
        isNot(contains(SfxCue.tumiConfirm)),
        reason: '撤銷後不得再播完成語音',
      );
      expect(home.debugCompletionArcActive, isFalse);

      await _tearDownHome(tester);
    });

    testWidgets('撤銷後兔咪回到撤銷後的 baseline，不停在完成情緒', (tester) async {
      _seed(3);
      final home = await _pumpHome(tester);

      await _tapHabit(tester, '習慣1');
      await tester.pump(const Duration(milliseconds: 150));
      await _tapHabit(tester, '習慣1');
      // sad 停留 2 秒後收
      await tester.pump(const Duration(milliseconds: 2500));

      expect(home.debugBaselineMascotContext, isNot(MascotContext.completedOne));
      expect(
        MascotPersona.current.value.assetPath,
        isNot(MascotEmotion.expect.assetPath),
        reason: '撤銷後不得停在「已經開始」的表情',
      );
      expect(
        MascotPersona.current.value.bubble,
        isNull,
        reason: '收拾不是新事件，不再冒泡泡',
      );

      await _tearDownHome(tester);
    });

    testWidgets('撤銷會收束正在跑的小跳', (tester) async {
      _seed(3);
      await _pumpHome(tester);

      await _tapHabit(tester, '習慣1');
      await tester.pump(CompletionPresentationController.kAnticipateDelay);
      final cancelBefore = _persona(tester).reactionCancelTick;

      await _tapHabit(tester, '習慣1');
      expect(_persona(tester).reactionCancelTick, cancelBefore + 1);

      await _tearDownHome(tester);
    });
  });

  // ── 20.2 / 11 Reduce Motion ─────────────────────────────────

  group('Reduce Motion', () {
    testWidgets('不播小跳與粒子，但保留完成語意與一次回饋', (tester) async {
      _seed(3);
      final home = await _pumpHome(tester, reduceMotion: true);
      log.clear();
      final reactionBefore = _persona(tester).reactionTick;
      final noticeBefore = _persona(tester).noticeTick;

      await _tapHabit(tester, '習慣1');
      await tester.pump(CompletionPresentationController.kReducedSpeakDelay);

      expect((home.habits as List)[0]['done'], isTrue);
      expect(log.bubbles, [EmotionBubble.note]);
      expect(
        MascotPersona.current.value.assetPath,
        MascotEmotion.expect.assetPath,
      );

      await tester.pump(const Duration(seconds: 3));
      expect(
        _persona(tester).reactionTick,
        reactionBefore,
        reason: 'Reduce Motion 不得跳躍（星星也跟著沒有）',
      );
      expect(_persona(tester).noticeTick, noticeBefore);
      expect(log.cues, [SfxCue.success], reason: '音效與觸覺是無障礙保留項');
      expect(log.haptics, [HapticLevel.light]);

      await _tearDownHome(tester);
    });

    testWidgets('進度條不按住，直接跟著真實進度', (tester) async {
      _seed(4);
      await _pumpHome(tester, reduceMotion: true);

      await _tapHabit(tester, '習慣1');
      final builder = tester.widget<TweenAnimationBuilder<double>>(
        find.byType(TweenAnimationBuilder<double>).first,
      );
      expect(builder.tween.end, closeTo(0.25, 0.001));

      await _tearDownHome(tester);
    });

    testWidgets('順序仍然存在，不是全部歸零同拍', (tester) async {
      expect(
        CompletionPresentationController.kReducedImpactDelay,
        greaterThan(Duration.zero),
      );
      expect(
        CompletionPresentationController.kReducedSpeakDelay,
        greaterThan(CompletionPresentationController.kReducedImpactDelay),
      );
      expect(
        CompletionPresentationController.kReducedRecoverDelay,
        greaterThan(CompletionPresentationController.kReducedSpeakDelay),
      );
    });
  });

  // ── 20.5 既有行為不被破壞 ───────────────────────────────────

  group('既有行為', () {
    testWidgets('點兔咪仍然是 tapReaction（問號泡泡保留給這條路）', (tester) async {
      _seed(3);
      await _pumpHome(tester);

      await tester.tap(find.byType(MascotStage));
      await tester.pump();

      expect(MascotPersona.current.value.bubble, EmotionBubble.question);
      expect(MascotPersona.current.value.speech, isNotNull);

      await _tearDownHome(tester);
    });

    testWidgets('完成最後一件仍走全完成演出', (tester) async {
      _seed(2);
      final home = await _pumpHome(tester);

      await _tapHabit(tester, '習慣1');
      await tester.pump(const Duration(seconds: 4));
      log.clear();

      await _tapHabit(tester, '習慣2');
      await tester.pump();

      expect(home.allDone0, isTrue);
      expect(log.cues, contains(SfxCue.complete));
      await tester.pump();
      expect(find.byType(RoomSceneEffects), findsOneWidget);

      await _tearDownHome(tester);
    });

    testWidgets('打卡進歷史，撤銷後也同步', (tester) async {
      _seed(3);
      final home = await _pumpHome(tester);

      await _tapHabit(tester, '習慣1');
      await tester.pump(const Duration(milliseconds: 400));
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getString(PrefsKeys.habitDoneDay(_todayString())),
        contains('id_習慣1'),
      );

      await _tapHabit(tester, '習慣1');
      await tester.pump(const Duration(milliseconds: 400));
      expect((home.habits as List)[0]['done'], isFalse);
      expect(
        prefs.getString(PrefsKeys.habitDoneDay(_todayString())),
        isNot(contains('id_習慣1')),
      );

      await _tearDownHome(tester);
    });
  });
}
