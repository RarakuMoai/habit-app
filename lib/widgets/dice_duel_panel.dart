// 隱藏彩蛋：與兔咪的骰子對決。
//
// 觸發：兔咪場景區（功能卡收合時）用「兩指同時按住不動」約 1.8 秒——
// 比一般長按更久、也不與任何單指互動（點／充電／摸頭）衝突，
// 純粹留給知道的人發現。觸發後像素窗簾（復古遊戲事件感）蓋過
// 功能卡「與底部分頁列」，退去時露出遊戲桌骰盤（[DiceDuelEgg]，
// 由 shell 掛在 root overlay 上，所以能蓋到 tab bar）。
//
// 規則刻意極簡：一顆對一顆、比點數；結果出現後直接再抓同一顆骰子
// 就開始下一局，落點與朝向都延續，不插入「再來一場」或自動重置。
// 底部只記錄這次彩蛋期間的勝場與平手，關閉即清空；沒有任何獎勵、
// 沒有教學文字——彩蛋的樂趣就是自己摸索（骰盤墊本身就是「在這裡甩」
// 的暗示）。骰子物理與畫家整組重用計時遊戲的 dice_world.dart /
// dice_tray.dart（DiceWorldPainter）；兔咪的輸贏反應走既有 persona
// 情境（贏＝星星＋歡呼、輸＝汗滴＋確認、平手＝音符＋確認），
// 不需要新 CG 素材。
//
// 手勢互讓：偵測層把場景區指數同步到 MascotScenePointers.count，
// MascotStage 看到第二指落下會立刻取消充電／摸頭（見 mascot_scene.dart）。

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/app_localizations.dart';
import '../pages/timer/game/dice_tray.dart' show DiceWorldPainter;
import '../pages/timer/game/dice_world.dart';
import '../pages/timer/game/table_timer_theme.dart';
import '../utils/app_feedback.dart';
import '../utils/app_style.dart';
import '../utils/mascot.dart';
import '../utils/prefs_keys.dart';
import '../utils/sfx_service.dart';
import 'mascot_scene.dart';

/// 二／三指長按彩蛋的共用仲裁層：包住兔咪場景區，恰好指定
/// 指數、且每指都近乎靜止地按滿 [holdDuration] 才觸發。指數改變
/// （第 3 指落下、第 4 指讓三指失格或任一指抬起）時立即取消計時，並從當下
/// 以新指數重新計算長按；一次觸控 session 所有彩蛋合計最多觸發一次，
/// 放光手指才重新武裝。指數精確比對讓兩種彩蛋互斥、不會誤觸。
///
/// 不論 [enabled] 與否都會把指數同步進 [MascotScenePointers]，
/// 單指互動的互讓（取消充電）不因彩蛋面板開著而失效。
class TwoFingerEggDetector extends StatefulWidget {
  final bool enabled;
  final VoidCallback onTrigger;

  /// 三指彩蛋為 optional，未提供時完全保持原本二指偵測器行為。
  final bool threeFingerEnabled;
  final VoidCallback? onThreeFingerTrigger;
  final Widget child;

  /// 彩蛋門檻刻意比一般長按（~0.5s）久，誤觸率趨近零。
  static const Duration holdDuration = Duration(milliseconds: 1800);

  const TwoFingerEggDetector({
    super.key,
    required this.enabled,
    required this.onTrigger,
    this.threeFingerEnabled = true,
    this.onThreeFingerTrigger,
    required this.child,
  });

  @override
  State<TwoFingerEggDetector> createState() => _TwoFingerEggDetectorState();
}

class _TwoFingerEggDetectorState extends State<TwoFingerEggDetector> {
  /// 兩指要「同時完全靜止」比單指難，位移容忍放寬一些。
  static const double _slop = 32.0;

  final Map<int, Offset> _origin = {};
  final Set<int> _moved = {};
  Timer? _holdTimer;
  bool _firedThisTouch = false;

  void _syncCount() => MascotScenePointers.count.value = _origin.length;

  void _pointerDown(PointerDownEvent e) {
    _origin[e.pointer] = e.position;
    _syncCount();
    _rearm();
  }

  void _pointerMove(PointerMoveEvent e) {
    final origin = _origin[e.pointer];
    if (origin == null || _moved.contains(e.pointer)) return;
    if ((e.position - origin).distance > _slop) {
      _moved.add(e.pointer);
      _disarm();
    }
  }

