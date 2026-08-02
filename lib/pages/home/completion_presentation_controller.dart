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

/// 呼叫端對一次語意交付的回覆。
///
/// speak 與 milestoneHandoff 是「一條弧線只發一次」的拍子，過去只要 timer
/// 響過就記成已交付。但呼叫端可能整拍被拒（更高優先的狀態、更新的擁有權），
/// 那一次其實什麼都沒發生——把資格消耗掉，之後**真的**跨過門檻的成員就再也
/// 交付不出去了。改成由呼叫端明確回覆，只有 [delivered] 才消耗資格。
enum CompletionDelivery {
  /// 呼叫端真的把語意套用上去了。
  delivered,

  /// 這一次被擋下或延後，什麼都沒發生。之後的成員仍可再試。
  rejected,

  /// 這個成員／語意已經不成立（畫面沒了、弧線已降級），丟掉就好。
  /// 與 [rejected] 一樣不消耗資格，分開只是為了讀得出原因。
  obsolete,
}

/// 一拍排程綁在誰身上。
///
/// 這是「被撤銷的 timer 不得冒用別人」的資料模型根據，不是四個時間點的特例。
enum _BeatScope {
  /// 綁在**排程它的那個成員**身上。那一件被撤銷，這一拍就作廢——不能改掛到
  /// 弧線裡其他還活著的成員身上。每一件自己的衝擊點與語意機會都是這種。
  member,

  /// 綁在**整條弧線**身上。只要弧線裡還有任何有效成員就照發，送出去的
  /// payload 換成仍然有效的代表成員。察覺、蹲跳與收尾拍是這種：領頭被撤銷
  /// 但別人還在時，那段共用的動作仍然該演完。
  arc,
}

/// 一次「跨過一半門檻」的事件。
///
/// 門檻不是弧線的屬性，是**有因果來源的一次事件**：某一件把進度從門檻以下
/// 推到門檻以上。舊模型只有一個 `crossedHalf` 歷史旗標加上一個 arc 層級的
/// terminal 布林，答不出四個問題——哪一件跨的、那一件演到衝擊點了沒、這次
/// 交付屬於哪一次跨越、撤銷有沒有把那次跨越否定掉。
///
/// 一條弧線同一時間最多只有一個有效 episode：已經在門檻之上時再完成一件
/// 不是「又跨了一次」，撤銷讓進度掉回門檻以下才會結束目前這一次。
class _MilestoneEpisode {
  _MilestoneEpisode({required this.id, required this.sourceEventId});

  /// 門檻世代。交付與否記的是這個 id，不是一個永久的布林。
  final int id;

  /// **歷史來源**：當初是哪一件把進度推過門檻的。
  ///
  /// 只用來認出「這次跨越的因果起點」，**不決定之後誰能交付**。撤銷它不等於
  /// 撤銷使用者看得見的進度——別的習慣可能仍然完成著，門檻照樣成立。
  final int sourceEventId;

  /// 因果起點已經發生：來源那一件演到自己的衝擊點了。
  ///
  /// 在那之前，任何成員的機會都不能把這次跨越講出去——使用者還沒看到那一勾
  /// 落下，兔咪不該先為它慶祝。之後即使來源被撤銷，這件事仍然「發生過」。
  bool crossingImpacted = false;

  /// 門檻此刻是否**真的**還成立。權威是 Home 的實際進度，不是成員的存活
  /// （見 [CompletionPresentationController.syncAboveThreshold]）。
  bool thresholdHolds = true;
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

  /// 一般完成的語意已經交付過了（整條弧線一次）。
  ///
  /// **只有呼叫端真的套用了才會設**——被拒的那一次什麼都沒發生，不該把後面
  /// 成員的機會一起吃掉。以 half 交付時同樣算數：里程碑本來就涵蓋一般完成。
  bool ordinaryDelivered = false;

  /// 目前這一次跨越門檻的事件；null = 進度不在門檻之上。
  _MilestoneEpisode? episode;

  /// 已經交付過語意的那一次跨越。
  ///
  /// 這裡放 id 而不是布林，是整組修正的關鍵：half 交付不再是「這條弧線的
  /// 語意到此為止」，而是「第 N 次跨越已經講過了」。撤銷讓進度掉回門檻以下
  /// 再重新跨過去，就是第 N+1 次，可以再講一次。
  int? deliveredEpisodeId;

