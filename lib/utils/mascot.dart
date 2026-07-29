// 兔咪角色資料層：情緒、情境、主要互動台詞、展開狀態。
//
// 人設參考 docs/tumi_character_guide.md；全 app 對話與觸發索引見
// docs/tumi_dialogue_catalog.md。這裡集中一般互動台詞，劇情、onboarding
// 與小遊戲等專屬文案仍跟著各功能的資料與畫面維護。

import 'dart:async';
import 'dart:math';

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'prefs_keys.dart';
import 'sfx_service.dart';

/// 兔咪的名字（玩家可自訂）與文案插值。
///
/// **三種聲音規則**（見 docs/tumi_character_guide.md）：
/// - 兔咪自己說話（對話泡泡、繪本回憶）→ 省略主詞或用「我」，**永不自稱名字**
/// - 系統提到牠（解鎖提示、區塊副標、說明文案）→ 用 `{name}` 佔位，經 [fill] 帶入
/// - 系統講功能／數值（建議水量、按鈕）→ 完全不提牠
///
/// 佔位符刻意用 ARB 的 `{name}` 格式，未來搬 i18n 不用再改一次文案。
///
/// 新程式碼一律用這個當名字來源；散在各頁的 `prefs.getString(mascotName)`
/// 是舊寫法（正是硬編碼「兔咪」的成因），改到那頁行為時順路換過來。
abstract final class MascotName {
  /// 最後防線：`load` 在 `runApp` 之前跑，那時還沒有 context 可以問 l10n。
  static const String fallback = '兔咪';

  /// 使用者沒取過名字時要顯示的名字。語言不同預設名也不同（中文「兔咪」／
  /// 英文 "Tumi"），所以 l10n 就緒後由 [applyDefaultName] 覆寫。
  static String _defaultName = fallback;

  /// 目前顯示的名字是預設值（使用者還沒取過名字）。
  static bool _usingDefault = true;

  /// 目前名字。改名後呼叫 [load] 或 [set] 會通知所有監聽者。
  static final ValueNotifier<String> current = ValueNotifier<String>(fallback);

  static String get value => current.value;

  static Future<void> load([SharedPreferences? prefs]) async {
    final p = prefs ?? await SharedPreferences.getInstance();
    set(p.getString(PrefsKeys.mascotName));
  }

  static void set(String? name) {
    final trimmed = name?.trim();
    _usingDefault = trimmed == null || trimmed.isEmpty;
    current.value = _usingDefault ? _defaultName : trimmed!;
  }

  /// 掛上這個語言的預設名（`l10n.mascotDefaultName`）。使用者已經取過名字就
  /// 不動他的名字，只換掉「還沒取名」時要顯示的那個。
  ///
  /// 呼叫端在 `MaterialApp.builder` 裡（拿得到 Localizations 的最外層），
  /// 語言改變時會再跑一次。
  ///
  /// 那裡是 build 期間，直接改 notifier 會讓正在 build 的監聽者
  /// `markNeedsBuild`，所以 build 中要延到這一幀畫完再改；不在 build 中
  /// （測試、或 l10n 之外的呼叫）就直接更新，免得等一個永遠不會來的 frame。
  static void applyDefaultName(String name) {
    if (_defaultName == name) return;
    _defaultName = name;
    if (!_usingDefault) return;
    final phase = SchedulerBinding.instance.schedulerPhase;
    final building =
        phase == SchedulerPhase.persistentCallbacks ||
        phase == SchedulerPhase.midFrameMicrotasks ||
        phase == SchedulerPhase.transientCallbacks;
    if (!building) {
      current.value = _defaultName;
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_usingDefault) current.value = _defaultName;
    });
  }

  /// 把文案模板裡的 `{name}` 換成目前名字。
  static String fill(String template) =>
      template.replaceAll('{name}', current.value);
}

// 兔咪情緒。每個情緒 = assets/mascot/core/tumi_<assetKey>.png 一張 CG 立繪。
//
// 基礎圖按「身體姿勢／手的高度」分（兔咪嘴巴不動，情緒靠眼/耳/手表達；
// 更細的情境之後再靠情緒泡泡 overlay 疊加，不必每種情緒各畫一張）。
// 快樂梯度＝手的高度：smile(手垂) → happy(手胸前) → popHappy(雙手高舉)。
// expect 與 happy 共用「手胸前」身體，只差眼睛（圓眼/笑眼）。
// 角色原則見 docs/tumi_character_guide.md；正式狀態以本 enum 為單一真相來源。
enum MascotEmotion {
  neutralFront('neutral_front'), // 站姿中性：待機、招呼
  sleep('sleep'), // 打瞌睡：還沒開始、懶懶等你
  wake('wake'), // 揉眼剛醒：被喚醒、剛開始動
  expect('expect'), // 手胸前＋圓眼：開始期待、進度在動
  smile('smile'), // 手垂＋笑眼：完成一件、安心陪跑
  happy('happy'), // 手胸前＋笑眼：今日全部完成
  popHappy('pop_happy'), // 雙手高舉雀躍：大慶祝
  streak('streak'), // 連續達成：雀躍（同 pop 美術，靠台詞/特效區分）
  sad('sad'), // 心疼低落：撤銷、中斷（暫用 V1，V2 尚無此圖）
  night('night'), // 夜晚閉眼：深夜小聲
  invite('invite'), // 伸手邀請：空狀態、邀請新增第一個習慣
  question('question'); // 歪頭疑問：溫柔提醒、喝水過量

