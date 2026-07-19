import 'dart:async';

import 'package:flutter/foundation.dart';

import 'usage_stats.dart';

// 專注 / 運動兩個計時器互斥：同一時間只允許一個「實際倒數中」。
//
// 兩者都放在 timer_page 的 IndexedStack 裡常駐，各自有獨立 ticker、鎖屏
// 鏈式通知與音效。若同時倒數，鎖屏會跳兩串通知、節拍器與專注提示音互相
// 蓋掉，使用者分不清。
//
// 策略：按開始（含暫停後 resume）時，若另一個正在跑，就「自動暫停對方並
// 保留它的進度」，再啟動自己；呼叫端跳一句提示告知對方已暫停。對方切回去
// 按開始可接著跑（届時換這邊被自動暫停）。
//
// 各計時器在 initState 用 [register] 掛上「暫停自己」的回呼，dispose 時
// [unregister]。暫停 / 重設 / 完成都要 [release]。
enum ActiveTimer { focus, exercise, metronome }

extension ActiveTimerLabel on ActiveTimer {
  /// 被搶鎖暫停時給使用者看的提示字。
  String get pausedMessage => switch (this) {
    ActiveTimer.focus => '專注計時已暫停',
    ActiveTimer.exercise => '運動計時已暫停',
    ActiveTimer.metronome => '節拍器已暫停',
  };
}

class TimerMutex {
  TimerMutex._();

  static ActiveTimer? _active;
  static final Map<ActiveTimer, VoidCallback> _pausers = {};

  /// 目前實際倒數中的計時器；都沒在跑時為 null。
  static ActiveTimer? get active => _active;

  /// 掛上 [who] 的「暫停自己（保留進度）」回呼。
  static void register(ActiveTimer who, VoidCallback pauseSelf) {
    _pausers[who] = pauseSelf;
  }

  /// 移除 [who] 的回呼；若它正持有鎖也一併釋放，避免留下殭屍持有者。
  static void unregister(ActiveTimer who) {
    _pausers.remove(who);
    if (_active == who) _active = null;
  }

  /// 開始 [who]：若另一個正在跑，呼叫它的暫停回呼讓它自己停下（回呼內部會
  /// release），再讓 [who] 持有鎖。回傳被暫停的計時器（給呼叫端跳提示），
  /// 沒有要停的就回 null。
  static ActiveTimer? acquire(ActiveTimer who) {
    final other = (_active != null && _active != who) ? _active : null;
    if (other != null) _pausers[other]?.call();
    _active = who;
    // 匿名統計：計時啟動（含 resume；當粗略 engagement 即可，不求精確）。
    unawaited(UsageStats.bump(UsageEvents.timerStart(who.name)));
    return other;
  }

  /// 使用者主動離開正在運作的模式時，暫停目前持有者並保留可恢復的進度。
  ///
  /// 回傳被暫停的模式，讓呼叫端顯示一致的切換提示。節拍器沒有倒數進度，
  /// 因此它的 pauser 會停止播放但保留 BPM 與拍號設定。
  static ActiveTimer? pauseActive() {
    final current = _active;
    if (current == null) return null;
    final pause = _pausers[current];
    if (pause != null) {
      pause();
    } else {
      _active = null;
    }
    return current;
  }

  /// 釋放 [who]。只有持有者能釋放，避免在對方持有時誤清。
  static void release(ActiveTimer who) {
    if (_active == who) _active = null;
  }
}
