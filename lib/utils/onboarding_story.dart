import 'companion_story_catalog.dart';
import 'mascot.dart';

enum OnboardingNamePrompt { none, mascot, user }

/// The first meeting has one script for setup, developer preview and memory.
/// Names are local form state; replay never claims an unsaved past answer.
class OnboardingStoryScene {
  const OnboardingStoryScene({
    required this.id,
    required this.text,
    this.showMascot = true,
    this.emotion = MascotEmotion.neutralFront,
    this.prompt = OnboardingNamePrompt.none,
    this.replayText,
  });

  final String id;
  final CompanionText text;
  final bool showMascot;
  final MascotEmotion emotion;
  final OnboardingNamePrompt prompt;
  final CompanionText? replayText;
}

const onboardingStoryTitle = CompanionText('從這次相遇開始', 'Our first meeting');

const onboardingStoryScenes = <OnboardingStoryScene>[
  OnboardingStoryScene(
    id: 'arrival',
    showMascot: false,
    text: CompanionText(
      '你走進這個家。\n一段新的日常，正要開始。',
      'You step inside.\nYour days together are about to begin.',
    ),
  ),
  OnboardingStoryScene(
    id: 'hello',
    text: CompanionText(
      '啊……你來了。\n我剛剛在練習打招呼。\n我叫兔咪。',
      'Oh... hello.\nI was practicing how to say hello.\nI’m Tumi.',
    ),
  ),
  OnboardingStoryScene(
    id: 'new_home',
    text: CompanionText(
      '最近才搬來這裡。\n還在學著自己安排生活。\n也想學著，主動跟人說話。',
      'I only moved here recently.\nI’m learning to manage things on my own.\nAnd to start conversations, too.',
    ),
  ),
  OnboardingStoryScene(
    id: 'mascot_name',
    prompt: OnboardingNamePrompt.mascot,
    text: CompanionText(
      '叫我兔咪就好。\n你也可以幫我取個暱稱。',
      'You can call me Tumi.\nOr give me a nickname, if you like.',
    ),
    replayText: CompanionText(
      '叫我兔咪就好。\n稱呼的事，可以之後再聊。',
      'You can call me Tumi.\nWe can talk about names another time.',
    ),
  ),
  OnboardingStoryScene(
    id: 'user_name',
    prompt: OnboardingNamePrompt.user,
    text: CompanionText(
      '那……怎麼叫你呢？\n也可以之後再告訴我。',
      'What would you like me to call you?\nYou can tell me another time, too.',
    ),
    replayText: CompanionText(
      '那……怎麼叫你呢？\n也可以之後再告訴我。',
      'What would you like me to call you?\nYou can tell me another time, too.',
    ),
  ),
  OnboardingStoryScene(
    id: 'together',
    emotion: MascotEmotion.smile,
    text: CompanionText(
      '我想慢慢把生活打理好。\n有什麼小事，也想跟你聊聊。\n今天認識你，滿開心的。',
      'I want to get better at looking after myself.\nAnd share little things from my day with you.\nI’m glad we met today.',
    ),
  ),
];
