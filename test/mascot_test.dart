import 'package:flutter_test/flutter_test.dart';
import 'package:habit_app/utils/mascot.dart';

void main() {
  setUp(() {
    MascotPersona.voiceMuted = true;
    MascotPersona.resetToOpening();
  });

  tearDown(() {
    MascotPersona.resetToOpening();
    MascotPersona.voiceMuted = false;
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
    expect(state.speech, isNull, reason: '充電互動是高頻演出，靠符號與動作就好');
    expect(
      MascotPersona.hasVoiceFor(MascotContext.energize),
      isFalse,
      reason: '蓄力跳躍不應共用偏高音的歡呼語音',
    );
    expect(
      MascotPersona.hasVoiceFor(MascotContext.allDone),
      isTrue,
      reason: '只移除蓄力映射，不影響真正的大慶祝',
    );
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
}
