// 待機呼吸：節奏與幅度隨情緒而異。
//
// 這組測試守的是「角色規則」而不是某幾個毫秒數：越睏越慢越深、越振奮越快越淺、
// 低落慢而淺。之後要調整手感時數值可以改，但下面幾條相對關係不該被改壞——
// 一旦全部情緒又變回同一組參數，待機就只剩一個機械循環。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:habit_app/utils/mascot.dart';
import 'package:habit_app/widgets/mascot_scene.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('情緒 ↔ 立繪路徑', () {
    test('認得所有情緒的 core 路徑', () {
      for (final e in MascotEmotion.values) {
        expect(
          MascotEmotion.fromAssetPath(e.assetPath),
          e,
          reason: e.assetKey,
        );
      }
    });

    test('pop_happy 不會被誤判成 happy', () {
      expect(
        MascotEmotion.fromAssetPath(MascotEmotion.popHappy.assetPath),
        MascotEmotion.popHappy,
      );
      expect(
        MascotEmotion.fromAssetPath(MascotEmotion.happy.assetPath),
        MascotEmotion.happy,
      );
    });

    test('穿造型（非 core 資料夾）一樣認得', () {
      expect(
        MascotEmotion.fromAssetPath('assets/mascot/sweater/tumi_sleep.png'),
        MascotEmotion.sleep,
      );
      expect(
        MascotEmotion.idleBreathForPath(
          'assets/mascot/sweater/tumi_sleep.png',
        ),
        MascotEmotion.sleep.idleBreath,
      );
    });

    test('閉眼差分與未知路徑退回基準呼吸，不會拋例外', () {
      for (final path in [
        'assets/mascot/core/tumi_neutral_front_blink.png',
        'assets/mascot/core/tumi_pet_bliss.png',
        '',
      ]) {
        expect(
          MascotEmotion.idleBreathForPath(path),
          MascotEmotion.fallbackIdleBreath,
          reason: path,
        );
      }
    });
  });

  group('角色規則：越睏越慢越深，越振奮越快越淺', () {
    MascotIdleBreath breathOf(MascotEmotion e) => e.idleBreath;

    test('睡著比雀躍慢，而且更深', () {
      final sleep = breathOf(MascotEmotion.sleep);
      final streak = breathOf(MascotEmotion.streak);
      expect(sleep.halfCycle, greaterThan(streak.halfCycle));
      expect(sleep.depth, greaterThan(streak.depth));
    });

    test('期待與開心比平靜基準快', () {
      final calm = breathOf(MascotEmotion.neutralFront);
      for (final e in [MascotEmotion.expect, MascotEmotion.happy]) {
        expect(breathOf(e).halfCycle, lessThan(calm.halfCycle), reason: e.name);
      }
    });

    test('低落是慢而淺——不能跟睡著混為一談', () {
      final sad = breathOf(MascotEmotion.sad);
      final calm = breathOf(MascotEmotion.neutralFront);
      final sleep = breathOf(MascotEmotion.sleep);
      // 比平靜慢
      expect(sad.halfCycle, greaterThan(calm.halfCycle));
      // 但比平靜還淺，而且遠比睡著淺：洩了氣，不是睡熟
      expect(sad.depth, lessThan(calm.depth));
      expect(sad.depth, lessThan(sleep.depth));
    });

    test('沒有任何情緒退化成零幅度或靜止', () {
      for (final e in MascotEmotion.values) {
        final b = breathOf(e);
        expect(b.depth, greaterThan(0), reason: e.name);
        expect(b.halfCycle.inMilliseconds, greaterThan(0), reason: e.name);
      }
    });

    test('不是所有情緒共用同一組參數', () {
      final distinct = MascotEmotion.values.map((e) => e.idleBreath).toSet();
      expect(distinct.length, greaterThan(1));
    });

    test('橫向擠壓由縱向幅度推導，不各寫一個數字', () {
      final b = MascotEmotion.sleep.idleBreath;
      expect(b.widthDepth, closeTo(b.depth * MascotIdleBreath.squashRatio, 1e-9));
      expect(b.widthDepth, lessThan(b.depth));
    });
  });

  group('畫面行為', () {
    // 呼吸是唯一「縱向拉長同時橫向擠壓」的變換，用這個特徵把它從其他
    // Transform（點擊小跳、摸頭傾靠、換圖沉降）裡認出來。
    double breathScaleY(WidgetTester tester) {
      for (final t in tester.widgetList<Transform>(find.byType(Transform))) {
        final sx = t.transform.storage[0];
        final sy = t.transform.storage[5];
        if (sy > 1.0 && sx < 1.0) return sy;
      }
      return 1.0;
    }

    // [key] 換新 = 換一個全新的 State（呼吸從 0 重新起算）。沿用同一個 State
    // 時 `repeat()` 是**從目前的值繼續**、不是從 0 重來，所以要比較「吸滿」
    // 就必須確保起點是 0。
    Future<void> pumpStage(
      WidgetTester tester,
      MascotEmotion emotion, {
      bool paused = false,
      Key? key,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: MascotStage(
                key: key,
                asset: emotion.assetPath,
                accent: Colors.orange,
                reactionTick: 0,
                onTap: () {},
                paused: paused,
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('吸滿時的縱向幅度就是該情緒的 depth', (tester) async {
      for (final e in [
        MascotEmotion.sleep,
        MascotEmotion.happy,
        MascotEmotion.neutralFront,
      ]) {
        // 每個情緒都用全新的 State，起點確定是 0。
        await pumpStage(tester, e, key: ValueKey(e));
        // repeat(reverse: true) 從 0 出發，推進一個 halfCycle 剛好吸滿。
        await tester.pump(e.idleBreath.halfCycle);
        expect(
          breathScaleY(tester),
          closeTo(1 + e.idleBreath.depth, 1e-6),
          reason: e.name,
        );
        // 收掉眨眼 timer，避免測試結束時還有 pending timer。
        await pumpStage(tester, e, key: ValueKey(e), paused: true);
      }
    });

    testWidgets('換情緒會換掉呼吸節奏，不是沿用上一個', (tester) async {
      // 這一條刻意**不換 key**：要驗的就是同一個 State 上換立繪時，
      // 節奏有沒有跟著換。
      await pumpStage(tester, MascotEmotion.sleep);
      await tester.pump(MascotEmotion.sleep.idleBreath.halfCycle);
      expect(
        breathScaleY(tester),
        closeTo(1 + MascotEmotion.sleep.idleBreath.depth, 1e-6),
      );
      // 再推一個 halfCycle 吐回 0，讓下一段從乾淨的起點開始。
      await tester.pump(MascotEmotion.sleep.idleBreath.halfCycle);
      expect(breathScaleY(tester), 1.0);

      // 換成雀躍：週期短很多。推進 streak 自己的 halfCycle 就該吸滿；
      // 若還沿用 sleep 的 2000ms，這時只會走到 43%，幅度也會是 sleep 的。
      await pumpStage(tester, MascotEmotion.streak);
      await tester.pump(MascotEmotion.streak.idleBreath.halfCycle);
      expect(
        breathScaleY(tester),
        closeTo(1 + MascotEmotion.streak.idleBreath.depth, 1e-6),
      );

      await pumpStage(tester, MascotEmotion.streak, paused: true);
    });

    testWidgets('Reduce Motion：呼吸完全靜止', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: MascotStage(
                asset: MascotEmotion.sleep.assetPath,
                accent: Colors.orange,
                reactionTick: 0,
                onTap: () {},
                reduceMotion: true,
              ),
            ),
          ),
        ),
      );
      await tester.pump(MascotEmotion.sleep.idleBreath.halfCycle);
      expect(breathScaleY(tester), 1.0);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: MascotStage(
                asset: MascotEmotion.sleep.assetPath,
                accent: Colors.orange,
                reactionTick: 0,
                onTap: () {},
                reduceMotion: true,
                paused: true,
              ),
            ),
          ),
        ),
      );
    });
  });

  // 閒置太久 → 兔咪睡著（Zzz）；碰它 → 揉眼剛醒 → 交棒回待機。
  // 兩個都是背景狀態不是事件：不出文字、不出聲、優先度最低。
  group('打瞌睡與甦醒', () {
    test('打瞌睡＝睡姿＋Zzz；剛醒＝wake、不冒符號', () {
      expect(
        MascotLines.emotionFor(MascotContext.dozeOff),
        MascotEmotion.sleep,
      );
      expect(
        EmotionBubble.forContext(MascotContext.dozeOff),
        EmotionBubble.zzz,
      );
      expect(MascotLines.emotionFor(MascotContext.wakeUp), MascotEmotion.wake);
      expect(
        EmotionBubble.forContext(MascotContext.wakeUp),
        isNull,
        reason: 'Zzz 已經在打瞌睡那一段講完了，醒來要安靜',
      );
    });

    test('兩者都不出文字', () {
      for (final ctx in [MascotContext.dozeOff, MascotContext.wakeUp]) {
        expect(MascotLines.speaksFor(ctx), isFalse, reason: ctx.name);
        expect(MascotLines.linesFor(ctx), isNotEmpty, reason: '池子仍要備著');
      }
    });

    test('睡著的呼吸比剛醒的慢而深', () {
      final asleep = MascotEmotion.sleep.idleBreath;
      final woken = MascotEmotion.wake.idleBreath;
      expect(asleep.halfCycle, greaterThan(woken.halfCycle));
      expect(asleep.depth, greaterThan(woken.depth));
    });
  });
}
