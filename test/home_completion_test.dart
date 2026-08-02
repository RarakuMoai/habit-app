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
import 'package:habit_app/pages/home/home_speech_owner.dart';
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

Map<String, dynamic> _weeklyHabit(String name, {int target = 3}) => {
  'id': 'id_$name',
  'createdAt': '2026-01-01',
  'name': name,
  'done': false,
  'frequency': 'weekly',
  'weeklyTarget': target,
  'weeklyDates': <String>[],
};

void _seed(int count, {int streak = 0, bool withWeekly = false}) {
  SharedPreferences.setMockInitialValues({
    PrefsKeys.lastOpenDate: _todayString(),
    if (streak > 0) PrefsKeys.streak: streak,
    PrefsKeys.habits: jsonEncode([
      for (var i = 1; i <= count; i++) _habit('習慣$i'),
      if (withWeekly) _weeklyHabit('每週習慣'),
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

/// 目前畫面上每一張兔咪立繪的實際不透明度。
/// 「衝擊點不得有雙影」＝這裡最多只有一個明顯可見的值。
List<double> _poseOpacities(WidgetTester tester) {
  final result = <double>[];
  for (final el
      in find
          .descendant(
            of: find.byType(MascotStage),
            matching: find.byType(Padding),
          )
          .evaluate()) {
    if ((el.widget as Padding).key is! ValueKey<String>) continue;
    var opacity = 1.0;
    el.visitAncestorElements((ancestor) {
      final widget = ancestor.widget;
      if (widget is FadeTransition) {
        opacity = widget.opacity.value;
        return false;
      }
      return widget is! MascotStage;
    });
    result.add(opacity);
  }
  return result;
}

/// 沒有雙影＝沒有任何一張立繪處於半透明。
///
/// 兩張都完全不透明時，上層那張會把下層完全蓋掉，看不到疊影；真正會透出
/// 背景、產生鬼影的是「兩張各半透明」那種混合。
void _expectNoGhostPose(WidgetTester tester) {
  final opacities = _poseOpacities(tester);
  expect(
    opacities.where((o) => o > 0.05 && o < 0.95),
    isEmpty,
    reason: '衝擊點不得出現半透明的兔咪立繪（實際：$opacities）',
  );
}

Future<void> _tapHabit(WidgetTester tester, String name) async {
  await tester.tap(find.text(name));
  await tester.pump();
}

/// 不覆寫 MediaQuery 的首頁：Reduce Motion 由**真實平台**的 accessibility
/// feature 決定。`_pumpHome` 的 `copyWith(disableAnimations: …)` 會把平台值
/// 蓋掉，測不到 framework 那層（AnimationController 會縮短 duration）的行為。
Future<dynamic> _pumpHomeOnPlatform(
  WidgetTester tester, {
  double height = 932,
}) async {
  _setSurface(tester, height: height);
  await tester.pumpWidget(l10nTestApp(home: const HomePage()));
  await tester.pump();
  final state = tester.state(find.byType(HomePage)) as dynamic;
  await state.loadHabits();
  await tester.pump();
  return state;
}

/// 勾勾描到哪了（0–1）；還沒開始描回 -1。
double _checkProgress(WidgetTester tester) {
  final painter = _checkPainter(tester);
  if (painter == null) return -1;
  return (painter as dynamic).t as double;
}

/// 兔咪身上的星星粒子 painter 收到的 progress（找不到回 -1）。
double _sparkleProgress(WidgetTester tester) {
  for (final paint in tester.widgetList<CustomPaint>(
    find.descendant(
      of: find.byType(MascotStage),
      matching: find.byType(CustomPaint),
    ),
  )) {
    final painter = paint.painter;
    if (painter != null && painter.runtimeType.toString().contains('Sparkle')) {
      return (painter as dynamic).progress as double;
    }
  }
  return -1;
}

/// 第 [card] 張習慣卡的打卡圓圈目前的縮放（按壓／回彈的實際輸出）。
double _circleScale(WidgetTester tester, {int card = 0}) {
  final t = tester.widget<ScaleTransition>(
    find
        .descendant(
          of: find.byType(HabitCard).at(card),
          matching: find.byType(ScaleTransition),
        )
        .first,
  );
  return t.scale.value;
}

/// 進度列尾端光暈的驅動器（就是首頁的 `_glowCtrl` 本身）。
Animation<double>? _glow(WidgetTester tester) {
  final found = find
      .byWidgetPredicate((w) => w.runtimeType.toString() == '_ProgressBar')
      .evaluate();
  if (found.isEmpty) return null;
  return (found.first.widget as dynamic).glow as Animation<double>;
}

/// 全完成慶祝場景目前的縮放（`_celebScale`）。
double _celebScale(WidgetTester tester) {
  final t = tester.widget<ScaleTransition>(
    find
        .ancestor(
          of: find.byType(PersonaScene),
          matching: find.byType(ScaleTransition),
        )
        .first,
  );
  return t.scale.value;
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
      expect(home.debugCompletionEventId, 1, reason: '過期／收尾都不是新的完成事件');
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
      // 5 件：第二件是 2/5，不會跨過一半，維持普通完成語意。
      _seed(5);
      await _pumpHome(tester);

      await _tapHabit(tester, '習慣1');
      await tester.pump(CompletionPresentationController.kQuietDelay);
      log.clear();

      await _tapHabit(tester, '習慣2');
      await tester.pump(CompletionPresentationController.kSpeakDelay);

      expect(log.voices, isEmpty, reason: '非首件保持安靜，只留符號＋音效');
      expect(MascotPersona.current.value.speech, isNull, reason: '非首件不冒文字');
      expect(MascotPersona.current.value.bubble, EmotionBubble.note);

      await _tearDownHome(tester);
    });

    testWidgets('打卡不會把兔咪原本正在說的話砍掉', (tester) async {
      _seed(4);
      await _pumpHome(tester);
      // 兔咪剛講了一句（例如開場問候）還沒講完
      // 正式的冷啟動問候會標記來源；silent 中間拍只保留這一種。
      MascotPersona.setForContext(
        MascotEmotion.neutralFront.assetPath,
        MascotContext.openApp,
        speech: '嗯...你來了。',
        force: true,
        origin: MascotStateOrigin.opening,
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
      expect(log.cues, isEmpty, reason: '按下去的第一拍只該有 ink 與勾，不該同拍就發聲');
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
      expect(_persona(tester).noticeTick, noticeBefore + 1, reason: '察覺要早於蹲跳');
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
      expect(builder.tween.end, 0.0, reason: '進度條在衝擊點之前維持舊值');

      await tester.pump(CompletionPresentationController.kImpactDelay);
      final released = tester.widget<TweenAnimationBuilder<double>>(
        find.byType(TweenAnimationBuilder<double>).first,
      );
      expect(released.tween.end, closeTo(0.25, 0.001));

      await _tearDownHome(tester);
    });

    testWidgets('一般模式的衝擊點也只有一張立繪', (tester) async {
      _seed(3);
      await _pumpHome(tester);

      await _tapHabit(tester, '習慣1');
      expect(_persona(tester).poseTransition, MascotPoseTransition.cut);

      await tester.pump(CompletionPresentationController.kImpactDelay);
      var framesWithTwo = 0;
      for (var i = 0; i < 12; i++) {
        _expectNoGhostPose(tester);
        if (_poseOpacities(tester).length > 1) framesWithTwo++;
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(
        framesWithTwo,
        lessThanOrEqualTo(1),
        reason: '退場的立繪最多只留一幀（而且被完全不透明的新姿勢蓋住）',
      );

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

      expect(log.cues, isEmpty, reason: '看不到兔咪就不該聽到打卡演出繼續播完');
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
      final stored = (jsonDecode(prefs.getString(PrefsKeys.habits)!) as List)
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
      expect(log.bubbles, [EmotionBubble.note], reason: '連打四件只該冒一顆泡泡，不是疊四層');

      await tester.pump(const Duration(seconds: 3));
      expect(log.bubbles.length, 1, reason: '尾韻不得再補冒泡泡');

      await _tearDownHome(tester);
    });

    testWidgets('連打穿越一半門檻：整條弧線交棒給 halfDone', (tester) async {
      _seed(4);
      final home = await _pumpHome(tester);
      log.clear();
      home.debugClearSemanticEvents();
      final reactionBefore = _persona(tester).reactionTick;

      for (var i = 1; i <= 2; i++) {
        await tester.tap(find.text('習慣$i'));
        await tester.pump(const Duration(milliseconds: 60));
      }
      await tester.pump(const Duration(seconds: 4));

      expect(home.debugSemanticEvents, [
        MascotContext.halfDone,
      ], reason: '連打穿越門檻時，普通完成必須整條交棒，不能兩套都播');
      expect(log.bubbles, hasLength(1));
      expect(log.voices.length, lessThanOrEqualTo(1));
      expect(
        _persona(tester).reactionTick,
        reactionBefore + 1,
        reason: '交棒不等於重演一次動作',
      );
      expect(home.debugBaselineMascotContext, MascotContext.halfDone);
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
      expect(log.cues, [SfxCue.cancel], reason: '過時的成功音不得補播');
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

      expect(
        home.debugBaselineMascotContext,
        isNot(MascotContext.completedOne),
      );
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
      final cancelBefore = _persona(tester).reactionCancelUpTo;

      await _tapHabit(tester, '習慣1');
      expect(_persona(tester).reactionCancelUpTo, cancelBefore + 1);

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

    testWidgets('Reduce Motion 下的換立繪一樣走安全的離散模式', (tester) async {
      _seed(3);
      await _pumpHome(tester, reduceMotion: true);

      await _tapHabit(tester, '習慣1');
      expect(
        _persona(tester).poseTransition,
        MascotPoseTransition.cut,
        reason: 'Reduce Motion 不得走 easeOutBack + 縮放的交叉淡入',
      );

      await tester.pump(CompletionPresentationController.kReducedImpactDelay);
      _expectNoGhostPose(tester);
      await tester.pump(const Duration(milliseconds: 40));
      expect(_poseOpacities(tester), hasLength(1), reason: '換圖的下一幀就只剩一張立繪');

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

  // ── Blocker 1：台詞擁有權 ────────────────────────────────────

  group('台詞擁有權', () {
    testWidgets('點兔咪的三秒過期不得清掉後來出現的打卡台詞', (tester) async {
      _seed(3);
      await _pumpHome(tester);

      await tester.tap(find.byType(MascotStage));
      await tester.pump();
      expect(MascotPersona.current.value.speech, isNotNull);

      // 2.4 秒後才打卡：完成台詞會在原本 tap expiry（3 秒）之後才出現
      await tester.pump(const Duration(milliseconds: 2400));
      await _tapHabit(tester, '習慣1');
      await tester.pump(CompletionPresentationController.kSpeakDelay);
      expect(MascotPersona.current.value.speech, '今天第一件。');

      // 跨過原本的 tap expiry
      await tester.pump(const Duration(milliseconds: 400));
      expect(
        MascotPersona.current.value.speech,
        '今天第一件。',
        reason: '舊的點擊 timer 只能清自己那一句',
      );

      // 由完成事件自己的 quiet 結束
      await tester.pump(CompletionPresentationController.kQuietDelay);
      expect(MascotPersona.current.value.speech, isNull);

      await _tearDownHome(tester);
    });

    testWidgets('completion speak 之後撤銷：成功句立即失效', (tester) async {
      _seed(3);
      await _pumpHome(tester);

      await _tapHabit(tester, '習慣1');
      await tester.pump(CompletionPresentationController.kSpeakDelay);
      expect(MascotPersona.current.value.speech, '今天第一件。');

      await _tapHabit(tester, '習慣1'); // 撤銷
      await tester.pump();
      expect(
        MascotPersona.current.value.speech,
        isNot('今天第一件。'),
        reason: '撤銷後不得留著過時的成功句',
      );

      await _tearDownHome(tester);
    });

    testWidgets('speak 之後、quiet 之前進入全完成：不攜帶普通完成句', (tester) async {
      // 3 件：第一件是 1/3，還沒過半，走普通完成並開口說一句。
      _seed(3);
      await _pumpHome(tester);

      await _tapHabit(tester, '習慣1');
      await tester.pump(CompletionPresentationController.kSpeakDelay);
      expect(MascotPersona.current.value.speech, '今天第一件。');

      // 尾韻還沒收（quiet 在 2900ms）就一路做到全完成
      await _tapHabit(tester, '習慣2');
      await tester.pump(const Duration(milliseconds: 60));
      await _tapHabit(tester, '習慣3');
      await tester.pump();
      expect(
        MascotPersona.current.value.speech,
        isNot('今天第一件。'),
        reason: '全完成不得沿用普通完成的句子',
      );
      expect(
        MascotLines.linesFor(MascotContext.allDone),
        contains(MascotPersona.current.value.speech),
        reason: '要換成 allDone 自己的台詞池',
      );

      await _tearDownHome(tester);
    });

    testWidgets('第二條弧線不重用「今天第一件。」', (tester) async {
      _seed(5);
      await _pumpHome(tester);

      await _tapHabit(tester, '習慣1');
      await tester.pump(CompletionPresentationController.kSpeakDelay);
      expect(MascotPersona.current.value.speech, '今天第一件。');

      // 落在第一條弧線的 700–2900ms 之間：合併視窗已關、尾韻還沒收
      await tester.pump(const Duration(milliseconds: 900));
      await _tapHabit(tester, '習慣2');
      await tester.pump(CompletionPresentationController.kSpeakDelay);
      expect(
        MascotPersona.current.value.speech,
        isNot('今天第一件。'),
        reason: '第二條弧線的台詞要在 speak 當下重算，不能沿用舊值',
      );

      await _tearDownHome(tester);
    });

    testWidgets('被優先度擋下的點擊不取得台詞擁有權', (tester) async {
      _seed(3);
      final home = await _pumpHome(tester);

      // 撤銷（undone，優先度 20）會 hold 住五秒
      await _tapHabit(tester, '習慣1');
      await tester.pump(const Duration(milliseconds: 900));
      await _tapHabit(tester, '習慣1');
      await tester.pump();
      final undoSpeech = MascotPersona.current.value.speech;
      expect(home.debugSpeechOwnerSource, HomeSpeechSource.undo);

      // tapReaction 優先度 5，會被擋下來
      await tester.tap(find.byType(MascotStage));
      await tester.pump();
      expect(
        home.debugSpeechOwnerSource,
        HomeSpeechSource.undo,
        reason: '沒有真的套用的互動不該搶走擁有權',
      );
      expect(MascotPersona.current.value.speech, undoSpeech);

      await _tearDownHome(tester);
    });

    testWidgets('開場問候可以撐過 silent 中間拍，且只由自己收掉', (tester) async {
      _seed(3);
      await _pumpHome(tester);
      // 正式的冷啟動問候會標記來源；silent 中間拍只保留這一種。
      MascotPersona.setForContext(
        MascotEmotion.neutralFront.assetPath,
        MascotContext.openApp,
        speech: '嗯...你來了。',
        force: true,
        origin: MascotStateOrigin.opening,
      );
      await tester.pump();

      await _tapHabit(tester, '習慣2'); // 非首件語意的那條路也要保留
      await tester.pump(CompletionPresentationController.kImpactDelay);
      expect(
        MascotPersona.current.value.speech,
        '嗯...你來了。',
        reason: '沒有人主張擁有的開場問候是唯一允許保留的來源',
      );

      await tester.pump(
        CompletionPresentationController.kSpeakDelay -
            CompletionPresentationController.kImpactDelay,
      );
      expect(MascotPersona.current.value.speech, '今天第一件。');

      await _tearDownHome(tester);
    });
  });

  // ── Blocker 2：演出身分與完整生命週期 ────────────────────────

  group('演出生命週期', () {
    testWidgets('離開首頁後，跟在後面的完成不得 offscreen 播出', (tester) async {
      _seed(4);
      final visible = ValueNotifier<bool>(true);
      _setSurface(tester);
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

      await _tapHabit(tester, '習慣1'); // A @ 0ms
      await tester.pump(const Duration(milliseconds: 650));
      await _tapHabit(tester, '習慣2'); // B @ 650ms（impact 還在 300ms 後）
      await tester.pump(const Duration(milliseconds: 100)); // 750ms
      log.clear();

      visible.value = false;
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(seconds: 4));

      expect(log.cues, isEmpty, reason: 'B 的 impact 不得在看不見時播出');
      expect(log.haptics, isEmpty);
      expect(log.voices, isEmpty);
      expect(log.bubbles, isEmpty);
      expect(home.debugPresentationActive, isFalse);

      // 切回來也不補播
      visible.value = true;
      await tester.pump();
      await tester.pump(const Duration(seconds: 3));
      expect(log.cues, isEmpty, reason: '切回來不得補播舊的完成');
      expect((home.habits as List)[0]['done'], isTrue);
      expect((home.habits as List)[1]['done'], isTrue);

      visible.dispose();
      await _tearDownHome(tester);
    });

    testWidgets('快照被換掉時，舊的完成 callback 全部失效', (tester) async {
      _seed(4);
      final home = await _pumpHome(tester);
      log.clear();

      await _tapHabit(tester, '習慣1');
      await tester.pump(const Duration(milliseconds: 100)); // impact 還沒到
      expect(home.debugPresentationActive, isTrue);

      // 邏輯日／resume 造成的快照替換
      await home.loadHabits();
      await tester.pump();
      expect(home.debugPresentationActive, isFalse);

      await tester.pump(const Duration(seconds: 4));
      expect(log.cues, isEmpty, reason: '舊 generation 的音效不得補播');
      expect(log.haptics, isEmpty);
      expect(log.voices, isEmpty);
      expect(log.bubbles, isEmpty);
      expect((home.habits as List)[0]['done'], isTrue, reason: '取消演出不得回滾資料');

      await _tearDownHome(tester);
    });

    testWidgets('連續完成 A、B 後撤銷 A：只有 A 的演出被取消', (tester) async {
      _seed(5);
      final home = await _pumpHome(tester);
      log.clear();

      await _tapHabit(tester, '習慣1'); // A
      await tester.pump(const Duration(milliseconds: 60));
      await _tapHabit(tester, '習慣2'); // B
      await tester.pump(const Duration(milliseconds: 60));
      // 兩件的 impact 都還沒到（300ms）
      expect(log.cues, isEmpty);

      await _tapHabit(tester, '習慣1'); // 撤銷 A
      await tester.pump(const Duration(seconds: 4));

      expect((home.habits as List)[0]['done'], isFalse);
      expect(
        (home.habits as List)[1]['done'],
        isTrue,
        reason: '撤銷 A 不得動到 B 的資料',
      );
      expect(
        log.cues,
        contains(SfxCue.success),
        reason: 'B 仍然有效，那一次成功回饋不該被 A 的撤銷全域取消',
      );
      expect(
        log.cues.where((c) => c == SfxCue.success).length,
        1,
        reason: '只剩 B 一次；A 的已被取消',
      );
      expect(log.cues, contains(SfxCue.cancel));

      final prefs = await SharedPreferences.getInstance();
      final history = prefs.getString(PrefsKeys.habitDoneDay(_todayString()));
      expect(history, contains('id_習慣2'));
      expect(history, isNot(contains('id_習慣1')));

      await _tearDownHome(tester);
    });
  });

  // ── Blocker 3：撤銷 transient 的擁有權 ──────────────────────

  group('撤銷 transient 擁有權', () {
    testWidgets('撤銷後 100ms 重做：跨過舊的兩秒過期仍維持正向狀態', (tester) async {
      _seed(3);
      final home = await _pumpHome(tester);

      await _tapHabit(tester, '習慣1');
      await tester.pump(const Duration(milliseconds: 200));
      await _tapHabit(tester, '習慣1'); // 撤銷
      await tester.pump(const Duration(milliseconds: 100));
      await _tapHabit(tester, '習慣1'); // 重做
      await tester.pump(const Duration(seconds: 3)); // 跨過舊 sad 的 2 秒

      expect(home.debugBaselineMascotContext, MascotContext.completedOne);
      expect(
        MascotPersona.current.value.assetPath,
        MascotEmotion.expect.assetPath,
        reason: '舊的 sad 過期不得把兔咪拉回難過的臉',
      );

      await _tearDownHome(tester);
    });

    testWidgets('撤銷後立刻全完成：舊的 sad 過期不得污染', (tester) async {
      _seed(2);
      final home = await _pumpHome(tester);

      await _tapHabit(tester, '習慣1');
      await tester.pump(const Duration(milliseconds: 200));
      await _tapHabit(tester, '習慣1'); // 撤銷
      await tester.pump(const Duration(milliseconds: 100));
      await _tapHabit(tester, '習慣1');
      await tester.pump(const Duration(milliseconds: 50));
      await _tapHabit(tester, '習慣2'); // 全完成
      await tester.pump();
      expect(home.allDone0, isTrue);

      await tester.pump(const Duration(seconds: 3));
      expect(
        MascotPersona.current.value.assetPath,
        isNot(MascotEmotion.sad.assetPath),
        reason: '舊 sad timer 不得覆寫全完成',
      );
      expect(home.debugBaselineMascotContext, MascotContext.allDone);

      await _tearDownHome(tester);
    });
  });

  // ── Blocker 4：全完成的動作交棒 ──────────────────────────────

  group('全完成交棒', () {
    testWidgets('進入全完成 300ms 後，新的反應仍在進行且沒有被舊取消壓掉', (tester) async {
      _seed(2);
      final home = await _pumpHome(tester);
      home.debugClearSemanticEvents();

      await _tapHabit(tester, '習慣1');
      await tester.pump(const Duration(milliseconds: 400));
      final tickBefore = _persona(tester).reactionTick;

      await _tapHabit(tester, '習慣2'); // 全完成
      await tester.pump();
      final persona = _persona(tester);
      expect(persona.reactionTick, greaterThan(tickBefore));
      expect(
        persona.reactionCancelUpTo,
        lessThan(persona.reactionTick),
        reason: '取消只針對舊那一代，不能把同一幀開始的新反應一起殺掉',
      );
      expect(persona.reactionStrength, 1.0);

      await tester.pump(const Duration(milliseconds: 300));
      expect(
        home.debugSemanticEvents,
        isNot(contains(MascotContext.completedOne)),
        reason: '全完成不得與普通完成疊播',
      );
      expect(home.debugSemanticEvents.last, MascotContext.allDone);

      await _tearDownHome(tester);
    });
  });

  // ── Blocker 5：一半門檻的主事件 ─────────────────────────────

  group('一半門檻', () {
    testWidgets('剛好跨過一半：只有一個 halfDone 語意事件', (tester) async {
      _seed(4);
      final home = await _pumpHome(tester);

      await _tapHabit(tester, '習慣1'); // 1/4，普通完成
      await tester.pump(const Duration(seconds: 4));
      log.clear();
      home.debugClearSemanticEvents();

      await _tapHabit(tester, '習慣2'); // 2/4 = 剛好跨過一半
      await tester.pump(const Duration(seconds: 4));

      expect(
        home.debugSemanticEvents,
        [MascotContext.halfDone],
        reason: '不得先完整播一次 completedOne 再靜靜換成 half baseline',
      );
      expect(
        home.debugSemanticEvents,
        isNot(contains(MascotContext.completedOne)),
      );
      expect(log.bubbles, [EmotionBubble.note], reason: '泡泡只有一次');
      expect(
        log.cues.where((c) => c == SfxCue.success).length,
        1,
        reason: '卡片自己的確認回饋仍然成立，而且只有一次',
      );
      expect(home.dailyDoneCount, 2);
      expect(home.debugBaselineMascotContext, MascotContext.halfDone);

      await _tearDownHome(tester);
    });
  });

  // ── 弧線語意身分（late half handoff／降級）────────────────────

  group('弧線語意身分', () {
    testWidgets('沒有 follower 時只交付 completedOne', (tester) async {
      _seed(4);
      final home = await _pumpHome(tester);
      home.debugClearSemanticEvents();
      log.clear();

      await _tapHabit(tester, '習慣1'); // 1/4，不過半
      await tester.pump(const Duration(seconds: 4));

      expect(home.debugSemanticEvents, [MascotContext.completedOne]);
      expect(log.bubbles, [EmotionBubble.note]);

      await _tearDownHome(tester);
    });

    for (final followerAt in [500, 650]) {
      testWidgets('過半的後續成員在 ${followerAt}ms 到達仍交付 halfDone 一次', (tester) async {
        _seed(4);
        final home = await _pumpHome(tester);
        home.debugClearSemanticEvents();
        log.clear();

        await _tapHabit(tester, '習慣1'); // 弧線由普通完成開頭
        await tester.pump(Duration(milliseconds: followerAt));
        expect(home.debugSemanticEvents, [
          MascotContext.completedOne,
        ], reason: 'speak 在 470ms，這時普通完成的語意已經送出去了');
        final reactionBefore = _persona(tester).reactionTick;
        final noticeBefore = _persona(tester).noticeTick;

        await _tapHabit(tester, '習慣2'); // 2/4 = 跨過一半，仍在合併視窗內
        await tester.pump(const Duration(seconds: 4));

        expect(
          home.debugSemanticEvents
              .where((MascotContext c) => c == MascotContext.halfDone)
              .length,
          1,
          reason: 'halfDone 必須恰好交付一次（實際：${home.debugSemanticEvents}）',
        );
        expect(
          _persona(tester).reactionTick,
          reactionBefore,
          reason: '補送里程碑不得重啟蹲跳',
        );
        expect(
          _persona(tester).noticeTick,
          noticeBefore,
          reason: '補送里程碑不得重跑察覺',
        );
        expect(home.debugBaselineMascotContext, MascotContext.halfDone);

        await _tearDownHome(tester);
      });
    }

    testWidgets('Reduce Motion：過半成員在 speak 之後、視窗關閉前到達', (tester) async {
      _seed(4);
      final home = await _pumpHome(tester, reduceMotion: true);
      home.debugClearSemanticEvents();

      await _tapHabit(tester, '習慣1');
      // Reduce Motion 的 speak 在 200ms；300ms 已經過了它，但還在 700ms 視窗內
      await tester.pump(const Duration(milliseconds: 300));
      expect(home.debugSemanticEvents, [MascotContext.completedOne]);

      await _tapHabit(tester, '習慣2');
      await tester.pump(const Duration(seconds: 4));

      expect(
        home.debugSemanticEvents
            .where((MascotContext c) => c == MascotContext.halfDone)
            .length,
        1,
      );

      await _tearDownHome(tester);
    });

    testWidgets('過半成員在語意交付前被撤銷：弧線降回 ordinary', (tester) async {
      _seed(4);
      final home = await _pumpHome(tester);
      home.debugClearSemanticEvents();

      await _tapHabit(tester, '習慣1'); // 1/4
      await tester.pump(const Duration(milliseconds: 60));
      await _tapHabit(tester, '習慣2'); // 2/4 跨過一半（speak 還沒到）
      await tester.pump(const Duration(milliseconds: 60));
      await _tapHabit(tester, '習慣2'); // 撤銷那一件
      await tester.pump(const Duration(seconds: 4));

      expect(
        home.debugSemanticEvents,
        isNot(contains(MascotContext.halfDone)),
        reason: '半程成員沒了就該降回普通完成（實際：${home.debugSemanticEvents}）',
      );
      expect(home.dailyDoneCount, 1);

      await _tearDownHome(tester);
    });
  });

  // ── 多事件撤銷：只取消那一件 ─────────────────────────────────

  group('多事件撤銷', () {
    for (final undoAt in [
      ('蹲跳前後', CompletionPresentationController.kAnticipateDelay),
      ('衝擊點附近', CompletionPresentationController.kImpactDelay),
    ]) {
      testWidgets('A、B 連打後在${undoAt.$1}撤銷 A：B 完整保留', (tester) async {
        _seed(5);
        final home = await _pumpHome(tester);
        log.clear();

        await _tapHabit(tester, '習慣1'); // A
        await tester.pump(const Duration(milliseconds: 40));
        await _tapHabit(tester, '習慣2'); // B（共用同一條弧線）
        final reactionAfterArc = _persona(tester).reactionTick;
        await tester.pump(undoAt.$2);

        final cancelBefore = _persona(tester).reactionCancelUpTo;
        await _tapHabit(tester, '習慣1'); // 撤銷 A
        await tester.pump();

        expect(
          _persona(tester).reactionCancelUpTo,
          cancelBefore,
          reason: 'B 還活著，共用的那段動作不得被 A 的撤銷收掉',
        );

        await tester.pump(const Duration(seconds: 4));

        expect((home.habits as List)[0]['done'], isFalse);
        expect((home.habits as List)[1]['done'], isTrue);
        expect(
          _persona(tester).reactionTick,
          greaterThanOrEqualTo(reactionAfterArc),
        );
        expect(
          log.cues.where((c) => c == SfxCue.success).length,
          lessThanOrEqualTo(2),
        );
        expect(log.cues, contains(SfxCue.cancel), reason: '撤銷本身仍要有回饋');
        // B 的姿勢不得借用 A 撤銷留下的 sad
        expect(
          MascotPersona.current.value.assetPath,
          isNot(MascotEmotion.sad.assetPath),
        );

        final prefs = await SharedPreferences.getInstance();
        final history = prefs.getString(PrefsKeys.habitDoneDay(_todayString()));
        expect(history, contains('id_習慣2'));
        expect(history, isNot(contains('id_習慣1')));

        await _tearDownHome(tester);
      });
    }

    testWidgets('存活弧線的收尾不清掉較新的撤銷台詞', (tester) async {
      _seed(5);
      await _pumpHome(tester);

      await _tapHabit(tester, '習慣1'); // A
      await tester.pump(const Duration(milliseconds: 40));
      await _tapHabit(tester, '習慣2'); // B
      await tester.pump(const Duration(milliseconds: 600));

      await _tapHabit(tester, '習慣1'); // 撤銷 A → 撤銷台詞
      await tester.pump();
      final undoSpeech = MascotPersona.current.value.speech;
      expect(undoSpeech, isNotNull);

      // 讓存活弧線的 recover / quiet 都跑過去
      await tester.pump(const Duration(milliseconds: 400));
      expect(
        MascotPersona.current.value.speech,
        undoSpeech,
        reason: 'recover 不得清掉比自己更新的撤銷台詞',
      );

      await _tearDownHome(tester);
    });

    testWidgets('存活弧線的收尾不清掉其他分頁建立的高優先狀態', (tester) async {
      _seed(5);
      await _pumpHome(tester);

      await _tapHabit(tester, '習慣1');
      await tester.pump(const Duration(milliseconds: 40));
      await _tapHabit(tester, '習慣2');
      await tester.pump(const Duration(milliseconds: 500));

      // 喝水頁的實際呼叫路徑：優先度 40，會蓋過首頁
      MascotPersona.interact(MascotContext.overhydration);
      final waterSpeech = MascotPersona.current.value.speech;
      final waterClaim = MascotPersona.claim;
      expect(waterSpeech, isNotNull);

      await tester.pump(const Duration(seconds: 4));
      expect(MascotPersona.claim, waterClaim, reason: '首頁的收尾不得再寫一次');
      expect(MascotPersona.current.value.speech, waterSpeech);

      await _tearDownHome(tester);
    });
  });

  // ── 全域擁有權：其他分頁接手之後 ────────────────────────────

  group('全域擁有權', () {
    testWidgets('點兔咪後切到喝水頁建立過量提醒：首頁的過期不得覆寫', (tester) async {
      _seed(3);
      await _pumpHome(tester);

      await tester.tap(find.byType(MascotStage));
      await tester.pump();
      expect(MascotPersona.current.value.speech, isNotNull);

      // 其他分頁寫入更高優先的狀態
      MascotPersona.interact(MascotContext.overhydration);
      final waterClaim = MascotPersona.claim;
      final waterSpeech = MascotPersona.current.value.speech;

      // 跨過首頁點擊的三秒過期
      await tester.pump(const Duration(seconds: 4));
      expect(MascotPersona.claim, waterClaim, reason: '首頁的舊 timer 不得覆寫其他分頁的狀態');
      expect(MascotPersona.current.value.speech, waterSpeech);

      await _tearDownHome(tester);
    });

    testWidgets('連續點擊被優先度擋下：保留原台詞與原本剩餘的過期時間', (tester) async {
      _seed(3);
      await _pumpHome(tester);

      await tester.tap(find.byType(MascotStage));
      await tester.pump();
      final firstSpeech = MascotPersona.current.value.speech;
      expect(firstSpeech, isNotNull);

      // 停留期內再點一次 → tapReaction 優先度相同，會被擋下
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tap(find.byType(MascotStage));
      await tester.pump();
      expect(
        MascotPersona.current.value.speech,
        firstSpeech,
        reason: '被擋下的點擊不得換掉台詞',
      );

      // 原本那條 expiry 仍然照原訂時間收掉（不是被第二次點擊延長或取消）
      await tester.pump(const Duration(milliseconds: 2400));
      expect(MascotPersona.current.value.speech, firstSpeech);
      await tester.pump(const Duration(milliseconds: 200));
      expect(
        MascotPersona.current.value.speech,
        isNull,
        reason: '舊 expiry 不得被第二次點擊弄丟',
      );

      await _tearDownHome(tester);
    });

    testWidgets('speak 之後切走分頁：只收自己的狀態，不動其他分頁的', (tester) async {
      _seed(3);
      final visible = ValueNotifier<bool>(true);
      _setSurface(tester);
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

      await _tapHabit(tester, '習慣1');
      await tester.pump(CompletionPresentationController.kSpeakDelay);
      expect(MascotPersona.current.value.speech, '今天第一件。');

      visible.value = false;
      await tester.pump();
      await tester.pump();
      expect(
        MascotPersona.current.value.speech,
        isNull,
        reason: '切走時要收掉自己還擁有的台詞',
      );

      // 換成其他分頁的狀態後再讓舊 timer 全部跑完
      MascotPersona.interact(MascotContext.overhydration);
      final waterClaim = MascotPersona.claim;
      await tester.pump(const Duration(seconds: 5));
      expect(MascotPersona.claim, waterClaim);

      visible.dispose();
      await _tearDownHome(tester);
    });

    testWidgets('同日換快照：只收舊 generation 還擁有的狀態', (tester) async {
      _seed(3);
      final home = await _pumpHome(tester);

      await _tapHabit(tester, '習慣1');
      await tester.pump(CompletionPresentationController.kSpeakDelay);
      expect(MascotPersona.current.value.speech, '今天第一件。');

      await home.loadHabits();
      await tester.pump();
      expect(
        MascotPersona.current.value.speech,
        isNull,
        reason: '換快照要收掉舊 generation 擁有的台詞',
      );

      MascotPersona.interact(MascotContext.overhydration);
      final waterClaim = MascotPersona.claim;
      await home.loadHabits();
      await tester.pump();
      expect(MascotPersona.claim, waterClaim, reason: '已經被其他分頁接手時，作廢必須 no-op');

      await _tearDownHome(tester);
    });

    testWidgets('dispose 收掉首頁 callback，且不清掉較新的外部狀態', (tester) async {
      _seed(3);
      await _pumpHome(tester);

      await _tapHabit(tester, '習慣1');
      await tester.pump(const Duration(milliseconds: 100));

      MascotPersona.interact(MascotContext.overhydration);
      final waterClaim = MascotPersona.claim;
      log.clear();

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 6));

      expect(tester.takeException(), isNull);
      expect(log.cues, isEmpty, reason: 'dispose 後不得再發回饋');
      expect(MascotPersona.claim, waterClaim, reason: 'dispose 不得清掉較新的外部狀態');
      // 排掉 MascotPersona 自己的十秒回神計時（那是全域的，不是首頁的）
      await tester.pump(const Duration(seconds: 6));
    });

    testWidgets('重載等待期間不得發出舊的 impact 與回饋', (tester) async {
      _seed(3);
      final home = await _pumpHome(tester);
      log.clear();

      await _tapHabit(tester, '習慣1');
      await tester.pump(const Duration(milliseconds: 60));

      // 不 await：重載進行中（storage 還在等），刻意讓時間跨過 impact
      final pending = home.loadHabits() as Future<void>;
      await tester.pump(const Duration(milliseconds: 600));
      expect(log.cues, isEmpty, reason: '重載等待期間不得播出舊的 impact 音效');
      expect(log.haptics, isEmpty);
      expect(log.voices, isEmpty);
      expect(log.bubbles, isEmpty);

      await pending;
      await tester.pump(const Duration(seconds: 3));
      expect(log.cues, isEmpty, reason: '重載結束後也不補播');
      expect((home.habits as List)[0]['done'], isTrue, reason: '取消演出不得回滾資料');

      await _tearDownHome(tester);
    });
  });

  // ── Reduce Motion：位移一律為零 ─────────────────────────────

  group('Reduce Motion 位移', () {
    testWidgets('completion 期間兔咪完全不位移、不縮放、不冒粒子', (tester) async {
      _seed(3);
      await _pumpHome(tester, reduceMotion: true);
      final before = _persona(tester);
      final baseTop = tester.getTopLeft(find.byType(MascotStage)).dy;

      await _tapHabit(tester, '習慣1');
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 50));
        final p = _persona(tester);
        expect(
          p.reactionTick,
          before.reactionTick,
          reason: 'Reduce Motion 不得蹲跳（粒子與它同一個控制器）',
        );
        expect(p.noticeTick, before.noticeTick);
        expect(p.reduceMotion, isTrue);
      }
      expect(
        tester.getTopLeft(find.byType(MascotStage)).dy,
        closeTo(baseTop, 0.01),
        reason: 'stage 本身不得被位移',
      );

      await _tearDownHome(tester);
    });

    testWidgets('衝擊點、音效、觸覺與勾勾終點共用同一個時間', (tester) async {
      expect(
        CompletionPresentationController.kReducedImpactDelay,
        kHabitCheckDrawDurationReduced,
        reason: '兩邊不能各寫一個數字',
      );

      _seed(3);
      await _pumpHome(tester, reduceMotion: true);
      log.clear();

      await _tapHabit(tester, '習慣1');
      await tester.pump(
        kHabitCheckDrawDurationReduced - const Duration(milliseconds: 20),
      );
      expect(log.cues, isEmpty, reason: '筆尖還沒到就不該有聲音');
      expect(log.haptics, isEmpty);

      await tester.pump(const Duration(milliseconds: 40));
      expect(log.cues, [SfxCue.success]);
      expect(log.haptics, [HapticLevel.light]);

      await _tearDownHome(tester);
    });
  });

  // ── 弧線語意身分：speak 綁的那一件被撤銷之後 ──────────────────
  //
  // 語意屬於整條弧線，不屬於某一個 callback 帶著的 event id。lead 被撤銷時
  // 舊版會讓 speak 拿著一個已經消失的 id：epoch 查不到而回退成 0、quiet 又
  // 拿 follower 的 id 去比對，於是誰也收不掉自己發出去的那句話。

  group('弧線語意擁有權', () {
    testWidgets('A=0ms、B=40ms，speak 前撤銷 A：470ms 的舊完成不得覆寫較新的撤銷', (tester) async {
      _seed(5);
      final home = await _pumpHome(tester);
      log.clear();

      await _tapHabit(tester, '習慣1'); // A（弧線的 lead）
      await tester.pump(const Duration(milliseconds: 40));
      await _tapHabit(tester, '習慣2'); // B（併進同一條弧線）

      // 落在 speak（470ms）之前撤銷 A：弧線還活著，但 lead 已經不在了。
      await tester.pump(const Duration(milliseconds: 210));
      await _tapHabit(tester, '習慣1');
      await tester.pump();

      final undoSpeech = MascotPersona.current.value.speech;
      final undoClaim = MascotPersona.claim;
      expect(undoSpeech, isNotNull, reason: '撤銷本身要講話');
      expect(
        MascotPersona.current.value.assetPath,
        MascotEmotion.sad.assetPath,
      );

      // 跨過 470ms 的 speak。
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        MascotPersona.claim,
        undoClaim,
        reason: '較舊的 completion speak 不得覆寫較新的 Undo',
      );
      expect(MascotPersona.current.value.speech, undoSpeech);
      expect(
        home.debugSpeechOwnerSource,
        isNot(HomeSpeechSource.completion),
        reason: '弧線不得因為 lead 被撤銷就取得假的 speech owner',
      );

      // 跨過 recover(820ms) 與 quiet(2900ms)：仍然不得冒出完成的台詞。
      await tester.pump(const Duration(seconds: 3));
      expect(
        MascotPersona.current.value.speech,
        isNot('今天第一件。'),
        reason: 'recover／quiet 之後不得殘留錯誤的 completion speech',
      );

      // B 的資料與它自己那一次成功回饋都要留著。
      // A 的衝擊點在 300ms，撤銷發生在 250ms——那一次本來就該被取消，
      // 所以整段只剩 B 在 340ms 的那一次。
      expect((home.habits as List)[0]['done'], isFalse);
      expect((home.habits as List)[1]['done'], isTrue);
      expect(
        log.cues.where((c) => c == SfxCue.success).length,
        1,
        reason: 'B 自己的衝擊點回饋不得被 A 的撤銷吃掉',
      );
      expect(log.cues, contains(SfxCue.cancel), reason: '撤銷本身仍要有回饋');
      final prefs = await SharedPreferences.getInstance();
      final history = prefs.getString(PrefsKeys.habitDoneDay(_todayString()));
      expect(history, contains('id_習慣2'));

      await _tearDownHome(tester);
    });

    testWidgets('弧線的台詞由自己的 quiet 收掉，不留到十秒全域回神', (tester) async {
      _seed(5);
      await _pumpHome(tester);

      // A 單獨完成 → speak 在 470ms 發出「今天第一件。」並取得台詞擁有權。
      await _tapHabit(tester, '習慣1');
      await tester.pump(CompletionPresentationController.kSpeakDelay);
      expect(MascotPersona.current.value.speech, '今天第一件。');

      // 合併視窗（700ms）還開著時第二件加入：收尾拍會重排並改綁 B。
      // 舊版 speak 綁 A 的 event id、quiet 綁 B 的，兩邊永遠對不上。
      await tester.pump(const Duration(milliseconds: 30));
      await _tapHabit(tester, '習慣2');

      // B 的 quiet 在它自己的 2900ms；十秒全域回神還早得很。
      await tester.pump(
        CompletionPresentationController.kQuietDelay +
            const Duration(milliseconds: 200),
      );
      expect(
        MascotPersona.current.value.speech,
        isNull,
        reason: 'A／B 的 token 不同不該讓 quiet 收不掉自己那句話',
      );
      expect(
        MascotPersona.origin,
        MascotStateOrigin.home,
        reason: '收尾仍是首頁自己做的，不是被全域十秒回神接手',
      );

      await _tearDownHome(tester);
    });
  });

  // ── 外部高優先狀態面前，完成演出只做得到「資料」那一半 ──────────

  group('外部高優先狀態', () {
    testWidgets('overhydration 停留中完成一件：資料與回饋成立，四拍都不動外部狀態', (tester) async {
      _seed(5);
      final home = await _pumpHome(tester);

      // 喝水頁的實際呼叫路徑：優先度 40，高於 completedOne 的 10。
      MascotPersona.interact(MascotContext.overhydration);
      final waterClaim = MascotPersona.claim;
      final waterSpeech = MascotPersona.current.value.speech;
      final waterAsset = MascotPersona.current.value.assetPath;
      final waterBubble = MascotPersona.current.value.bubble;
      expect(waterSpeech, isNotNull);
      log.clear();

      await _tapHabit(tester, '習慣1');
      // 一路跨過 impact／speak／recover／quiet。
      await tester.pump(
        CompletionPresentationController.kQuietDelay +
            const Duration(milliseconds: 200),
      );

      expect((home.habits as List)[0]['done'], isTrue, reason: '資料照常提交');
      expect(
        log.cues,
        contains(SfxCue.success),
        reason: '衝擊點的成功回饋不受 persona 被擋影響',
      );
      expect(log.haptics, contains(HapticLevel.light));

      expect(MascotPersona.claim, waterClaim, reason: '外部收據不得被任何一拍改寫');
      expect(MascotPersona.current.value.speech, waterSpeech);
      expect(MascotPersona.current.value.assetPath, waterAsset);
      expect(MascotPersona.current.value.bubble, waterBubble);
      expect(
        home.debugSpeechOwnerSource,
        isNot(HomeSpeechSource.completion),
        reason: '被擋下的語意不得取得台詞擁有權',
      );

      await _tearDownHome(tester);
    });

    testWidgets('overhydration 停留中的 late half handoff：不得 force 蓋過去', (
      tester,
    ) async {
      // 4 件：第一件不過半，第二件剛好到 2/4 → 觸發 late half handoff。
      _seed(4);
      final home = await _pumpHome(tester);

      await _tapHabit(tester, '習慣1');
      // 等 speak 發完普通完成的語意，之後才讓第二件跨過門檻。
      await tester.pump(CompletionPresentationController.kSpeakDelay);
      expect(home.debugSemanticEvents, contains(MascotContext.completedOne));

      MascotPersona.interact(MascotContext.overhydration);
      final waterClaim = MascotPersona.claim;
      final waterSpeech = MascotPersona.current.value.speech;
      home.debugClearSemanticEvents();

      // 仍在同一條弧線的合併視窗內（700ms）→ 走 milestoneHandoff。
      await _tapHabit(tester, '習慣2');
      await tester.pump(const Duration(seconds: 4));

      expect((home.habits as List)[1]['done'], isTrue, reason: '資料照常提交');
      expect(MascotPersona.claim, waterClaim, reason: 'handoff 不得繞過外部優先度');
      expect(MascotPersona.current.value.speech, waterSpeech);
      expect(
        home.debugSemanticEvents,
        isNot(contains(MascotContext.halfDone)),
        reason: '被擋下的 handoff 不算一次語意事件',
      );
      expect(
        home.debugSpeechOwnerSource,
        isNot(HomeSpeechSource.completion),
        reason: 'half 語意不得取得假的 owner',
      );

      await _tearDownHome(tester);
    });

    testWidgets('外部高優先狀態中撤銷：外部不變，本地 sad 到期後確實消失', (tester) async {
      _seed(3);
      final home = await _pumpHome(tester);

      await _tapHabit(tester, '習慣1');
      await tester.pump(const Duration(seconds: 4));

      MascotPersona.interact(MascotContext.overhydration);
      final waterClaim = MascotPersona.claim;
      final waterAsset = MascotPersona.current.value.assetPath;

      await _tapHabit(tester, '習慣1'); // 撤銷：undone(20) 打不過 overhydration(40)
      await tester.pump();
      expect(MascotPersona.claim, waterClaim, reason: '被擋下的撤銷不得改寫外部狀態');
      expect(MascotPersona.current.value.assetPath, waterAsset);

      // 本地 sad 仍照自己的 seq／generation 到期，不會因為全域收據不符就卡住。
      await tester.pump(const Duration(seconds: 3));
      expect(
        home.debugBaselineMascotContext,
        isNot(MascotContext.undone),
        reason: '被拒絕的撤銷不得留下 latent sad 情境',
      );
      expect(MascotPersona.claim, waterClaim, reason: '到期清理不得碰外部狀態');

      // 下一次點兔咪不得出現「sad 立繪＋問號泡泡」的混合狀態。
      await tester.pump(const Duration(seconds: 8)); // 讓全域回神，點擊才進得去
      await tester.tap(find.byType(MascotStage));
      await tester.pump();
      expect(MascotPersona.current.value.bubble, EmotionBubble.question);
      expect(
        MascotPersona.current.value.assetPath,
        isNot(MascotEmotion.sad.assetPath),
        reason: '被拒絕的撤銷不得在下一次 tap 帶回 sad 立繪',
      );

      await _tearDownHome(tester);
    });
  });

  // ── Home 擁有的 persona 一定要有人收 ─────────────────────────
  //
  // 「有沒有台詞」不等於「Home 有沒有擁有 persona」：speech 為 null 的普通
  // 完成同樣寫過姿勢與停留狀態，那些也要收。

  group('Home persona 生命週期', () {
    testWidgets('speak 之後直接 dispose：Home 擁有的台詞、泡泡與姿勢都被收掉', (tester) async {
      _seed(3);
      await _pumpHome(tester);

      await _tapHabit(tester, '習慣1');
      await tester.pump(CompletionPresentationController.kSpeakDelay);
      expect(MascotPersona.current.value.speech, '今天第一件。');
      expect(MascotPersona.origin, MascotStateOrigin.home);
      log.clear();

      await tester.pumpWidget(const SizedBox());
      await tester.pump();

      expect(
        MascotPersona.current.value.speech,
        isNull,
        reason: 'dispose 要收掉仍由 Home 擁有的台詞',
      );
      expect(MascotPersona.current.value.bubble, isNull, reason: '泡泡也要收掉');
      expect(
        MascotPersona.origin,
        MascotStateOrigin.opening,
        reason: '收拾之後狀態不再屬於首頁',
      );

      // timers 不再回呼：既沒有聲音，也沒有新的泡泡。
      final afterDispose = MascotPersona.claim;
      await tester.pump(const Duration(seconds: 12));
      expect(log.cues, isEmpty);
      expect(log.voices, isEmpty);
      expect(log.bubbles, isEmpty);
      expect(
        MascotPersona.claim,
        afterDispose,
        reason: '收拾過就不該再排一次回神；十秒後也不得再寫一次',
      );
      expect(tester.takeException(), isNull);
    });

    for (final scenario in ['tab switch', 'reload', 'dispose']) {
      testWidgets('speech 為 null 的普通完成：$scenario 仍收掉 Home 的姿勢', (tester) async {
        _seed(5);
        final visible = ValueNotifier<bool>(true);
        _setSurface(tester);
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

        // 第一件走完整條弧線，第二件才是「不講話」的那一種。
        await _tapHabit(tester, '習慣1');
        await tester.pump(const Duration(seconds: 4));
        await _tapHabit(tester, '習慣2');
        await tester.pump(CompletionPresentationController.kSpeakDelay);
        expect(
          MascotPersona.current.value.speech,
          isNull,
          reason: '非首件本來就不講話——這正是要守的情況',
        );
        expect(
          MascotPersona.origin,
          MascotStateOrigin.home,
          reason: '沒有台詞，但姿勢與泡泡確實是首頁寫的',
        );

        switch (scenario) {
          case 'tab switch':
            visible.value = false;
            await tester.pump();
            await tester.pump();
          case 'reload':
            await home.loadHabits();
            await tester.pump();
          case 'dispose':
            await tester.pumpWidget(const SizedBox());
            await tester.pump();
        }

        expect(
          MascotPersona.origin,
          MascotStateOrigin.opening,
          reason: '$scenario 之後，Home 擁有的姿勢／泡泡必須已經收掉',
        );
        expect(MascotPersona.current.value.bubble, isNull);

        visible.dispose();
        await _tearDownHome(tester);
      });

      testWidgets('同一個 $scenario，但已被更新的外部狀態接手：完全 no-op', (tester) async {
        _seed(5);
        final visible = ValueNotifier<bool>(true);
        _setSurface(tester);
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

        await _tapHabit(tester, '習慣1');
        await tester.pump(const Duration(seconds: 4));
        await _tapHabit(tester, '習慣2');
        await tester.pump(CompletionPresentationController.kSpeakDelay);

        MascotPersona.interact(MascotContext.overhydration);
        final waterClaim = MascotPersona.claim;
        final waterSpeech = MascotPersona.current.value.speech;
        final waterAsset = MascotPersona.current.value.assetPath;

        switch (scenario) {
          case 'tab switch':
            visible.value = false;
            await tester.pump();
            await tester.pump();
          case 'reload':
            await home.loadHabits();
            await tester.pump();
          case 'dispose':
            await tester.pumpWidget(const SizedBox());
            await tester.pump();
        }

        expect(
          MascotPersona.claim,
          waterClaim,
          reason: '收據不符時，$scenario 的清理必須整段 no-op',
        );
        expect(MascotPersona.current.value.speech, waterSpeech);
        expect(MascotPersona.current.value.assetPath, waterAsset);

        visible.dispose();
        await _tearDownHome(tester);
      });
    }
  });

  // ── 全完成的 Reduce Motion ──────────────────────────────────

  group('Reduce Motion 全完成', () {
    testWidgets('一開始就是 Reduce Motion：沒有縮放、小跳、星星或移動特效', (tester) async {
      _seed(2);
      final home = await _pumpHome(tester, reduceMotion: true);
      final reactionBefore = _persona(tester).reactionTick;
      log.clear();

      await _tapHabit(tester, '習慣1');
      await tester.pump(const Duration(seconds: 4));
      await _tapHabit(tester, '習慣2'); // 全完成
      await tester.pump();

      expect(home.allDone0, isTrue, reason: '資料照常成立');
      expect(log.cues, contains(SfxCue.complete), reason: '全完成的音效要保留');
      expect(
        find.byType(RoomSceneEffects),
        findsNothing,
        reason: 'Reduce Motion 不得掛移動中的星光層',
      );

      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 60));
        expect(_celebScale(tester), closeTo(1.0, 1e-6), reason: '場景不得縮放');
        expect(
          _persona(tester).reactionTick,
          reactionBefore,
          reason: '不得起跳（星星與它共用控制器）',
        );
        expect(_sparkleProgress(tester), 0.0, reason: '粒子 progress 必須是零');
      }

      // 靜態語意仍然完整。
      expect(MascotPersona.current.value.speech, isNotNull);
      expect(MascotPersona.current.value.bubble, EmotionBubble.star);
      expect(
        MascotPersona.current.value.assetPath,
        MascotEmotion.happy.assetPath,
      );

      await _tearDownHome(tester);
    });

    testWidgets('全完成演出途中打開 Reduce Motion：正在播的當場停住或消失', (tester) async {
      _seed(2);
      final reduce = ValueNotifier<bool>(false);
      _setSurface(tester);
      await tester.pumpWidget(
        l10nTestApp(
          home: ValueListenableBuilder<bool>(
            valueListenable: reduce,
            builder: (context, v, _) => MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: v),
              child: const HomePage(),
            ),
          ),
        ),
      );
      await tester.pump();
      final home = tester.state(find.byType(HomePage)) as dynamic;
      await home.loadHabits();
      await tester.pump();

      await _tapHabit(tester, '習慣1');
      await tester.pump(const Duration(seconds: 4));
      await _tapHabit(tester, '習慣2'); // 全完成，動作開始
      await tester.pump(const Duration(milliseconds: 120));

      // 對照組：一般模式此刻確實在動。
      expect(_celebScale(tester), greaterThan(1.0));
      expect(find.byType(RoomSceneEffects), findsOneWidget);
      expect(_sparkleProgress(tester), greaterThan(0.0));
      final speech = MascotPersona.current.value.speech;

      reduce.value = true;
      await tester.pump();

      expect(_celebScale(tester), closeTo(1.0, 1e-6), reason: '場景縮放要當場停住');
      expect(find.byType(RoomSceneEffects), findsNothing, reason: '移動中的星光層要消失');
      expect(_sparkleProgress(tester), 0.0, reason: '粒子要立刻歸零');
      expect(MascotPersona.current.value.speech, speech, reason: '台詞與資料不受影響');
      expect(home.allDone0, isTrue);

      reduce.dispose();
      await _tearDownHome(tester);
    });
  });

  // ── 真實平台的無障礙設定（不是只改局部 MediaQuery）──────────────
  //
  // 這一組必須走 platformDispatcher：AnimationController 只看
  // SemanticsBinding.disableAnimations，局部 MediaQuery 影響不到它。
  // 預設的 AnimationBehavior.normal 會把 duration 壓成 5%，勾在約 7ms 就
  // 描完，而衝擊點仍照 140ms 的 Timer 走——聲音變成「後補」。

  group('真實平台無障礙設定', () {
    testWidgets('disableAnimations：勾勾仍照 140ms 描完，與衝擊點同一拍', (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );

      _seed(3);
      await _pumpHomeOnPlatform(tester);
      log.clear();

      await _tapHabit(tester, '習慣1');
      await tester.pump(
        kHabitCheckDrawDurationReduced - const Duration(milliseconds: 20),
      );
      expect(
        _checkProgress(tester),
        lessThan(0.999),
        reason: '140ms 之前勾勾不得已經描到終點',
      );
      expect(log.cues, isEmpty, reason: '筆尖還沒到就不該有聲音');
      expect(log.haptics, isEmpty);

      await tester.pump(const Duration(milliseconds: 40));
      expect(
        _checkProgress(tester),
        closeTo(1.0, 1e-6),
        reason: '140ms 的終點與衝擊點必須同一拍',
      );
      expect(log.cues, [SfxCue.success]);
      expect(log.haptics, [HapticLevel.light]);

      await _tearDownHome(tester);
    });

    testWidgets('accessibleNavigation 也走同一條 140ms 時間軸', (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(accessibleNavigation: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );

      _seed(3);
      await _pumpHomeOnPlatform(tester);
      log.clear();

      await _tapHabit(tester, '習慣1');
      await tester.pump(
        kHabitCheckDrawDurationReduced - const Duration(milliseconds: 20),
      );
      expect(_checkProgress(tester), lessThan(0.999));
      expect(log.cues, isEmpty);

      await tester.pump(const Duration(milliseconds: 40));
      expect(_checkProgress(tester), closeTo(1.0, 1e-6));
      expect(log.cues, [SfxCue.success]);
      expect(log.haptics, [HapticLevel.light]);

      await _tearDownHome(tester);
    });

    testWidgets('一般模式仍然是 300ms', (tester) async {
      _seed(3);
      await _pumpHomeOnPlatform(tester);
      log.clear();

      await _tapHabit(tester, '習慣1');
      await tester.pump(
        kHabitCheckDrawDurationReduced + const Duration(milliseconds: 20),
      );
      expect(
        _checkProgress(tester),
        lessThan(0.999),
        reason: '沒開無障礙設定時 140ms 還不該描完',
      );
      expect(log.cues, isEmpty);

      await tester.pump(
        kHabitCheckDrawDuration - kHabitCheckDrawDurationReduced,
      );
      expect(_checkProgress(tester), closeTo(1.0, 1e-6));
      expect(log.cues, [SfxCue.success]);

      await _tearDownHome(tester);
    });
  });

  // ── external takeover 之後，本地那句話必須真的消失 ──────────────
  //
  // 兩層清理必須分開：本地欄位只看自己的 token，能不能改寫全域才看收據。
  // 綁在一起的話，external 接手期間本地那句話永遠沒人收，之後任何一次
  // 沿用（inherit）都會把它帶回畫面上。

  group('external takeover 後的本地台詞', () {
    /// 走完整條時序：首頁拿到一句自己的台詞 → external 接手 → 離開首頁
    /// → external 自己回神 → 回到首頁。
    ///
    /// 那一句刻意用打卡的「帶件數」回應（`doneCountLine`）：它不在任何一般
    /// 台詞池裡，之後只要再出現就一定是本地殘留被沿用回來，不會跟隨機抽到
    /// 的同義句混淆。**不用點兔咪**當來源——`MascotPersona` 的停留時間走的是
    /// 真實時鐘，widget test 的假時鐘跨不過去，點擊會被完成事件的優先度擋掉；
    /// 兩者在本地擁有權上完全等價（都是 Home 擁有的 `_transientSpeech`）。
    /// 點擊那條路由「tap expiry …」那個案例覆蓋。
    Future<dynamic> takeoverThenReturn(
      WidgetTester tester,
      ValueNotifier<bool> visible,
    ) async {
      final home = tester.state(find.byType(HomePage)) as dynamic;
      await home.loadHabits();
      await tester.pump();

      await _tapHabit(tester, '習慣1');
      await tester.pump(CompletionPresentationController.kSpeakDelay);
      expect(
        MascotPersona.current.value.speech,
        '今天第一件。',
        reason: '這一句只有打卡與點擊會用，之後重新出現就是本地殘留',
      );

      // external 以更高優先度接手。
      MascotPersona.interact(MascotContext.overhydration);
      final waterClaim = MascotPersona.claim;

      // 離開首頁 → 整代作廢。
      visible.value = false;
      await tester.pump();
      await tester.pump();
      expect(
        MascotPersona.claim,
        waterClaim,
        reason: 'takeover 期間 Home 的清理不得改寫 external 狀態',
      );

      // external 自己十秒回神。
      await tester.pump(const Duration(seconds: 11));

      // 回到首頁。
      visible.value = true;
      await tester.pump();
      await tester.pump();
      return home;
    }

    for (final event in [
      'weekly 正向事件',
      'ordinary completion',
      'half completion',
    ]) {
      testWidgets('回到首頁後的 speech-null $event 不得帶回舊的點擊台詞', (tester) async {
        // 5 件 daily：完成 1 件是 1/5、2 件是 2/5（都還是 ordinary），
        // 第 3 件才跨過一半——三種事件各自走得到。
        // 再加一張每週卡 → 畫面要夠高，否則點不到最下面那張。
        _seed(5, withWeekly: true);
        final visible = ValueNotifier<bool>(true);
        _setSurface(tester, height: 1700);
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
        final home = await takeoverThenReturn(tester, visible);

        switch (event) {
          case 'weekly 正向事件':
            // 每週卡是按「＋」累加，不是點整張卡。
            await tester.tap(
              find.descendant(
                of: find.byType(HabitCard).last,
                matching: find.byIcon(Icons.add_rounded),
              ),
            );
            await tester.pump();
          case 'ordinary completion':
            await _tapHabit(tester, '習慣2'); // 2/5，仍是普通完成
            await tester.pump(CompletionPresentationController.kSpeakDelay);
          case 'half completion':
            await _tapHabit(tester, '習慣2');
            await tester.pump(const Duration(seconds: 4));
            await _tapHabit(tester, '習慣3'); // 3/5 → 跨過一半
            await tester.pump(CompletionPresentationController.kSpeakDelay);
        }
        // 進度已經足夠讓 baseline 走到「不講話」的情境，出現文字就只可能
        // 是本地殘留。
        expect(
          home.debugBaselineMascotContext,
          anyOf(MascotContext.completedOne, MascotContext.halfDone),
        );

        final speech = MascotPersona.current.value.speech;
        expect(
          speech,
          isNull,
          reason:
              '這三種事件本來都不講話（`MascotLines.speaksFor` 為 false）；'
              '出現任何文字就是離開首頁時沒清乾淨的本地台詞被沿用回來（實際：$speech）',
        );
        expect(
          home.debugSpeechOwnerSource,
          isNot(HomeSpeechSource.tap),
          reason: '那一句的擁有權早該在離開首頁時就收掉了',
        );

        visible.dispose();
        await _tearDownHome(tester);
      });
    }

    testWidgets('tap expiry 在 external 接手後仍清掉自己的本地台詞，但不碰全域', (tester) async {
      // 畫面要夠高，最下面那張每週卡才會真的掛載（否則只找得到區塊標題）。
      _seed(3, withWeekly: true);
      final home = await _pumpHome(tester, height: 1500);

      await tester.tap(find.byType(MascotStage));
      await tester.pump();
      expect(home.debugSpeechOwnerSource, HomeSpeechSource.tap);

      MascotPersona.interact(MascotContext.overhydration);
      final waterClaim = MascotPersona.claim;
      final waterSpeech = MascotPersona.current.value.speech;

      // 跨過點擊的三秒 expiry。
      await tester.pump(const Duration(seconds: 4));
      expect(
        home.debugSpeechOwnerSource,
        isNull,
        reason: 'expiry 要收掉自己那一句的本地擁有權，即使全域已被接手',
      );
      expect(MascotPersona.claim, waterClaim, reason: '但完全不得碰 external 的全域狀態');
      expect(MascotPersona.current.value.speech, waterSpeech);

      // 本地已經清乾淨 → 之後的 speech-null 事件不會把它帶回來。
      await tester.pump(const Duration(seconds: 8)); // external 回神
      await tester.tap(
        find.descendant(
          of: find.byType(HabitCard).last,
          matching: find.byIcon(Icons.add_rounded),
        ),
      );
      await tester.pump();
      expect(
        MascotPersona.current.value.speech,
        isNot(waterSpeech),
        reason: 'weekly 事件本身不該沿用 external 的話',
      );

      await _tearDownHome(tester);
    });
  });

  // ── 全完成之後立刻撤銷 ──────────────────────────────────────
  //
  // 撤銷的那一刻，剛才那個 allDone／streak 已經不成立了。它還壓在全域上
  // （優先度 30、停留五秒）就會把 undone（20）整個擋掉。

  group('全完成後立即撤銷', () {
    for (final variant in [('allDone', 0), ('streak', 9)]) {
      testWidgets('${variant.$1} 之後撤銷最後一件：sad 立即出現，不必等過期', (tester) async {
        _seed(2, streak: variant.$2);
        final home = await _pumpHome(tester);

        await _tapHabit(tester, '習慣1');
        await tester.pump(const Duration(seconds: 4));
        await _tapHabit(tester, '習慣2'); // 全完成
        await tester.pump();
        expect(home.allDone0, isTrue);
        expect(
          MascotPersona.current.value.assetPath,
          variant.$2 >= 7
              ? MascotEmotion.streak.assetPath
              : MascotEmotion.happy.assetPath,
          reason: '先確認確實進了 ${variant.$1}',
        );
        final milestoneClaim = MascotPersona.claim;
        log.clear();

        // 立刻撤銷最後一件。
        await _tapHabit(tester, '習慣2');
        await tester.pump();

        expect(
          MascotPersona.claim,
          isNot(milestoneClaim),
          reason: '過期的 ${variant.$1} 必須讓位給撤銷',
        );
        expect(
          MascotPersona.current.value.assetPath,
          MascotEmotion.sad.assetPath,
          reason: 'sad 立繪要當場出現，不得等兩秒 transient 或十秒回神',
        );
        expect(MascotPersona.current.value.speech, isNotNull, reason: '撤銷要講話');
        // 撤銷刻意**不**冒泡泡（`EmotionBubble.forContext` 的既定設計：汗滴
        // 是尷尬／無奈，跟 sad 的心疼互相打架，而且撤銷是低調時刻）。
        // 這裡守的是「里程碑讓位之後泡泡不會殘留」。
        expect(
          MascotPersona.current.value.bubble,
          isNull,
          reason: '不得留著全完成的星星泡泡',
        );
        expect(log.voices, contains(SfxCue.tumiSad), reason: '難過的語音要當場播');
        expect(log.cues, contains(SfxCue.cancel));

        // 資料與 history 不回歸。
        expect(home.allDone0, isFalse);
        expect((home.habits as List)[0]['done'], isTrue);
        expect((home.habits as List)[1]['done'], isFalse);
        final prefs = await SharedPreferences.getInstance();
        final history = prefs.getString(PrefsKeys.habitDoneDay(_todayString()));
        expect(history, contains('id_習慣1'));
        expect(history, isNot(contains('id_習慣2')));

        await _tearDownHome(tester);
      });
    }

    testWidgets('newer external claim 存在時，撤銷不得動它', (tester) async {
      _seed(2);
      final home = await _pumpHome(tester);

      await _tapHabit(tester, '習慣1');
      await tester.pump(const Duration(seconds: 4));
      await _tapHabit(tester, '習慣2'); // 全完成
      await tester.pump();

      MascotPersona.interact(MascotContext.overhydration);
      final waterClaim = MascotPersona.claim;
      final waterAsset = MascotPersona.current.value.assetPath;

      await _tapHabit(tester, '習慣2'); // 撤銷
      await tester.pump();

      expect(MascotPersona.claim, waterClaim, reason: '清 milestone 必須是 no-op');
      expect(MascotPersona.current.value.assetPath, waterAsset);
      expect(home.allDone0, isFalse, reason: '資料仍然照常撤銷');

      await _tearDownHome(tester);
    });
  });

  // ── half follower 撤銷後，同一個 window 內再次跨過門檻 ────────────

  group('half 重新跨越', () {
    testWidgets('B 跨 half 後被撤銷，C 在同一個 window 再跨：交付恰好一次', (tester) async {
      _seed(4);
      final home = await _pumpHome(tester);

      await _tapHabit(tester, '習慣1'); // A@0ms，1/4 ordinary
      await tester.pump(CompletionPresentationController.kSpeakDelay);
      home.debugClearSemanticEvents();

      await tester.pump(const Duration(milliseconds: 30)); // t=500
      await _tapHabit(tester, '習慣2'); // B 跨 half（2/4）
      final noticeAfterB = _persona(tester).noticeTick;
      final reactionAfterB = _persona(tester).reactionTick;

      await tester.pump(const Duration(milliseconds: 20)); // t=520
      await _tapHabit(tester, '習慣2'); // 撤銷 B → 回到 1/4

      await tester.pump(const Duration(milliseconds: 160)); // t=680
      await _tapHabit(tester, '習慣3'); // C 再次跨 half，仍在同一個 arc window
      expect(
        home.debugCompletionArcActive,
        isTrue,
        reason: 'C 必須併進同一條弧線（700ms 合併視窗）',
      );

      await tester.pump(const Duration(seconds: 4));

      expect((home.habits as List)[0]['done'], isTrue);
      expect((home.habits as List)[1]['done'], isFalse);
      expect((home.habits as List)[2]['done'], isTrue);
      expect(home.dailyDoneCount, 2, reason: '資料為 2/4');
      expect(
        home.debugBaselineMascotContext,
        MascotContext.halfDone,
        reason: 'baseline 必須是 halfDone',
      );
      expect(
        (home.debugSemanticEvents as List)
            .where((e) => e == MascotContext.halfDone)
            .length,
        1,
        reason: 'half milestone handoff 必須恰好交付一次',
      );
      expect(
        _persona(tester).noticeTick,
        noticeAfterB,
        reason: 'handoff 不得重啟察覺',
      );
      expect(
        _persona(tester).reactionTick,
        reactionAfterB,
        reason: 'handoff 不得重啟蹲跳',
      );

      await _tearDownHome(tester);
    });
  });

  // ── speech-null 的收尾也要結束演出 ───────────────────────────

  group('演出結束的 poseTransition', () {
    for (final variant in ['有台詞', 'speech 為 null']) {
      testWidgets('$variant 的 quiet 之後，換立繪立刻回到交叉淡入', (tester) async {
        _seed(5);
        await _pumpHome(tester);

        if (variant == 'speech 為 null') {
          // 第一件走完（會講話），第二件才是不講話的那一種。
          await _tapHabit(tester, '習慣1');
          await tester.pump(const Duration(seconds: 4));
        }
        await _tapHabit(tester, variant == 'speech 為 null' ? '習慣2' : '習慣1');
        await tester.pump(CompletionPresentationController.kSpeakDelay);
        expect(
          MascotPersona.current.value.speech,
          variant == 'speech 為 null' ? isNull : isNotNull,
          reason: '先確認這一輪確實是「$variant」',
        );
        expect(
          _persona(tester).poseTransition,
          MascotPoseTransition.cut,
          reason: '演出期間本來就該是離散換圖',
        );

        // 跑完 quiet；刻意不做任何其他互動。
        await tester.pump(
          CompletionPresentationController.kQuietDelay +
              const Duration(milliseconds: 100),
        );
        expect(
          _persona(tester).poseTransition,
          MascotPoseTransition.crossFade,
          reason: '演出結束就要回到交叉淡入，不能等下一次無關的互動才修正',
        );

        await _tearDownHome(tester);
      });
    }

    testWidgets('quiet 不得清掉更新的撤銷台詞', (tester) async {
      _seed(5);
      await _pumpHome(tester);

      // 第一件走完整條弧線，之後才有「已完成、可以撤銷」的另一件。
      await _tapHabit(tester, '習慣1');
      await tester.pump(const Duration(seconds: 4));

      await _tapHabit(tester, '習慣2'); // 這條弧線的 quiet 在 2900ms
      await tester.pump(const Duration(milliseconds: 2500));

      // quiet 之前撤銷**另一件**：那句話比這條弧線新，而且弧線本身還活著。
      await _tapHabit(tester, '習慣1');
      await tester.pump();
      final undoSpeech = MascotPersona.current.value.speech;
      final undoClaim = MascotPersona.claim;
      expect(undoSpeech, isNotNull);
      expect(
        MascotPersona.current.value.assetPath,
        MascotEmotion.sad.assetPath,
      );

      await tester.pump(const Duration(milliseconds: 500)); // 跨過 quiet
      expect(MascotPersona.claim, undoClaim, reason: 'quiet 不得覆寫更新的台詞');
      expect(MascotPersona.current.value.speech, undoSpeech);

      await _tearDownHome(tester);
    });
  });

  // ── Reduce Motion 下的全完成立繪 ────────────────────────────

  group('Reduce Motion 全完成立繪', () {
    for (final variant in [('allDone', 0), ('streak', 9)]) {
      testWidgets('${variant.$1}：最後一勾是單一不透明立繪，沒有交叉淡入', (tester) async {
        _seed(2, streak: variant.$2);
        final home = await _pumpHome(tester, reduceMotion: true);
        log.clear();

        await _tapHabit(tester, '習慣1');
        await tester.pump(const Duration(seconds: 4));
        await _tapHabit(tester, '習慣2'); // 全完成
        await tester.pump();

        expect(
          _persona(tester).poseTransition,
          MascotPoseTransition.cut,
          reason: 'Reduce Motion 下不得走交叉淡入',
        );
        for (var i = 0; i < 12; i++) {
          _expectNoGhostPose(tester);
          expect(_celebScale(tester), closeTo(1.0, 1e-6));
          await tester.pump(const Duration(milliseconds: 40));
        }

        // 語意與回饋完整保留。
        expect(home.allDone0, isTrue);
        expect(log.cues, contains(SfxCue.complete));
        expect(MascotPersona.current.value.speech, isNotNull);
        expect(MascotPersona.current.value.bubble, EmotionBubble.star);
        expect(
          MascotPersona.current.value.assetPath,
          variant.$2 >= 7
              ? MascotEmotion.streak.assetPath
              : MascotEmotion.happy.assetPath,
        );

        await _tearDownHome(tester);
      });
    }

    testWidgets('全完成的交叉淡入途中打開 Reduce Motion：立即收斂成單一不透明立繪', (tester) async {
      _seed(2);
      final reduce = ValueNotifier<bool>(false);
      _setSurface(tester);
      await tester.pumpWidget(
        l10nTestApp(
          home: ValueListenableBuilder<bool>(
            valueListenable: reduce,
            builder: (context, v, _) => MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: v),
              child: const HomePage(),
            ),
          ),
        ),
      );
      await tester.pump();
      final home = tester.state(find.byType(HomePage)) as dynamic;
      await home.loadHabits();
      await tester.pump();

      await _tapHabit(tester, '習慣1');
      await tester.pump(const Duration(seconds: 4));
      await _tapHabit(tester, '習慣2'); // 全完成 → 一般模式走交叉淡入
      await tester.pump(const Duration(milliseconds: 80));

      // 對照組：此刻確實有兩張半透明立繪。
      final mid = _poseOpacities(tester);
      expect(
        mid.where((o) => o > 0.05 && o < 0.95),
        isNotEmpty,
        reason: '一般模式此刻應該正在交叉淡入（實際：$mid）',
      );

      reduce.value = true;
      await tester.pump();

      _expectNoGhostPose(tester);
      expect(_persona(tester).poseTransition, MascotPoseTransition.cut);
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 40));
        _expectNoGhostPose(tester);
      }
      expect(home.allDone0, isTrue, reason: '資料不受影響');

      reduce.dispose();
      await _tearDownHome(tester);
    });
  });

  // ── 動態 Reduce Motion：卡片圓圈與進度光暈 ────────────────────

  group('動態 Reduce Motion 的卡片與光暈', () {
    for (final feature in ['disableAnimations', 'accessibleNavigation']) {
      testWidgets('$feature 打開時，正在跑的圓圈回彈當場停住', (tester) async {
        _seed(3);
        await _pumpHomeOnPlatform(tester);

        await _tapHabit(tester, '習慣1');
        await tester.pump(const Duration(milliseconds: 80));
        expect(
          _circleScale(tester),
          isNot(closeTo(1.0, 1e-3)),
          reason: '對照組：一般模式此刻圓圈確實在縮放',
        );

        tester.platformDispatcher.accessibilityFeaturesTestValue =
            feature == 'disableAnimations'
            ? const FakeAccessibilityFeatures(disableAnimations: true)
            : const FakeAccessibilityFeatures(accessibleNavigation: true);
        addTearDown(
          tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
        );
        await tester.pump();

        expect(_circleScale(tester), closeTo(1.0, 1e-6), reason: '當場回到原尺寸');
        for (var i = 0; i < 8; i++) {
          await tester.pump(const Duration(milliseconds: 40));
          expect(
            _circleScale(tester),
            closeTo(1.0, 1e-6),
            reason: '${(i + 1) * 40}ms 後仍不得有回彈',
          );
        }

        // 關掉偏好不得補播剛才被取消的那一次。
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue();
        await tester.pump();
        for (var i = 0; i < 6; i++) {
          await tester.pump(const Duration(milliseconds: 50));
          expect(_circleScale(tester), closeTo(1.0, 1e-6), reason: '不得補播');
        }

        await _tearDownHome(tester);
      });
    }

    testWidgets('一般模式的按壓回饋不回歸', (tester) async {
      _seed(3);
      await _pumpHomeOnPlatform(tester);

      await _tapHabit(tester, '習慣1');
      await tester.pump(const Duration(milliseconds: 80));
      expect(
        _circleScale(tester),
        isNot(closeTo(1.0, 1e-3)),
        reason: '一般模式仍要有按壓回彈',
      );
      await tester.pump(const Duration(milliseconds: 400));
      expect(_circleScale(tester), closeTo(1.0, 1e-6), reason: '跑完要回到原尺寸');

      await _tearDownHome(tester);
    });

    for (final variant in [('allDone', 0), ('streak', 9)]) {
      testWidgets('${variant.$1} 達標的光暈：Reduce Motion 下不排幀', (tester) async {
        _seed(2, streak: variant.$2);
        final reduce = ValueNotifier<bool>(false);
        _setSurface(tester);
        await tester.pumpWidget(
          l10nTestApp(
            home: ValueListenableBuilder<bool>(
              valueListenable: reduce,
              builder: (context, v, _) => MediaQuery(
                data: MediaQuery.of(context).copyWith(disableAnimations: v),
                child: const HomePage(),
              ),
            ),
          ),
        );
        await tester.pump();
        final home = tester.state(find.byType(HomePage)) as dynamic;
        await home.loadHabits();
        await tester.pump();

        await _tapHabit(tester, '習慣1');
        await tester.pump(const Duration(seconds: 4));
        await _tapHabit(tester, '習慣2'); // 達標
        await tester.pump(const Duration(milliseconds: 200));

        final glow = _glow(tester)! as AnimationController;
        expect(glow.isAnimating, isTrue, reason: '對照組：一般模式達標後光暈確實在跑');

        reduce.value = true;
        await tester.pump();
        expect(glow.isAnimating, isFalse, reason: '不得只是藏起來，controller 要真的停');
        expect(glow.value, 0.0);
        for (var i = 0; i < 8; i++) {
          await tester.pump(const Duration(milliseconds: 60));
          expect(glow.value, 0.0, reason: '${(i + 1) * 60}ms 後仍要維持零');
          expect(glow.isAnimating, isFalse);
        }

        // 關掉偏好、仍然達標 → 一般模式的光暈可以接回來。
        reduce.value = false;
        await tester.pump();
        expect(_glow(tester)!.value, isNotNull);
        expect(
          (_glow(tester)! as AnimationController).isAnimating,
          isTrue,
          reason: '偏好關掉後，仍達標就該恢復',
        );

        reduce.dispose();
        await _tearDownHome(tester);
      });
    }

    testWidgets('一開始就是 Reduce Motion：達標也不啟動光暈', (tester) async {
      _seed(2);
      await _pumpHome(tester, reduceMotion: true);

      await _tapHabit(tester, '習慣1');
      await tester.pump(const Duration(seconds: 4));
      await _tapHabit(tester, '習慣2'); // 達標
      await tester.pump(const Duration(milliseconds: 200));

      final glow = _glow(tester)! as AnimationController;
      expect(glow.isAnimating, isFalse, reason: '靜態開啟時不得 repeat');
      expect(glow.value, 0.0);

      await _tearDownHome(tester);
    });

    testWidgets('未達標的光暈行為不回歸', (tester) async {
      _seed(3);
      await _pumpHome(tester);

      await _tapHabit(tester, '習慣1'); // 1/3，未達標
      await tester.pump(const Duration(milliseconds: 400));

      final glow = _glow(tester)! as AnimationController;
      expect(glow.isAnimating, isFalse, reason: '未達標本來就不該亮');
      expect(glow.value, 0.0);

      await _tearDownHome(tester);
    });
  });

  // ── 語意機會：被拒之後仍有合法重試入口 ────────────────────────

  group('語意機會的重試', () {
    testWidgets('撤銷擋掉領頭的語意後，後來跨過門檻的成員補送一次 halfDone', (tester) async {
      // 5 件、其中 1 件已完成：再完成 2 件就會跨過一半。
      SharedPreferences.setMockInitialValues({
        PrefsKeys.lastOpenDate: _todayString(),
        PrefsKeys.habits: jsonEncode([
          _habit('既有完成', done: true),
          for (var i = 1; i <= 4; i++) _habit('習慣$i'),
        ]),
      });
      final home = await _pumpHome(tester, height: 1500);
      log.clear();

      await _tapHabit(tester, '習慣1'); // t=0：2/5
      await tester.pump(const Duration(milliseconds: 350));
      await _tapHabit(tester, '既有完成'); // 撤銷 → undone 取得 claim
      await tester.pump();
      expect(
        MascotPersona.current.value.assetPath,
        MascotEmotion.sad.assetPath,
        reason: '撤銷要當場拿到擁有權',
      );
      home.debugClearSemanticEvents();

      // t=470：領頭的語意機會撞上撤銷，被優先度擋下。
      await tester.pump(const Duration(milliseconds: 130));
      expect(home.debugSemanticEvents, isEmpty, reason: '被撤銷擋下的那一次什麼都沒發生');

      // t=500／550：兩件新的完成加入同一條弧線並跨過門檻。
      await tester.pump(const Duration(milliseconds: 30));
      await _tapHabit(tester, '習慣2');
      expect(home.debugCompletionArcActive, isTrue, reason: '仍在合併視窗內');
      await tester.pump(const Duration(milliseconds: 50));
      await _tapHabit(tester, '習慣3');

      await tester.pump(const Duration(seconds: 4));

      expect(home.dailyDoneCount, 3, reason: '資料為 3/5');
      expect((home.habits as List)[0]['done'], isFalse);
      expect(
        (home.debugSemanticEvents as List)
            .where((e) => e == MascotContext.halfDone)
            .length,
        1,
        reason: '被拒的語意必須由後續有效成員補送，而且恰好一次',
      );
      expect(
        home.debugBaselineMascotContext,
        MascotContext.halfDone,
        reason: '3/5 已經過半',
      );
      expect(
        MascotPersona.current.value.assetPath,
        isNot(MascotEmotion.sad.assetPath),
        reason: '撤銷的狀態不得殘留',
      );
      expect(
        home.debugSpeechOwnerSource,
        isNot(HomeSpeechSource.undo),
        reason: '不得殘留撤銷的台詞擁有權',
      );

      await _tearDownHome(tester);
    });
  });

  // ── 排程身分：被撤銷的成員不得把 timer 借給別人 ────────────────

  group('里程碑的排程身分', () {
    testWidgets('撤銷 B 後 C 再跨門檻：只由 C 自己的 timer 在 C 衝擊點之後交付', (tester) async {
      _seed(4);
      final home = await _pumpHome(tester);

      await _tapHabit(tester, '習慣1'); // A@0：1/4
      await tester.pump(CompletionPresentationController.kSpeakDelay);
      expect(
        home.debugSemanticEvents,
        contains(MascotContext.completedOne),
        reason: 'A 的一般語意先成功',
      );
      home.debugClearSemanticEvents();

      await tester.pump(const Duration(milliseconds: 30)); // t=500
      await _tapHabit(tester, '習慣2'); // B 跨 half（2/4）
      await tester.pump(const Duration(milliseconds: 20)); // t=520
      await _tapHabit(tester, '習慣2'); // 撤銷 B
      log.clear();

      await tester.pump(const Duration(milliseconds: 160)); // t=680
      await _tapHabit(tester, '習慣3'); // C 再次跨 half，同一條弧線
      expect(home.debugCompletionArcActive, isTrue);

      // B 原本的機會在 t=970；C 的衝擊點在 t=980。
      await tester.pump(const Duration(milliseconds: 295)); // t=975
      expect(
        home.debugSemanticEvents,
        isNot(contains(MascotContext.halfDone)),
        reason: 'B 已被撤銷，它的 timer 不得改掛到 C 身上提前交付',
      );
      expect(log.cues, isNot(contains(SfxCue.success)), reason: 'C 自己的衝擊點都還沒到');

      await tester.pump(const Duration(seconds: 3));
      expect(
        (home.debugSemanticEvents as List)
            .where((e) => e == MascotContext.halfDone)
            .length,
        1,
        reason: '里程碑只能由 C 自己的 timer 交付一次',
      );
      // C 自己的回饋與資料完整保留。
      expect(log.cues, contains(SfxCue.success));
      expect(log.haptics, contains(HapticLevel.light));
      expect(home.dailyDoneCount, 2);
      expect((home.habits as List)[1]['done'], isFalse);
      expect((home.habits as List)[2]['done'], isTrue);
      final prefs = await SharedPreferences.getInstance();
      final history = prefs.getString(PrefsKeys.habitDoneDay(_todayString()));
      expect(history, contains('id_習慣3'));
      expect(history, isNot(contains('id_習慣2')));

      await _tearDownHome(tester);
    });

    testWidgets('B 沒被撤銷時由 B 交付，C 不重複', (tester) async {
      _seed(4);
      final home = await _pumpHome(tester);

      await _tapHabit(tester, '習慣1');
      await tester.pump(CompletionPresentationController.kSpeakDelay);
      home.debugClearSemanticEvents();

      await tester.pump(const Duration(milliseconds: 30));
      await _tapHabit(tester, '習慣2'); // B 跨 half
      await tester.pump(const Duration(milliseconds: 180));
      await _tapHabit(tester, '習慣3'); // C 也在同一條弧線
      await tester.pump(const Duration(seconds: 4));

      expect(
        (home.debugSemanticEvents as List)
            .where((e) => e == MascotContext.halfDone)
            .length,
        1,
        reason: '兩個半程成員只補一次',
      );

      await _tearDownHome(tester);
    });

    testWidgets('撤銷 B 且沒有後續半程成員：弧線降回一般完成', (tester) async {
      _seed(4);
      final home = await _pumpHome(tester);

      await _tapHabit(tester, '習慣1');
      await tester.pump(CompletionPresentationController.kSpeakDelay);
      home.debugClearSemanticEvents();

      await tester.pump(const Duration(milliseconds: 30));
      await _tapHabit(tester, '習慣2'); // B 跨 half
      await tester.pump(const Duration(milliseconds: 20));
      await _tapHabit(tester, '習慣2'); // 撤銷 B
      await tester.pump(const Duration(seconds: 4));

      expect(
        home.debugSemanticEvents,
        isNot(contains(MascotContext.halfDone)),
        reason: '半程成員沒了就不該再補里程碑',
      );

      await _tearDownHome(tester);
    });
  });

  // ── 開場問候的來源不得被打卡的換姿勢洗掉 ──────────────────────

  group('開場問候的 provenance', () {
    testWidgets('非首件完成沒有自己的台詞時，整段演出都不得清掉還在講的問候', (tester) async {
      _seed(5);
      final home = await _pumpHome(tester);

      // 先完成一件，讓下一件不會有「今天第一件。」那句自有台詞。
      await _tapHabit(tester, '習慣1');
      await tester.pump(const Duration(seconds: 4));

      // 真正的開場問候：origin 明確是 opening。
      MascotPersona.setForContext(
        MascotEmotion.neutralFront.assetPath,
        MascotContext.openApp,
        speech: '醒了醒了。',
        force: true,
        origin: MascotStateOrigin.opening,
      );
      expect(MascotPersona.speechOrigin, MascotStateOrigin.opening);
      log.clear();

      await _tapHabit(tester, '習慣2'); // 2/5，仍是普通完成、沒有自有台詞

      // 300ms：衝擊點換了姿勢，但那句問候還在。
      await tester.pump(CompletionPresentationController.kImpactDelay);
      expect(
        MascotPersona.current.value.speech,
        '醒了醒了。',
        reason: '衝擊點只換姿勢，不該把還在講的問候收掉',
      );
      expect(
        MascotPersona.speechOrigin,
        MascotStateOrigin.opening,
        reason: '換姿勢取得的是狀態擁有權，不是那句話的來源',
      );
      expect(log.cues, contains(SfxCue.success), reason: '成功回饋照發');
      expect(log.haptics, contains(HapticLevel.light));

      // 470ms：語意拍沒有自己的文字，仍然不得提前清掉問候。
      await tester.pump(
        CompletionPresentationController.kSpeakDelay -
            CompletionPresentationController.kImpactDelay,
      );
      expect(
        MascotPersona.current.value.speech,
        '醒了醒了。',
        reason: '沒有自己的台詞就不該把別人的收掉',
      );
      expect(
        home.debugSemanticEvents,
        contains(MascotContext.completedOne),
        reason: '語意本身仍然成立',
      );
      expect(
        MascotPersona.current.value.assetPath,
        MascotEmotion.expect.assetPath,
        reason: '姿勢走進度 baseline（2/5）',
      );
      expect(
        home.debugSpeechOwnerSource,
        isNot(HomeSpeechSource.completion),
        reason: '沿用來的問候不得被登記成打卡的台詞',
      );

      // 收尾拍也不收它：問候要活到自己的十秒回神。
      await tester.pump(
        CompletionPresentationController.kQuietDelay +
            const Duration(milliseconds: 200),
      );
      expect(
        MascotPersona.current.value.speech,
        '醒了醒了。',
        reason: '打卡的收尾不該替問候決定壽命',
      );

      await tester.pump(const Duration(seconds: 8)); // 問候自己的回神
      expect(
        MascotPersona.current.value.speech,
        isNull,
        reason: '問候由自己原本的顯示生命週期結束',
      );

      await _tearDownHome(tester);
    });

    testWidgets('衝擊點與語意拍之間出現更新的撤銷：保留較新的狀態', (tester) async {
      _seed(5);
      final home = await _pumpHome(tester);

      await _tapHabit(tester, '習慣1');
      await tester.pump(const Duration(seconds: 4));
      MascotPersona.setForContext(
        MascotEmotion.neutralFront.assetPath,
        MascotContext.openApp,
        speech: '醒了醒了。',
        force: true,
        origin: MascotStateOrigin.opening,
      );

      await _tapHabit(tester, '習慣2');
      await tester.pump(CompletionPresentationController.kImpactDelay);
      expect(MascotPersona.current.value.speech, '醒了醒了。');

      // 衝擊點之後、語意拍之前撤銷另一件。
      await _tapHabit(tester, '習慣1');
      await tester.pump();
      final undoSpeech = MascotPersona.current.value.speech;
      final undoClaim = MascotPersona.claim;
      expect(
        MascotPersona.current.value.assetPath,
        MascotEmotion.sad.assetPath,
      );

      await tester.pump(const Duration(milliseconds: 200)); // 跨過語意拍
      expect(MascotPersona.claim, undoClaim, reason: '較新的撤銷不得被打卡的語意覆寫');
      expect(MascotPersona.current.value.speech, undoSpeech);
      expect(home.dailyDoneCount, 1);

      await _tearDownHome(tester);
    });

    testWidgets('衝擊點與語意拍之間出現外部高優先狀態：完全不碰', (tester) async {
      _seed(5);
      await _pumpHome(tester);

      await _tapHabit(tester, '習慣1');
      await tester.pump(const Duration(seconds: 4));
      MascotPersona.setForContext(
        MascotEmotion.neutralFront.assetPath,
        MascotContext.openApp,
        speech: '醒了醒了。',
        force: true,
        origin: MascotStateOrigin.opening,
      );

      await _tapHabit(tester, '習慣2');
      await tester.pump(CompletionPresentationController.kImpactDelay);

      MascotPersona.interact(MascotContext.overhydration);
      final waterClaim = MascotPersona.claim;
      final waterSpeech = MascotPersona.current.value.speech;

      await tester.pump(const Duration(seconds: 4)); // 跨過語意拍與收尾
      expect(MascotPersona.claim, waterClaim);
      expect(MascotPersona.current.value.speech, waterSpeech);

      await _tearDownHome(tester);
    });
  });

  // ── 每週卡的按壓也要服從 Reduce Motion ──────────────────────

  group('每週卡的 Reduce Motion', () {
    /// 每週卡的「＋」；它是累加鈕，不是整張卡。
    Finder weeklyPlus() => find.descendant(
      of: find.byType(HabitCard).last,
      matching: find.byIcon(Icons.add_rounded),
    );

    for (final feature in ['disableAnimations', 'accessibleNavigation']) {
      testWidgets('mount 時就是 $feature：按「＋」全程沒有縮放', (tester) async {
        tester.platformDispatcher.accessibilityFeaturesTestValue =
            feature == 'disableAnimations'
            ? const FakeAccessibilityFeatures(disableAnimations: true)
            : const FakeAccessibilityFeatures(accessibleNavigation: true);
        addTearDown(
          tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
        );

        _seed(2, withWeekly: true);
        final home = await _pumpHomeOnPlatform(tester, height: 1500);
        log.clear();

        await tester.tap(weeklyPlus());
        await tester.pump();

        // 一般模式在 80ms 前後正壓到最小；這裡整段都必須是原尺寸。
        var elapsed = 0;
        expect(_circleScale(tester, card: 2), closeTo(1.0, 1e-6));
        for (final step in [20, 20, 40, 80, 160]) {
          await tester.pump(Duration(milliseconds: step));
          elapsed += step;
          expect(
            _circleScale(tester, card: 2),
            closeTo(1.0, 1e-6),
            reason: '$elapsed ms 時每週卡的「＋」圓圈不得縮放',
          );
        }

        // 資料、儲存與回饋照常。
        final weekly = (home.habits as List).last as Map<String, dynamic>;
        expect((weekly['weeklyDates'] as List).length, 1, reason: '計數必須真的加上去');
        expect(log.cues, contains(SfxCue.tap), reason: '回饋照發');
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString(PrefsKeys.habits), contains('每週習慣'));

        await _tearDownHome(tester);
      });
    }

    testWidgets('按壓途中打開偏好：當場停住並歸零，關掉也不補播', (tester) async {
      _seed(2, withWeekly: true);
      await _pumpHomeOnPlatform(tester, height: 1500);

      await tester.tap(weeklyPlus());
      await tester.pump(); // 這一幀才處理 onTap
      // 50ms 落在按下去的壓縮段；80ms 剛好是 0.92→1.06 的中點會經過 1.0，
      // 對照組挑那裡就沒有鑑別力了。
      await tester.pump(const Duration(milliseconds: 50));
      expect(
        _circleScale(tester, card: 2),
        lessThan(0.99),
        reason: '對照組：一般模式此刻確實壓下去了',
      );

      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      await tester.pump();

      expect(_circleScale(tester, card: 2), closeTo(1.0, 1e-6));
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 40));
        expect(_circleScale(tester, card: 2), closeTo(1.0, 1e-6));
      }

      // 關掉偏好不得補播被抑制的那一次。
      tester.platformDispatcher.clearAccessibilityFeaturesTestValue();
      await tester.pump();
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 50));
        expect(_circleScale(tester, card: 2), closeTo(1.0, 1e-6));
      }

      // 下一次一般模式的點擊才重新播放。
      await tester.tap(weeklyPlus());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(
        _circleScale(tester, card: 2),
        lessThan(0.99),
        reason: '偏好關掉後，新的一次點擊仍要有按壓回饋',
      );

      await _tearDownHome(tester);
    });
  });

  // ── 門檻事件的因果與世代 ────────────────────────────────────
  //
  // 「跨過一半」是一次有來源的事件，不是弧線的屬性。誰跨的、那一件演到
  // 衝擊點了沒、這次交付屬於哪一次跨越、撤銷有沒有把它否定掉——四件事
  // 都要答得出來。

  group('門檻事件', () {
    testWidgets('還活著的 ordinary 成員不得借用尚未 impact 的跨越', (tester) async {
      _seed(6);
      final home = await _pumpHome(tester, height: 1500);

      await _tapHabit(tester, '習慣1'); // A@0，1/6
      await tester.pump(CompletionPresentationController.kSpeakDelay); // t=470
      expect(home.debugSemanticEvents, contains(MascotContext.completedOne));
      home.debugClearSemanticEvents();

      await _tapHabit(tester, '習慣2'); // B@470，2/6，仍是一般完成
      await tester.pump(const Duration(milliseconds: 180)); // t=650
      await _tapHabit(tester, '習慣3'); // C@650，3/6，真正跨過門檻

      // B 的衝擊點在 t=770；先讓它過去，之後的回饋才只會來自 C。
      await tester.pump(const Duration(milliseconds: 130)); // t=780
      log.clear();

      // B 的語意機會在 t=940，C 的衝擊點在 t=950。
      await tester.pump(const Duration(milliseconds: 165)); // t=945
      expect(
        home.debugSemanticEvents,
        isNot(contains(MascotContext.halfDone)),
        reason: 'C 還沒演到自己的衝擊點，B 的機會不得先把 half 講出來',
      );
      expect(
        MascotPersona.current.value.bubble,
        isNot(EmotionBubble.note),
        reason: '不得有 half 的泡泡',
      );
      expect(log.voices, isEmpty, reason: '不得有 half 的語音');
      expect(log.cues, isEmpty, reason: 'C 的衝擊點回饋都還沒發生');

      // C 的衝擊點先到，之後才輪到它自己的語意機會。
      await tester.pump(const Duration(milliseconds: 20)); // t=965
      expect(log.cues, contains(SfxCue.success), reason: 'C 的成功回饋先發生');
      expect(log.haptics, contains(HapticLevel.light));
      expect(
        home.debugSemanticEvents,
        isNot(contains(MascotContext.halfDone)),
        reason: '衝擊點那一拍還不是語意拍',
      );

      await tester.pump(const Duration(seconds: 3));
      expect(
        (home.debugSemanticEvents as List)
            .where((e) => e == MascotContext.halfDone)
            .length,
        1,
        reason: '門檻語意只能由與這次跨越有因果關係的機會交付一次',
      );
      expect(home.dailyDoneCount, 3);

      await _tearDownHome(tester);
    });

    testWidgets('保留合法整合：門檻成員已 impact 時，領頭那一拍直接講 half', (tester) async {
      _seed(4);
      final home = await _pumpHome(tester);

      await _tapHabit(tester, '習慣1'); // A@0，1/4
      await tester.pump(const Duration(milliseconds: 100));
      await _tapHabit(tester, '習慣2'); // B@100，2/4 跨過門檻，衝擊點 t=400

      await tester.pump(const Duration(milliseconds: 370)); // t=470：領頭的機會
      expect(
        (home.debugSemanticEvents as List)
            .where((e) => e == MascotContext.halfDone)
            .length,
        1,
        reason: 'B 已經演到衝擊點，領頭那一拍可以直接整合成一次 half',
      );
      expect(
        home.debugSemanticEvents,
        isNot(contains(MascotContext.completedOne)),
        reason: '不該先講一次一般完成再補一次',
      );

      await _tearDownHome(tester);
    });

    testWidgets('half 交付後撤銷跌回門檻以下，重新跨越要再講一次', (tester) async {
      _seed(4);
      final home = await _pumpHome(tester);

      await _tapHabit(tester, '習慣1'); // A@0
      await tester.pump(const Duration(milliseconds: 100));
      await _tapHabit(tester, '習慣2'); // B@100 跨過門檻
      await tester.pump(const Duration(milliseconds: 370)); // t=470
      expect(
        (home.debugSemanticEvents as List)
            .where((e) => e == MascotContext.halfDone)
            .length,
        1,
      );
      expect(MascotPersona.current.value.bubble, EmotionBubble.note);

      // 使用者看得見地撤銷了唯一那個跨越——進度跌回一半以下。
      await tester.pump(const Duration(milliseconds: 10)); // t=480
      await _tapHabit(tester, '習慣2');
      expect(
        MascotPersona.current.value.assetPath,
        MascotEmotion.sad.assetPath,
      );
      expect(home.dailyDoneCount, 1);

      // 在同一個合併視窗內再次跨過門檻：那是新的一次，要有自己的一次語意。
      await tester.pump(const Duration(milliseconds: 20)); // t=500
      log.clear();
      // 語音的 18 秒冷卻走真實時鐘，測試裡跨不過去。它跟門檻世代是正交的
      // 規則——重置之後才看得出「第二次 episode 走的是完整的語意路徑」，
      // 而不是繞過冷卻。
      MascotPersona.debugResetVoiceCooldowns();
      await _tapHabit(tester, '習慣3');
      await tester.pump(const Duration(seconds: 3));

      expect(home.dailyDoneCount, 2);
      expect((home.habits as List)[1]['done'], isFalse);
      expect((home.habits as List)[2]['done'], isTrue);
      expect(
        (home.debugSemanticEvents as List)
            .where((e) => e == MascotContext.halfDone)
            .length,
        2,
        reason: '撤銷讓第一次跨越失效；重新跨過去是新的一次，可以再講一次',
      );
      // log 在撤銷之後才 clear，所以這裡的泡泡與語音都是第二次跨越冒出來的。
      expect(log.bubbles, contains(EmotionBubble.note), reason: '第二次要有新的泡泡');
      expect(log.voices, contains(SfxCue.tumiConfirm), reason: '第二次要有語音');

      await _tearDownHome(tester);
    });

    testWidgets('撤銷不屬於這條弧線的舊習慣也會讓門檻失效', (tester) async {
      // 一件早就完成的舊習慣 + 3 件新的：完成 1 件就是 2/4，剛好過半。
      SharedPreferences.setMockInitialValues({
        PrefsKeys.lastOpenDate: _todayString(),
        PrefsKeys.habits: jsonEncode([
          _habit('既有完成', done: true),
          for (var i = 1; i <= 3; i++) _habit('習慣$i'),
        ]),
      });
      final home = await _pumpHome(tester);

      await _tapHabit(tester, '習慣1'); // 2/4，跨過門檻
      await tester.pump(CompletionPresentationController.kSpeakDelay);
      expect(
        (home.debugSemanticEvents as List)
            .where((e) => e == MascotContext.halfDone)
            .length,
        1,
      );
      home.debugClearSemanticEvents();

      // 撤銷一件**根本不屬於這條弧線**的舊習慣：進度掉回 1/4。
      await tester.pump(const Duration(milliseconds: 30));
      await _tapHabit(tester, '既有完成');
      expect(home.dailyDoneCount, 1);

      // 再次跨過門檻 → 新的一次，要再講一次。
      await tester.pump(const Duration(milliseconds: 100));
      await _tapHabit(tester, '習慣2'); // 2/4
      await tester.pump(const Duration(seconds: 4));

      expect(home.dailyDoneCount, 2);
      expect(
        (home.debugSemanticEvents as List)
            .where((e) => e == MascotContext.halfDone)
            .length,
        1,
        reason: '撤銷別的習慣一樣讓門檻失效；重新跨過去要建立新的一次',
      );

      await _tearDownHome(tester);
    });

    testWidgets('撤銷後沒有重新跨越：不得重播一般完成或門檻語意', (tester) async {
      _seed(4);
      final home = await _pumpHome(tester);

      await _tapHabit(tester, '習慣1'); // A@0
      await tester.pump(const Duration(milliseconds: 100));
      await _tapHabit(tester, '習慣2'); // B@100 跨過門檻
      await tester.pump(const Duration(milliseconds: 370)); // t=470，第一次 half
      home.debugClearSemanticEvents();

      await tester.pump(const Duration(milliseconds: 10));
      await _tapHabit(tester, '習慣2'); // 撤銷，跌回 1/4
      await tester.pump(const Duration(seconds: 4));

      // 撤銷本身是一個語意事件（sad + 撤銷台詞），那是應該的；
      // 不該出現的是「完成」那一側的任何重播。
      expect(
        home.debugSemanticEvents,
        isNot(
          anyOf(
            contains(MascotContext.halfDone),
            contains(MascotContext.completedOne),
          ),
        ),
        reason: '沒有重新跨越就沒有新的完成語意，一般完成也不該重播',
      );
      expect(home.dailyDoneCount, 1);

      await _tearDownHome(tester);
    });
  });

  // ── 台詞的租約獨立於狀態 ────────────────────────────────────

  group('台詞租約', () {
    /// 讓下一件完成是「沒有自有台詞」的普通完成，並把開場問候放上畫面。
    Future<dynamic> openingThenSpeechlessCompletion(WidgetTester tester) async {
      final home = await _pumpHome(tester, height: 1500);
      await _tapHabit(tester, '習慣1');
      await tester.pump(const Duration(seconds: 4));
      MascotPersona.setForContext(
        MascotEmotion.neutralFront.assetPath,
        MascotContext.openApp,
        speech: '醒了醒了。',
        force: true,
        origin: MascotStateOrigin.opening,
      );
      return home;
    }

    testWidgets('沿用開場問候不重排它原本的十秒期限', (tester) async {
      _seed(5);
      await openingThenSpeechlessCompletion(tester);
      final lease = MascotPersona.speechLease;
      expect(lease.deadline, isNotNull);

      // 快到期時才完成下一件：9.7s 的衝擊點與 9.87s 的語意拍都會沿用它。
      await tester.pump(const Duration(milliseconds: 9400));
      expect(MascotPersona.current.value.speech, '醒了醒了。');

      await _tapHabit(tester, '習慣2');
      await tester.pump(CompletionPresentationController.kImpactDelay);
      expect(MascotPersona.current.value.speech, '醒了醒了。');
      expect(MascotPersona.speechOrigin, MascotStateOrigin.opening);
      expect(
        MascotPersona.speechLease,
        lease,
        reason: '沿用時整份租約原封不動：來源與絕對期限都不能換',
      );
      expect(
        MascotPersona.origin,
        MascotStateOrigin.home,
        reason: '但狀態確實換成首頁的了',
      );

      await tester.pump(
        CompletionPresentationController.kSpeakDelay -
            CompletionPresentationController.kImpactDelay,
      );
      expect(MascotPersona.current.value.speech, '醒了醒了。');
      expect(MascotPersona.speechLease, lease);

      // 原本的十秒到了就該消失——不是「首頁寫入之後再十秒」。
      await tester.pump(const Duration(milliseconds: 350));
      expect(
        MascotPersona.current.value.speech,
        isNull,
        reason: '沿用的拍子不得把問候變成新的十秒',
      );

      await _tearDownHome(tester);
    });

    for (final scenario in ['dispose', 'tab switch', 'reload', 'logical-day']) {
      testWidgets('$scenario 只收 Home 的狀態，保留還在講的開場問候', (tester) async {
        _seed(5);
        final visible = ValueNotifier<bool>(true);
        _setSurface(tester, height: 1500);
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

        await _tapHabit(tester, '習慣1');
        await tester.pump(const Duration(seconds: 4));
        MascotPersona.setForContext(
          MascotEmotion.neutralFront.assetPath,
          MascotContext.openApp,
          speech: '醒了醒了。',
          force: true,
          origin: MascotStateOrigin.opening,
        );
        final lease = MascotPersona.speechLease;

        // 非首件完成走到 470ms：Home 擁有姿勢、泡泡與狀態收據，
        // 台詞仍然是開場問候的。
        await _tapHabit(tester, '習慣2');
        await tester.pump(CompletionPresentationController.kSpeakDelay);
        expect(MascotPersona.origin, MascotStateOrigin.home);
        expect(MascotPersona.speechOrigin, MascotStateOrigin.opening);
        expect(MascotPersona.current.value.speech, '醒了醒了。');
        expect(MascotPersona.current.value.bubble, EmotionBubble.note);

        switch (scenario) {
          case 'dispose':
            await tester.pumpWidget(const SizedBox());
            await tester.pump();
          case 'tab switch':
            visible.value = false;
            await tester.pump();
            await tester.pump();
          case 'reload':
            await home.loadHabits();
            await tester.pump();
          case 'logical-day':
            await home.loadHabits();
            await tester.pump();
        }

        expect(
          MascotPersona.origin,
          MascotStateOrigin.opening,
          reason: '$scenario 之後 Home 的狀態擁有權要收掉',
        );
        expect(
          MascotPersona.current.value.bubble,
          isNull,
          reason: 'Home 的泡泡要收掉',
        );
        expect(
          MascotPersona.current.value.speech,
          '醒了醒了。',
          reason: '$scenario 不得整份 reset：那句問候不是首頁的',
        );
        expect(MascotPersona.speechLease, lease, reason: '問候的租約（來源與期限）完全不變');

        // 問候到自己的期限才消失。
        await tester.pump(const Duration(seconds: 11));
        expect(MascotPersona.current.value.speech, isNull);

        visible.dispose();
        await _tearDownHome(tester);
      });
    }

    testWidgets('台詞也是 Home 的時候，cleanup 仍然要把它清掉', (tester) async {
      _seed(5);
      final home = await _pumpHome(tester);

      // 今天第一件會帶自己的台詞。
      await _tapHabit(tester, '習慣1');
      await tester.pump(CompletionPresentationController.kSpeakDelay);
      expect(MascotPersona.current.value.speech, '今天第一件。');
      expect(MascotPersona.speechOrigin, MascotStateOrigin.home);

      await home.loadHabits();
      await tester.pump();
      expect(
        MascotPersona.current.value.speech,
        isNull,
        reason: '台詞是首頁自己的，收拾時就要一起清掉',
      );
      expect(MascotPersona.origin, MascotStateOrigin.opening);

      await _tearDownHome(tester);
    });

    testWidgets('更新的外部狀態與台詞完全不被 Home 的 cleanup 觸碰', (tester) async {
      _seed(5);
      final home = await _pumpHome(tester);

      await _tapHabit(tester, '習慣1');
      await tester.pump(CompletionPresentationController.kSpeakDelay);

      MascotPersona.interact(MascotContext.overhydration);
      final waterClaim = MascotPersona.claim;
      final waterLease = MascotPersona.speechLease;
      final waterSpeech = MascotPersona.current.value.speech;
      final waterAsset = MascotPersona.current.value.assetPath;

      await home.loadHabits();
      await tester.pump();
      expect(MascotPersona.claim, waterClaim);
      expect(MascotPersona.speechLease, waterLease);
      expect(MascotPersona.current.value.speech, waterSpeech);
      expect(MascotPersona.current.value.assetPath, waterAsset);

      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      expect(MascotPersona.claim, waterClaim, reason: 'dispose 同樣完全 no-op');
      expect(MascotPersona.speechLease, waterLease);

      await tester.pump(const Duration(seconds: 12));
    });
  });

  // ── 台詞寫入意圖：矛盾組合無法表示 ───────────────────────────

  group('台詞寫入意圖', () {
    test('preserve 不換來源、不重排期限；generate 會建立呼叫端自己的租約', () {
      MascotPersona.resetToIdle();
      MascotPersona.debugResetVoiceCooldowns();

      // 先讓「開場問候」建立一份有期限的租約。
      MascotPersona.setForContext(
        MascotEmotion.neutralFront.assetPath,
        MascotContext.openApp,
        speech: '醒了醒了。',
        force: true,
        origin: MascotStateOrigin.opening,
      );
      final lease = MascotPersona.speechLease;
      expect(lease.origin, MascotStateOrigin.opening);
      expect(lease.deadline, isNotNull);

      // preserve：換姿勢與狀態擁有權，台詞那一份整組不動。
      MascotPersona.setForContext(
        MascotEmotion.expect.assetPath,
        MascotContext.completedOne,
        speechWrite: MascotSpeechWrite.preserve,
        silent: true,
        force: true,
        origin: MascotStateOrigin.home,
      );
      expect(MascotPersona.current.value.speech, '醒了醒了。');
      expect(MascotPersona.origin, MascotStateOrigin.home, reason: '狀態換人了');
      expect(MascotPersona.speechLease, lease, reason: '台詞的租約（來源與絕對期限）必須一模一樣');

      // generate：會講話的情境自己抽一句，租約歸這次的呼叫端。
      MascotPersona.setForContext(
        MascotEmotion.sleep.assetPath,
        MascotContext.notStarted,
        speechWrite: MascotSpeechWrite.generate,
        force: true,
      );
      expect(MascotPersona.current.value.speech, isNotNull);
      expect(MascotPersona.speechLease, isNot(lease));
      expect(MascotPersona.speechOrigin, MascotStateOrigin.other);

      // generate 交給情境決定：不會講話的情境抽不出東西。
      MascotPersona.setForContext(
        MascotEmotion.expect.assetPath,
        MascotContext.completedOne,
        speechWrite: MascotSpeechWrite.generate,
        force: true,
      );
      expect(MascotPersona.current.value.speech, isNull);
    });

    test('preserve 不得同時帶文字：矛盾組合在入口就被擋下', () {
      MascotPersona.resetToIdle();
      // 「保留現有那句」＋「這是我的新台詞」是互相矛盾的意圖；
      // 舊的 nullable speech ＋ bool 組合表達得出來，這個型別表達不出來。
      expect(
        () => MascotPersona.setForContext(
          MascotEmotion.expect.assetPath,
          MascotContext.completedOne,
          speechWrite: MascotSpeechWrite.preserve,
          speech: '這句不該被接受',
          force: true,
        ),
        throwsA(isA<AssertionError>()),
      );
      // own 一定要帶話，否則同樣是矛盾。
      expect(
        () => MascotPersona.setForContext(
          MascotEmotion.expect.assetPath,
          MascotContext.completedOne,
          speechWrite: MascotSpeechWrite.own,
          force: true,
        ),
        throwsA(isA<AssertionError>()),
      );
    });

    test('preserve 不會讓會講話的情境憑空生出一句掛著舊來源的話', () {
      MascotPersona.resetToIdle();
      MascotPersona.setForContext(
        MascotEmotion.neutralFront.assetPath,
        MascotContext.openApp,
        speech: '醒了醒了。',
        force: true,
        origin: MascotStateOrigin.opening,
      );
      final lease = MascotPersona.speechLease;

      // notStarted 是「會講話」的情境；preserve 仍然只保留原本那一句。
      expect(MascotLines.speaksFor(MascotContext.notStarted), isTrue);
      MascotPersona.setForContext(
        MascotEmotion.sleep.assetPath,
        MascotContext.notStarted,
        speechWrite: MascotSpeechWrite.preserve,
        force: true,
        origin: MascotStateOrigin.home,
      );
      expect(
        MascotPersona.current.value.speech,
        '醒了醒了。',
        reason: '不得從台詞池補一句新的，卻掛著開場問候的來源',
      );
      expect(MascotPersona.speechLease, lease);
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
