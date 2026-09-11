import 'dart:io';

import 'package:characters/characters.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:habit_app/utils/companion_story_catalog.dart';
import 'package:habit_app/utils/mascot.dart';

Iterable<CompanionText> episodeTexts(CompanionEpisode episode) sync* {
  yield episode.title;
  for (final beat in episode.beats) {
    yield* beat.lines;
    for (final choice in beat.choices) {
      yield choice.label;
      yield* choice.replies;
    }
  }
}

void main() {
  const expectedDays = <String, int>{
    'story_01': 1,
    'daily_02': 2,
    'daily_03': 3,
    'story_02': 4,
    'daily_05': 5,
    'daily_06': 6,
    'story_03': 7,
    'story_04': 12,
    'story_05': 18,
    'story_06': 24,
    'story_07': 31,
    'story_08': 38,
    'story_09': 45,
    'story_10': 53,
    'story_11': 62,
    'story_12': 72,
    'story_13': 82,
    'story_14': 90,
  };

  test('the first season has all 18 stable episode IDs in day order', () {
    expect(companionEpisodes, hasLength(18));
    expect(
      companionEpisodes.map((episode) => episode.id),
      orderedEquals(expectedDays.keys),
    );
    expect(
      companionEpisodes.map((episode) => episode.day),
      orderedEquals(expectedDays.values),
    );
    for (final episode in companionEpisodes) {
      expect(
        episode.kind,
        episode.id.startsWith('daily_')
            ? CompanionStoryKind.daily
            : CompanionStoryKind.main,
        reason: episode.id,
      );
      expect(companionEpisodeById(episode.id), same(episode));
    }
    expect(companionEpisodeById('missing_episode'), isNull);
    expect(companionEpisodeById(''), isNull);
    expect(companionEpisodeById('STORY_01'), isNull);
  });

  test(
    'every title, line, choice and reply has usable Chinese and English',
    () {
      for (final episode in companionEpisodes) {
        for (final text in episodeTexts(episode)) {
          expect(text.zh.trim(), isNotEmpty, reason: episode.id);
          expect(text.en.trim(), isNotEmpty, reason: episode.id);
          expect(text.zh, text.zh.trim(), reason: episode.id);
          expect(text.en, text.en.trim(), reason: episode.id);
          expect(text.zh, isNot(text.en), reason: episode.id);
          expect(
            RegExp(r'[\u3400-\u9fff]').hasMatch(text.en),
            isFalse,
            reason: '${episode.id}: untranslated English: ${text.en}',
          );
          expect(
            RegExp(r'\{[^}]+\}').hasMatch('${text.zh} ${text.en}'),
            isFalse,
            reason: '${episode.id}: unresolved content placeholder',
          );
          expect(text.resolve('zh'), text.zh);
          expect(text.resolve('en'), text.en);
          expect(text.resolve('fr'), text.en);
        }
      }
    },
  );

  test('all Chinese story text fits the 20-character rule', () {
    for (final episode in companionEpisodes) {
      for (final text in episodeTexts(episode)) {
        expect(
          text.zh.characters.length,
          lessThanOrEqualTo(20),
          reason: '${episode.id}: ${text.zh}',
        );
        expect(text.zh.contains('\n'), isFalse, reason: episode.id);
      }
    }
  });

  test('every beat and choice has a unique stable ID and readable content', () {
    final beatIds = <String>{};
    final choiceIds = <String>{};
    final validId = RegExp(r'^[a-z][a-z0-9_]*$');
    for (final episode in companionEpisodes) {
      expect(episode.beats, isNotEmpty, reason: episode.id);
      for (final beat in episode.beats) {
        expect(validId.hasMatch(beat.id), isTrue, reason: beat.id);
        expect(beat.id.startsWith('${episode.id}_'), isTrue);
        expect(beatIds.add(beat.id), isTrue, reason: 'duplicate ${beat.id}');
        expect(beat.lines, isNotEmpty, reason: beat.id);
        expect(beat.lines.length, lessThanOrEqualTo(4), reason: beat.id);
        if (beat.choices.isNotEmpty) {
          expect(beat.choices.length, inInclusiveRange(2, 3), reason: beat.id);
        }
        final chineseLabels = <String>{};
        final englishLabels = <String>{};
        for (final choice in beat.choices) {
          expect(validId.hasMatch(choice.id), isTrue, reason: choice.id);
          expect(choice.id.startsWith('${beat.id}_'), isTrue);
          expect(
            choiceIds.add(choice.id),
            isTrue,
            reason: 'duplicate ${choice.id}',
          );
          expect(choice.replies, isNotEmpty, reason: choice.id);
          expect(chineseLabels.add(choice.label.zh), isTrue, reason: choice.id);
          expect(englishLabels.add(choice.label.en), isTrue, reason: choice.id);
        }
      }
    }
  });

  test('later main episodes remain short and end with an actual choice', () {
    for (final episode in companionEpisodes.where(
      (episode) => episode.day >= 12,
    )) {
      final lineCount = episode.beats.fold<int>(
        0,
        (count, beat) => count + beat.lines.length,
      );
      expect(lineCount, inInclusiveRange(8, 14), reason: episode.id);
      expect(episode.beats.last.choices, isNotEmpty, reason: episode.id);
      expect(
        episode.beats.where((beat) => beat.choices.isNotEmpty),
        hasLength(1),
        reason: episode.id,
      );
    }
  });

  test('self-introduction and nickname wording stay in the first meeting', () {
    final namingInChinese = RegExp(r'兔咪|暱稱|取名');
    final namingInEnglish = RegExp(
      r'\bTumi\b|\bnickname\b',
      caseSensitive: false,
    );
    final firstMeeting = companionEpisodeById('story_01')!;
    expect(
      episodeTexts(firstMeeting).any((text) => text.zh == '我叫兔咪。'),
      isTrue,
    );
    expect(
      episodeTexts(firstMeeting).any((text) => text.en == "I'm Tumi."),
      isTrue,
    );
    for (final episode in companionEpisodes.skip(1)) {
      for (final text in episodeTexts(episode)) {
        expect(namingInChinese.hasMatch(text.zh), isFalse, reason: episode.id);
        expect(namingInEnglish.hasMatch(text.en), isFalse, reason: episode.id);
      }
    }
  });

  test('story portraits all resolve to existing approved PNG assets', () {
    final usedEmotions = <MascotEmotion>{};
    for (final episode in companionEpisodes) {
      for (final beat in episode.beats) {
        usedEmotions.add(beat.emotion);
        for (final choice in beat.choices) {
          final emotion = choice.emotion;
          if (emotion != null) usedEmotions.add(emotion);
        }
      }
    }
    for (final emotion in usedEmotions) {
      final file = File(emotion.assetPath);
      expect(file.existsSync(), isTrue, reason: emotion.assetPath);
      expect(
        file.readAsBytesSync().take(8),
        orderedEquals(<int>[137, 80, 78, 71, 13, 10, 26, 10]),
        reason: 'Missing PNG data for ${emotion.assetPath}',
      );
    }
  });

  test('the loss chapter keeps a restrained portrait in every branch', () {
    final loss = companionEpisodeById('story_08')!;
    const celebratory = <MascotEmotion>{
      MascotEmotion.happy,
      MascotEmotion.popHappy,
      MascotEmotion.streak,
    };
    for (final beat in loss.beats) {
      expect(celebratory, isNot(contains(beat.emotion)));
      for (final choice in beat.choices) {
        expect(celebratory, isNot(contains(choice.emotion)));
      }
    }
  });
}