  final String assetKey;
  const MascotEmotion(this.assetKey);

  String get assetPath => 'assets/mascot/core/tumi_$assetKey.png';

  // 有閉眼差分圖（tumi_<key>_blink.png）的情緒。
  // 眨眼動畫由 MascotStage 處理；新增差分圖後把情緒加進這裡即可生效。
  static const Set<MascotEmotion> _hasBlink = {MascotEmotion.neutralFront};

  /// 由 asset 路徑反查對應的閉眼差分；沒有差分圖回 null（不眨眼）。
  /// 給只拿得到路徑字串的 widget（MascotStage）用。
  ///
  /// **比對檔名而非完整路徑**，所以穿造型（`assets/mascot/<skin>/…`）時會找
  /// 同資料夾的差分，不會退回 core 的原始造型。前提是**每套造型都要跟 core
  /// 一樣完整**——`test/wardrobe_skin_assets_test.dart` 會守住這件事。
  static String? blinkAssetForPath(String assetPath) {
    for (final e in _hasBlink) {
      if (assetPath.endsWith('/tumi_${e.assetKey}.png')) {
        return assetPath.replaceFirst('.png', '_blink.png');
      }
    }
    return null;
  }

  // 摸頭「瞇眼享受」通用差分（tumi_pet_bliss.png，手垂＋幸福瞇眼）。
  // 圖檔進 repo 後把這個旗標改 true 即全表情生效。
  //
  // 2026-07-25 評估：**這張圖非必要，目前刻意不做。** 摸頭會把表情切成
  // smile（手垂＋笑眼），笑眼本來就是彎的，看起來已經像被摸到瞇眼享受；
  // 補 bliss 只多一階情緒層次（開心 → 融化），卻要讓每一套造型都多生一張
  // （造型＝core 的完整鏡像）。詳見 docs/pending_assets.md 第 1 節。
  static const bool _petBlissReady = false;

  /// 被摸夠久時的「瞇眼享受」差分；回 null 代表這張立繪摸了不閉眼。
  ///
  /// 穿造型時取**同資料夾**的 `tumi_pet_bliss.png`（每套造型一張，通用於
  /// 所有情緒），不會退回 core 的原始造型。
  static String? petBlissAssetForPath(String assetPath) {
    if (_petBlissReady) {
      final idx = assetPath.lastIndexOf('/');
      if (idx != -1) {
        return '${assetPath.substring(0, idx)}/tumi_pet_bliss.png';
      }
    }
    return blinkAssetForPath(assetPath);
  }
}

// 兔咪陪伴情境。每個情境對應一組台詞與預設情緒。
// 之後想新增/修改台詞，只改下方 [_lines] 這個 map 就好。
enum MascotContext {
  openApp,
  // 專注計時開始／從休息回到專注（不能借用 openApp 問候）
  focusStarted,
  notStarted,
  completedOne,
  halfDone,
  allDone,
  streak,
  undone,
  night,
  // 點兔咪本身的隨機反應
  tapReaction,
  // 摸兔咪頭時的反應
  headPet,
  // 充電互動：長按兔咪蓄力、放開（或蓄滿）爆發大跳
  energize,
  // 骰子彩蛋的三種結果有自己的表情／符號／聲音語意，不能借用
  // tapReaction，否則稱讚或認輸時也會冒問號並播放疑問聲。
  diceMascotWin,
  diceMascotLoss,
  diceTie,
  // 還沒有任何習慣時（空狀態）
  emptyHabits,
  // 喝水高量提醒（目前 >=4L/day）：兔咪驚訝 + 溫和提示，
  // 但不擋使用者繼續紀錄（硬擋在 6L）。
  overhydration,
}