  /// 已經演到自己衝擊點的成員。
  ///
  /// 「誰可以當交付的 anchor」看的是這個集合，不是誰當初跨過門檻的：
  /// 語意必須由**自己**的因果鏈（自己的 impact → 自己的機會）觸發。
  final Set<int> impacted = {};

  /// 這一件把進度推過門檻了。
  ///
  /// 門檻還成立時不算新的一次——那只是「又完成一件」，不是重新跨越。
  void openEpisode({required int id, required int sourceEventId}) {
    if (episode != null && episode!.thresholdHolds) return;
    episode = _MilestoneEpisode(id: id, sourceEventId: sourceEventId);
  }

  /// 進度真的跌回門檻以下了：這一次跨越到此為止。
  void invalidateEpisode() => episode?.thresholdHolds = false;

  /// 某一件演到自己的衝擊點了。
  void markImpactReached(int eventId) {
    impacted.add(eventId);
    if (episode?.sourceEventId == eventId) episode!.crossingImpacted = true;
  }

  /// 從 [anchorEventId] 這個成員的角度看，這一刻的語意是一般完成還是里程碑。
  ///
  /// 四個條件缺一不可：
  ///   1. 有一次跨越；
  ///   2. 它此刻仍然成立（Home 的實際進度說了算，**不是**來源的存活）；
  ///   3. 這次跨越的因果起點已經發生（來源演到過自己的衝擊點）；
  ///   4. anchor 自己也已經演到衝擊點。
  ///
  /// 第 2 與第 3 點分開，是這一版的重點：撤銷 C 不代表使用者看得見的進度
  /// 掉下去了——別的習慣還完成著。那時這次跨越仍然 pending，只是要換一個
  /// 已經 impact 的有效成員在**它自己的**機會上交付。
  CompletionKind kindFor(int anchorEventId) {
    final ep = episode;
    if (ep == null || !ep.thresholdHolds || !ep.crossingImpacted) {
      return CompletionKind.ordinary;
    }
    if (!impacted.contains(anchorEventId)) return CompletionKind.ordinary;
    return CompletionKind.half;
  }

  /// 這一刻的語意還需不需要送。
  bool needsSemantic(CompletionKind kind) => kind == CompletionKind.half
      ? episode!.id != deliveredEpisodeId
      : !ordinaryDelivered;

  /// 呼叫端回覆 [CompletionDelivery.delivered] 之後才呼叫。
  void markSemanticDelivered(CompletionKind kind) {
    ordinaryDelivered = true;
    if (kind == CompletionKind.half) deliveredEpisodeId = episode?.id;
  }

  /// 合併視窗還開著（還能收新成員進來）。
  bool windowOpen = true;

  Timer? windowTimer;
  Timer? recoverTimer;
  Timer? quietTimer;
  final Set<Timer> beats = {};

  bool get hasLiveMember => live.isNotEmpty;

