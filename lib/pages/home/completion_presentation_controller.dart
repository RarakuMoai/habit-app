// 首頁「完成一件普通每日習慣」的演出編排器。
//
// 只服務這一個時刻：使用者勾完一件、今天還有沒做完的。**不是全 app 的
// event bus**，也不管資料——習慣的 done 狀態、storage、history 由
// `HomePage.toggleHabit` 當場提交完，這裡只決定「裝飾要在第幾毫秒發生」。
//
// 存在的理由是三件事單靠 home_page 很難不出錯：
//   1. event identity：一次 input 一個語意事件，清 transient／expiry 不再算一次
//   2. timer lifecycle：所有延後的 phase 集中管理，dispose／切分頁一次收乾淨
//   3. 連打與 Undo：合併同一條 MI 動作弧線、並讓撤銷能**只**中斷那一件的裝飾
//
// 時間軸見 CompletionPhase 各項註解；實際套用在 home_page 的
// `_onCompletionPhase`。

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'completion_timing.dart';

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
  /// 同步發出（不排 timer），使用者不會等任何 I/O。
  confirm,

  /// MI 察覺這件事。只允許 2–3px 級別的位移，不換表情、不出聲。
  notice,

  /// MI 蹲下蓄勢。比直接點擊克制。
  anticipate,

  /// 主衝擊：勾勾觸底。haptic、SFX、pose 切換、進度條開始收束都在這裡。
  impact,

  /// 泡泡／台詞／語音。一定晚於 [impact]，讓 MI 先動起來再開口。
  /// **一條弧線只發一次**，語意由該弧線當下的成員決定。
  speak,

  /// 里程碑補送：弧線已經發過普通完成的語意之後，才有成員跨過門檻。
  ///
  /// 只補語意（泡泡／語音／情境），**不重啟** notice／crouch／jump——
  /// 使用者已經看過那段動作了，再演一次只會像卡住。
  milestoneHandoff,

  /// 落地：回到由目前進度推導的 baseline（不是開 app 的中性臉）。
  recover,

  /// 情緒尾韻結束：清掉台詞。連打時跟著最後一件往後滾。
  quiet,
}

/// 這條弧線要用哪一種語意收尾。
///
/// 普通完成是 `completedOne`；一旦某一件跨過一半門檻，整條弧線**升級**成
/// `halfDone`。kind 不是存下來的欄位，而是每次要用時從**目前仍然有效的
/// 成員**重算——所以半程成員被撤銷後會自動降回 ordinary，
/// 而且下一條弧線改不到上一條的語意。
enum CompletionKind { ordinary, half }

/// 一次「使用者完成一件習慣」的語意事件。
///
/// [id] 是唯一身分：清 transient、persona expiry、recover 都不會產生新的 id。
/// [generation]、[habitKey]、[dayRevision] 用來判斷「這個延後的 callback
/// 現在還算不算數」——離開首頁、跨日換快照、dispose 之後一律不算。
@immutable
class HomeCompletionEvent {
  /// 單調遞增的事件序號（每次 [CompletionPresentationController.start] +1）。
  final int id;

  /// 這一件屬於哪一條動作弧線。跟在後面的成員共用同一個 arcId。
  final int arcId;

  /// 建立當下的 presentation generation。
  final int generation;

  /// 這次完成的習慣身分（id 優先，沒有 id 才退回名稱）。
  final String habitKey;

  /// 建立當下的邏輯日 revision；跨日換快照後舊事件即失效。
  final int? dayRevision;

  /// 這一件是否讓今天的進度跨過一半門檻。
  final bool crossedHalf;

  /// 這次完成後今天已完成的件數（僅供除錯／記錄；台詞一律在 speak 當下重算）。
  final int doneCount;

  /// 系統開了 Reduce Motion / Disable Animations。
  final bool reduceMotion;

