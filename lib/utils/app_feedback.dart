// 操作回饋的單一入口：音效 + 觸覺一起發。
// 全 app 的震動一律走這裡（不要直接呼叫 HapticFeedback），
// 未來在設定頁加「觸覺回饋開關」時只需要在這裡把關。
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

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

// 播音效並配對觸覺回饋
void playFeedback(SfxCue cue, {HapticLevel? haptic}) {
  final level = haptic ?? _defaultHaptic(cue);
  final sink = debugFeedbackSink;
  if (sink != null) {
    sink(cue, level);
    return;
  }
  unawaited(SfxService.instance.play(cue));
  playHaptic(level);
}

// 只發觸覺（無音效的輕互動：chip 選取、開關切換等）
void playHaptic(HapticLevel level) {
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
