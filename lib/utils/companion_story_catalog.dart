// Companion dialogue content uses existing approved MascotEmotion portraits.
// No new event CG, onboarding action, reward, or persistence operation is defined
// here. In particular, replaying story_01 only replays the first meeting; it never
// opens naming or feature settings. The user's existing nickname stays unchanged.
// Narrative sources: docs/tumi_first_week_script_v1.md and
// docs/tumi_story_outline_v1.md. These translations still need reader review.

import 'mascot.dart';

class CompanionText {
  final String zh;
  final String en;

  const CompanionText(this.zh, this.en);

  String resolve(String languageCode) => languageCode == 'zh' ? zh : en;
}

enum CompanionStoryKind { main, daily }

class CompanionChoice {
  final String id;
  final CompanionText label;
  final List<CompanionText> replies;
  final MascotEmotion? emotion;

  const CompanionChoice({
    required this.id,
    required this.label,
    required this.replies,
    this.emotion,
  });
}

class CompanionBeat {
  final String id;
  final List<CompanionText> lines;
  final List<CompanionChoice> choices;
  final MascotEmotion emotion;

  const CompanionBeat({
    required this.id,
    required this.lines,
    this.choices = const [],
    this.emotion = MascotEmotion.neutralFront,
  });
}

class CompanionEpisode {
  final String id;
  final int day;
  final CompanionStoryKind kind;
  final CompanionText title;
  final List<CompanionBeat> beats;

  const CompanionEpisode({
    required this.id,
    required this.day,
    required this.kind,
    required this.title,
    required this.beats,
  });
}

