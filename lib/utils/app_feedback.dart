// 操作回饋的單一入口：音效 + 觸覺一起發。
// 全 app 的震動一律走這裡（不要直接呼叫 HapticFeedback），
// 未來在設定頁加「觸覺回饋開關」時只需要在這裡把關。
import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'sfx_service.dart';

enum HapticLevel { none, selection, light, medium }

// 各音效的預設觸覺強度（全 app 慣例）；
// 個別情境要加強/減弱時用 haptic 參數覆寫。
HapticLevel _defaultHaptic(SfxCue cue) => switch (cue) {
  SfxCue.complete => HapticLevel.medium,
  SfxCue.success => HapticLevel.light,
  SfxCue.tap => HapticLevel.light,
  SfxCue.cancel => HapticLevel.selection,
  SfxCue.unlock => HapticLevel.light,
  SfxCue.loginStreakIntro => HapticLevel.none,
  SfxCue.footprintStamp => HapticLevel.medium,
  SfxCue.footprintCoinAbsorb => HapticLevel.none,
  SfxCue.footprintCoinTick => HapticLevel.none,
  SfxCue.waterAdd => HapticLevel.light,
  SfxCue.waterGoal => HapticLevel.medium,
  SfxCue.tumiCheer => HapticLevel.none,
  SfxCue.tumiConfirm => HapticLevel.none,
  SfxCue.tumiHappy => HapticLevel.none,
  SfxCue.tumiQuestion => HapticLevel.none,
  SfxCue.tumiSad => HapticLevel.none,
  SfxCue.tumiCharge => HapticLevel.none,
  SfxCue.tumiJump => HapticLevel.none,
  SfxCue.tumiPet => HapticLevel.none,
  SfxCue.snakeStart => HapticLevel.selection,
  SfxCue.snakeCollect => HapticLevel.selection,
  SfxCue.snakeBonus => HapticLevel.light,
  SfxCue.snakePower => HapticLevel.light,
  SfxCue.snakeSeed => HapticLevel.selection,
  SfxCue.snakeHit => HapticLevel.light,
  SfxCue.snakeHunt => HapticLevel.medium,
  SfxCue.snakeWarning => HapticLevel.light,
  SfxCue.snakeGameOver => HapticLevel.medium,
  SfxCue.snakeRevive => HapticLevel.medium,
  SfxCue.snakeMagnetSpawn => HapticLevel.light,
  SfxCue.snakeMagnetVacuum => HapticLevel.medium,
  SfxCue.snakeLaserCharge => HapticLevel.medium,
  SfxCue.snakeLaserShot => HapticLevel.light,
  SfxCue.snakeMoleRise => HapticLevel.medium,
  SfxCue.gamePass => HapticLevel.medium, // 換人/擲骰要有份量
  SfxCue.gameWarn => HapticLevel.light,
  SfxCue.gameFlag => HapticLevel.medium,
  SfxCue.gameDice => HapticLevel.light, // 碰撞聲基準；重擊處另升級
};

/// 測試用：接住實際發出去的回饋（cue 為 null = 只有觸覺）。
/// 設了就只記錄不真的發聲／震動，讓時序測試能數「各發生幾次、在第幾毫秒」。
@visibleForTesting
void Function(SfxCue? cue, HapticLevel haptic)? debugFeedbackSink;

/// 最近一次**由使用者操作觸發**的回饋時刻。
///
/// **只給 [PopupFeedbackObserver] 判斷「這個面板是不是某個已經自己出過回饋的
/// 按鈕打開的」用，不是全域節流。** 打卡連打那種情境每一次完成都必須各自發，
/// 全域節流會直接吃掉第二次的音效與觸覺。
///
/// 「由使用者操作觸發」這個限定是必要的，不是修飾語：引擎逐拍／逐幀發的回饋
/// （節拍器就是）跟使用者按了什麼完全無關，讓它蓋這個時戳，observer 就會把
/// 「剛剛有人按了按鈕」誤判成真。BPM 273 以上拍距小於 220ms，面板浮出的觸覺
/// 會永遠被吃掉。所以那種呼叫端要傳 `fromUserAction: false`。
DateTime? _lastFeedbackAt;

@visibleForTesting
void debugResetFeedbackClock() => _lastFeedbackAt = null;

bool _feedbackWithin(Duration window) {
  final at = _lastFeedbackAt;
  return at != null && DateTime.now().difference(at) < window;
}

// 播音效並配對觸覺回饋。
//
// [fromUserAction] = false 用在**不是回應使用者操作**的回饋（引擎逐拍、逐幀）。
// 那種不該被當成「剛剛有人按了按鈕」，理由見 [_lastFeedbackAt]。
void playFeedback(SfxCue cue, {HapticLevel? haptic, bool fromUserAction = true}) {
  final level = haptic ?? _defaultHaptic(cue);
  if (fromUserAction) _lastFeedbackAt = DateTime.now();
  final sink = debugFeedbackSink;
  if (sink != null) {
    sink(cue, level);
    return;
  }
  unawaited(SfxService.instance.play(cue));
  playHaptic(level);
}

// 只發觸覺（無音效的輕互動：chip 選取、開關切換等）。
// [fromUserAction] 的意思見 [playFeedback]。
void playHaptic(HapticLevel level, {bool fromUserAction = true}) {
  if (fromUserAction) _lastFeedbackAt = DateTime.now();
  final sink = debugFeedbackSink;
  if (sink != null) {
    sink(null, level);
    return;
  }
  switch (level) {
    case HapticLevel.none:
      break;
    case HapticLevel.selection:
      unawaited(HapticFeedback.selectionClick());
    case HapticLevel.light:
      unawaited(HapticFeedback.lightImpact());
    case HapticLevel.medium:
      unawaited(HapticFeedback.mediumImpact());
  }
}

/// 任何蓋在內容上的東西出現時，給一次最輕的觸覺。
///
/// 對話框與底部面板底層都是 `PopupRoute`（`showDialog`／
/// `showModalBottomSheet`／`showMenu` 都是），所以掛一個 observer 就覆蓋全部
/// 呼叫端——不必在幾十個 `showXxx` 前面各補一行，也不會有人新增面板時忘記。
///
/// 一般的頁面推送（`MaterialPageRoute`）**不是** `PopupRoute`，不會觸發：
/// 換頁本來就有轉場可看，不需要再震一下。
///
/// ⚠️ **覆蓋率有一個隱含前提：repo 裡沒有巢狀 Navigator。**
/// `showModalBottomSheet` 的 `useRootNavigator` 預設是 `false`（`showDialog`
/// 是 `true`），所以掛在 `MaterialApp` 上的 observer 只收得到根 Navigator 的
/// route。目前全 repo 沒有任何 `Navigator(` 建構、也沒有覆寫
/// `useRootNavigator`，所以成立；哪天有人加了分頁內導覽之類的巢狀 Navigator，
/// 那個子樹底下的面板會**安靜地**失去浮出觸覺。
///
/// [_recentWindow] 內剛發過回饋就跳過：有些面板是由已經播過 `tap` 的按鈕打開的
/// （實測 67 個開啟點裡有 14 個是這樣），連著震兩下手感是壞的。這個窗口只擋
/// observer 自己這一次，不影響任何真實事件的回饋。
class PopupFeedbackObserver extends NavigatorObserver {
  PopupFeedbackObserver();

  static const Duration _recentWindow = Duration(milliseconds: 220);

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    if (route is! PopupRoute) return;
    if (_feedbackWithin(_recentWindow)) return;
    playHaptic(HapticLevel.selection);
  }
}
