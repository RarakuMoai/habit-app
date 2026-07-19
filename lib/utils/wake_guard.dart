import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

/// 防螢幕自動鎖定的單一入口。給「使用者長時間不碰螢幕、但計時不能停／要一直
/// 盯著看」的計時器用：
///   - 節拍器（背景會整個停掉，螢幕一鎖節拍就斷）
///   - 運動間歇（運動中不碰手機，畫面與每秒提示音要持續）
///
/// 專注計時刻意不用——它走背景 wall-clock + 鎖屏通知，本來就要「放下手機」，
/// 強制亮屏只會耗電。
///
/// 用 tag 做引用計數：理論上 [TimerMutex] 已保證同時只有一個計時器在跑，
/// 引用計數只是保險，避免某一方 disable 把另一方的需求一起關掉。
abstract final class WakeGuard {
  static final Set<String> _holders = <String>{};

  /// [tag] 要求保持螢幕喚醒。第一個要求者才真的開啟。
  static void acquire(String tag) {
    final wasEmpty = _holders.isEmpty;
    _holders.add(tag);
    if (wasEmpty) _apply(enable: true);
  }

  /// [tag] 放開需求。最後一個放開者才真的解除。重複放開安全（無效果）。
  static void release(String tag) {
    if (_holders.remove(tag) && _holders.isEmpty) _apply(enable: false);
  }

  static void _apply({required bool enable}) {
    // wakelock 失敗（某些模擬器/平台不支援）絕不該拖垮計時功能，吞掉即可。
    unawaited(
      (enable ? WakelockPlus.enable() : WakelockPlus.disable()).catchError(
        (Object e) =>
            debugPrint('WakeGuard ${enable ? 'enable' : 'disable'} failed: $e'),
      ),
    );
  }
}