// 頭頂情緒泡泡：疊在兔咪頭頂上方的漫畫式小符號（愛心／音符／星／汗滴／
// Zzz／驚嘆／問號）。CG 立繪只畫純角色，泡泡一律 Flutter 端 CustomPainter
// 畫成 overlay（同 sparkle／pet 波紋那套），可隨頁面主色上色。
//
// 每次情緒事件（interact / setForContext）會依情境帶一顆泡泡，演出一次後淡出；
// 中性待機與空狀態刻意不冒，避免畫面太吵。
// 這裡只管「哪個情境冒哪顆」（改 [forContext] 這個 switch）；
// 每顆泡泡的外觀／配色／動態個性宣告在 widgets/mascot_bubbles.dart 的註冊表。
enum EmotionBubble {
  heart, // 愛心：摸頭
  note, // 音符：完成、進度在動
  star, // 星閃：今日全完成、連續達成
  sweat, // 汗滴：撤銷、失落
  zzz, // 打瞌睡：還沒開始、夜晚
  // 驚嘆：目前沒有情境使用（喝水過量已改用溫柔的 question）。
  // 保留 spec 給未來真正需要「警示」語氣的情境；兔咪的日常提醒不該用它。
  exclaim,
  question; // 問號：點兔咪的疑問反應

  /// 情境 → 泡泡；回 null 代表這個情境不冒泡泡（留白）。
  static EmotionBubble? forContext(MascotContext c) {
    switch (c) {
      case MascotContext.headPet:
        return EmotionBubble.heart;
      case MascotContext.completedOne:
      case MascotContext.halfDone:
        return EmotionBubble.note;
      case MascotContext.allDone:
      case MascotContext.streak:
      case MascotContext.energize:
      case MascotContext.diceMascotWin:
        return EmotionBubble.star;
      // 骰子輸了配汗滴合理（懊惱）；撤銷則不冒泡泡——汗滴在漫畫語彙是
      // 「尷尬／無奈」，跟 sad 的心疼互相打架，而且撤銷是低調時刻，
      // 冒符號反而吵。
      case MascotContext.diceMascotLoss:
        return EmotionBubble.sweat;
      case MascotContext.notStarted:
      case MascotContext.night:
        return EmotionBubble.zzz;
      // 喝水過量用歪頭疑問「溫柔提醒」，泡泡就不能是警示用的驚嘆號，
      // 否則表情與符號反著走
      case MascotContext.overhydration:
      case MascotContext.tapReaction:
        return EmotionBubble.question;
      // diceTie 維持音符：在對決畫面裡問號的語意是「點到兔咪」的反應，
      // 會被誤讀成互動而不是賽果（見 mascot_test.dart 的 isNot(question) 斷言）
      case MascotContext.diceTie:
        return EmotionBubble.note;
      // 專注剛開始是「安靜下來」，不是進度在動；留白比音符貼切
      case MascotContext.undone:
      case MascotContext.focusStarted:
      case MascotContext.openApp:
      case MascotContext.emptyHabits:
        return null;
    }
  }
}

// 各情境對應的預設情緒（呼叫端可以另外覆寫）。
const Map<MascotContext, MascotEmotion> _defaultEmotion = {
  MascotContext.openApp: MascotEmotion.neutralFront,
  MascotContext.focusStarted: MascotEmotion.expect,
  MascotContext.notStarted: MascotEmotion.sleep,
  MascotContext.completedOne: MascotEmotion.smile,
  MascotContext.halfDone: MascotEmotion.expect,
  MascotContext.allDone: MascotEmotion.happy,
  MascotContext.streak: MascotEmotion.streak,
  MascotContext.undone: MascotEmotion.sad,
  MascotContext.night: MascotEmotion.night,
  MascotContext.tapReaction: MascotEmotion.neutralFront,
  MascotContext.headPet: MascotEmotion.smile,
  // 充電爆發：雙手高舉雀躍，正好接住「蓄力→放開」的演出弧線
  MascotContext.energize: MascotEmotion.popHappy,
  MascotContext.diceMascotWin: MascotEmotion.popHappy,
  MascotContext.diceMascotLoss: MascotEmotion.expect,
  MascotContext.diceTie: MascotEmotion.expect,
  // 空狀態用「伸手邀請」姿勢，比中性更主動地邀使用者新增第一個習慣
  MascotContext.emptyHabits: MascotEmotion.invite,
  // 喝水過量改用「歪頭疑問」溫柔提醒，而非心疼的 sad
  MascotContext.overhydration: MascotEmotion.question,
};