const List<CompanionEpisode> companionEpisodes = [
  CompanionEpisode(
    id: 'story_01',
    day: 1,
    kind: CompanionStoryKind.main,
    title: CompanionText('從這次相遇開始', 'Our first meeting'),
    beats: [
      CompanionBeat(
        id: 'story_01_arrival',
        lines: [
          CompanionText('啊……你來了。', 'Oh... hello.'),
          CompanionText('我剛剛在練習打招呼。', 'I was practicing how to say hello.'),
          CompanionText('結果，只記得這一句。', 'And that was all I remembered.'),
        ],
      ),
      CompanionBeat(
        id: 'story_01_name',
        lines: [
          CompanionText('我叫兔咪。', "I'm Tumi."),
          CompanionText('你也可以幫我取個暱稱。', 'You can give me a nickname, too.'),
        ],
        choices: [
          CompanionChoice(
            id: 'story_01_name_keep',
            label: CompanionText('先叫你兔咪。', "I'll call you Tumi for now."),
            emotion: MascotEmotion.smile,
            replies: [CompanionText('嗯，叫我兔咪就好。', 'Mm. Tumi is fine.')],
          ),
          CompanionChoice(
            id: 'story_01_name_later',
            label: CompanionText(
              '稱呼的事，慢慢決定。',
              'We can decide on a nickname later.',
            ),
            replies: [
              CompanionText('好。先認識一下。', "Okay. Let's get to know each other."),
            ],
          ),
        ],
      ),
      CompanionBeat(
        id: 'story_01_wish',
        lines: [
          CompanionText(
            '最近才住進來。',
            'I only moved in recently.', // units-ok: English preposition.
          ),
          CompanionText(
            '還在學著自己安排生活。',
            "I'm learning to manage things on my own.",
          ),
          CompanionText('也想變得外向一點。', "I'd like to be a little more outgoing."),
          CompanionText(
            '這樣應該……比較好相處吧。',
            "Maybe then... I'd be easier to get along with.",
          ),
        ],
        choices: [
          CompanionChoice(
            id: 'story_01_wish_change',
            label: CompanionText(
              '我也有想改變的事。',
              "There are things I'd like to change, too.",
            ),
            emotion: MascotEmotion.smile,
            replies: [
              CompanionText('原來，你也有。', 'Oh, you do too.'),
              CompanionText(
                '那……就慢慢認識吧。',
                "Then... let's take our time getting to know each other.",
              ),
            ],
          ),
          CompanionChoice(
            id: 'story_01_wish_your_way',
            label: CompanionText(
              '先照你習慣的方式就好。',
              'You can just be yourself with me.',
            ),
            replies: [
              CompanionText('好。', 'Okay.'),
              CompanionText(
                '不過，我可能會停頓很久。',
                'There might be some long pauses, though.',
              ),
            ],
          ),
          CompanionChoice(
            id: 'story_01_wish_nervous',
            label: CompanionText(
              '其實我現在也有點緊張。',
              "I'm a little nervous right now, too.",
            ),
            emotion: MascotEmotion.smile,
            replies: [
              CompanionText('啊，那我們一樣。', "Oh. Then we're the same."),
              CompanionText('剛才還以為只有我。', 'I thought it was just me.'),
            ],
          ),
        ],
      ),
      CompanionBeat(
        id: 'story_01_hello',
        lines: [
          CompanionText(
            '準備了很久的開場白……',
            'That introduction I spent so long practicing...',
          ),
          CompanionText('好像只說出一半。', 'I think I only said half of it.'),
        ],
        choices: [
          CompanionChoice(
            id: 'story_01_hello_another_time',
            label: CompanionText(
              '另外一半，留著下次說。',
              'Save the other half for another time.',
            ),
            emotion: MascotEmotion.smile,
            replies: [
              CompanionText('好。', 'Okay.'),
              CompanionText('希望下次還記得。', 'I hope I remember it by then.'),
            ],
          ),
          CompanionChoice(
            id: 'story_01_hello_enough',
            label: CompanionText('這樣就認識了呀。', "Well, we've met now."),
            emotion: MascotEmotion.smile,
            replies: [CompanionText('嗯。好像真的認識了。', 'Mm. I suppose we have.')],
          ),
          CompanionChoice(
            id: 'story_01_hello_look_around',
            label: CompanionText('我先看看這裡。', "I'll have a look around."),
            replies: [CompanionText('好，你慢慢看。', 'Okay. Take your time.')],
          ),
        ],
      ),
    ],
  ),
  CompanionEpisode(
    id: 'daily_02',
    day: 2,
    kind: CompanionStoryKind.daily,
    title: CompanionText('回話慢半拍', 'A Little Pause'),
    beats: [
      CompanionBeat(
        id: 'daily_02_pause',
        lines: [
          CompanionText(
            '剛剛，在想要怎麼說。',
            'I was just thinking how to put something into words.',
          ),
          CompanionText('我回話，有時候會慢一點。', 'Sometimes I take a while to answer.'),
          CompanionText('不是故意不理你。', "I'm not ignoring you."),
          CompanionText('有時候在想，要怎麼說清楚。', "I'm trying to find the right words."),
        ],
        choices: [
          CompanionChoice(
            id: 'daily_02_pause_also_think',
            label: CompanionText(
              '我也常常想很久。',
              'I often take a while to think, too.',
            ),
            emotion: MascotEmotion.smile,
            replies: [
              CompanionText('那剛剛……', 'Then just now...'),
              CompanionText('可能是兩邊都在想。', 'Maybe we were both thinking.'),
            ],
          ),
          CompanionChoice(
            id: 'daily_02_pause_talkative',
            label: CompanionText('我倒是很容易一直講。', 'I tend to keep talking.'),
            replies: [
              CompanionText('那我可以先聽。', 'Then I can listen.'),
              CompanionText(
                '想到什麼，再慢慢接。',
                "I'll join in when I have something to say.", // units-ok: English preposition.
              ),
            ],
          ),
          CompanionChoice(
            id: 'daily_02_pause_quiet',
            label: CompanionText('安靜待著也不錯。', 'Quiet company is nice, too.'),
            emotion: MascotEmotion.smile,
            replies: [
              CompanionText('嗯。', 'Mm.'),
              CompanionText(
                '一起待著，不急著把話說滿。',
                'We can sit together without filling every pause.',
              ),
            ],
          ),
        ],
      ),
      CompanionBeat(
        id: 'daily_02_said',
        emotion: MascotEmotion.smile,
        lines: [
          CompanionText(
            '這件事也想了一會兒。',
            'I thought about saying that for a while, too.',
          ),
          CompanionText('現在總算講完了。', "And now I've finally said it."),
        ],
      ),
    ],
  ),
  CompanionEpisode(
    id: 'daily_03',
    day: 3,
    kind: CompanionStoryKind.daily,
    title: CompanionText('今天的小事', 'Something from Today'),
    beats: [
      CompanionBeat(
        id: 'daily_03_today',
        lines: [CompanionText('今天過得怎麼樣？', 'How has your day been?')],
        choices: [
          CompanionChoice(
            id: 'daily_03_today_good',
            label: CompanionText('今天還不錯。', "It's been pretty good."),
            emotion: MascotEmotion.smile,
            replies: [
              CompanionText('那就好。', "I'm glad."),
              CompanionText('聽你這樣說，滿開心的。', "It's nice to hear that."),
            ],
          ),
          CompanionChoice(
            id: 'daily_03_today_your_day',
            label: CompanionText(
              '換你說一件今天的小事？',
              'How about something from your day?',
            ),
            emotion: MascotEmotion.smile,
            replies: [
              CompanionText(
                '想起以前看過的一本書。',
                'I remembered a book I read a while ago.',
              ),
              CompanionText(
                '明明知道結局，還想再看。',
                'I know how it ends, but I want to read it again.',
              ),
            ],
          ),
          CompanionChoice(
            id: 'daily_03_today_nothing',
            label: CompanionText(
              '今天沒什麼想說的。',
              "I don't have much to say today.",
            ),
            replies: [
              CompanionText('好。', 'Okay.'),
              CompanionText('那就先待一會兒。', 'We can just sit for a bit.'),
            ],
          ),
        ],
      ),
    ],
  ),
  CompanionEpisode(
    id: 'story_02',
    day: 4,
    kind: CompanionStoryKind.main,
    title: CompanionText('還沒全部做好', 'Not Quite Finished'),
    beats: [
      CompanionBeat(
        id: 'story_02_comic',
        emotion: MascotEmotion.question,
        lines: [
          CompanionText(
            '整理桌子時，翻到一本漫畫。',
            'I found a comic while clearing my desk.',
          ),
          CompanionText('本來只想看一頁。', 'I thought, just one page.'),
          CompanionText('桌子還沒整理完。', 'The desk was still a mess.'),
          CompanionText('漫畫倒是看完了。', 'But I finished the comic.'),
        ],
      ),
      CompanionBeat(
        id: 'story_02_small_space',
        lines: [
          CompanionText(
            '後來，還是收好了一小塊。',
            'I did clear one little patch afterward.',
          ),
          CompanionText(
            '本來想全部做好，再跟你說。',
            'I wanted to finish everything before telling you.',
          ),
        ],
        choices: [
          CompanionChoice(
            id: 'story_02_small_space_distracted',
            label: CompanionText(
              '我也很容易被別的東西吸引。',
              'I get distracted by other things, too.',
            ),
            emotion: MascotEmotion.smile,
            replies: [
              CompanionText('明明只想看一下。', 'I only meant to have a quick look.'),
              CompanionText(
                '抬頭才想起原本要做什麼。',
                'When I looked up, I remembered what I was meant to be doing.',
              ),
            ],
          ),
          CompanionChoice(
            id: 'story_02_small_space_feeling',
            label: CompanionText(
              '那一小塊整理完，感覺怎樣？',
              'How does that clear patch feel?',
            ),
            emotion: MascotEmotion.smile,
            replies: [
              CompanionText('看著，還滿舒服的。', "It's quite nice to look at."),
              CompanionText('想先讓它保持這樣。', "I'd like to keep that part clear."),
            ],
          ),
          CompanionChoice(
            id: 'story_02_small_space_put_away',
            label: CompanionText(
              '下次先把漫畫收起來？',
              'Put the comic away first next time?',
            ),
            emotion: MascotEmotion.smile,
            replies: [CompanionText('嗯，先不要翻開。', 'Mm. Before I open it.')],
          ),
        ],
      ),
      CompanionBeat(
        id: 'story_02_your_turn',
        lines: [
          CompanionText('剩下的，想分幾次做。', "I'll do the rest a bit at a time."),
          CompanionText('我講了好多自己的事。', "I've talked a lot about myself."),
          CompanionText(
            '你呢？有沒有想分享的？',
            'What about you? Anything you want to share?',
          ),
        ],
        choices: [
          CompanionChoice(
            id: 'story_02_your_turn_good_thing',
            label: CompanionText(
              '今天有件事做得還不錯。',
              'Something went well for me today.',
            ),
            emotion: MascotEmotion.smile,
            replies: [
              CompanionText('喔，替你開心一下。', "Oh, I'm happy for you."),
              CompanionText('今天多了一件好事。', "That's a nice part of today."),
            ],
          ),
          CompanionChoice(
            id: 'story_02_your_turn_rest',
            label: CompanionText(
              '今天不太順，想休息一下。',
              "It's been a rough day. I'd like to rest.",
            ),
            replies: [
              CompanionText('嗯。', 'Mm.'),
              CompanionText(
                '那就先休息，改天再聊。',
                'Have a rest. We can talk another time.',
              ),
            ],
          ),
          CompanionChoice(
            id: 'story_02_your_turn_about_comic',
            label: CompanionText(
              '我比較想知道那本漫畫。',
              "I'd rather hear about the comic.",
            ),
            emotion: MascotEmotion.smile,
            replies: [
              CompanionText('冒險故事。', "It's an adventure story."),
              CompanionText(
                '這次有把它放回書架了。',
                'I did put it back on the shelf this time.',
              ),
            ],
          ),
        ],
      ),
    ],
  ),
  CompanionEpisode(
    id: 'daily_05',
    day: 5,
    kind: CompanionStoryKind.daily,
    title: CompanionText('只是來看看你', 'Just Stopping By'),
    beats: [
      CompanionBeat(
        id: 'daily_05_listen',
        lines: [
          CompanionText('今天，換我當聽的那個？', 'Shall I be the one who listens today?'),
          CompanionText('沒有要問很正式的問題。', 'Nothing like an interview.'),
          CompanionText('有想到什麼，再說就好。', 'Just whatever comes to mind.'),
        ],
        choices: [
          CompanionChoice(
            id: 'daily_05_listen_putting_off',
            label: CompanionText(
              '有件事一直拖著，還沒做。',
              "There's something I keep putting off.",
            ),
            replies: [
              CompanionText('我也有。', 'I have something like that, too.'),
              CompanionText(
                '說出來，好像不用先裝沒事。',
                "It's nice to say it without pretending everything is fine.",
              ),
            ],
          ),
          CompanionChoice(
            id: 'daily_05_listen_light',
            label: CompanionText(
              '今天想聽點輕鬆的。',
              "I'd like to hear something light today.",
            ),
            emotion: MascotEmotion.smile,
            replies: [
              CompanionText(
                '有次想看完最後一頁再睡。',
                'Once, I tried to finish one last page before bed.',
              ),
              CompanionText(
                '醒來，書還在同一頁。',
                'When I woke up, the book was still on that page.',
              ),
            ],
          ),
          CompanionChoice(
            id: 'daily_05_listen_visit',
            label: CompanionText('其實只是來看看你。', 'I just wanted to see you.'),
            emotion: MascotEmotion.smile,
            replies: [
              CompanionText('喔……', 'Oh...'),
              CompanionText('看到你，滿開心的。', "I'm glad you came by."),
            ],
          ),
        ],
      ),
    ],
  ),
  CompanionEpisode(
    id: 'daily_06',
    day: 6,
    kind: CompanionStoryKind.daily,
    title: CompanionText('像棉被的雲', 'A Cloud Like a Blanket'),
    beats: [
      CompanionBeat(
        id: 'daily_06_cloud',
        lines: [
          CompanionText('有次看到一朵雲。', 'I saw a cloud once.'),
          CompanionText(
            '很厚，看起來像一大團棉被。',
            'It was thick and looked like a big, soft blanket.',
          ),
        ],
        choices: [
          CompanionChoice(
            id: 'daily_06_cloud_cozy',
            label: CompanionText('感覺很舒服。', 'That sounds cozy.'),
            emotion: MascotEmotion.smile,
            replies: [
              CompanionText('嗯，看了好一會兒。', 'Mm. I watched it for quite a while.'),
            ],
          ),
          CompanionChoice(
            id: 'daily_06_cloud_animals',
            label: CompanionText(
              '我以前也看過像動物的雲。',
              "I've seen clouds shaped like animals.",
            ),
            emotion: MascotEmotion.smile,
            replies: [
              CompanionText(
                '嗯，每次看都不太一樣。',
                'Mm. They look a little different every time.',
              ),
              CompanionText(
                '看著它慢慢飄，也很舒服。',
                'It feels nice just watching them drift.',
              ),
            ],
          ),
          CompanionChoice(
            id: 'daily_06_cloud_sleepy',
            label: CompanionText(
              '聽你說，我也有點想睡。',
              'Hearing that makes me a little sleepy.',
            ),
            replies: [CompanionText('那就先休息一下。', 'Then have a little rest.')],
          ),
        ],
      ),
    ],
  ),
  CompanionEpisode(
    id: 'story_03',
    day: 7,
    kind: CompanionStoryKind.main,
    title: CompanionText('沒有問出口', 'The Question I Kept'),
    beats: [
      CompanionBeat(
        id: 'story_03_shop',
        lines: [
          CompanionText(
            '去買東西時，找了好幾圈。',
            'I walked around the shop a few times, looking for something.',
          ),
          CompanionText('明明有店員經過。', 'A shop assistant even walked past.'),
          CompanionText('可是，話一直沒有說出口。', "But I couldn't get the words out."),
        ],
      ),
      CompanionBeat(
        id: 'story_03_honest',
        lines: [
          CompanionText(
            '本來想說，只是剛好沒貨。',
            'I was going to say they were just out of stock.',
          ),
          CompanionText('但其實……我沒有問。', 'But really... I never asked.'),
        ],
        choices: [
          CompanionChoice(
            id: 'story_03_honest_circles',
            label: CompanionText(
              '我也會先多繞幾圈。',
              'I take a few extra laps first, too.',
            ),
            emotion: MascotEmotion.smile,
            replies: [
              CompanionText(
                '每次都想，下一圈就問。',
                "I kept thinking I'd ask after one more lap.",
              ),
              CompanionText('結果先把走道記熟了。', 'Now I know every aisle.'),
            ],
          ),
          CompanionChoice(
            id: 'story_03_honest_practice',
            label: CompanionText(
              '先練一句『不好意思』看看？',
              "Want to try saying 'Excuse me' first?",
            ),
            replies: [
              CompanionText('好。那……', 'Okay. So...'),
              CompanionText('不好意思。', 'Excuse me.'),
              CompanionText('嗯，這句先記住。', "Mm. I'll start with that."),
            ],
          ),
          CompanionChoice(
            id: 'story_03_honest_listen',
            label: CompanionText('你先說，我聽。', "Go on. I'm listening."),
            replies: [
              CompanionText('嗯。', 'Mm.'),
              CompanionText(
                '講出來，有點不好意思。',
                "It's a little embarrassing to say.",
              ),
              CompanionText(
                '但不用想別的理由了。',
                "But I don't have to make up another reason.",
              ),
            ],
          ),
        ],
      ),
      CompanionBeat(
        id: 'story_03_try_again',
        emotion: MascotEmotion.smile,
        lines: [
          CompanionText('下次，想再試試看。', "I'd like to try again next time."),
          CompanionText('要是又卡住，再跟你說。', "If I get stuck again, I'll tell you."),
        ],
      ),
    ],
  ),
  CompanionEpisode(
    id: 'story_04',
    day: 12,
    kind: CompanionStoryKind.main,
    title: CompanionText('可以再說一次嗎', 'Could You Say That Again?'),
    beats: [
      CompanionBeat(
        id: 'story_04_returned',
        lines: [
          CompanionText('又去了那家店。', 'I went back to that shop.'),
          CompanionText('這次，終於問出口了。', 'This time, I managed to ask.'),
          CompanionText('可是店員說得好快。', 'But the answer came so quickly.'),
        ],
      ),
      CompanionBeat(
        id: 'story_04_asked_again',
        emotion: MascotEmotion.expect,
        lines: [
          CompanionText(
            '差點就點頭，假裝聽懂。',
            'I nearly nodded and pretended I understood.',
          ),
          CompanionText(
            '後來說了，能不能再說一次。',
            'Then I asked if they could say it again.',
          ),
          CompanionText('對方就放慢一點告訴我。', 'They just explained it more slowly.'),
        ],
      ),
      CompanionBeat(
        id: 'story_04_home',
        emotion: MascotEmotion.smile,
        lines: [
          CompanionText('最後，有找到要買的東西。', 'I found what I was looking for.'),
          CompanionText('明明說話還是很小聲。', 'My voice was still quiet.'),
          CompanionText(
            '不過，這次有說清楚。',
            'But this time, I got my question across.',
          ),
        ],
        choices: [
          CompanionChoice(
            id: 'story_04_home_glad',
            label: CompanionText('替你開心。', "I'm happy for you."),
            emotion: MascotEmotion.smile,
            replies: [
              CompanionText(
                '嗯。回來時，有點得意。',
                'Mm. I felt a little proud on the way home.',
              ),
            ],
          ),
          CompanionChoice(
            id: 'story_04_home_did_it',
            label: CompanionText(
              '小聲也有把事情說清楚。',
              'You got your point across, even quietly.',
            ),
            emotion: MascotEmotion.smile,
            replies: [
              CompanionText('對。', 'Yes.'),
              CompanionText(
                '沒有變很厲害，也做到了。',
                "I didn't suddenly become great at talking. But I did it.",
              ),
            ],
          ),
          CompanionChoice(
            id: 'story_04_home_relate',
            label: CompanionText(
              '我也常常要請人再說一次。',
              'I often need to ask people to repeat things.',
            ),
            emotion: MascotEmotion.smile,
            replies: [
              CompanionText('原來，不只我會。', "Oh, so it's not just me."),
              CompanionText(
                '下次聽不懂，還是會再問。',
                "If I don't understand next time, I'll ask again.",
              ),
            ],
          ),
        ],
      ),
    ],
  ),
  CompanionEpisode(
    id: 'story_05',
    day: 18,
    kind: CompanionStoryKind.main,
    title: CompanionText('牠忙牠的，我說我的', 'A Very Busy Listener'),
    beats: [
      CompanionBeat(
        id: 'story_05_xiaomai',
        emotion: MascotEmotion.smile,
        lines: [
          CompanionText('以前，養過一隻黃金鼠。', 'I used to have a golden hamster.'),
          CompanionText('名字叫小麥。', 'I called my hamster Xiaomai.'),
          CompanionText(
            '小小的，常常忙自己的事。',
            'Such a little thing, always busy with something.',
          ),
        ],
      ),
      CompanionBeat(
        id: 'story_05_listener',
        emotion: MascotEmotion.smile,
        lines: [
          CompanionText('有次我一直跟牠說話。', 'Once, I kept chatting away to Xiaomai.'),
          CompanionText(
            '牠一趟一趟，從旁邊經過。',
            'My little friend kept going past, back and forth.',
          ),
          CompanionText('原來是在把食物搬回去。', 'Xiaomai was busy carrying food back.'),
        ],
      ),
      CompanionBeat(
        id: 'story_05_together',
        emotion: MascotEmotion.smile,
        lines: [
          CompanionText(
            '我還以為，牠特地來聽。',
            'I thought Xiaomai had come over just to listen.',
          ),
          CompanionText(
            '那時不用一直找話題。',
            "I didn't have to keep finding things to say.",
          ),
          CompanionText('只是一起待著，就很開心。', 'Just being together made me happy.'),
        ],
        choices: [
          CompanionChoice(
            id: 'story_05_together_picture',
            label: CompanionText('好像能想像那個畫面。', 'I can almost picture it.'),
            emotion: MascotEmotion.smile,
            replies: [
              CompanionText(
                '嗯。牠忙牠的，我說我的。',
                'Mm. Xiaomai kept busy, and I kept talking.',
              ),
            ],
          ),
          CompanionChoice(
            id: 'story_05_together_precious',
            label: CompanionText('你很珍惜小麥呢。', 'Xiaomai means a lot to you.'),
            emotion: MascotEmotion.smile,
            replies: [CompanionText('嗯，是很重要的朋友。', 'Mm. A very dear friend.')],
          ),
          CompanionChoice(
            id: 'story_05_together_where',
            label: CompanionText('小麥現在在哪裡？', 'Where is Xiaomai now?'),
            emotion: MascotEmotion.sad,
            replies: [
              CompanionText('現在不在了。', "Xiaomai isn't here anymore."),
              CompanionText(
                '很想牠，但還不太會說。',
                "I miss my little friend. I'm not ready to talk about it yet.",
              ),
            ],
          ),
        ],
      ),
    ],
  ),
  CompanionEpisode(
    id: 'story_06',
    day: 24,
    kind: CompanionStoryKind.main,
    title: CompanionText('排得太滿的一天', 'A Day Too Full'),
    beats: [
      CompanionBeat(
        id: 'story_06_busy',
        lines: [
          CompanionText('今天，跟好多人說了話。', 'I talked to so many people today.'),
          CompanionText(
            '買東西，也去跟人打招呼。',
            'I went shopping and said hello to people.',
          ),
          CompanionText(
            '想說這樣就會進步很快。',
            'I thought it would help me improve quickly.',
          ),
        ],
      ),
      CompanionBeat(
        id: 'story_06_tired',
        emotion: MascotEmotion.sleep,
        lines: [
          CompanionText(
            '可是現在……一句都不想說。',
            "But now... I don't want to say another word.",
          ),
          CompanionText(
            '本來還有一件趣事想講。',
            'There was something nice I wanted to tell you.',
          ),
          CompanionText('現在只想先坐一下。', 'Right now, I just want to sit down.'),
        ],
      ),
      CompanionBeat(
        id: 'story_06_enough',
        lines: [
          CompanionText('我是不是又做不好了？', 'Did I mess it up again?'),
          CompanionText(
            '好像有點太勉強自己。',
            'I think I pushed myself a bit too hard.',
          ),
        ],
        choices: [
          CompanionChoice(
            id: 'story_06_enough_also_tired',
            label: CompanionText(
              '我跟人相處久了也會累。',
              'Being around people tires me out, too.',
            ),
            replies: [
              CompanionText('原來，你也會。', 'Oh, you too.'),
              CompanionText('那……先休息一下。', "Then... I'll have a rest."),
            ],
          ),
          CompanionChoice(
            id: 'story_06_enough_quiet',
            label: CompanionText('今天先安靜也可以。', 'We can be quiet today.'),
            replies: [
              CompanionText('好。', 'Okay.'),
              CompanionText(
                '不用想話題，輕鬆一點了。',
                "It's a relief not to think of something to say.",
              ),
            ],
          ),
          CompanionChoice(
            id: 'story_06_enough_too_much',
            label: CompanionText(
              '感覺今天排太滿了。',
              'It sounds like you planned too much.',
            ),
            replies: [
              CompanionText(
                '嗯，想一次練習太多。',
                'Mm. I tried to practice too much at once.',
              ),
              CompanionText('下次，我想少排一點。', "I'll plan a little less next time."),
            ],
          ),
        ],
      ),
    ],
  ),
  CompanionEpisode(
    id: 'story_07',
    day: 31,
    kind: CompanionStoryKind.main,
    title: CompanionText('以前的教室', 'The Classroom I Remember'),
    beats: [
      CompanionBeat(
        id: 'story_07_something',
        lines: [
          CompanionText(
            '後來休息了一下，好多了。',
            'I had some rest afterward. I felt better.',
          ),
          CompanionText(
            '有件以前的事，想跟你說。',
            "There's something from before I'd like to tell you.",
          ),
          CompanionText('在學校時，曾經被欺負。', 'I used to be bullied at school.'),
        ],
      ),
      CompanionBeat(
        id: 'story_07_withdrew',
        emotion: MascotEmotion.sad,
        lines: [
          CompanionText(
            '那之後，越來越不敢開口。',
            'After that, speaking up became harder and harder.',
          ),
          CompanionText('也不太想再去學校。', "I didn't want to go to school anymore."),
          CompanionText(
            '總覺得，是自己太不會說話。',
            'I kept thinking it was because I was bad at talking.',
          ),
        ],
      ),
      CompanionBeat(
        id: 'story_07_tell',
        emotion: MascotEmotion.sad,
        lines: [
          CompanionText(
            '所以才一直想變得很外向。',
            "That's why I wanted so much to be outgoing.",
          ),
          CompanionText(
            '現在想起，還是會緊張。',
            'I still get nervous thinking about it.',
          ),
          CompanionText('今天，先說到這裡。', "That's as much as I want to say today."),
        ],
        choices: [
          CompanionChoice(
            id: 'story_07_tell_hear',
            label: CompanionText('嗯，我聽到了。', 'Mm. I hear you.'),
            replies: [
              CompanionText('謝謝。', 'Thank you.'),
              CompanionText(
                '把這些說出來，還不太習慣。',
                "I'm still not used to saying these things aloud.",
              ),
            ],
          ),
          CompanionChoice(
            id: 'story_07_tell_not_fault',
            label: CompanionText(
              '被欺負不是你的錯。',
              "Being bullied wasn't your fault.",
            ),
            replies: [
              CompanionText(
                '嗯……想慢慢相信這件事。',
                'Mm... I want to let myself believe that.',
              ),
            ],
          ),
          CompanionChoice(
            id: 'story_07_tell_stop',
            label: CompanionText('那就先不說了。', 'We can stop here.'),
            replies: [
              CompanionText('好。今天先到這裡。', "Okay. That's enough for today."),
            ],
          ),
        ],
      ),
    ],
  ),
  CompanionEpisode(
    id: 'story_08',
    day: 38,
    kind: CompanionStoryKind.main,
    title: CompanionText('我沒有照顧好牠', "I Didn't Take Care of My Friend"),
    beats: [
      CompanionBeat(
        id: 'story_08_friend',
        lines: [
          CompanionText(
            '今天，想說說小麥的事。',
            "I'd like to tell you about Xiaomai today.",
          ),
          CompanionText('牠曾經是我最好的朋友。', 'Xiaomai was my best friend.'),
          CompanionText(
            '好多想說的話，都跟牠說。',
            'I told my little friend so many things.',
          ),
        ],
      ),
      CompanionBeat(
        id: 'story_08_loss',
        emotion: MascotEmotion.sad,
        lines: [
          CompanionText('有次，父母出遠門。', 'Once, my parents went away.'),
          CompanionText('我忘了餵牠。', 'I forgot to feed Xiaomai.'),
          CompanionText('沒有照顧好牠。', "I didn't take care of my friend."),
          CompanionText('後來，小麥過世了。', 'Xiaomai died.'),
        ],
      ),
      CompanionBeat(
        id: 'story_08_grief',
        emotion: MascotEmotion.sad,
        lines: [
          CompanionText(
            '那時覺得，自己什麼都不好。',
            'Back then, I thought everything about me was wrong.',
          ),
          CompanionText('連想到開心的事，也很難過。', 'Even remembering happy things hurt.'),
          CompanionText('現在，還是很想牠。', 'I still miss my little friend so much.'),
        ],
        choices: [
          CompanionChoice(
            id: 'story_08_grief_listen',
            label: CompanionText('我願意聽你說。', "I'm here to listen."),
            emotion: MascotEmotion.sad,
            replies: [
              CompanionText(
                '嗯。說到這裡，有點想哭。',
                'Mm. Saying this makes me want to cry.',
              ),
              CompanionText('先讓我停一下。', 'Let me pause for a moment.'),
            ],
          ),
          CompanionChoice(
            id: 'story_08_grief_no_words',
            label: CompanionText('我不太知道怎麼安慰你。', "I'm not sure what to say."),
            emotion: MascotEmotion.sad,
            replies: [
              CompanionText(
                '嗯，不用急著想一句話。',
                "Mm. You don't have to find the right words.",
              ),
              CompanionText(
                '這些一直很難說出口。',
                'It has been hard to tell anyone this.',
              ),
            ],
          ),
          CompanionChoice(
            id: 'story_08_grief_pause',
            label: CompanionText('我們先停一下。', "Let's pause for a bit."),
            emotion: MascotEmotion.sad,
            replies: [CompanionText('好。先安靜一下。', 'Okay. A quiet moment.')],
          ),
        ],
      ),
    ],
  ),
  CompanionEpisode(
    id: 'story_09',
    day: 45,
    kind: CompanionStoryKind.main,
    title: CompanionText('這次，我會先開口', "This Time, I'll Ask"),
    beats: [
      CompanionBeat(
        id: 'story_09_visit',
        lines: [
          CompanionText('父母前陣子來看我。', 'My parents came to see me recently.'),
          CompanionText(
            '本來想把家裡全部整理好。',
            'I wanted to tidy the whole place before they came.',
          ),
          CompanionText(
            '好像這樣，就能讓他們放心。',
            'I thought that would help them worry less.',
          ),
        ],
      ),
      CompanionBeat(
        id: 'story_09_asked',
        lines: [
          CompanionText(
            '可是，時間沒有排好。',
            "But I hadn't planned my time very well.",
          ),
          CompanionText(
            '這次沒有等到最後才說。',
            "This time, I didn't wait until the last moment to say so.",
          ),
          CompanionText(
            '請他們幫忙買一部分東西。',
            'I asked them to help with some of the shopping.',
          ),
        ],
      ),
      CompanionBeat(
        id: 'story_09_together',
        emotion: MascotEmotion.smile,
        lines: [
          CompanionText(
            '自己答應的整理，有做完。',
            'I finished the tidying I had agreed to do.',
          ),
          CompanionText(
            '他們也照約好的來幫忙。',
            'And they helped with what we had agreed.',
          ),
          CompanionText(
            '後來，還一起吃了點東西。',
            'Afterward, we had something to eat together.',
          ),
          CompanionText(
            '沒有全部自己來，也過得好。',
            "It went well, even though I didn't do everything alone.",
          ),
        ],
        choices: [
          CompanionChoice(
            id: 'story_09_together_glad',
            label: CompanionText('聽起來過得滿好的。', 'That sounds like a nice visit.'),
            emotion: MascotEmotion.smile,
            replies: [
              CompanionText(
                '嗯。這次比較能好好聊天。',
                'Mm. This time, I could enjoy talking with them.',
              ),
            ],
          ),
          CompanionChoice(
            id: 'story_09_together_early',
            label: CompanionText(
              '有提早說出需要什麼。',
              'You told them what you needed in time.', // units-ok: English preposition.
            ),
            emotion: MascotEmotion.smile,
            replies: [
              CompanionText(
                '對。比一直假裝沒事輕鬆。',
                'Yes. Easier than pretending everything was fine.',
              ),
            ],
          ),
          CompanionChoice(
            id: 'story_09_together_relate',
            label: CompanionText(
              '我有時候也不太敢求助。',
              'I find it hard to ask for help sometimes.',
            ),
            replies: [
              CompanionText(
                '嗯。開口前，也想了很久。',
                'Mm. I thought about it for quite a while first.',
              ),
              CompanionText('只是這次，真的有說出來。', 'But this time, I did say it.'),
            ],
          ),
        ],
      ),
    ],
  ),
  CompanionEpisode(
    id: 'story_10',
    day: 53,
    kind: CompanionStoryKind.main,
    title: CompanionText('那天也有開心的事', 'A Happy Part of That Day'),
    beats: [
      CompanionBeat(
        id: 'story_10_memory',
        emotion: MascotEmotion.smile,
        lines: [
          CompanionText(
            '又想起小麥的一件事。',
            'I remembered something else about Xiaomai.',
          ),
          CompanionText(
            '有次，牠把食物藏得很仔細。',
            'Once, my little friend hid some food very carefully.',
          ),
          CompanionText('藏好之後，又回去看了一次。', 'Then went back for another look.'),
        ],
      ),
      CompanionBeat(
        id: 'story_10_laugh',
        lines: [
          CompanionText(
            '那時覺得，牠好認真。',
            'I remember thinking how serious Xiaomai looked.',
          ),
          CompanionText(
            '剛才想到，忍不住笑了一下。',
            'I smiled a little when I remembered it.',
          ),
          CompanionText(
            '然後又怕，這樣像忘記了牠。',
            'Then I worried that smiling meant I had forgotten my friend.',
          ),
        ],
      ),
      CompanionBeat(
        id: 'story_10_remember',
        lines: [
          CompanionText('可是，那天真的很開心。', 'But that really was a happy day.'),
          CompanionText('想把那個樣子也記住。', 'I want to remember that part, too.'),
          CompanionText('不只記得最後的難過。', 'Not only the sadness at the end.'),
        ],
        choices: [
          CompanionChoice(
            id: 'story_10_remember_tell',
            label: CompanionText(
              '我也想聽這樣的小麥。',
              "I'd like to hear about that side of Xiaomai, too.",
            ),
            emotion: MascotEmotion.smile,
            replies: [
              CompanionText(
                '嗯。原來還有好多可以說。',
                "Mm. There's still so much I could tell you.",
              ),
            ],
          ),
          CompanionChoice(
            id: 'story_10_remember_both',
            label: CompanionText(
              '想念的時候，也會想到開心的事。',
              'Missing someone can bring back happy memories, too.',
            ),
            replies: [
              CompanionText(
                '嗯。笑了一下，還是會想牠。',
                'Mm. I can smile and still miss my friend.',
              ),
            ],
          ),
          CompanionChoice(
            id: 'story_10_remember_listen',
            label: CompanionText('我就先聽你說。', "I'll listen."),
            emotion: MascotEmotion.smile,
            replies: [
              CompanionText(
                '好。今天，想記得這一段。',
                'Okay. Today, I want to remember this part.',
              ),
            ],
          ),
        ],
      ),
    ],
  ),
  CompanionEpisode(
    id: 'story_11',
    day: 62,
    kind: CompanionStoryKind.main,
    title: CompanionText('想回去的理由', 'A Reason to Go Back'),
    beats: [
      CompanionBeat(
        id: 'story_11_school',
        lines: [
          CompanionText(
            '最近，開始想念學校的事。',
            "Lately, I've started missing things about school.",
          ),
          CompanionText('有些課，原本很喜歡。', 'There were classes I really liked.'),
          CompanionText('也想把沒學完的接下去。', "I'd like to pick up where I left off."),
        ],
      ),
      CompanionBeat(
        id: 'story_11_support',
        lines: [
          CompanionText(
            '以前欺負我的事，學校處理好了。',
            'The school has dealt with the bullying that happened before.',
          ),
          CompanionText(
            '也知道有事時，可以找誰幫忙。',
            'And I know who I can turn to if I need help.',
          ),
          CompanionText(
            '不是叫我自己忍過去。',
            "I'm not being asked to just put up with it.",
          ),
        ],
      ),
      CompanionBeat(
        id: 'story_11_decision',
        emotion: MascotEmotion.expect,
        lines: [
          CompanionText('所以想回原本的學校看看。', "So I'd like to visit my old school."),
          CompanionText('先約了短短的一次見面。', "We've arranged a short meeting first."),
          CompanionText(
            '還是會怕，但這次是自己想去。',
            "I'm still scared. But this time, I want to go.",
          ),
        ],
        choices: [
          CompanionChoice(
            id: 'story_11_decision_want',
            label: CompanionText(
              '你有想回去的理由。',
              'You have your own reasons for going back.',
            ),
            emotion: MascotEmotion.smile,
            replies: [
              CompanionText('嗯。想再繼續學下去。', 'Mm. I want to keep learning.'),
            ],
          ),
          CompanionChoice(
            id: 'story_11_decision_nervous',
            label: CompanionText(
              '緊張的話，先準備一下？',
              'Want to prepare a little if you feel nervous?',
            ),
            replies: [
              CompanionText(
                '嗯，先記下想問的事。',
                "Yes. I'll write down what I want to ask.",
              ),
              CompanionText(
                '也會再確認有事能找誰。',
                "And I'll check who I can go to for help.",
              ),
            ],
          ),
          CompanionChoice(
            id: 'story_11_decision_listen',
            label: CompanionText(
              '我想聽你之後的感覺。',
              "I'd like to hear how it feels afterward.",
            ),
            emotion: MascotEmotion.smile,
            replies: [
              CompanionText(
                '好。等自己試過，再跟你說。',
                "Okay. I'll tell you after I've tried.",
              ),
            ],
          ),
        ],
      ),
    ],
  ),
  CompanionEpisode(
    id: 'story_12',
    day: 72,
    kind: CompanionStoryKind.main,
    title: CompanionText('改成一小段', 'A Smaller Step'),
    beats: [
      CompanionBeat(
        id: 'story_12_visit',
        lines: [
          CompanionText(
            '去看了回學校的路。',
            'I went to check the route back to school.',
          ),
          CompanionText(
            '那附近，比想像中熱鬧。',
            'It was busier around there than I expected.',
          ),
          CompanionText(
            '才待一下，就覺得有點累。',
            'I felt tired after only a little while.',
          ),
        ],
      ),
      CompanionBeat(
        id: 'story_12_adjust',
        lines: [
          CompanionText(
            '本來想硬撐，把準備全做完。',
            'I wanted to push through and finish all the preparations.',
          ),
          CompanionText('後來先找了安靜的地方。', 'Then I found somewhere quiet first.'),
          CompanionText('也把見面改約得短一點。', 'I also arranged a shorter meeting.'),
        ],
      ),
      CompanionBeat(
        id: 'story_12_still_a_step',
        lines: [
          CompanionText(
            '有再確認時間，和能找誰幫忙。',
            'I checked the time and who I could ask for help.',
          ),
          CompanionText('沒有全部照原本的計畫。', "It didn't all go as I first planned."),
          CompanionText(
            '但需要知道的，還是問到了。',
            'But I still found out what I needed to know.',
          ),
          CompanionText(
            '這次，沒有只把話吞回去。',
            "This time, I didn't keep everything to myself.",
          ),
        ],
        choices: [
          CompanionChoice(
            id: 'story_12_still_a_step_adjusted',
            label: CompanionText(
              '你有把需要調整的說出來。',
              'You said what needed to change.',
            ),
            emotion: MascotEmotion.smile,
            replies: [
              CompanionText(
                '嗯。說完之後，比較踏實。',
                'Mm. I felt more settled after saying it.',
              ),
            ],
          ),
          CompanionChoice(
            id: 'story_12_still_a_step_rest',
            label: CompanionText('現在先休息一下？', 'How about a rest now?'),
            replies: [
              CompanionText('好。今天先做到這裡。', "Okay. That's enough for today."),
            ],
          ),
          CompanionChoice(
            id: 'story_12_still_a_step_familiar',
            label: CompanionText(
              '我也常常要邊做邊調整。',
              'I often need to adjust things as I go, too.',
            ),
            replies: [
              CompanionText('原來，你也會。', 'Oh, you too.'),
              CompanionText(
                '不是每次都能先想好全部。',
                "We can't always work everything out in advance.", // units-ok: English preposition.
              ),
            ],
          ),
        ],
      ),
    ],
  ),
  CompanionEpisode(
    id: 'story_13',
    day: 82,
    kind: CompanionStoryKind.main,
    title: CompanionText('帶著自己的步調進去', 'Going at My Own Pace'),
    beats: [
      CompanionBeat(
        id: 'story_13_back',
        lines: [
          CompanionText('去學校見過面了。', 'I went to the meeting at school.'),
          CompanionText(
            '出門前，還練習了第一句。',
            'I still practiced my first sentence before leaving.',
          ),
          CompanionText(
            '走進去時，心跳很快。',
            'My heart was beating fast when I went in.', // units-ok: English preposition.
          ),
        ],
      ),
      CompanionBeat(
        id: 'story_13_voice',
        emotion: MascotEmotion.expect,
        lines: [
          CompanionText(
            '有些地方，沒聽得很清楚。',
            'There were things I had trouble following.',
          ),
          CompanionText('就請對方說慢一點。', 'So I asked them to slow down a little.'),
          CompanionText(
            '也說了，想慢慢回去上課。',
            'I also said I wanted to start attending classes gradually.',
          ),
        ],
      ),
      CompanionBeat(
        id: 'story_13_after',
        emotion: MascotEmotion.smile,
        lines: [
          CompanionText(
            '沒有突然變得很會聊天。',
            "I didn't suddenly become good at chatting.",
          ),
          CompanionText('不過，想說的有說出來。', 'But I said what I wanted to say.'),
          CompanionText(
            '回來有點累，也有點開心。',
            'I came home a little tired, and a little happy.',
          ),
        ],
        choices: [
          CompanionChoice(
            id: 'story_13_after_happy',
            label: CompanionText('替你開心。', "I'm happy for you."),
            emotion: MascotEmotion.smile,
            replies: [
              CompanionText(
                '嗯。想先把這份開心留一下。',
                'Mm. I want to enjoy this feeling for a bit.',
              ),
            ],
          ),
          CompanionChoice(
            id: 'story_13_after_voice',
            label: CompanionText(
              '你有照自己的步調說清楚。',
              'You said what you needed, at your own pace.',
            ),
            emotion: MascotEmotion.smile,
            replies: [
              CompanionText(
                '對。慢一點，還是有說完。',
                'Yes. It took time, but I got there.',
              ),
            ],
          ),
          CompanionChoice(
            id: 'story_13_after_rest',
            label: CompanionText(
              '回來就先歇一會兒。',
              "Have a rest now that you're home.",
            ),
            emotion: MascotEmotion.smile,
            replies: [
              CompanionText(
                '好。終於可以放鬆一下了。',
                'Okay. I can finally relax a little.',
              ),
            ],
          ),
        ],
      ),
    ],
  ),
  CompanionEpisode(
    id: 'story_14',
    day: 90,
    kind: CompanionStoryKind.main,
    title: CompanionText('不用把話說滿', 'No Need to Fill the Silence'),
    beats: [
      CompanionBeat(
        id: 'story_14_first_meeting',
        lines: [
          CompanionText(
            '剛認識時，我有點怕。',
            'When we first met, I was a little scared.',
          ),
          CompanionText(
            '怕你覺得，跟我待著很無聊。',
            "I worried you'd find me boring to be around.",
          ),
          CompanionText(
            '所以，一直想找話說。',
            'So I kept trying to think of things to say.',
          ),
        ],
      ),
      CompanionBeat(
        id: 'story_14_myself',
        emotion: MascotEmotion.smile,
        lines: [
          CompanionText('現在，還是比較內向。', "I'm still more of an introvert."),
          CompanionText(
            '跟人相處久了，也會累。',
            'Being around people for a while still tires me out.',
          ),
          CompanionText(
            '但想說的話，敢慢慢說了。',
            "But I'm learning to say what matters to me.",
          ),
          CompanionText(
            '不用變成別人，也能一起生活。',
            'I can be close to people without becoming someone else.',
          ),
        ],
      ),
      CompanionBeat(
        id: 'story_14_home',
        emotion: MascotEmotion.smile,
        lines: [
          CompanionText('越來越喜歡這個家了。', "I've grown to love this home."),
          CompanionText('今天有點累。', "I'm a little tired today."),
          CompanionText(
            '可以陪我安靜坐一下嗎？',
            'Would you sit quietly with me for a bit?',
          ),
        ],
        choices: [
          CompanionChoice(
            id: 'story_14_home_together',
            label: CompanionText('好，我也想休息一下。', "Yes. I'd like a rest, too."),
            emotion: MascotEmotion.smile,
            replies: [
              CompanionText('那就一起。', "Then let's rest together."),
              CompanionText('不用想話題。', 'No need to think of something to say.'),
            ],
          ),
          CompanionChoice(
            id: 'story_14_home_quiet',
            label: CompanionText(
              '你不用一直找話說。',
              "You don't have to keep finding things to say.",
            ),
            emotion: MascotEmotion.smile,
            replies: [
              CompanionText('嗯。', 'Mm.'),
              CompanionText('安靜一點，也很好。', 'Quiet is nice, too.'),
            ],
          ),
          CompanionChoice(
            id: 'story_14_home_later',
            label: CompanionText(
              '我先去忙，晚點再來。',
              "I need to go. I'll come back later.",
            ),
            emotion: MascotEmotion.smile,
            replies: [
              CompanionText('好。你先忙。', 'Okay. Go do what you need to do.'),
              CompanionText('晚點見。', 'See you later.'),
            ],
          ),
        ],
      ),
    ],
  ),
];

CompanionEpisode? companionEpisodeById(String id) {
  for (final episode in companionEpisodes) {
    if (episode.id == id) return episode;
  }
  return null;
}