  const HomeCompletionEvent({
    required this.id,
    required this.arcId,
    required this.generation,
    required this.habitKey,
    required this.dayRevision,
    required this.crossedHalf,
    required this.doneCount,
    required this.reduceMotion,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HomeCompletionEvent &&
          id == other.id &&
          arcId == other.arcId &&
          generation == other.generation &&
          habitKey == other.habitKey &&
          dayRevision == other.dayRevision &&
          crossedHalf == other.crossedHalf &&
          doneCount == other.doneCount &&
          reduceMotion == other.reduceMotion;

  @override
  int get hashCode => Object.hash(
    id,
    arcId,
    generation,
    habitKey,
    dayRevision,
    crossedHalf,
    doneCount,
    reduceMotion,
  );

  @override
  String toString() =>
      'HomeCompletionEvent(#$id arc$arcId gen$generation $habitKey)';
}

/// 撤銷單一件之後，這條弧線的下場。
///
/// 呼叫端需要明確知道「還有沒有人活著」才能決定要不要送出動作取消，
/// 不該用目前的 reaction tick 去猜。
enum CompletionCancelOutcome {
  /// 這個 id 本來就不在（重複撤銷、或已經失效）。
  unknown,

  /// 取消了，但同一條弧線還有其他有效成員：共用動作要留著。
  arcSurvives,

  /// 最後一個有效成員也沒了：整條弧線結束，可以送出動作取消。
  arcEnded,
}

/// 一條共用的 MI 動作弧線。
class _CompletionArc {
  _CompletionArc(this.id, this.generation, this.leadEventId);

  final int id;
  final int generation;
  final int leadEventId;

  /// 收進這條弧線的所有事件（含已撤銷的，用 [live] 過濾）。
  final Map<int, HomeCompletionEvent> members = {};

  /// 仍然有效的成員 id。
  final Set<int> live = {};

  /// 這條弧線已經發過語意事件（speak）了。
  bool semanticDelivered = false;

  /// 已經補送過里程碑，之後不再補第二次。
  bool milestoneDelivered = false;

  /// 合併視窗還開著（還能收新成員進來）。
  bool windowOpen = true;

  Timer? windowTimer;
  Timer? recoverTimer;
  Timer? quietTimer;
  final Set<Timer> beats = {};

  bool get hasLiveMember => live.isNotEmpty;

  /// 由**目前仍然有效的成員**重算語意。半程成員被撤銷就自動降回 ordinary。
  CompletionKind get kind => live.any((id) => members[id]?.crossedHalf == true)
      ? CompletionKind.half
      : CompletionKind.ordinary;

  void disposeTimers() {
    windowTimer?.cancel();
    windowTimer = null;
    recoverTimer?.cancel();
    recoverTimer = null;
    quietTimer?.cancel();
    quietTimer = null;
    for (final t in beats) {
      t.cancel();
    }
    beats.clear();
  }
}

/// 把一次完成拆成有先後的 phase 發出去。
///
/// 呼叫端負責「做什麼」，這裡只負責「什麼時候」「發幾次」「還算不算數」。
class CompletionPresentationController {
  CompletionPresentationController({required this.onPhase, this.isStillValid});

  /// 每個 phase 的接收端。
  ///
  /// [kind] 是**這一拍所屬弧線**當下的語意，由 controller 解析後傳進來——
  /// 呼叫端不需要（也不可以）去問一個會被下一條弧線改寫的全域欄位。
  final void Function(
    CompletionPhase phase,
    HomeCompletionEvent event,
    CompletionKind kind,
  )
  onPhase;

  /// 呼叫端最後一道關卡：timer 已經喚醒，但畫面可能已經看不到、已經跨日、
  /// 正在重載、已經 dispose。回 false 就整拍變成 no-op（**不會**回滾資料）。
  final bool Function(HomeCompletionEvent event)? isStillValid;

  // ── 一般時間軸 ──
  static const Duration kNoticeDelay = Duration(milliseconds: 120);
  static const Duration kAnticipateDelay = Duration(milliseconds: 210);

  /// 衝擊點＝勾勾筆尖落點。兩者共用 [kCheckDrawDuration]，不各寫一個數字。
  static const Duration kImpactDelay = kCheckDrawDuration;
  static const Duration kSpeakDelay = Duration(
    milliseconds: kCheckDrawMs + kSpeakAfterImpactMs,
  );
  static const Duration kRecoverDelay = Duration(milliseconds: 820);
  static const Duration kQuietDelay = Duration(milliseconds: 2900);

  /// Reduce Motion：保留順序與語意，只是把位移演出拿掉。
  /// 刻意不歸零——全部同拍會變成突兀的閃爍，反而讓人讀不出因果。
  /// 衝擊點一樣綁在（縮短後的）勾勾筆尖上。
  static const Duration kReducedImpactDelay = kCheckDrawDurationReduced;
  static const Duration kReducedSpeakDelay = Duration(
    milliseconds: kCheckDrawReducedMs + kSpeakAfterImpactReducedMs,
  );
  static const Duration kReducedRecoverDelay = Duration(milliseconds: 400);

  /// 里程碑補送距離該成員自己的衝擊點多久（跟一般的 speak 同一個間隔）。
  static const Duration kMilestoneHandoffAfterImpact = Duration(
    milliseconds: kSpeakAfterImpactMs,
  );

  /// 連打合併視窗：這段時間內再完成一件，共用同一條 MI 動作弧線，
  /// 不會讓兔咪從第 0 幀重蹲一次。每一件自己的 check / haptic / SFX 照發。
  static const Duration kArcWindow = Duration(milliseconds: 700);

  int _lastEventId = 0;
  int _lastArcId = 0;
  int _generation = 0;

  /// 所有還沒收乾淨的弧線。上一條沒播完的 recover／quiet 不會被下一條蓋掉。
  final List<_CompletionArc> _arcs = [];

  /// 目前的 generation；離開首頁／跨日／dispose 會遞增。
  int get generation => _generation;

  _CompletionArc? get _openArc {
    for (final arc in _arcs) {
      if (arc.generation == _generation &&
          arc.windowOpen &&
          arc.hasLiveMember) {
        return arc;
      }
    }
    return null;
  }

  /// 連打合併視窗還開著（**不代表整條演出結束**，收尾拍另外看
  /// [presentationActive]）。
  bool get arcActive => _openArc != null;

  /// 還有任何一拍沒播完：跟在後面的 impact、recover、quiet 都算。
  bool get presentationActive => _arcs.any(
    (a) => a.beats.isNotEmpty || a.recoverTimer != null || a.quietTimer != null,
  );

  /// 最後一次發出的事件序號。
  int get lastEventId => _lastEventId;

  /// 這個事件還沒被撤銷／失效。
  bool isLive(int eventId) =>
      _arcs.any((a) => a.generation == _generation && a.live.contains(eventId));

  /// 開始一次完成演出，回傳這次的事件。
  ///
  /// [CompletionPhase.confirm] 會同步發出（資料已經提交了，確認不該等）。
  /// [crossedHalf] 為 true 時整條弧線升級成里程碑語意：已經在跑的弧線不重啟
  /// 動作；若語意已經發過了，就安排一次 [CompletionPhase.milestoneHandoff]。
  HomeCompletionEvent start({
    required String habitKey,
    required int? dayRevision,
    required bool crossedHalf,
    required int doneCount,
    required bool reduceMotion,
  }) {
    final arc = _openArc ?? _startArc();
    final event = HomeCompletionEvent(
      id: ++_lastEventId,
      arcId: arc.id,
      generation: _generation,
      habitKey: habitKey,
      dayRevision: dayRevision,
      crossedHalf: crossedHalf,
      doneCount: doneCount,
      reduceMotion: reduceMotion,
    );
    arc.members[event.id] = event;
    arc.live.add(event.id);

    onPhase(CompletionPhase.confirm, event, arc.kind);

    final isLead = arc.leadEventId == event.id;
    if (isLead) {
      arc.windowTimer = Timer(kArcWindow, () {
        arc.windowTimer = null;
        arc.windowOpen = false;
        _sweep();
      });
      if (reduceMotion) {
        _armArc(arc, kReducedSpeakDelay, CompletionPhase.speak, event);
      } else {
        _armArc(arc, kNoticeDelay, CompletionPhase.notice, event);
        _armArc(arc, kAnticipateDelay, CompletionPhase.anticipate, event);
        _armArc(arc, kSpeakDelay, CompletionPhase.speak, event);
      }
    } else if (crossedHalf) {
      // 跟在後面才跨過門檻：語意還沒發就等 speak 自己重算；已經發過了就
      // 補送一次里程碑（不重啟動作）。
      _armArc(
        arc,
        Duration(
          milliseconds:
              (reduceMotion ? kCheckDrawReducedMs : kCheckDrawMs) +
              kSpeakAfterImpactMs,
        ),
        CompletionPhase.milestoneHandoff,
        event,
      );
    }

    // 每一件都有自己的衝擊點：勾勾、觸覺、音效不會因為合併而消失。
    _armArc(
      arc,
      reduceMotion ? kReducedImpactDelay : kImpactDelay,
      CompletionPhase.impact,
      event,
      soloBeat: true,
    );

    // 尾韻掛在這條弧線上，跟著它最後一件往後延；**不會**被下一條弧線取消。
    arc.recoverTimer?.cancel();
    arc.recoverTimer = Timer(
      reduceMotion ? kReducedRecoverDelay : kRecoverDelay,
      () {
        arc.recoverTimer = null;
        _dispatch(CompletionPhase.recover, event, arc, soloBeat: false);
        _sweep();
      },
    );
    arc.quietTimer?.cancel();
    arc.quietTimer = Timer(kQuietDelay, () {
      arc.quietTimer = null;
      _dispatch(CompletionPhase.quiet, event, arc, soloBeat: false);
      _sweep();
    });

    return event;
  }

  _CompletionArc _startArc() {
    final arc = _CompletionArc(++_lastArcId, _generation, _lastEventId + 1);
    _arcs.add(arc);
    return arc;
  }

  /// 只讓**某一件**的演出失效（撤銷那一件時用）。
  ///
  /// 回傳這條弧線還在不在——呼叫端據此決定要不要送出動作取消，
  /// 而不是用目前的 reaction tick 去猜。
  CompletionCancelOutcome cancelEvent(int eventId) {
    for (final arc in _arcs) {
      if (!arc.live.contains(eventId)) continue;
      arc.live.remove(eventId);
      if (arc.hasLiveMember) return CompletionCancelOutcome.arcSurvives;
      arc.disposeTimers();
      arc.windowOpen = false;
      _arcs.remove(arc);
      return CompletionCancelOutcome.arcEnded;
    }
    return CompletionCancelOutcome.unknown;
  }

  /// 丟掉所有還沒發生的 phase 並讓整個 generation 失效。
  ///
  /// 用在離開首頁、跨日／同日換快照、重載開始、dispose。已經發生過的不會
  /// 回滾——撤銷資料是 [onPhase] 呼叫端的事，這裡只保證「過時的裝飾不會再播」。
  void invalidate() {
    cancel();
    _generation++;
  }

  /// 清掉所有排程但保留 generation。
  void cancel() {
    for (final arc in _arcs) {
      arc.disposeTimers();
    }
    _arcs.clear();
  }

  void dispose() => invalidate();

  void _sweep() {
    _arcs.removeWhere(
      (a) =>
          !a.windowOpen &&
          a.beats.isEmpty &&
          a.recoverTimer == null &&
          a.quietTimer == null,
    );
  }

  void _armArc(
    _CompletionArc arc,
    Duration delay,
    CompletionPhase phase,
    HomeCompletionEvent event, {
    bool soloBeat = false,
  }) {
    late final Timer timer;
    timer = Timer(delay, () {
      arc.beats.remove(timer);
      _dispatch(phase, event, arc, soloBeat: soloBeat);
      _sweep();
    });
    arc.beats.add(timer);
  }

  /// 發出前的最後一道關卡。
  ///
  /// - generation 不同 → 這是上一個畫面／上一天留下來的，丟掉。
  /// - 單件拍（impact）只看自己那一件還在不在。
  /// - 弧線拍只要弧線裡還有任何一件有效就照發：撤銷 A 不該把 B 的反應吃掉。
  /// - speak／milestoneHandoff 各自只發一次，語意由**這條弧線**當下的成員決定。
  /// - 最後再問呼叫端「現在還播得出來嗎」。
  void _dispatch(
    CompletionPhase phase,
    HomeCompletionEvent event,
    _CompletionArc arc, {
    required bool soloBeat,
  }) {
    if (event.generation != _generation || arc.generation != _generation) {
      return;
    }
    if (soloBeat) {
      if (!arc.live.contains(event.id)) return;
    } else if (!arc.hasLiveMember) {
      return;
    }
    if (phase == CompletionPhase.speak) {
      if (arc.semanticDelivered) return;
    } else if (phase == CompletionPhase.milestoneHandoff) {
      // 語意還沒發 → speak 自己會用重算後的 kind，不需要補送。
      // 已經降回 ordinary（半程成員被撤銷）→ 也不補送。
      if (!arc.semanticDelivered ||
          arc.milestoneDelivered ||
          arc.kind != CompletionKind.half) {
        return;
      }
    }
    if (isStillValid != null && !isStillValid!(event)) return;
    if (phase == CompletionPhase.speak) {
      arc.semanticDelivered = true;
      if (arc.kind == CompletionKind.half) {
        arc.milestoneDelivered = true;
      }
    } else if (phase == CompletionPhase.milestoneHandoff) {
      arc.milestoneDelivered = true;
    }
    onPhase(phase, event, arc.kind);
  }
}