// ─────────────────────────────────────────────────────────────
//  📝 兔咪台詞庫
//  -----------------------------------------------------------
//  首頁、喝水、計時等共用互動的台詞來源。功能專屬台詞的
//  實際位置與觸發條件統一記在 docs/tumi_dialogue_catalog.md。
//
//  每個 key（MascotContext）對應一個台詞池，呼叫端拿其中一句使用。
//  - lineFor(ctx, seed): 同 seed 拿固定一句（避免 build 時抖動）
//  - randomLineFor(ctx): 隨機抽一句
//
//  人設參考 docs/tumi_character_guide.md。
// ─────────────────────────────────────────────────────────────
const Map<MascotContext, List<String>> _lines = {
  // ── 打開 app / 一般招呼 ──
  MascotContext.openApp: ['嗯...你來了。', '啊，是你。', '剛剛在打瞌睡。', '醒了醒了。'],

  // ── 專注計時開始／重新進入專注 ──
  MascotContext.focusStarted: ['好，先專心一下。', '時間開始了，慢慢來。', '先做這一小段就好。'],

  // ── 今天還沒開始做任何習慣 ──
  MascotContext.notStarted: [
    '還沒開始也沒關係。',
    '嗯...要開始了嗎？',
    '今天還很長。',
    '一件就好。',
    '哪一件最簡單？',
  ],

  // ── 完成了第一個 / 任一個習慣 ──
  MascotContext.completedOne: ['這件做完了。', '剛剛那一小步，很好。', '又多完成一件了。', '嗯，這樣就很好。'],

  // ── 完成過一半 ──
  MascotContext.halfDone: ['已經一半了。', '你做到不少了。', '我有點醒了。', '剩下的等你。'],

  // ── 今天全部完成 ──
  // 「很棒」是評分，換成陳述：角色原則是「不是評分，是看見」。
  MascotContext.allDone: ['全部完成了。', '今天都做完了。', '可以好好休息了。', '我替你開心。'],

  // ── 連續達標一段時間（streak >= 7） ──
  MascotContext.streak: ['連續好多天了。', '你一直有回來。', '我有點感動。', '這些天，你是一天一天走來的。'],

  // ── 取消已完成的習慣（撤銷感） ──
  // 撤銷最常見的原因是誤點，不是「慢」或「累」。舊版「今天慢一點也可以」
  // 「先休息一下也沒關係」在誤點時等於安慰一個不存在的情緒，改成單純確認。
  MascotContext.undone: ['取消這一筆也沒關係。', '嗯，改掉了。', '需要的話，等一下再來。', '隨時可以再勾回來。'],

  // ── 夜晚（22:00 ~ 06:00） ──
  MascotContext.night: ['很晚了，我小聲一點。', '今天辛苦了。', '如果累了，也可以休息。', '明天再一起慢慢來。'],

  // ── 使用者點兔咪本身的隨機反應 ──
  // 點兔咪是「想跟牠互動」，不是來討任務的：這組只放「反應」，
  // 不放建議或催促（舊版混了「今天也慢慢來」「先做一點點也可以」）。
  MascotContext.tapReaction: [
    '嗯？',
    '你在找我嗎？',
    '怎麼了嗎？',
    '耳朵被碰到了。',
    '眼睛睜開了。',
    '你回來了，真好。',
    '剛剛在發呆。',
    '嗯，我有看到你。',
  ],

  // ── 摸頭反應 ──
  MascotContext.headPet: [
    '嗯...舒服。',
    '耳朵旁邊癢癢的。',
    '還想再摸。',
    '我有點開心。',
    // 舊版「好，我乖乖的。」有服從／寵物感；兔咪是陪伴者不是被馴養的
    '頭低下來了。',
  ],

  // ── 充電互動（長按蓄力放開）──
  // speaksFor 為 false，平常只靠星星泡泡＋歡呼語音；
  // 台詞池備著給之後「明確帶 speech」的場合（登入禮、活動）取用。
  // 兔咪不是元氣型角色，充電也用牠自己的音量講（舊版「充飽電了！」
  // 「嗯！力氣滿滿。」是一般吉祥物的元氣宣言）
  MascotContext.energize: ['嗯...充飽了。', '有力氣了。', '謝謝你幫我打氣。', '好像可以跳得更高了。'],

  // ── 骰子彩蛋結果 ──
  // 顯示時由小遊戲明確帶 speech；放在角色資料層，讓台詞、表情符號與
  // 聲音情境維持同一份可稽核來源。
  MascotContext.diceMascotWin: ['我贏了…嘿嘿。', '這次是我的。', '骰子今天站我這邊。'],
  MascotContext.diceMascotLoss: ['你贏了…好厲害。', '輸了…再來一次好不好？', '嗯…下次換我贏。'],
  MascotContext.diceTie: ['一樣大。', '平手…再來一次。', '嗯？同點。'],

  // ── 還沒新增任何習慣（空狀態） ──
  MascotContext.emptyHabits: ['要不要先放一個小習慣？', '從一個小小的開始。', '不用很多，一個就好。'],

  // ── 喝水高量提醒（目前 >=4L/day）──
  // 兔咪只負責「我看到了」，不下指令也不給健康建議——那是 UI 的職責
  // （角色原則：醫療性建議由 UI 或正式說明承擔）。舊版五句裡有三句
  // 是命令句、一句是「水量」這種數據詞的系統通知口吻。
  MascotContext.overhydration: [
    '欸…今天喝好多。',
    '嗯？今天的水…有點多欸。',
    '我看著你喝了好多。',
    '欸…你今天喝有點多了。',
  ],
};

