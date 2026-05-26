// 兔咪角色資料層：情緒、情境、台詞、展開狀態。
//
// 設計參考 docs/tumi_character_guide.md。台詞庫直接由指南搬過來，
// 之後人設更新只改這檔不必動 widget。

import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

// 8 種情緒，對應 assets/images/mascot/tumi_*.png 的檔名。
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

  String get assetPath => 'assets/images/mascot/tumi_$assetKey.png';
}

// 7 種陪伴情境（再加一個 night）。每個情境對應一組台詞與預設情緒。
enum MascotContext {
  openApp,
  notStarted,
  completedOne,
  halfDone,
  allDone,
  streak,
  undone,
  night,
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
};

// 各情境台詞庫（搬自 docs/tumi_character_guide.md）。
const Map<MascotContext, List<String>> _lines = {
  MascotContext.openApp: [
    '嗯...你來了。',
    '我有醒著喔。',
    '今天也從一點點開始？',
    '要先做最小的那一步嗎？',
  ],
  MascotContext.notStarted: [
    '我在等你，不急。',
    '先碰一下也可以。',
    '今天可以很小步。',
    '嗯...要開始了嗎？',
  ],
  MascotContext.completedOne: [
    '做到了，我有看到。',
    '這一格亮起來了。',
    '小小一步，收好。',
    '嗯，今天有留下痕跡。',
  ],
  MascotContext.halfDone: [
    '已經一半了耶。',
    '你慢慢在前進。',
    '我開始精神了。',
    '再一點點就很棒。',
  ],
  MascotContext.allDone: [
    '全部完成了。',
    '今天的你，好認真。',
    '我替你收好了。',
    '這一天亮亮的。',
  ],
  MascotContext.streak: [
    '我們連起來了！',
    '兔咪精神來了。',
    '這不是一點點了耶。',
    '你看，真的長出來了。',
  ],
  MascotContext.undone: [
    '沒關係，我還在。',
    '今天比較難，對吧。',
    '我們可以重新放一格。',
    '不是壞掉，只是停了一下。',
  ],
  MascotContext.night: [
    '很晚了，聲音小一點。',
    '今天辛苦了。',
    '如果累了，也可以休息。',
    '明天我還會在這裡。',
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
