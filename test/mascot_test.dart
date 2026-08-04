import 'dart:io';
import 'package:characters/characters.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:habit_app/utils/mascot.dart';
import 'package:habit_app/utils/sfx_service.dart';

void main() {
  setUp(() {
    MascotPersona.voiceMuted = true;
    MascotPersona.debugResetVoiceCooldowns();
    MascotPersona.resetToOpening();
  });

  tearDown(() {
    MascotPersona.debugResetVoiceCooldowns();
    MascotPersona.resetToOpening();
    MascotPersona.voiceMuted = false;
  });

  // 冷啟動過去是唯一一條不排回神的路徑，兔咪會停在中性臉直到下一次互動；
  // 場景 20 秒後凍結時停的也是那張睜眼的臉。現在它跟其他事件走同一套。
  group('冷啟動之後要回到待機姿', () {
    test('問候到期後姿勢回到 idleBaseline，台詞照原本的租約留著', () {
      fakeAsync((async) {
        MascotPersona.idleBaseline = () =>
            MascotState(MascotEmotion.sleep.assetPath, null);
        addTearDown(() => MascotPersona.idleBaseline = null);

        MascotPersona.resetToOpening();
        expect(
          MascotPersona.current.value.assetPath,
          MascotEmotion.neutralFront.assetPath,
          reason: '問候當下用的是中性臉',
        );
        final greeting = MascotPersona.current.value.speech;
        expect(greeting, isNotNull);

        async.elapse(const Duration(seconds: 11));

        expect(
          MascotPersona.current.value.assetPath,
          MascotEmotion.sleep.assetPath,
          reason: '姿勢要回到依今天進度推導的待機姿，不是停在開 app 的中性臉',
        );
        expect(
          MascotPersona.current.value.speech,
          greeting,
          reason: '只回姿勢：台詞有自己的租約，冷啟動問候仍然沒有期限',
        );
        expect(MascotPersona.speechDeadline, isNull);
      });
    });

    test('沒有人註冊 idleBaseline 時回神是無害的：仍然停在中性臉', () {
      fakeAsync((async) {
        MascotPersona.idleBaseline = null;
        MascotPersona.resetToOpening();
        async.elapse(const Duration(seconds: 11));
        expect(
          MascotPersona.current.value.assetPath,
          MascotEmotion.neutralFront.assetPath,
        );
      });
    });
  });

  test('direct mascot interactions share a seven-second voice cooldown', () {
    final start = DateTime(2026, 7, 13, 12);
    MascotPersona.debugMarkVoicePlayedAt(MascotContext.tapReaction, start);

    expect(
      MascotPersona.debugVoiceAllowedAt(
        MascotContext.headPet,
        start.add(const Duration(seconds: 6, milliseconds: 999)),
      ),
      isFalse,
    );
    expect(
      MascotPersona.debugVoiceAllowedAt(
        MascotContext.energize,
        start.add(const Duration(seconds: 7)),
      ),
      isTrue,
    );
  });

  test('direct and routine voices use independent cooldowns', () {
    final start = DateTime(2026, 7, 13, 12);
    MascotPersona.debugMarkVoicePlayedAt(MascotContext.completedOne, start);

    expect(
      MascotPersona.debugVoiceAllowedAt(MascotContext.tapReaction, start),
      isTrue,
      reason: '剛打卡後仍應能立即回應使用者直接互動',
    );
    expect(
      MascotPersona.debugVoiceAllowedAt(
        MascotContext.halfDone,
        start.add(const Duration(seconds: 17, milliseconds: 999)),
      ),
      isFalse,
    );
    expect(
      MascotPersona.debugVoiceAllowedAt(
        MascotContext.halfDone,
        start.add(const Duration(seconds: 18)),
      ),
      isTrue,
    );

    MascotPersona.debugResetVoiceCooldowns();
    MascotPersona.debugMarkVoicePlayedAt(MascotContext.headPet, start);
    expect(
      MascotPersona.debugVoiceAllowedAt(MascotContext.completedOne, start),
      isTrue,
      reason: '摸兔咪也不應吃掉下一次打卡確認聲',
    );
  });

  test('important mascot events still bypass voice cooldowns', () {
    final start = DateTime(2026, 7, 13, 12);
    MascotPersona.debugMarkVoicePlayedAt(MascotContext.completedOne, start);

    expect(
      MascotPersona.debugVoiceAllowedAt(
        MascotContext.undone,
        start.add(const Duration(seconds: 1)),
      ),
      isTrue,
    );
  });

  test('simple taps use a 70 percent question and 30 percent confirm mix', () {
    final cues = [
      for (var bucket = 0; bucket < 10; bucket++)
        MascotPersona.debugTapVoiceCueForBucket(bucket),
    ];

    expect(cues.where((cue) => cue == SfxCue.tumiQuestion), hasLength(7));
    expect(cues.where((cue) => cue == SfxCue.tumiConfirm), hasLength(3));
    expect(cues.toSet(), {SfxCue.tumiQuestion, SfxCue.tumiConfirm});
  });

  test('repeated accepted bubble contexts advance the bubble tick', () {
    expect(
      MascotPersona.interact(MascotContext.completedOne, force: true),
      isTrue,
    );
    final first = MascotPersona.current.value;

    expect(
      MascotPersona.interact(MascotContext.completedOne, force: true),
      isTrue,
    );
    final second = MascotPersona.current.value;

    expect(first.bubble, EmotionBubble.note);
    expect(second.bubble, EmotionBubble.note);
    expect(second.bubbleTick, greaterThan(first.bubbleTick));
  });

  test('direct set defaults to no bubble instead of tap question bubble', () {
    expect(
      MascotPersona.set(MascotEmotion.happy.assetPath, 'hello', force: true),
      isTrue,
    );

    final state = MascotPersona.current.value;
    expect(state.bubble, isNull);
    expect(state.bubbleTick, 0);
  });

  test('direct set can opt into a contextual bubble', () {
    expect(
      MascotPersona.set(
        MascotEmotion.happy.assetPath,
        'hello',
        context: MascotContext.allDone,
        force: true,
      ),
      isTrue,
    );

    final state = MascotPersona.current.value;
    expect(state.bubble, EmotionBubble.star);
    expect(state.bubbleTick, greaterThan(0));
  });

  test('energize bursts into pop-happy with a star bubble', () {
    expect(MascotPersona.interact(MascotContext.energize, force: true), isTrue);

    final state = MascotPersona.current.value;
    expect(state.assetPath, MascotEmotion.popHappy.assetPath);
    expect(state.bubble, EmotionBubble.star);
    expect(state.speech, isNull, reason: '充電互動是高頻演出，靠符號與語音就好');
  });

  test(
    'dice outcomes use dedicated matching emotions instead of tap questions',
    () {
      final cases = <MascotContext, (MascotEmotion, EmotionBubble)>{
        MascotContext.diceMascotWin: (
          MascotEmotion.popHappy,
          EmotionBubble.star,
        ),
        MascotContext.diceMascotLoss: (
          MascotEmotion.expect,
          EmotionBubble.sweat,
        ),
        MascotContext.diceTie: (MascotEmotion.expect, EmotionBubble.note),
      };

      for (final MapEntry(key: context, value: expected) in cases.entries) {
        expect(MascotPersona.interact(context, force: true), isTrue);
        final state = MascotPersona.current.value;
        expect(state.assetPath, expected.$1.assetPath, reason: '$context');
        expect(state.bubble, expected.$2, reason: '$context');
        expect(state.bubble, isNot(EmotionBubble.question), reason: '$context');
      }
    },
  );

  test('high-frequency contexts stay silent (symbol only, no speech text)', () {
    for (final ctx in [
      MascotContext.completedOne,
      MascotContext.halfDone,
      MascotContext.tapReaction,
      MascotContext.headPet,
      MascotContext.energize,
    ]) {
      expect(MascotPersona.interact(ctx, force: true), isTrue);
      expect(
        MascotPersona.current.value.speech,
        isNull,
        reason: '$ctx 應只靠符號泡泡，不冒文字',
      );
      expect(MascotLines.speaksFor(ctx), isFalse, reason: '$ctx');
    }
  });

  test('key-beat contexts keep their speech text', () {
    for (final ctx in [
      MascotContext.allDone,
      MascotContext.streak,
      MascotContext.undone,
      MascotContext.night,
      MascotContext.notStarted,
      MascotContext.emptyHabits,
      MascotContext.overhydration,
    ]) {
      expect(MascotPersona.interact(ctx, force: true), isTrue);
      expect(
        MascotPersona.current.value.speech,
        isNotNull,
        reason: '$ctx 是關鍵時刻，應保留文字台詞',
      );
      expect(MascotLines.speaksFor(ctx), isTrue, reason: '$ctx');
    }
  });

  test('explicit speech is honored even on a silent context', () {
    // 首頁點兔咪 / 衣櫃 / 登入禮這類「明確帶文字」的時刻，不該被靜音規則吃掉。
    expect(
      MascotPersona.setForContext(
        MascotEmotion.smile.assetPath,
        MascotContext.completedOne,
        speech: '剛剛那一下，我有看到。',
        force: true,
      ),
      isTrue,
    );
    expect(MascotPersona.current.value.speech, '剛剛那一下，我有看到。');
  });

  test('all mascot contexts have an auditable non-empty line pool', () {
    for (final ctx in MascotContext.values) {
      final lines = MascotLines.linesFor(ctx);
      expect(lines, isNotEmpty, reason: '$ctx');
      expect(lines, isNot(contains('...')), reason: '$ctx 不應回退到 placeholder');
    }
  });

  test('shared dialogue pools avoid out-of-context presence statements', () {
    final lines = <String>[
      for (final ctx in MascotContext.values) ...MascotLines.linesFor(ctx),
      for (final ctx in MascotContext.values)
        ...MascotLines.homeTapLinesFor(ctx),
    ];

    expect(lines.where((line) => line.contains('我在這裡')), isEmpty);
    expect(lines.where((line) => line.contains('我還在')), isEmpty);
  });

  test(
    'an interaction settles into silent idle instead of another greeting',
    () {
      fakeAsync((async) {
        expect(
          MascotPersona.interact(MascotContext.allDone, force: true),
          isTrue,
        );
        expect(MascotPersona.current.value.speech, isNotNull);

        async.elapse(const Duration(seconds: 10));

        final state = MascotPersona.current.value;
        expect(state.assetPath, MascotEmotion.neutralFront.assetPath);
        expect(state.speech, isNull);
        expect(state.bubble, isNull);
      });
    },
  );

  // 「三種聲音」規則（docs/tumi_character_guide.md）：兔咪自己說話時
  // 永遠不自稱名字——不管是寫死的「兔咪」還是 {name} 佔位。名字只出現在
  // 系統描述牠的文案裡（那些走 MascotName.fill）。
  test('兔咪的台詞不自稱名字，也不寫死「兔咪」', () {
    for (final ctx in MascotContext.values) {
      for (final pools in [
        MascotLines.linesFor(ctx),
        MascotLines.homeTapLinesFor(ctx),
      ]) {
        for (final line in pools) {
          expect(
            line.contains('兔咪'),
            isFalse,
            reason: '$ctx 的「$line」寫死了「兔咪」，玩家改名後會對不上',
          );
          expect(
            line.contains('{name}'),
            isFalse,
            reason: '$ctx 的「$line」讓兔咪自稱名字，違反三種聲音規則',
          );
        }
      }
    }
  });

  // 事件總表是兔咪所有反應的追蹤點（docs/tumi_dialogue_catalog.md）。
  // 新增情境卻忘了進表，這條會失敗——規範靠人記會腐爛，靠測試才不會。
  test('每個 MascotContext 都在對話總表裡有一行', () {
    final doc = File('docs/tumi_dialogue_catalog.md').readAsStringSync();
    for (final ctx in MascotContext.values) {
      expect(
        doc.contains('`${ctx.name}`'),
        isTrue,
        reason:
            '${ctx.name} 沒出現在 docs/tumi_dialogue_catalog.md 的事件總表。'
            '新增或修改兔咪反應要先進表再寫程式（見該文件最下方的檢查清單）。',
      );
    }
  });

  test('帶件數的回應：第一件有專屬句，之後同數字同句、不講總數', () {
    expect(MascotLines.doneCountLine(0), '今天第一件。');
    expect(MascotLines.doneCountLine(1), '今天第一件。');
    // 同一個數字每次都回一樣，避免 rebuild 時台詞跳動
    expect(MascotLines.doneCountLine(3), MascotLines.doneCountLine(3));
    // 換數字要換句，才不會每天都同一句
    expect(
      {for (var n = 2; n <= 7; n++) MascotLines.doneCountLine(n)}.length,
      greaterThan(1),
    );
    // 第 1 件走中文「第一件」（中文習慣），第 2 件之後才用阿拉伯數字
    for (var n = 2; n <= 30; n++) {
      final line = MascotLines.doneCountLine(n);
      expect(line.contains('$n'), isTrue, reason: '第 $n 件應該講出數字：$line');
      expect(line.contains('/'), isFalse, reason: '不講總數（3/5 是系統通知口吻）');
      expect(line.characters.length, lessThanOrEqualTo(20), reason: line);
    }
  });

  test('兔咪一句話不超過 20 字', () {
    for (final ctx in MascotContext.values) {
      for (final pools in [
        MascotLines.linesFor(ctx),
        MascotLines.homeTapLinesFor(ctx),
      ]) {
        for (final line in pools) {
          // 換行的多句台詞逐行算，不把 \n 當一句
          for (final part in line.split('\n')) {
            expect(
              part.characters.length,
              lessThanOrEqualTo(20),
              reason: '$ctx 的「$part」太長了，兔咪講話要短',
            );
          }
        }
      }
    }
  });

  group('預設名跟著語言走', () {
    // MascotName.load 在 runApp 之前跑（拿不到 context），所以英文的預設名
    // "Tumi" 是 MaterialApp.builder 拿到 l10n 之後才用 applyDefaultName 補上。
    // 這幾條守住「補的時候不能動到使用者自己取的名字」。
    tearDown(() {
      MascotName.applyDefaultName(MascotName.fallback);
      MascotName.set(null);
    });

    testWidgets('沒取過名字時，套用語言預設名會換掉顯示的名字', (tester) async {
      MascotName.set(null);
      expect(MascotName.value, MascotName.fallback);

      MascotName.applyDefaultName('Tumi');
      await tester.pump();

      expect(MascotName.value, 'Tumi');
    });

    testWidgets('取過名字的人不受影響', (tester) async {
      MascotName.set('小雲');

      MascotName.applyDefaultName('Tumi');
      await tester.pump();

      expect(MascotName.value, '小雲');
    });

    testWidgets('取過名字後又清空，回到目前語言的預設名', (tester) async {
      MascotName.applyDefaultName('Tumi');
      await tester.pump();
      MascotName.set('Mochi');
      expect(MascotName.value, 'Mochi');

      MascotName.set('   '); // 只有空白＝沒取名
      expect(MascotName.value, 'Tumi');
    });
  });
}