// 首頁點兔咪時的情境回應。這組比一般 tapReaction 更像「兔咪看見今天的狀態」：
// 不給指令、不評分，只把使用者當下的進度接住。
const Map<MascotContext, List<String>> _homeTapLines = {
  MascotContext.emptyHabits: [
    '我們可以先放一件很小的事。',
    '一件就好。\n從最小的開始。',
    '你想養成什麼，我會陪著記。',
  ],
  MascotContext.notStarted: [
    '還沒開始也沒關係。',
    '先挑最小的那一件就好。',
    '今天還很長。',
    '要不要從最簡單那個開始？',
  ],
  MascotContext.completedOne: ['剛剛那一件，做完了。', '已經開始了。\n就從這裡慢慢來。', '你有往前一點點了。'],
  MascotContext.halfDone: ['你已經做到一半了。', '剩下的等你。', '我有點醒了。\n你做得不錯。'],
  MascotContext.allDone: ['今天的份已經完成了。', '可以安心休息一下。', '你有把今天照顧好。'],
  MascotContext.streak: ['你已經連續回來好多天了。', '這段時間，我都有記得。', '這些都是一天一天累積起來的。'],
  // 「不用硬撐」同樣預設了使用者在硬撐；撤銷多半只是誤點
  MascotContext.undone: ['取消這一筆也沒關係。', '今天可以重新調整。', '嗯，我改掉了。'],
  MascotContext.night: ['很晚了，我小聲一點。', '今天慢慢收尾就好。', '如果累了，明天再繼續也可以。'],
};

class MascotLines {
  static MascotEmotion emotionFor(MascotContext c) =>
      _defaultEmotion[c] ?? MascotEmotion.neutralFront;

  /// 從情境抽一句台詞。同一個 (context, seed) 會回固定結果，
  /// 避免每次 rebuild 換句話讓使用者覺得抖。
  static String lineFor(MascotContext c, {int seed = 0}) {
    final list = linesFor(c);
    if (list.isEmpty) return '...';
    return list[seed.abs() % list.length];
  }

  /// 隨機抽一句（用在「開 app 時換句話講」這種場景）。
  static String randomLineFor(MascotContext c) {
    final list = linesFor(c);
    if (list.isEmpty) return '...';
    return list[Random().nextInt(list.length)];
  }

  /// 帶件數的具體回應：「我有看到」只是宣告自己在看，講得出今天第幾件
  /// 才是證明真的在數。用 done 取餘數挑句子，所以同一個數字永遠同一句
  /// （不會 rebuild 時抖動），換數字才換句。
  ///
  /// 刻意不講總數（「3/5」是系統通知口吻，兔咪只數你做到的）。
  static String doneCountLine(int doneToday) {
    if (doneToday <= 1) return '今天第一件。';
    return switch (doneToday % 3) {
      0 => '數到第 $doneToday 件了。',
      1 => '已經 $doneToday 件了。',
      _ => '今天第 $doneToday 件。',
    };
  }

  /// 首頁點兔咪：依目前進度抽一句更貼身的回應。
  static String randomHomeTapLineFor(MascotContext c) {
    final list = homeTapLinesFor(c);
    if (list.isEmpty) return '...';
    return list[Random().nextInt(list.length)];
  }

  /// 取得指定情境的完整台詞池；給測試、開發工具與文案審查使用。
  static List<String> linesFor(MascotContext c) =>
      List<String>.unmodifiable(_lines[c] ?? const ['...']);

  /// 取得首頁點兔咪的完整情境回應池。
  static List<String> homeTapLinesFor(MascotContext c) =>
      List<String>.unmodifiable(
        _homeTapLines[c] ?? _lines[MascotContext.tapReaction] ?? const ['...'],
      );

  /// 這個情境要不要顯示文字台詞（沒明確帶 speech 時才看這裡）。
  ///
  /// false = 只靠頭頂符號泡泡 + 語音 SFX。高頻、純情緒確認的互動
  /// （點兔咪、摸頭、完成單一、過半）走這條，避免兔咪太多話、也省下翻譯量。
  /// true = 文字承載「符號表達不出的聲音」（連勝、撤銷後的安慰、夜晚、邀請）
  /// 或「符號講不清的資訊」（喝水過量提醒）。
  ///
  /// 註：呼叫端若明確帶了 speech（首頁點兔咪、登入禮、衣櫃），一律照顯示，不看這裡。
  static bool speaksFor(MascotContext c) {
    switch (c) {
      case MascotContext.completedOne:
      case MascotContext.halfDone:
      case MascotContext.tapReaction:
      case MascotContext.headPet:
      case MascotContext.energize:
      case MascotContext.diceMascotWin:
      case MascotContext.diceMascotLoss:
      case MascotContext.diceTie:
        return false;
      case MascotContext.openApp:
      case MascotContext.focusStarted:
      case MascotContext.notStarted:
      case MascotContext.allDone:
      case MascotContext.streak:
      case MascotContext.undone:
      case MascotContext.night:
      case MascotContext.emptyHabits:
      case MascotContext.overhydration:
        return true;
    }
  }

