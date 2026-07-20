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
}
