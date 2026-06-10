// 兔咪角色資料層：情緒、情境、台詞、展開狀態。
//
// 設計參考 docs/tumi_character_guide.md。台詞庫直接由指南搬過來，
// 之後人設更新只改這檔不必動 widget。

import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

// 8 種情緒。
//
// 過渡期：已遷移到新 CG 風格的情緒走 `assets/mascot/core/tumi_<key>.png`，
// 還沒遷移的暫時退回 `happy` 表情當佔位。使用者生好新 CG 後加進 [_migratedToCG]。
enum MascotEmotion {
  neutralFront('neutral_front'),
  sleep('sleep'),
  expect('expect'),
  smile('smile'),
  happy('happy'),
  streak('streak'),
  sad('sad'),
  night('night');

  final String assetKey;
  const MascotEmotion(this.assetKey);

  // 已換成新 CG 風格的情緒（其他仍走舊圖避免 app 出現破圖）
  static const Set<MascotEmotion> _migratedToCG = {
    MascotEmotion.neutralFront,
    MascotEmotion.sleep,
    MascotEmotion.expect,
    MascotEmotion.smile,
    MascotEmotion.happy,
    MascotEmotion.sad,
    MascotEmotion.night,
  };

  String get assetPath => _migratedToCG.contains(this)
      ? 'assets/mascot/core/tumi_$assetKey.png'
      // 還沒生 CG 的情緒（目前只剩 streak），暫時用 happy 代替避免破圖
      : 'assets/mascot/core/tumi_happy.png';
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
  // 還沒有任何習慣時（空狀態）
  emptyHabits,
  // 喝水過量警告（>=4L/day，醫學上「過量但還沒到水中毒」灰色地帶）
  // 兔咪驚嚇 + 提示語，但不擋使用者繼續紀錄（硬擋在 6L）
  overhydration,
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
  MascotContext.emptyHabits: MascotEmotion.neutralFront,
  MascotContext.overhydration: MascotEmotion.sad,
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
  MascotContext.openApp: [
    '嗯...你來了。',
    '我在這裡。',
    '今天也慢慢來？',
    '要先做一件小事嗎？',
  ],

  // ── 今天還沒開始做任何習慣 ──
  MascotContext.notStarted: [
    '嗯...今天也慢慢開始？',
    '我在等你，不急。',
    '先做一個小小的也可以。',
    '今天不用很快。',
    '嗯...要開始了嗎？',
  ],

  // ── 完成了第一個 / 任一個習慣 ──
  MascotContext.completedOne: [
    '做到了，我有看到。',
    '剛剛那一下，很好。',
    '你完成了一個。',
    '嗯，這樣就很好。',
  ],

  // ── 完成過一半 ──
  MascotContext.halfDone: [
    '已經一半了。',
    '你做到不少了。',
    '我有點醒了。',
    '照這樣慢慢來就好。',
  ],

  // ── 今天全部完成 ──
  MascotContext.allDone: [
    '全部完成了。',
    '今天真的很棒。',
    '可以好好休息了。',
    '我替你開心。',
  ],

  // ── 連續達標一段時間（streak >= 7） ──
  MascotContext.streak: [
    '連續好多天了。',
    '你一直有回來。',
    '我有點感動。',
    '這段時間，你做到了。',
  ],

  // ── 取消已完成的習慣（撤銷感） ──
  MascotContext.undone: [
    '沒關係，我還在。',
    '今天慢一點也可以。',
    '我們等一下再來。',
    '先休息一下也沒關係。',
  ],

  // ── 夜晚（22:00 ~ 06:00） ──
  MascotContext.night: [
    '很晚了，我小聲一點。',
    '今天辛苦了。',
    '如果累了，也可以休息。',
    '明天我還會在這裡。',
  ],

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

  // ── 還沒新增任何習慣（空狀態） ──
  MascotContext.emptyHabits: [
    '先新增一個小習慣吧。',
    '從一個小小的開始。',
    '不用很多，一個就好。',
  ],

  // ── 喝水過量（>=4L/day，過量但還沒到水中毒）──
  MascotContext.overhydration: [
    '欸…你今天喝有點多了。',
    '水也是有上限的喔，慢慢來。',
    '已經喝很多了，先停一下吧。',
    '再喝下去身體會吃不消。',
    '記得補一點電解質。',
  ],
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
  final String speech;
  const MascotState(this.assetPath, this.speech);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MascotState &&
          assetPath == other.assetPath &&
          speech == other.speech;

  @override
  int get hashCode => Object.hash(assetPath, speech);
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

  /// 互動：根據情境換情緒 + 隨機抽一句台詞。10 秒後自動回神。
  ///
  /// 回傳 false 代表兔咪目前正在停留一個狀態，這次普通互動被忽略。
  static bool interact(MascotContext ctx, {bool force = false}) {
    if (!_canApply(ctx, force: force)) return false;
    _apply(
      MascotState(
        MascotLines.emotionFor(ctx).assetPath,
        MascotLines.randomLineFor(ctx),
      ),
      ctx,
    );
    return true;
  }

  /// 直接設定（呼叫端自己決定 asset + 台詞）。10 秒後自動回神。
  static bool set(String assetPath, String speech, {bool force = false}) {
    return setForContext(
      assetPath,
      MascotContext.tapReaction,
      speech: speech,
      force: force,
    );
  }

  /// 用指定情境設定自訂 asset。台詞可交給情境台詞池抽，並套用同一套停留規則。
  static bool setForContext(
    String assetPath,
    MascotContext ctx, {
    String? speech,
    bool force = false,
  }) {
    if (!_canApply(ctx, force: force)) return false;
    _apply(
      MascotState(assetPath, speech ?? MascotLines.randomLineFor(ctx)),
      ctx,
    );
    return true;
  }

  static void _apply(MascotState state, MascotContext ctx) {
    current.value = state;
    _holdUntil = DateTime.now().add(_holdDuration);
    _activePriority = _priorityOf(ctx);
    _scheduleRevert();
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
  static final ValueNotifier<double> openValue = ValueNotifier<double>(1.0);

  static bool get expanded => openValue.value >= 0.5;

  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    openValue.value = (prefs.getBool(_key) ?? true) ? 1.0 : 0.0;
  }

  // 把目前狀態落地到 prefs（呼叫端在拖曳/動畫結束後再存）
  static Future<void> persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, expanded);
  }
}