  /// 22:00 ~ 06:00 期間，呼叫端可選擇直接用 [MascotContext.night] 覆寫。
  static bool isNightHour([DateTime? now]) {
    final h = (now ?? DateTime.now()).hour;
    return h >= 22 || h < 6;
  }
}

// 兔咪當下表情 + 台詞 的全域狀態。
//
// 設計：兔咪是「一隻跟著你跑的角色」，切換頁面時情緒/台詞不該被重置；
// 只有真的有互動（使用者點了、做了什麼）才會改變。
//
// 用法：
//   - 每個頁面的場景透過 [MascotPersona.current] 讀（ValueListenableBuilder）
//   - 互動時呼叫 [MascotPersona.interact] 推一個新情境
//   - App 冷啟動會呼叫 [MascotPersona.resetToOpening]，從 openApp 抽一句問候
class MascotState {
  final String assetPath;

  /// 要顯示的台詞；null = 這次不講話（只靠頭頂符號泡泡 + SFX）。
  /// 高頻、純情緒確認的情境（點兔咪、摸頭、完成單一）刻意留 null，
  /// 把文字省給「符號表達不出的聲音」或「符號講不清的資訊」。見 [MascotLines.speaksFor]。
  final String? speech;

  /// 這次情緒事件要冒的頭頂泡泡；null = 不冒（中性待機等）。
  final EmotionBubble? bubble;

  /// 泡泡事件序號；同一種泡泡連續觸發時也用它重播動畫。
  final int bubbleTick;