  void _pointerUp(int pointer) {
    _origin.remove(pointer);
    _moved.remove(pointer);
    if (_origin.isEmpty) _firedThisTouch = false;
    _syncCount();
    _rearm();
  }

  VoidCallback? _callbackFor(int pointerCount) => switch (pointerCount) {
    2 when widget.enabled => widget.onTrigger,
    3 when widget.threeFingerEnabled => widget.onThreeFingerTrigger,
    _ => null,
  };

  void _rearm() {
    _disarm();
    if (_firedThisTouch) return;
    if (_moved.isNotEmpty) return;
    final pointerCount = _origin.length;
    if (_callbackFor(pointerCount) == null) return;
    _holdTimer = Timer(TwoFingerEggDetector.holdDuration, () {
      // shell 可能在按住期間收起功能卡或關閉彩蛋；觸發
      // 前重讀當下 widget 門檻，避免執行已失效的舊 callback。
      final callback = _callbackFor(pointerCount);
      if (callback == null ||
          _origin.length != pointerCount ||
          _moved.isNotEmpty) {
        return;
      }
      _firedThisTouch = true;
      callback();
    });
  }

  void _disarm() {
    _holdTimer?.cancel();
    _holdTimer = null;
  }

  @override
  void didUpdateWidget(covariant TwoFingerEggDetector oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.enabled != widget.enabled ||
        oldWidget.threeFingerEnabled != widget.threeFingerEnabled ||
        (oldWidget.onThreeFingerTrigger == null) !=
            (widget.onThreeFingerTrigger == null)) {
      _rearm();
    }
  }

  @override
  void dispose() {
    _disarm();
    // 切頁時別把殘留指數留給共用 notifier。
    if (_origin.isNotEmpty) MascotScenePointers.count.value = 0;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _pointerDown,
      onPointerMove: _pointerMove,
      onPointerUp: (e) => _pointerUp(e.pointer),
      onPointerCancel: (e) => _pointerUp(e.pointer),
      child: widget.child,
    );
  }
}

/// 彩蛋整體演出：像素窗簾蓋上 → 換景成骰盤 → 窗簾退去。
/// 結束時同一套倒著跑（窗簾蓋上 → 骰盤卸下 → 退去露回原 UI），
/// 跑完才回呼 [onClosed] 讓 shell 移除 overlay entry。
///
/// 特殊事件不走一般 bottom sheet 上滑——像素馬賽克是「進入小遊戲」
/// 的復古儀式感；音效用現有 unlock（揭曉）／cancel（收場），之後
/// 若補 8-bit 專用音效資產再替換。
class DiceDuelEgg extends StatefulWidget {
  final VoidCallback onClosed;

  /// 面板互動時回報 shell（重置場景閒置凍結，兔咪對局中不睡著）。
  final VoidCallback? onActivity;

  const DiceDuelEgg({super.key, required this.onClosed, this.onActivity});

  @override
  State<DiceDuelEgg> createState() => _DiceDuelEggState();
}

