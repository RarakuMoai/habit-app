// 兔咪角色資料層：情緒、情境、台詞、展開狀態。
//
// 設計參考 docs/tumi_character_guide.md。台詞庫直接由指南搬過來，
// 之後人設更新只改這檔不必動 widget。

import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'sfx_service.dart';

// 兔咪情緒。每個情緒 = assets/mascot/core/tumi_<assetKey>.png 一張 CG 立繪。
//
// 基礎圖按「身體姿勢／手的高度」分（兔咪嘴巴不動，情緒靠眼/耳/手表達；
// 更細的情境之後再靠情緒泡泡 overlay 疊加，不必每種情緒各畫一張）。
// 快樂梯度＝手的高度：smile(手垂) → happy(手胸前) → popHappy(雙手高舉)。
// expect 與 happy 共用「手胸前」身體，只差眼睛（圓眼/笑眼）。
// 狀態盤點見 docs/tumi_character_guide.md 與 assets/mascot/candidates/。
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
  static String? blinkAssetForPath(String assetPath) {
    for (final e in _hasBlink) {
      if (e.assetPath == assetPath) {
        return 'assets/mascot/core/tumi_${e.assetKey}_blink.png';
      }
    }
    return null;
  }
}

// 兔咪陪伴情境。每個情境對應一組台詞與預設情緒。
// 之後想新增/修改台詞，只改下方 [_lines] 這個 map 就好。
enum MascotContext {
  openApp,
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
  // 還沒有任何習慣時（空狀態）
  emptyHabits,
  // 喝水過量警告（>=4L/day，醫學上「過量但還沒到水中毒」灰色地帶）
  // 兔咪驚嚇 + 提示語，但不擋使用者繼續紀錄（硬擋在 6L）
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
  exclaim, // 驚嘆：喝水過量提醒
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
        return EmotionBubble.star;
      case MascotContext.undone:
        return EmotionBubble.sweat;
      case MascotContext.notStarted:
      case MascotContext.night:
        return EmotionBubble.zzz;
      case MascotContext.overhydration:
        return EmotionBubble.exclaim;
      case MascotContext.tapReaction:
        return EmotionBubble.question;
      case MascotContext.openApp:
      case MascotContext.emptyHabits:
        return null;
    }
  }
}

// 各情境對應的預設情緒（呼叫端可以另外覆寫）。
const Map<MascotContext, MascotEmotion> _defaultEmotion = {
  MascotContext.openApp: MascotEmotion.neutralFront,
  MascotContext.notStarted: MascotEmotion.sleep,
  MascotContext.completedOne: MascotEmotion.smile,
  MascotContext.halfDone: MascotEmotion.expect,
  MascotContext.allDone: MascotEmotion.happy,
  MascotContext.streak: MascotEmotion.streak,
  MascotContext.undone: MascotEmotion.sad,
  MascotContext.night: MascotEmotion.night,
  MascotContext.tapReaction: MascotEmotion.neutralFront,
  MascotContext.headPet: MascotEmotion.smile,
  // 空狀態用「伸手邀請」姿勢，比中性更主動地邀使用者新增第一個習慣
  MascotContext.emptyHabits: MascotEmotion.invite,
  // 喝水過量改用「歪頭疑問」溫柔提醒，而非心疼的 sad
  MascotContext.overhydration: MascotEmotion.question,
};

