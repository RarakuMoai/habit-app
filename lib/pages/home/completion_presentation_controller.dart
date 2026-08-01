// 首頁「完成一件普通每日習慣」的演出編排器。
//
// 只服務這一個時刻：使用者勾完一件、今天還有沒做完的。**不是全 app 的
// event bus**，也不管資料——習慣的 done 狀態、storage、history 由
// `HomePage.toggleHabit` 當場提交完，這裡只決定「裝飾要在第幾毫秒發生」。
//
// 存在的理由是三件事單靠 home_page 很難不出錯：
//   1. event identity：一次 input 一個語意事件，清 transient／expiry 不再算一次
//   2. timer lifecycle：所有延後的 phase 集中管理，dispose／切分頁一次收乾淨
//   3. 連打與 Undo：合併同一條 MI 動作弧線、並讓撤銷能中斷還沒播的正向裝飾
//
// 時間軸見 CompletionPhase 各項註解；實際套用在 home_page 的
// `_onCompletionPhase`。

import 'dart:async';

import 'package:flutter/foundation.dart';

/// 完成演出的階段。呼叫端依 phase 決定要做什麼，controller 只負責時序。
///
/// 一般時間軸（相對於使用者放手那一刻）：
/// ```
/// confirm     0ms   資料已提交、卡片開始描勾
/// notice    120ms   MI 察覺（極小幅前傾）
/// anticipate210ms   MI 蹲下蓄勢（勾勾同時在收尾）
/// impact    300ms   勾勾觸底＝主衝擊：haptic + SFX + 換 pose + 放開進度條
/// speak     470ms   MI 已經在反應了，才冒泡泡／台詞／語音
/// recover   820ms   落地，回到目前進度推導的 baseline
/// quiet    2900ms   台詞淡出後清乾淨
/// ```
enum CompletionPhase {
  /// 資料已提交，卡片開始描勾。與 [CompletionPresentationController.start]
  /// 同步發生（不排 timer），使用者不會等任何 I/O。
  confirm,

  /// MI 察覺這件事。只允許 2–3px 級別的位移，不換表情、不出聲。
  notice,

  /// MI 蹲下蓄勢。比直接點擊克制。
  anticipate,

  /// 主衝擊：勾勾觸底。haptic、SFX、pose 切換、進度條開始收束都在這裡。
  impact,

  /// 泡泡／台詞／語音。一定晚於 [impact]，讓 MI 先動起來再開口。
  speak,

  /// 落地：回到由目前進度推導的 baseline（不是開 app 的中性臉）。
  recover,

  /// 情緒尾韻結束：清掉台詞。連打時跟著最後一件往後滾。
  quiet,
}

/// 一次「使用者完成一件習慣」的語意事件。
///
/// [id] 是唯一身分：清 transient、persona expiry、recover 都不會產生新的 id。
@immutable
class HomeCompletionEvent {
  /// 單調遞增的事件序號（每次 [CompletionPresentationController.start] +1）。
  final int id;

  /// 今天的第一件。只有它會開口說話 / 播 confirm 語音。
  final bool isFirstOfDay;

  /// 這次完成後今天已完成的件數。
  final int doneCount;

  /// 系統開了 Reduce Motion / Disable Animations。
  final bool reduceMotion;