  /// 這條弧線目前的代表成員：原本那一件還活著就是它，否則挑最早的有效成員。
  ///
  /// 弧線拍（speak／recover／quiet／milestoneHandoff）不該帶著一個**已經被
  /// 撤銷**的事件出去：呼叫端會拿它去查 epoch、組 token，查到的都是已經被
  /// 清掉的東西。語意身分本身另外掛在 [id]（見 [HomeCompletionEvent.arcId]），
  /// 這裡只保證「傳出去的成員是活的」。
  HomeCompletionEvent? canonicalFor(HomeCompletionEvent event) {
    if (live.contains(event.id)) return event;
    if (live.isEmpty) return null;
    final firstLive = live.reduce((a, b) => a < b ? a : b);
    return members[firstLive];
  }

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
  ///
  /// 回傳值只對 speak 與 milestoneHandoff 有意義：見 [CompletionDelivery]。
  final CompletionDelivery Function(
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
  int _lastEpisodeId = 0;
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
    if (crossedHalf) {
      arc.openEpisode(id: ++_lastEpisodeId, sourceEventId: event.id);
    }

    onPhase(CompletionPhase.confirm, event, arc.kindFor(event.id));

    final isLead = arc.leadEventId == event.id;
    if (isLead) {
      arc.windowTimer = Timer(kArcWindow, () {
        arc.windowTimer = null;
        arc.windowOpen = false;
        _sweep();
      });
      // 察覺與蹲跳是整條弧線共用的那段動作：領頭被撤銷但別人還在時，
      // 它們仍然該演完，所以綁在弧線上。
      if (!reduceMotion) {
        _arm(
          arc,
          kNoticeDelay,
          event,
          phase: CompletionPhase.notice,
          scope: _BeatScope.arc,
        );
        _arm(
          arc,
          kAnticipateDelay,
          event,
          phase: CompletionPhase.anticipate,
          scope: _BeatScope.arc,
        );
      }
    }

    // 每一件都有自己的衝擊點：勾勾、觸覺、音效不會因為合併而消失。
    _arm(
      arc,
      reduceMotion ? kReducedImpactDelay : kImpactDelay,
      event,
      phase: CompletionPhase.impact,
      scope: _BeatScope.member,
    );

    // 每一件都在自己的衝擊點之後提供**一次語意機會**。
    //
    // 不是「領頭發 speak、跨門檻的後續成員發 handoff」那種寫死的分工：
    // 領頭那一次可能被更高優先的狀態擋下來（撤銷、喝水過量），若只有它有
    // 機會，這條弧線就再也開不了口。改成人人有機會、但由弧線的交付進度
    // 決定要不要用（見 [_CompletionArc.needsSemantic]），被拒的那一次
    // 什麼都不消耗。
    //
    // 時間點沿用各自原本的公式：領頭在 Reduce Motion 下用較短的間隔，
    // 後續成員維持一般間隔（兩者本來就不同，本輪不調整）。
    _arm(
      arc,
      isLead
          ? (reduceMotion ? kReducedSpeakDelay : kSpeakDelay)
          : Duration(
              milliseconds:
                  (reduceMotion ? kCheckDrawReducedMs : kCheckDrawMs) +
                  kSpeakAfterImpactMs,
            ),
      event,
      phase: null, // 語意機會：要送哪一種在交付當下才決定
      scope: _BeatScope.member,
    );

    // 尾韻掛在這條弧線上，跟著它最後一件往後延；**不會**被下一條弧線取消。
    arc.recoverTimer?.cancel();
    arc.recoverTimer = Timer(
      reduceMotion ? kReducedRecoverDelay : kRecoverDelay,
      () {
        arc.recoverTimer = null;
        _dispatch(
          arc,
          event,
          phase: CompletionPhase.recover,
          scope: _BeatScope.arc,
        );
        _sweep();
      },
    );
    arc.quietTimer?.cancel();
    arc.quietTimer = Timer(kQuietDelay, () {
      arc.quietTimer = null;
      _dispatch(
        arc,
        event,
        phase: CompletionPhase.quiet,
        scope: _BeatScope.arc,
      );
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
      // **不**在這裡動 episode：撤銷歷史來源不等於使用者看得見的進度掉下去
      // （別的習慣可能仍然完成著）。門檻還成不成立由 Home 在資料寫完之後
      // 用 [syncAboveThreshold] 回報——這裡沒有那個資訊，不該單方面銷毀。
      if (arc.hasLiveMember) return CompletionCancelOutcome.arcSurvives;
      arc.disposeTimers();
      arc.windowOpen = false;
      _arcs.remove(arc);
      return CompletionCancelOutcome.arcEnded;
    }
    return CompletionCancelOutcome.unknown;
  }

  /// Home 回報「目前的進度是不是還在門檻之上」。
  ///
  /// 門檻的真相在 Home 的資料，不在弧線成員的歷史旗標：使用者可能撤銷一件
  /// **根本不屬於這條弧線**的舊習慣，進度一樣會掉回門檻以下。跌下去之後
  /// 正在進行的那一次跨越就不成立了；要再講一次里程碑，必須真的再跨一次。
  ///
  /// 只有「跌下去」需要處理——重新跨過去一定伴隨一次新的完成事件，那時
  /// [start] 會帶著 `crossedHalf` 開一次新的 episode。
  void syncAboveThreshold(bool aboveThreshold) {
    if (aboveThreshold) return;
    for (final arc in _arcs) {
      arc.invalidateEpisode();
    }
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

  /// 排一拍。
  ///
  /// [source] 是**排程來源成員**——這一拍是誰排的。它跟送出去的 payload 是
  /// 兩件事：[_BeatScope.arc] 會在來源被撤銷時換成仍有效的代表成員，
  /// [_BeatScope.member] 則直接作廢。[phase] 為 null 代表這是一次語意機會，
  /// 要送 speak 還是 milestoneHandoff 在交付當下才決定。
  void _arm(
    _CompletionArc arc,
    Duration delay,
    HomeCompletionEvent source, {
    required CompletionPhase? phase,
    required _BeatScope scope,
  }) {
    late final Timer timer;
    timer = Timer(delay, () {
      arc.beats.remove(timer);
      _dispatch(arc, source, phase: phase, scope: scope);
      _sweep();
    });
    arc.beats.add(timer);
  }

  /// 發出前的最後一道關卡。
  ///
  /// 順序刻意固定：generation → 排程身分 → 語意資格 → 呼叫端的可播檢查。
  ///
  /// - generation 不同 → 這是上一個畫面／上一天留下來的，丟掉。
  /// - [_BeatScope.member] → 排它的那一件被撤銷就整拍作廢。**不 canonicalize**：
  ///   被撤銷的 B 留下的里程碑 timer 不得改掛到後來才加入的 C 身上，
  ///   否則 C 的語意會在 C 自己的衝擊點之前就先發出去。
  /// - [_BeatScope.arc] → 弧線裡還有任何一件有效就照發，payload 換成仍然
  ///   有效的代表成員（撤銷領頭不該把跟著的人的收尾一起吃掉）。
  /// - 語意機會 → 由弧線的交付進度決定要不要用；被拒不消耗。
  void _dispatch(
    _CompletionArc arc,
    HomeCompletionEvent source, {
    required CompletionPhase? phase,
    required _BeatScope scope,
  }) {
    if (source.generation != _generation || arc.generation != _generation) {
      return;
    }
    final HomeCompletionEvent payload;
    switch (scope) {
      case _BeatScope.member:
        if (!arc.live.contains(source.id)) return;
        payload = source;
      case _BeatScope.arc:
        final canonical = arc.canonicalFor(source);
        if (canonical == null) return;
        payload = canonical;
    }

    if (phase != null) {
      if (isStillValid != null && !isStillValid!(payload)) return;
      // 衝擊點是門檻事件的因果起點：那一勾落下之後，這次跨越才能被講出來。
      // 放在可播檢查之後——看不到的那一拍不算真的發生過。
      if (phase == CompletionPhase.impact) arc.markImpactReached(payload.id);
      onPhase(phase, payload, arc.kindFor(payload.id));
      return;
    }

    // ── 語意機會 ──
    // kind 從**這個 anchor** 的角度在這一刻重算。語意機會是 member-scoped，
    // payload 就是排程它的那一件（被撤銷的話上面已經整拍作廢），所以
    // 「交付由 anchor 自己的因果鏈觸發」在資料模型上就成立，不需要在
    // callback 當下臨時挑一個人頂替。
    final kind = arc.kindFor(payload.id);
    if (!arc.needsSemantic(kind)) return;
    if (isStillValid != null && !isStillValid!(payload)) return;
    // 這條弧線還沒開過口 → 這一次就是它的第一次開口（speak），不論語意是
    // 一般完成還是里程碑（領頭之前若已經有成員跨過門檻並演到衝擊點，
    // 第一次開口就直接整合成里程碑，不必先講一次一般完成再補一次）。
    // 已經開過口、之後才跨過門檻 → 那才是補送（milestoneHandoff）。
    final semanticPhase = arc.ordinaryDelivered && kind == CompletionKind.half
        ? CompletionPhase.milestoneHandoff
        : CompletionPhase.speak;
    // 交付與否由呼叫端回覆。先設旗標的話，被擋下的那一次會把資格吃掉——
    // 後面真正有效的成員就永遠交付不出去了。
    if (onPhase(semanticPhase, payload, kind) == CompletionDelivery.delivered) {
      arc.markSemanticDelivered(kind);
    }
  }
}