  const MascotState(
    this.assetPath,
    this.speech, {
    this.bubble,
    this.bubbleTick = 0,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MascotState &&
          assetPath == other.assetPath &&
          speech == other.speech &&
          bubble == other.bubble &&
          bubbleTick == other.bubbleTick;

  @override
  int get hashCode => Object.hash(assetPath, speech, bubble, bubbleTick);
}

class MascotPersona {
  static final Random _voiceRandom = Random();

  static final ValueNotifier<MascotState> current = ValueNotifier<MascotState>(
    MascotState(MascotEmotion.neutralFront.assetPath, '嗯...你來了。'),
  );

  // 互動後過多久自動回到中性狀態（避免兔咪一直歡呼/難過）
  static const Duration _revertAfter = Duration(seconds: 10);
  // 一般互動至少停留一小段時間，避免連續打卡時每一下都換圖/換台詞。
  static const Duration _holdDuration = Duration(seconds: 5);
  static Timer? _revertTimer;
  static DateTime? _holdUntil;
  static int _activePriority = 0;
  static int _bubbleSeq = 0;

  /// 互動：根據情境換情緒 + 隨機抽一句台詞。10 秒後自動回神。
  ///
  /// 回傳 false 代表兔咪目前正在停留一個狀態，這次普通互動被忽略。
  static bool interact(MascotContext ctx, {bool force = false}) {
    if (!_canApply(ctx, force: force)) return false;
    _apply(
      MascotState(
        MascotLines.emotionFor(ctx).assetPath,
        MascotLines.speaksFor(ctx) ? MascotLines.randomLineFor(ctx) : null,
        bubble: EmotionBubble.forContext(ctx),
      ),
      ctx,
    );
    return true;
  }

  /// 直接設定（呼叫端自己決定 asset + 台詞）。10 秒後自動回神。
  static bool set(
    String assetPath,
    String speech, {
    bool force = false,
    MascotContext context = MascotContext.openApp,
  }) {
    return setForContext(assetPath, context, speech: speech, force: force);
  }

  /// 用指定情境設定自訂 asset。台詞可交給情境台詞池抽，並套用同一套停留規則。
  static bool setForContext(
    String assetPath,
    MascotContext ctx, {
    String? speech,
    bool force = false,
  }) {
    if (!_canApply(ctx, force: force)) return false;
    // 呼叫端明確帶了 speech 就照顯示；沒帶才看情境要不要講話（[MascotLines.speaksFor]）。
    _apply(
      MascotState(
        assetPath,
        speech ??
            (MascotLines.speaksFor(ctx)
                ? MascotLines.randomLineFor(ctx)
                : null),
        bubble: EmotionBubble.forContext(ctx),
      ),
      ctx,
    );
    return true;
  }

  /// 兔咪被畫面蓋住時（如節拍器運作中）設 true：情緒/台詞照常更新，只是不發聲，
  /// 避免「看不到兔咪卻聽到牠的聲音」的突兀感。
  static bool voiceMuted = false;

  static void _apply(MascotState state, MascotContext ctx) {
    current.value = MascotState(
      state.assetPath,
      state.speech,
      bubble: state.bubble,
      bubbleTick: state.bubble == null ? 0 : ++_bubbleSeq,
    );
    final cue = _voiceCueFor(ctx);
    final now = DateTime.now();
    if (cue != null && !voiceMuted && _voiceAllowed(ctx, now: now)) {
      unawaited(SfxService.instance.play(cue));
      _markVoicePlayed(ctx, now);
    }
    _holdUntil = DateTime.now().add(_holdDuration);
    _activePriority = _priorityOf(ctx);
    _scheduleRevert();
  }

  // ── 語音冷卻 ──
  // 直接互動（點兔咪、摸頭、蓄力跳躍）使用較短的 7 秒 CD，讓使用者
  // 確實感受到回應；打卡等日常事件維持 18 秒，兩組互不互相消耗。
  // 大事件（優先度 >= 20：全完成、連勝、撤銷、喝水過量）不受冷卻限制。
  static const Duration _directVoiceCooldown = Duration(seconds: 7);
  static const Duration _routineVoiceCooldown = Duration(seconds: 18);
  static const int _voiceBypassPriority = 20;
  static DateTime? _lastDirectVoiceAt;
  static DateTime? _lastRoutineVoiceAt;

  static bool _usesDirectVoiceCooldown(MascotContext ctx) {
    return switch (ctx) {
      MascotContext.tapReaction ||
      MascotContext.headPet ||
      MascotContext.energize ||
      MascotContext.diceMascotWin ||
      MascotContext.diceMascotLoss ||
      MascotContext.diceTie => true,
      _ => false,
    };
  }

  static bool _voiceAllowed(MascotContext ctx, {DateTime? now}) {
    if (_priorityOf(ctx) >= _voiceBypassPriority) return true;
    final direct = _usesDirectVoiceCooldown(ctx);
    final last = direct ? _lastDirectVoiceAt : _lastRoutineVoiceAt;
    if (last == null) return true;
    final elapsed = (now ?? DateTime.now()).difference(last);
    final cooldown = direct ? _directVoiceCooldown : _routineVoiceCooldown;
    // 系統時間若往回調，不應讓語音被鎖到時鐘追上舊時間為止。
    return elapsed.isNegative || elapsed >= cooldown;
  }

  static void _markVoicePlayed(MascotContext ctx, DateTime at) {
    if (_usesDirectVoiceCooldown(ctx)) {
      _lastDirectVoiceAt = at;
    } else {
      _lastRoutineVoiceAt = at;
    }
  }

  @visibleForTesting
  static bool debugVoiceAllowedAt(MascotContext ctx, DateTime now) =>
      _voiceAllowed(ctx, now: now);

  @visibleForTesting
  static void debugMarkVoicePlayedAt(MascotContext ctx, DateTime at) =>
      _markVoicePlayed(ctx, at);

  @visibleForTesting
  static void debugResetVoiceCooldowns() {
    _lastDirectVoiceAt = null;
    _lastRoutineVoiceAt = null;
  }

  @visibleForTesting
  static SfxCue debugTapVoiceCueForBucket(int bucket) {
    if (bucket < 0 || bucket >= 10) {
      throw RangeError.range(bucket, 0, 9, 'bucket');
    }
    return _tapVoiceCue(bucket: bucket);
  }

  /// 單點以疑問聲為主，偶爾用確認聲表示有注意到使用者；其他語音保留給
  /// 摸頭、蓄力與關鍵事件，避免互動語意混在一起。
  static SfxCue _tapVoiceCue({int? bucket}) {
    final resolvedBucket = bucket ?? _voiceRandom.nextInt(10);
    return resolvedBucket < 7 ? SfxCue.tumiQuestion : SfxCue.tumiConfirm;
  }

  /// 情境 → 兔咪語音。回 null 代表這個情境保持安靜
  /// （睡著/夜晚出聲反而違和，靠 Zzz 泡泡表達就好）。
  static SfxCue? _voiceCueFor(MascotContext ctx) {
    switch (ctx) {
      // 大慶祝：歡呼（表情 happy / streak 雀躍；充電爆發同款）
      case MascotContext.allDone:
      case MascotContext.streak:
      case MascotContext.energize:
      case MascotContext.diceMascotWin:
        return SfxCue.tumiCheer;
      // 輕聲確認：打卡、進度過半、開場招呼（最高頻，選最短促的）
      case MascotContext.completedOne:
      case MascotContext.halfDone:
      case MascotContext.openApp:
      case MascotContext.focusStarted:
      case MascotContext.diceMascotLoss:
      case MascotContext.diceTie:
        return SfxCue.tumiConfirm;
      // 開心：摸頭（表情 smile）
      case MascotContext.headPet:
        return SfxCue.tumiHappy;
      // 難過：撤銷（表情 sad）
      case MascotContext.undone:
        return SfxCue.tumiSad;
      // 單點：70% 疑問／30% 輕聲確認，保留慢熱感也避免每次都一樣。
      case MascotContext.tapReaction:
        return _tapVoiceCue();
      // 疑問：空狀態、喝水過量（表情 invite / question 歪頭）
      case MascotContext.emptyHabits:
      case MascotContext.overhydration:
        return SfxCue.tumiQuestion;
      // 睡著中不出聲
      case MascotContext.notStarted:
      case MascotContext.night:
        return null;
    }
  }

  static bool _canApply(MascotContext ctx, {required bool force}) {
    if (force) return true;
    final until = _holdUntil;
    if (until == null || DateTime.now().isAfter(until)) return true;
    return _priorityOf(ctx) > _activePriority;
  }

  static int _priorityOf(MascotContext ctx) {
    switch (ctx) {
      // 警告類最高：喝過量比達標還重要，要先講
      case MascotContext.overhydration:
        return 40;
      case MascotContext.allDone:
      case MascotContext.streak:
        return 30;
      case MascotContext.undone:
        return 20;
      case MascotContext.halfDone:
        return 12;
      case MascotContext.completedOne:
        return 10;
      case MascotContext.headPet:
      case MascotContext.energize:
      case MascotContext.diceMascotWin:
      case MascotContext.diceMascotLoss:
      case MascotContext.diceTie:
        return 6;
      case MascotContext.tapReaction:
      case MascotContext.openApp:
      case MascotContext.focusStarted:
      case MascotContext.notStarted:
      case MascotContext.night:
      case MascotContext.emptyHabits:
        return 5;
    }
  }

  /// App 冷啟動：從 openApp 池隨機抽一句問候（每次打開都有變化）。
  /// 已經是中性狀態，不需要安排回神。
  static void resetToOpening() {
    _revertTimer?.cancel();
    _holdUntil = null;
    _activePriority = 0;
    current.value = MascotState(
      MascotLines.emotionFor(MascotContext.openApp).assetPath,
      MascotLines.randomLineFor(MascotContext.openApp),
    );
  }

  /// 回到不帶文字、泡泡或語音的中性待機。
  /// 用在個人化問候取代一般開場，或互動演出自然結束時。
  static void resetToIdle() {
    _revertTimer?.cancel();
    _holdUntil = null;
    _activePriority = 0;
    current.value = MascotState(
      MascotLines.emotionFor(MascotContext.openApp).assetPath,
      null,
    );
  }

  /// 安排 N 秒後回到安靜待機。新互動會 reset 計時。
  ///
  /// 不能在這裡重抽 openApp 問候：否則任何打卡、摸頭或計時事件結束後，
  /// 兔咪都會像剛開 app 一樣突然再說一句。
  static void _scheduleRevert() {
    _revertTimer?.cancel();
    _revertTimer = Timer(_revertAfter, () {
      _holdUntil = null;
      _activePriority = 0;
      current.value = MascotState(
        MascotLines.emotionFor(MascotContext.openApp).assetPath,
        null,
      );
    });
  }
}

// 兔咪面板展開／收合狀態。
//
// 為了讓拖曳能即時跟隨手指（iOS bottom sheet 感），這裡用
// `ValueNotifier<double>`：0.0 = 完全收合、1.0 = 完全展開、中間
// 浮點 = 拖曳過程中的瞬時狀態。
//
// 面板只在本次 App 使用期間記住；每次冷啟動固定展開兔咪區（也就是把下方
// 功能卡收小），避免開場問候與每日足跡幣演出被功能卡遮住。只有教學提示
// 是否看過需要永久化。
class MascotPanelPrefs {
  static final ValueNotifier<double> openValue = ValueNotifier<double>(1.0);
  static final ValueNotifier<bool> hintSeenValue = ValueNotifier<bool>(false);
  static final ValueNotifier<MascotPanelSettleRequest?> settleRequest =
      ValueNotifier<MascotPanelSettleRequest?>(null);
  static int _settleSeq = 0;

  static bool get expanded => openValue.value >= 0.5;
  static bool get hintSeen => hintSeenValue.value;

  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    // 不讀舊版 mascot_panel_expanded：冷啟動一律先露出兔咪。
    openValue.value = 1.0;
    hintSeenValue.value = prefs.getBool(PrefsKeys.mascotPanelHintSeen) ?? false;
  }

  static Future<void> markHintSeen() async {
    if (hintSeenValue.value) return;
    hintSeenValue.value = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(PrefsKeys.mascotPanelHintSeen, true);
  }

  static void requestSettle(double target) {
    settleRequest.value = MascotPanelSettleRequest(
      _settleSeq++,
      target.clamp(0.0, 1.0).toDouble(),
    );
  }

  static void requestCollapsed() => requestSettle(0.0);

  /// 展開兔咪面板＝把功能卡收回縮小狀態（設定頁「完成」鈕用）。
  static void requestExpanded() => requestSettle(1.0);

  /// 每日獎勵開始前立即露出兔咪，再通知前景把手停止可能尚未完成的拖曳動畫。
  static void revealMascotForDailyReward() {
    openValue.value = 1.0;
    requestExpanded();
  }
}

class MascotPanelSettleRequest {
  final int id;
  final double target;

  const MascotPanelSettleRequest(this.id, this.target);
}