// ─────────────────────────────────────────────────────────────
//  📝 兔咪台詞庫
//  -----------------------------------------------------------
//  全 app 唯一一份台詞來源。要新增 / 修改 / 刪除任何兔咪講的話，
//  直接改下面這個 map 就好，不需要動其他檔案。
//
//  每個 key（MascotContext）對應一個台詞池，呼叫端拿其中一句使用。
//  - lineFor(ctx, seed): 同 seed 拿固定一句（避免 build 時抖動）
//  - randomLineFor(ctx): 隨機抽一句
//
//  人設參考 docs/tumi_character_guide.md。
// ─────────────────────────────────────────────────────────────
const Map<MascotContext, List<String>> _lines = {
  // ── 打開 app / 一般招呼 ──
  MascotContext.openApp: ['嗯...你來了。', '我在這裡。', '今天也慢慢來？', '要先做一件小事嗎？'],

  // ── 今天還沒開始做任何習慣 ──
  MascotContext.notStarted: [
    '嗯...今天也慢慢開始？',
    '我在等你，不急。',
    '先做一個小小的也可以。',
    '今天不用很快。',
    '嗯...要開始了嗎？',
  ],

  // ── 完成了第一個 / 任一個習慣 ──
  MascotContext.completedOne: ['做到了，我有看到。', '剛剛那一下，很好。', '你完成了一個。', '嗯，這樣就很好。'],

  // ── 完成過一半 ──
  MascotContext.halfDone: ['已經一半了。', '你做到不少了。', '我有點醒了。', '照這樣慢慢來就好。'],

  // ── 今天全部完成 ──
  MascotContext.allDone: ['全部完成了。', '今天真的很棒。', '可以好好休息了。', '我替你開心。'],

  // ── 連續達標一段時間（streak >= 7） ──
  MascotContext.streak: ['連續好多天了。', '你一直有回來。', '我有點感動。', '這段時間，你做到了。'],

  // ── 取消已完成的習慣（撤銷感） ──
  MascotContext.undone: ['沒關係，我還在。', '今天慢一點也可以。', '我們等一下再來。', '先休息一下也沒關係。'],

  // ── 夜晚（22:00 ~ 06:00） ──
  MascotContext.night: ['很晚了，我小聲一點。', '今天辛苦了。', '如果累了，也可以休息。', '明天我還會在這裡。'],

  // ── 使用者點兔咪本身的隨機反應 ──
  MascotContext.tapReaction: [
    '嗯？',
    '我在這裡。',
    '今天也慢慢來。',
    '先做一點點也可以。',
    '我有醒著喔。',
    '你回來了，真好。',
    '我陪你一下。',
    '我陪你。',
  ],

  // ── 摸頭反應 ──
  MascotContext.headPet: [
    '嗯...舒服。',
    '頭頂被摸到了。',
    '再一下下也可以。',
    '我有點開心。',
    '好，我乖乖的。',
  ],

  // ── 還沒新增任何習慣（空狀態） ──
  MascotContext.emptyHabits: ['先新增一個小習慣吧。', '從一個小小的開始。', '不用很多，一個就好。'],

  // ── 喝水過量（>=4L/day，過量但還沒到水中毒）──
  MascotContext.overhydration: [
    '欸…你今天喝有點多了。',
    '水也是有上限的喔，慢慢來。',
    '已經喝很多了，先停一下吧。',
    '再喝下去身體會吃不消。',
    '記得補一點電解質。',
  ],
};

// 首頁點兔咪時的情境回應。這組比一般 tapReaction 更像「兔咪看見今天的狀態」：
// 不給指令、不評分，只把使用者當下的進度接住。
const Map<MascotContext, List<String>> _homeTapLines = {
  MascotContext.emptyHabits: [
    '我們可以先放一件很小的事。',
    '不用急著變很多。\n先從一個開始。',
    '你想養成什麼，我會陪著記。',
  ],
  MascotContext.notStarted: [
    '還沒開始也沒關係。',
    '我在等你。\n第一件可以很小。',
    '今天先做一點點就好。',
    '要不要從最簡單那個開始？',
  ],
  MascotContext.completedOne: ['剛剛那一下，我有看到。', '已經開始了。\n這很重要。', '你有往前一點點了。'],
  MascotContext.halfDone: ['你已經做到一半了。', '照這個速度慢慢來就好。', '我有點醒了。\n你做得不錯。'],
  MascotContext.allDone: ['今天的份已經完成了。', '可以安心休息一下。', '你有把今天照顧好。'],
  MascotContext.streak: ['你已經連續回來好多天了。', '這段時間，我都有記得。', '你不是突然做到的。\n是一天一天來的。'],
  MascotContext.undone: ['改掉也沒關係。', '今天可以重新調整。', '我們慢慢來，不用硬撐。'],
  MascotContext.night: ['很晚了，我小聲一點。', '今天先不要太逼自己。', '如果累了，明天再繼續也可以。'],
};

class MascotLines {
  static MascotEmotion emotionFor(MascotContext c) =>
      _defaultEmotion[c] ?? MascotEmotion.neutralFront;