  const HomeCompletionEvent({
    required this.id,
    required this.isFirstOfDay,
    required this.doneCount,
    required this.reduceMotion,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HomeCompletionEvent &&
          id == other.id &&
          isFirstOfDay == other.isFirstOfDay &&
          doneCount == other.doneCount &&
          reduceMotion == other.reduceMotion;

  @override
  int get hashCode => Object.hash(id, isFirstOfDay, doneCount, reduceMotion);

  @override
  String toString() =>
      'HomeCompletionEvent(#$id, first: $isFirstOfDay, done: $doneCount)';
}

/// 把一次完成拆成有先後的 phase 發出去。
///
/// 呼叫端負責「做什麼」，這裡只負責「什麼時候」與「發幾次」。
class CompletionPresentationController {
  CompletionPresentationController({required this.onPhase});

  /// 每個 phase 的接收端。同一個 event 的同一個 phase 最多發一次。
  final void Function(CompletionPhase phase, HomeCompletionEvent event) onPhase;

  // ── 一般時間軸 ──
  static const Duration kNoticeDelay = Duration(milliseconds: 120);
  static const Duration kAnticipateDelay = Duration(milliseconds: 210);
  static const Duration kImpactDelay = Duration(milliseconds: 300);
  static const Duration kSpeakDelay = Duration(milliseconds: 470);
  static const Duration kRecoverDelay = Duration(milliseconds: 820);
  static const Duration kQuietDelay = Duration(milliseconds: 2900);

  /// Reduce Motion：保留順序與語意，只是把位移演出拿掉。
  /// 刻意不歸零——全部同拍會變成突兀的閃爍，反而讓人讀不出因果。
  static const Duration kReducedImpactDelay = Duration(milliseconds: 60);
  static const Duration kReducedSpeakDelay = Duration(milliseconds: 140);
  static const Duration kReducedRecoverDelay = Duration(milliseconds: 400);

  /// 連打合併視窗：這段時間內再完成一件，共用同一條 MI 動作弧線，
  /// 不會讓兔咪從第 0 幀重蹲一次。每一件自己的 check / haptic / SFX 照發。
  static const Duration kArcWindow = Duration(milliseconds: 700);

  final Set<Timer> _pending = {};
  Timer? _recoverTimer;
  Timer? _quietTimer;
  Timer? _arcTimer;

  int _lastEventId = 0;
  HomeCompletionEvent? _arcLead;

  /// 目前有沒有一條 MI 動作弧線正在跑（給測試與呼叫端判讀用）。
  bool get arcActive => _arcLead != null;

  /// 目前這條弧線的領頭事件；沒有就 null。
  HomeCompletionEvent? get arcLead => _arcLead;

  /// 最後一次發出的事件序號。
  int get lastEventId => _lastEventId;

  /// 開始一次完成演出，回傳這次的事件序號。
  ///
  /// [CompletionPhase.confirm] 會同步發出（資料已經提交了，確認不該等）。
  /// 其餘 phase 依時間軸排程；連打時只有第一件會開新的 MI 弧線。
  int start({
    required bool isFirstOfDay,
    required int doneCount,
    required bool reduceMotion,
  }) {
    final event = HomeCompletionEvent(
      id: ++_lastEventId,
      isFirstOfDay: isFirstOfDay,
      doneCount: doneCount,
      reduceMotion: reduceMotion,
    );

    onPhase(CompletionPhase.confirm, event);

    // 弧線只由視窗內的第一件開；後面的併進來，不重啟動作。
    if (_arcLead == null) {
      _arcLead = event;
      _arcTimer = Timer(kArcWindow, () {
        _arcTimer = null;
        _arcLead = null;
      });
      if (reduceMotion) {
        _arm(kReducedSpeakDelay, CompletionPhase.speak, event);
      } else {
        _arm(kNoticeDelay, CompletionPhase.notice, event);
        _arm(kAnticipateDelay, CompletionPhase.anticipate, event);
        _arm(kSpeakDelay, CompletionPhase.speak, event);
      }
    }

    // 每一件都有自己的衝擊點：勾勾、觸覺、音效不會因為合併而消失。
    _arm(
      reduceMotion ? kReducedImpactDelay : kImpactDelay,
      CompletionPhase.impact,
      event,
    );

    // 尾韻永遠掛在「最後一件」上，連打時自然往後延而不是各排各的。
    _recoverTimer?.cancel();
    _recoverTimer = Timer(
      reduceMotion ? kReducedRecoverDelay : kRecoverDelay,
      () {
        _recoverTimer = null;
        onPhase(CompletionPhase.recover, event);
      },
    );
    _quietTimer?.cancel();
    _quietTimer = Timer(kQuietDelay, () {
      _quietTimer = null;
      onPhase(CompletionPhase.quiet, event);
    });

    return event.id;
  }

  /// 丟掉所有還沒發生的 phase。
  ///
  /// 用在 Undo、切走分頁、跨進 all-done、dispose。已經發生過的不會回滾——
  /// 撤銷資料是 [onPhase] 呼叫端的事，這裡只保證「過時的裝飾不會再播」。
  void cancel() {
    for (final timer in _pending) {
      timer.cancel();
    }
    _pending.clear();
    _recoverTimer?.cancel();
    _recoverTimer = null;
    _quietTimer?.cancel();
    _quietTimer = null;
    _arcTimer?.cancel();
    _arcTimer = null;
    _arcLead = null;
  }

  void dispose() => cancel();

  void _arm(Duration delay, CompletionPhase phase, HomeCompletionEvent event) {
    late final Timer timer;
    timer = Timer(delay, () {
      _pending.remove(timer);
      onPhase(phase, event);
    });
    _pending.add(timer);
  }
}
