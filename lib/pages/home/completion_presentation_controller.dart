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
  /// **整條弧線只有這一拍會發出語意事件**，所以里程碑交棒也是換掉它。
  speak,

  /// 落地：回到由目前進度推導的 baseline（不是開 app 的中性臉）。
  recover,

  /// 情緒尾韻結束：清掉台詞。連打時跟著最後一件往後滾。
  quiet,
}

/// 這條弧線最後要用哪一種語意收尾。
///
/// 普通完成是 `completedOne`；一旦某一件跨過一半門檻，整條弧線**升級**成
/// `halfDone`，由里程碑取代普通完成發出唯一那一次泡泡／語音，
/// 而不是先完整演一次普通完成、再靜靜換成 half baseline。
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

  /// 建立當下的 presentation generation。
  final int generation;

  /// 這次完成的習慣身分（id 優先，沒有 id 才退回名稱）。
  final String habitKey;

  /// 建立當下的邏輯日 revision；跨日換快照後舊事件即失效。
  final int? dayRevision;

  /// 這次完成後今天已完成的件數（僅供除錯／記錄；台詞一律在 speak 當下重算）。
  final int doneCount;

  /// 系統開了 Reduce Motion / Disable Animations。
  final bool reduceMotion;

  const HomeCompletionEvent({
    required this.id,
    required this.generation,
    required this.habitKey,
    required this.dayRevision,
    required this.doneCount,
    required this.reduceMotion,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HomeCompletionEvent &&
          id == other.id &&
          generation == other.generation &&
          habitKey == other.habitKey &&
          dayRevision == other.dayRevision &&
          doneCount == other.doneCount &&
          reduceMotion == other.reduceMotion;

  @override
  int get hashCode =>
      Object.hash(id, generation, habitKey, dayRevision, doneCount, reduceMotion);

  @override
  String toString() =>
      'HomeCompletionEvent(#$id gen$generation $habitKey done:$doneCount)';
}

/// 把一次完成拆成有先後的 phase 發出去。
///
/// 呼叫端負責「做什麼」，這裡只負責「什麼時候」「發幾次」「還算不算數」。
class CompletionPresentationController {
  CompletionPresentationController({required this.onPhase, this.isStillValid});

  /// 每個 phase 的接收端。同一個 event 的同一個 phase 最多發一次。
  final void Function(CompletionPhase phase, HomeCompletionEvent event) onPhase;

  /// 呼叫端最後一道關卡：timer 已經喚醒，但畫面可能已經看不到、已經跨日、
  /// 已經 dispose。回 false 就整拍變成 no-op（**不會**回滾任何資料）。
  final bool Function(HomeCompletionEvent event)? isStillValid;

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
  int _generation = 0;

  /// 目前仍然有效的事件 id。撤銷單一件時只從這裡拿掉那一個，
  /// 其他件的 impact 不受影響。
  final Set<int> _live = {};

  /// 這條弧線收進來的所有事件 id（含已被撤銷的，用來判斷弧線還活著沒）。
  final Set<int> _arcMembers = {};
  HomeCompletionEvent? _arcLead;
  CompletionKind _arcKind = CompletionKind.ordinary;

  /// 目前的 generation；離開首頁／跨日／dispose 會遞增。
  int get generation => _generation;

  /// 連打合併視窗還開著（**不代表整條演出結束**，收尾拍另外看
  /// [presentationActive]）。
  bool get arcActive => _arcLead != null;

  /// 還有任何一拍沒播完：跟在後面的 impact、recover、quiet 都算。
  ///
  /// 舊版用 700ms 的 [arcActive] 當「演出結束」，導致視窗關掉之後仍有
  /// follower impact／recover／quiet 會播出去。
  bool get presentationActive =>
      _pending.isNotEmpty || _recoverTimer != null || _quietTimer != null;

  /// 這條弧線最後要用哪一種語意收尾。
  CompletionKind get arcKind => _arcKind;

  /// 最後一次發出的事件序號。
  int get lastEventId => _lastEventId;

  /// 這個事件還沒被撤銷／失效。
  bool isLive(int eventId) => _live.contains(eventId);

  /// 開始一次完成演出，回傳這次的事件。
  ///
  /// [CompletionPhase.confirm] 會同步發出（資料已經提交了，確認不該等）。
  /// [kind] 為 [CompletionKind.half] 時，整條弧線升級成里程碑語意：
  /// 已經在跑的弧線不重啟動作，只把 speak 那一拍換成里程碑。
  HomeCompletionEvent start({
    required String habitKey,
    required int? dayRevision,
    required int doneCount,
    required bool reduceMotion,
    CompletionKind kind = CompletionKind.ordinary,
  }) {
    final event = HomeCompletionEvent(
      id: ++_lastEventId,
      generation: _generation,
      habitKey: habitKey,
      dayRevision: dayRevision,
      doneCount: doneCount,
      reduceMotion: reduceMotion,
    );
    _live.add(event.id);

    onPhase(CompletionPhase.confirm, event);

    // 弧線只由視窗內的第一件開；後面的併進來，不重啟動作。
    if (_arcLead == null) {
      _arcLead = event;
      _arcKind = kind;
      _arcMembers
        ..clear()
        ..add(event.id);
      _arcTimer = Timer(kArcWindow, () {
        _arcTimer = null;
        _arcLead = null;
      });
      if (reduceMotion) {
        _arm(kReducedSpeakDelay, CompletionPhase.speak, event, arcBeat: true);
      } else {
        _arm(kNoticeDelay, CompletionPhase.notice, event, arcBeat: true);
        _arm(kAnticipateDelay, CompletionPhase.anticipate, event, arcBeat: true);
        _arm(kSpeakDelay, CompletionPhase.speak, event, arcBeat: true);
      }
    } else {
      _arcMembers.add(event.id);
      // 里程碑只升不降：連打中途跨過門檻，整條弧線交給里程碑收尾。
      if (kind == CompletionKind.half) _arcKind = CompletionKind.half;
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
        _dispatch(CompletionPhase.recover, event, arcBeat: true);
      },
    );
    _quietTimer?.cancel();
    _quietTimer = Timer(kQuietDelay, () {
      _quietTimer = null;
      _dispatch(CompletionPhase.quiet, event, arcBeat: true);
    });

    return event;
  }

  /// 只讓**某一件**的演出失效（撤銷那一件時用）。
  ///
  /// 其他仍然有效的完成不受影響：它們自己的 impact 照發、資料照留。
  /// 若被撤銷的是弧線裡最後一個還活著的成員，整條弧線一起收掉。
  void cancelEvent(int eventId) {
    _live.remove(eventId);
    if (!_arcMembers.any(_live.contains)) {
      _endArc();
      _recoverTimer?.cancel();
      _recoverTimer = null;
      _quietTimer?.cancel();
      _quietTimer = null;
    }
  }

  /// 丟掉所有還沒發生的 phase 並讓整個 generation 失效。
  ///
  /// 用在離開首頁、跨日換快照、dispose。已經發生過的不會回滾——
  /// 撤銷資料是 [onPhase] 呼叫端的事，這裡只保證「過時的裝飾不會再播」。
  void invalidate() {
    cancel();
    _generation++;
  }

  /// 清掉所有排程但保留 generation（同一個 generation 內的全面停手）。
  void cancel() {
    for (final timer in _pending) {
      timer.cancel();
    }
    _pending.clear();
    _recoverTimer?.cancel();
    _recoverTimer = null;
    _quietTimer?.cancel();
    _quietTimer = null;
    _live.clear();
    _endArc();
  }

  void dispose() => invalidate();

  void _endArc() {
    _arcTimer?.cancel();
    _arcTimer = null;
    _arcLead = null;
    _arcMembers.clear();
    _arcKind = CompletionKind.ordinary;
  }

  void _arm(
    Duration delay,
    CompletionPhase phase,
    HomeCompletionEvent event, {
    bool arcBeat = false,
  }) {
    late final Timer timer;
    timer = Timer(delay, () {
      _pending.remove(timer);
      _dispatch(phase, event, arcBeat: arcBeat);
    });
    _pending.add(timer);
  }

  /// 發出前的最後一道關卡。
  ///
  /// - generation 不同 → 這是上一個畫面／上一天留下來的，丟掉。
  /// - 弧線拍（notice／anticipate／speak／recover／quiet）只要弧線裡還有
  ///   任何一件有效就照發：撤銷 A 不該把 B 的反應一起吃掉。
  /// - 單件拍（impact）只看自己那一件還在不在。
  /// - 最後再問呼叫端「現在還看得到嗎」。
  void _dispatch(
    CompletionPhase phase,
    HomeCompletionEvent event, {
    required bool arcBeat,
  }) {
    if (event.generation != _generation) return;
    final alive = arcBeat
        ? (_arcMembers.any(_live.contains) || _live.contains(event.id))
        : _live.contains(event.id);
    if (!alive) return;
    if (isStillValid != null && !isStillValid!(event)) return;
    onPhase(phase, event);
  }
}