class _DiceDuelEggState extends State<DiceDuelEgg>
    with SingleTickerProviderStateMixin {
  late final AnimationController _curtain; // 0 = 全透明、1 = 蓋滿
  bool _panelVisible = false;
  bool _closing = false;
  int _curtainStep = 0; // 窗簾觸覺節拍（跨檔才震）

  @override
  void initState() {
    super.initState();
    _curtain = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 550),
    )..addListener(_onCurtainTick);
    _openSequence();
  }

  @override
  void dispose() {
    _curtain.dispose();
    super.dispose();
  }

  /// 像素格一路「啵啵啵」鋪滿的觸覺節拍。
  void _onCurtainTick() {
    final step = (_curtain.value * 5).floor();
    if (step != _curtainStep) {
      _curtainStep = step;
      playHaptic(HapticLevel.selection);
    }
  }

  Future<void> _openSequence() async {
    playHaptic(HapticLevel.medium); // 「找到了」的確認感
    try {
      await _curtain.forward().orCancel;
      if (!mounted) return;
      setState(() => _panelVisible = true); // 蓋滿的瞬間換景
      playFeedback(SfxCue.unlock);
      await _curtain.reverse().orCancel;
    } on TickerCanceled {
      return;
    }
  }

  Future<void> _close() async {
    if (_closing) return;
    _closing = true;
    playHaptic(HapticLevel.light);
    try {
      await _curtain.forward().orCancel;
      if (!mounted) return;
      setState(() => _panelVisible = false); // 蓋滿時卸下骰盤，露回原 UI
      unawaited(SfxService.instance.play(SfxCue.cancel));
      await _curtain.reverse().orCancel;
    } on TickerCanceled {
      return;
    }
    widget.onClosed();
  }

  @override
  Widget build(BuildContext context) {
    // 掛在 root overlay、沒有頁面的 Material 祖先：不包一層透明
    // Material 的話，所有 Text 會被畫上黃色雙底線的除錯樣式。
    return Material(
      type: MaterialType.transparency,
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // 窗簾過場期間吸掉觸控，別讓點擊穿到下層功能卡／分頁列。
            Listener(
              behavior: HitTestBehavior.opaque,
              child: const SizedBox.expand(),
            ),
            if (_panelVisible)
              DiceDuelPanel(onClose: _close, onActivity: widget.onActivity),
            IgnorePointer(
              child: AnimatedBuilder(
                animation: _curtain,
                builder: (_, _) => CustomPaint(
                  painter: _PixelCurtainPainter(_curtain.value),
                  isComplex: true,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 像素窗簾：奶油紙／鼠尾草亮階的馬賽克方格按穩定偽隨機順序鋪滿
/// ／退去，偶爾摻一格 sage 深綠當「訊號雜訊」點綴。純方格、無淡入
/// 淡出＝像素感；特殊事件感靠節奏與音效，不靠暗色。
class _PixelCurtainPainter extends CustomPainter {
  final double progress;

  _PixelCurtainPainter(this.progress);

  static const List<Color> _palette = [
    Color(0xFFFFF8EC), // 奶油紙面
    Color(0xFFF6EDDC), // 暖紙
    Color(0xFFDDE9E0), // 鼠尾草收邊
    Color(0xFFCBDFD2), // 淡鼠尾草
  ];

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0) return;
    final cell = (size.width / 22).clamp(14.0, 26.0);
    final cols = (size.width / cell).ceil();
    final rows = (size.height / cell).ceil();
    final paintBox = Paint();
    for (var iy = 0; iy < rows; iy++) {
      for (var ix = 0; ix < cols; ix++) {
        // 每格一個穩定的偽隨機序：progress 掃過去時格子順序固定，
        // 前進／倒帶都是同一張「雜訊圖」在鋪滿／退去。
        final h = ((ix * 73856093) ^ (iy * 19349663)) & 0x7fffffff;
        if ((h % 997) / 997 >= progress) continue;
        paintBox.color = h % 29 == 0
            ? kGameAccent
            : _palette[h % _palette.length];
        canvas.drawRect(
          Rect.fromLTWH(ix * cell, iy * cell, cell + 0.5, cell + 0.5),
          paintBox,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_PixelCurtainPainter old) => old.progress != progress;
}

/// 布墊裝飾：內縮一圈縫線虛線＋中央淺色圓區與蕾絲虛線圓邊。
/// 手縫布物的語彙（樓上房間的圓地毯、蕾絲籃同一家人），
/// 讓墊有「物品感」而不是一片色塊。
class _MatDecorPainter extends CustomPainter {
  const _MatDecorPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final stitch = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round
      ..color = kGameAccent.withValues(alpha: 0.30);

    // 中央圓區：比墊亮半階的「落骰區」，像地毯上再鋪一塊圓布。
    final center = size.center(Offset.zero);
    final radius = math.min(size.width, size.height) * 0.36;
    canvas.drawCircle(center, radius, Paint()..color = const Color(0xFFE9F2EC));
    _dashPath(
      canvas,
      Path()..addOval(Rect.fromCircle(center: center, radius: radius - 7)),
      stitch,
      dash: 7,
      gap: 7,
    );

    // 墊邊內縫線：沿圓角矩形一圈虛線。
    _dashPath(
      canvas,
      Path()..addRRect(
        RRect.fromRectAndRadius(
          Offset.zero & size,
          const Radius.circular(26),
        ).deflate(9),
      ),
      stitch,
      dash: 6,
      gap: 6,
    );
  }

  /// 沿路徑畫等距虛線（PathMetrics 取段）。
  void _dashPath(
    Canvas canvas,
    Path path,
    Paint paint, {
    required double dash,
    required double gap,
  }) {
    for (final metric in path.computeMetrics()) {
      var d = 0.0;
      while (d < metric.length) {
        canvas.drawPath(
          metric.extractPath(d, math.min(d + dash, metric.length)),
          paint,
        );
        d += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(_MatDecorPainter old) => false;
}

/// 對決回合：你擲 → 定格交棒 → 角色擲（throwAll 自動）→ 結果。
enum _DuelPhase { player, handoff, mascot, result }

enum DiceDuelOutcome { playerWin, mascotWin, tie }

/// 只存在這次骰子彩蛋生命週期內的戰績；不讀寫 SharedPreferences。
@immutable
class DiceDuelSessionScore {
  final int rounds;
  final int playerWins;
  final int mascotWins;
  final int ties;

  const DiceDuelSessionScore({
    this.rounds = 0,
    this.playerWins = 0,
    this.mascotWins = 0,
    this.ties = 0,
  });

  DiceDuelSessionScore record(DiceDuelOutcome outcome) {
    return DiceDuelSessionScore(
      rounds: rounds + 1,
      playerWins: playerWins + (outcome == DiceDuelOutcome.playerWin ? 1 : 0),
      mascotWins: mascotWins + (outcome == DiceDuelOutcome.mascotWin ? 1 : 0),
      ties: ties + (outcome == DiceDuelOutcome.tie ? 1 : 0),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DiceDuelSessionScore &&
          rounds == other.rounds &&
          playerWins == other.playerWins &&
          mascotWins == other.mascotWins &&
          ties == other.ties;

  @override
  int get hashCode => Object.hash(rounds, playerWins, mascotWins, ties);
}

/// 常駐在骰盤底部的本次戰績。完整名稱交給語意朗讀；畫面文字會在
/// 狹窄空間等比縮小，避免改名後把「結束遊戲」擠出畫面。
class DiceDuelScoreboard extends StatelessWidget {
  final DiceDuelSessionScore score;
  final String mascotName;

  const DiceDuelScoreboard({
    super.key,
    required this.score,
    required this.mascotName,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final detail = l10n.ddpScoreLine(
      score.playerWins,
      mascotName,
      score.mascotWins,
      score.ties,
    );
    return Semantics(
      container: true,
      label: l10n.ddpScoreSemantics(
        score.rounds,
        score.playerWins,
        mascotName,
        score.mascotWins,
        score.ties,
      ),
      child: ExcludeSemantics(
        child: Container(
          key: const ValueKey('dice-duel-scoreboard'),
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xFFFFFDF9),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: kGameAccent.withValues(alpha: 0.22)),
            boxShadow: [
              BoxShadow(
                color: kGameAccent.withValues(alpha: 0.10),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            children: [
              Icon(
                Icons.emoji_events_rounded,
                size: 19,
                color: kGameAccent.withValues(alpha: 0.82),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.ddpRoundsThisTime(score.rounds),
                      maxLines: 1,
                      style: const TextStyle(
                        color: AppInk.strong,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w900,
                        height: 1,
                      ),
                    ),
                    const SizedBox(height: 4),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        detail,
                        maxLines: 1,
                        style: TextStyle(
                          color: TableTheme.tableInkSoft,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          height: 1,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 對決結果文字獨立成可縮放的摘要。角色名稱雖然目前輸入上限是 6 字，
/// 仍不能假設一定叫「兔咪」或一定是短中文；結果標題與比分各自縮放，
/// 狹窄螢幕也維持單行，而完整內容交給語意標籤朗讀。
class DiceDuelResultSummary extends StatelessWidget {
  final DiceDuelOutcome outcome;
  final String mascotName;
  final int playerValue;
  final int mascotValue;

  const DiceDuelResultSummary({
    super.key,
    required this.outcome,
    required this.mascotName,
    required this.playerValue,
    required this.mascotValue,
  });

  String _resultLabel(AppLocalizations l10n) => switch (outcome) {
    DiceDuelOutcome.playerWin => l10n.ddpYouWin,
    DiceDuelOutcome.mascotWin => l10n.ddpMascotWin(mascotName),
    DiceDuelOutcome.tie => l10n.ddpTie,
  };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final resultLabel = _resultLabel(l10n);
    return Semantics(
      label: l10n.ddpResultSemantics(
        resultLabel,
        playerValue,
        mascotName,
        mascotValue,
      ),
      child: ExcludeSemantics(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                resultLabel,
                maxLines: 1,
                style: AppType.digits(
                  fontSize: 25,
                  fontWeight: FontWeight.w800,
                  color: AppInk.strong,
                ),
              ),
            ),
            const SizedBox(height: 3),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                l10n.ddpVsLine(playerValue, mascotName, mascotValue),
                maxLines: 1,
                style: AppType.digits(
                  fontSize: 13.5,
                  color: TableTheme.tableInkSoft,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 骰盤本體：暖奶油桌面（與對局面同款）＋中央淡鼠尾草布墊＝物理範圍。
/// 沒有擲骰鈕、沒有教學文字——墊上一顆骰子，自己摸索怎麼甩。
class DiceDuelPanel extends StatefulWidget {
  /// 「結束遊戲」按下（退場動畫由 [DiceDuelEgg] 跑）。
  final VoidCallback onClose;
  final VoidCallback? onActivity;

  const DiceDuelPanel({super.key, required this.onClose, this.onActivity});

  @override
  State<DiceDuelPanel> createState() => _DiceDuelPanelState();
}

class _DiceDuelPanelState extends State<DiceDuelPanel>
    with SingleTickerProviderStateMixin {
  final DiceWorld _world = DiceWorld();
  final Map<int, Offset> _pointers = {};

  late final Ticker _ticker;
  Duration _lastTick = Duration.zero;
  bool _settleHandled = false;

  _DuelPhase _phase = _DuelPhase.player;
  int? _playerValue;
  int? _mascotValue;
  DiceDuelOutcome? _outcome;
  DiceDuelSessionScore _score = const DiceDuelSessionScore();
  Timer? _handoffTimer;

  String _mascotName = MascotName.fallback;
  DateTime _lastImpactFeedback = DateTime.fromMillisecondsSinceEpoch(0);
  bool _matReady = false;

  @override
  void initState() {
    super.initState();
    _world.onImpact = _handleImpact;
    _world.spawn(1);
    _ticker = createTicker(_onTick)..start();
    SharedPreferences.getInstance().then((p) {
      if (!mounted) return;
      final name = p.getString(PrefsKeys.mascotName)?.trim();
      if (name != null && name.isNotEmpty) setState(() => _mascotName = name);
    });
  }

  @override
  void dispose() {
    _handoffTimer?.cancel();
    _ticker.dispose();
    _world.dispose();
    super.dispose();
  }

  void _onTick(Duration elapsed) {
    final dt = ((elapsed - _lastTick).inMicroseconds / 1e6).clamp(0.0, 1 / 30);
    _lastTick = elapsed;
    if (_world.bounds == Rect.zero) return;
    _world.step(
      dt,
      _phase == _DuelPhase.player ? _pointers.values.toList() : const [],
    );
    if (_world.settled && !_settleHandled) {
      _settleHandled = true;
      _handleSettled();
    } else if (!_world.settled && _settleHandled) {
      _settleHandled = false;
    }
  }

  void _handleSettled() {
    switch (_phase) {
      case _DuelPhase.player:
        _playerValue = _world.total;
        playHaptic(HapticLevel.medium); // 定格
        setState(() => _phase = _DuelPhase.handoff);
        // 交棒小停頓：看清自己的點數，兔咪才出手。
        _handoffTimer = Timer(const Duration(milliseconds: 1100), () {
          if (!mounted) return;
          setState(() => _phase = _DuelPhase.mascot);
          playFeedback(SfxCue.gameDice);
          _world.throwAll();
        });
      case _DuelPhase.mascot:
        _mascotValue = _world.total;
        _finishRound();
      case _DuelPhase.handoff:
      case _DuelPhase.result:
        break;
    }
  }

  void _finishRound() {
    final p = _playerValue!;
    final b = _mascotValue!;
    final outcome = p == b
        ? DiceDuelOutcome.tie
        : (b > p ? DiceDuelOutcome.mascotWin : DiceDuelOutcome.playerWin);
    setState(() {
      _outcome = outcome;
      _score = _score.record(outcome);
      _phase = _DuelPhase.result;
    });
    switch (outcome) {
      case DiceDuelOutcome.mascotWin:
        playHaptic(HapticLevel.medium);
        // 星星泡泡＋歡呼聲＋雙手高舉。
        MascotPersona.setForContext(
          MascotEmotion.popHappy.assetPath,
          MascotContext.diceMascotWin,
          speech: MascotLines.randomLineFor(MascotContext.diceMascotWin),
          force: true,
        );
      case DiceDuelOutcome.playerWin:
        playHaptic(HapticLevel.light);
        // 輸了不難過（sad 太重）：圓眼期待＋小汗滴，並用確認聲接住稱讚／認輸台詞。
        MascotPersona.setForContext(
          MascotEmotion.expect.assetPath,
          MascotContext.diceMascotLoss,
          speech: MascotLines.randomLineFor(MascotContext.diceMascotLoss),
          force: true,
        );
      case DiceDuelOutcome.tie:
        playHaptic(HapticLevel.light);
        MascotPersona.setForContext(
          MascotEmotion.expect.assetPath,
          MascotContext.diceTie,
          speech: MascotLines.randomLineFor(MascotContext.diceTie),
          force: true,
        );
    }
  }

  /// spawn 的掌心隊形算式對單顆也會右偏 1.15×骰寬；
  /// 對決只有一顆，擺回墊（蕾絲圓區）正中央。
  void _spawnCentered() {
    _world.spawn(1);
    if (_world.bounds != Rect.zero) {
      _world.dice.single.pos = _world.bounds.center;
    }
  }

  /// 結果後直接接續同一顆骰子：不 spawn、不改位置、不改朝向。
  /// 下一個 pointer-down 會立刻把這顆已停穩的骰子重新喚醒並吸向手指。
  void _continueFromResult() {
    if (_phase != _DuelPhase.result) return;
    _handoffTimer?.cancel();
    _pointers.clear();
    _playerValue = null;
    _mascotValue = null;
    _outcome = null;
    _settleHandled = false;
    _world.wake();
    setState(() => _phase = _DuelPhase.player);
  }

  // 碰撞回饋：同骰盤（音量隨力道、90ms 節流）。
  void _handleImpact(double strength) {
    final now = DateTime.now();
    if (now.difference(_lastImpactFeedback).inMilliseconds < 90) return;
    _lastImpactFeedback = now;
    unawaited(
      SfxService.instance.play(
        SfxCue.gameDice,
        volumeScale: (strength / 2400).clamp(0.25, 1.0),
      ),
    );
    playHaptic(strength > 1100 ? HapticLevel.medium : HapticLevel.selection);
  }

  void _pointerDown(PointerDownEvent e) {
    widget.onActivity?.call();
    if (_phase == _DuelPhase.result) _continueFromResult();
    if (_phase != _DuelPhase.player) return;
    _pointers[e.pointer] = e.localPosition;
    _world.wake();
    playHaptic(HapticLevel.selection); // 「吸住了」
  }

  void _pointerMove(PointerMoveEvent e) {
    if (_pointers.containsKey(e.pointer)) {
      _pointers[e.pointer] = e.localPosition;
    }
  }

  void _pointerUp(int pointer) {
    if (_pointers.remove(pointer) == null) return;
    if (_pointers.isNotEmpty) return;
    _world.releaseBurst();
    if (_world.anyFast) {
      playFeedback(SfxCue.gameDice, haptic: HapticLevel.medium);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).padding.bottom;
    return LayoutBuilder(
      builder: (context, box) {
        // 底部按鈕帶以外都是骰盤墊；墊內縮一圈＝物理牆，
        // 骰子尺寸跟墊高走（SE 超緊湊高度也要能玩）。
        final buttonZone = 68.0 + bottomPad;
        final mat = Rect.fromLTRB(
          14,
          14,
          box.maxWidth - 14,
          box.maxHeight - buttonZone - 4,
        );
        final die = (mat.height * 0.30).clamp(60.0, 100.0);
        _world.setBounds(mat.deflate(12), die);
        // 第一次拿到真實墊範圍後把骰子重擺到墊中央（initState 的
        // spawn 發生在 bounds 之前，會縮在 fallback 座標）。
        if (!_matReady) {
          _matReady = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && !_world.hasBeenThrown) _spawnCentered();
          });
        }
        return Stack(
          fit: StackFit.expand,
          children: [
            // 桌面：與對局面同一套暖奶油紙面（遊戲桌融合定案的語彙），
            // 彩蛋是「兔咪家的桌遊角落」，不是賭場。
            DecoratedBox(decoration: TableTheme.feltBackground()),
            // 骰盤墊：鼠尾草布墊——縫線虛線邊＋中央蕾絲圓區，
            // 呼應樓上房間圓地毯的語彙，也是「在這裡甩」的無文字暗示。
            Positioned.fromRect(
              rect: mat,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFFDFEDE3), Color(0xFFCFE2D6)],
                  ),
                  borderRadius: BorderRadius.circular(26),
                  border: Border.all(
                    color: kGameAccent.withValues(alpha: 0.38),
                    width: 1.4,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: kGameAccent.withValues(alpha: 0.22),
                      blurRadius: 22,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: const CustomPaint(painter: _MatDecorPainter()),
              ),
            ),
            // 物理場：你的回合整面都能按住吸骰子、甩出去。
            IgnorePointer(
              ignoring:
                  _phase != _DuelPhase.player && _phase != _DuelPhase.result,
              child: Listener(
                key: const ValueKey('dice-duel-physics-field'),
                behavior: HitTestBehavior.opaque,
                onPointerDown: _pointerDown,
                onPointerMove: _pointerMove,
                onPointerUp: (e) => _pointerUp(e.pointer),
                onPointerCancel: (e) => _pointerUp(e.pointer),
                child: CustomPaint(
                  painter: DiceWorldPainter(_world),
                  isComplex: true,
                ),
              ),
            ),
            // 你的點數：定格後小膠囊浮在墊頂，兔咪擲的時候還看得到。
            if (_playerValue != null &&
                (_phase == _DuelPhase.handoff || _phase == _DuelPhase.mascot))
              Positioned(
                top: mat.top + 10,
                left: 0,
                right: 0,
                child: Center(
                  child: _capsule(
                    child: Text(
                      AppLocalizations.of(context).ddpYouPrefix(_playerValue!),
                      style: AppType.digits(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: AppInk.strong,
                      ),
                    ),
                  ),
                ),
              ),
            // 結果：墊中央偏上浮現，大字＋小比分。
            if (_phase == _DuelPhase.result)
              Positioned(
                top: mat.top,
                left: mat.left,
                right: box.maxWidth - mat.right,
                height: mat.height,
                child: Align(
                  alignment: const Alignment(0, -0.55),
                  child: IgnorePointer(
                    child: SizedBox(
                      width: math.min(mat.width - 24, 320),
                      child: _capsule(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 26,
                          vertical: 12,
                        ),
                        child: DiceDuelResultSummary(
                          outcome: _outcome!,
                          mascotName: _mascotName,
                          playerValue: _playerValue!,
                          mascotValue: _mascotValue!,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            // 底部只保留本次戰績＋退出；下一局直接抓骰子，不插入按鈕。
            Positioned(
              left: 14,
              right: 14,
              bottom: bottomPad + 10,
              child: Row(
                children: [
                  Expanded(
                    child: DiceDuelScoreboard(
                      score: _score,
                      mascotName: _mascotName,
                    ),
                  ),
                  const SizedBox(width: 9),
                  _pillButton(
                    label: AppLocalizations.of(context).ddpEndGame,
                    filled: false,
                    width: 100,
                    onTap: widget.onClose,
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  /// 暖白膠囊卡：與全 app 卡片同語彙（暖白底＋淡 sage 邊＋柔影）。
  Widget _capsule({Widget? child, EdgeInsetsGeometry? padding}) {
    return Container(
      padding:
          padding ?? const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFDF9),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: kGameAccent.withValues(alpha: 0.18)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }

  /// 一頁一實色 CTA：主鈕鼠尾草實色白字、次鈕暖白底淡染描邊。
  Widget _pillButton({
    required String label,
    required bool filled,
    double width = 132,
    required VoidCallback onTap,
  }) {
    return Material(
      color: filled ? kGameAccent : const Color(0xFFFFFDF9),
      shape: filled
          ? const StadiumBorder()
          : StadiumBorder(
              side: BorderSide(
                color: kGameAccent.withValues(alpha: 0.35),
                width: 1.2,
              ),
            ),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: SizedBox(
          width: width,
          height: 46,
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w900,
                color: filled ? Colors.white : kGameAccentDark,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