  /// 從情境抽一句台詞。同一個 (context, seed) 會回固定結果，
  /// 避免每次 rebuild 換句話讓使用者覺得抖。
  static String lineFor(MascotContext c, {int seed = 0}) {
    final list = _lines[c] ?? const ['...'];
    if (list.isEmpty) return '...';
    return list[seed.abs() % list.length];
  }

  /// 隨機抽一句（用在「開 app 時換句話講」這種場景）。
  static String randomLineFor(MascotContext c) {
    final list = _lines[c] ?? const ['...'];
    if (list.isEmpty) return '...';
    return list[Random().nextInt(list.length)];
  }

  /// 首頁點兔咪：依目前進度抽一句更貼身的回應。
  static String randomHomeTapLineFor(MascotContext c) {
    final list = _homeTapLines[c] ?? _lines[MascotContext.tapReaction];
    if (list == null || list.isEmpty) return '...';
    return list[Random().nextInt(list.length)];
  }

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
        return false;
      case MascotContext.openApp:
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
    if (!voiceMuted) unawaited(SfxService.instance.play(_voiceCueFor(ctx)));
    _holdUntil = DateTime.now().add(_holdDuration);
    _activePriority = _priorityOf(ctx);
    _scheduleRevert();
  }

  static SfxCue _voiceCueFor(MascotContext ctx) {
    switch (ctx) {
      case MascotContext.allDone:
      case MascotContext.completedOne:
      case MascotContext.streak:
      case MascotContext.headPet:
        return SfxCue.tumiHappy;
      case MascotContext.undone:
      case MascotContext.overhydration:
        return SfxCue.tumiSad;
      case MascotContext.notStarted:
      case MascotContext.night:
        return SfxCue.tumiSleepy;
      case MascotContext.tapReaction:
      case MascotContext.emptyHabits:
        return SfxCue.tumiQuestion;
      case MascotContext.openApp:
      case MascotContext.halfDone:
        return SfxCue.tumiNeutral;
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
        return 6;
      case MascotContext.tapReaction:
      case MascotContext.openApp:
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

  /// 安排 N 秒後回到中性狀態。新互動會 reset 計時。
  static void _scheduleRevert() {
    _revertTimer?.cancel();
    _revertTimer = Timer(_revertAfter, () {
      _holdUntil = null;
      _activePriority = 0;
      current.value = MascotState(
        MascotLines.emotionFor(MascotContext.openApp).assetPath,
        MascotLines.randomLineFor(MascotContext.openApp),
      );
    });
  }
}

// 兔咪面板展開／收合偏好。
//
// 為了讓拖曳能即時跟隨手指（iOS bottom sheet 感），這裡用
// `ValueNotifier<double>`：0.0 = 完全收合、1.0 = 完全展開、中間
// 浮點 = 拖曳過程中的瞬時狀態。
//
// 永久化偏好只存最終態（>=0.5 視為展開），不存中間值。
class MascotPanelPrefs {
  static const String _key = 'mascot_panel_expanded';
  static const String _hintSeenKey = 'mascot_panel_hint_seen';
  static final ValueNotifier<double> openValue = ValueNotifier<double>(1.0);
  static final ValueNotifier<bool> hintSeenValue = ValueNotifier<bool>(false);
  static final ValueNotifier<MascotPanelSettleRequest?> settleRequest =
      ValueNotifier<MascotPanelSettleRequest?>(null);
  static int _settleSeq = 0;

  static bool get expanded => openValue.value >= 0.5;
  static bool get hintSeen => hintSeenValue.value;

  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    openValue.value = (prefs.getBool(_key) ?? true) ? 1.0 : 0.0;
    hintSeenValue.value = prefs.getBool(_hintSeenKey) ?? false;
  }

  // 把目前狀態落地到 prefs（呼叫端在拖曳/動畫結束後再存）
  static Future<void> persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, expanded);
  }

  static Future<void> markHintSeen() async {
    if (hintSeenValue.value) return;
    hintSeenValue.value = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_hintSeenKey, true);
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
}

class MascotPanelSettleRequest {
  final int id;
  final double target;

  const MascotPanelSettleRequest(this.id, this.target);
}
