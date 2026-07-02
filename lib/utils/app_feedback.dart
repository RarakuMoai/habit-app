// 操作回饋的單一入口：音效 + 觸覺一起發。
// 全 app 的震動一律走這裡（不要直接呼叫 HapticFeedback），
// 未來在設定頁加「觸覺回饋開關」時只需要在這裡把關。
import 'dart:async';

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
  SfxCue.gameTurn => HapticLevel.medium,
  SfxCue.tumiNeutral => HapticLevel.none,
  SfxCue.tumiQuestion => HapticLevel.none,
  SfxCue.tumiHappy => HapticLevel.none,
  SfxCue.tumiSad => HapticLevel.none,
  SfxCue.tumiSleepy => HapticLevel.none,
};

// 播音效並配對觸覺回饋
void playFeedback(SfxCue cue, {HapticLevel? haptic}) {
  unawaited(SfxService.instance.play(cue));
  playHaptic(haptic ?? _defaultHaptic(cue));
}

// 只發觸覺（無音效的輕互動：chip 選取、開關切換等）
void playHaptic(HapticLevel level) {
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
