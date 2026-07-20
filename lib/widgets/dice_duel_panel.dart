// 隱藏彩蛋：與兔咪的骰子對決。
//
// 觸發：兔咪場景區（功能卡收合時）用「兩指同時按住不動」約 1.8 秒——
// 比一般長按更久、也不與任何單指互動（點／充電／摸頭）衝突，
// 純粹留給知道的人發現。觸發後功能卡位置蓋上一塊深色骰盤墊
// （[DiceDuelPanel]），跟兔咪一人一擲比大小。
//
// 規則刻意極簡：一顆對一顆、比點數、平手自動再擲；沒有任何獎勵——
// 彩蛋的價值就是無目的的驚喜。骰子物理與畫家整組重用計時遊戲的
// dice_world.dart / dice_tray.dart（DiceWorldPainter）；兔咪的輸贏反應
// 走既有 persona 情境（贏＝energize 星星＋歡呼、輸與平手＝tapReaction
// 問號＋疑問聲），不需要新 CG 素材。
//
// 手勢互讓：偵測層把場景區指數同步到 MascotScenePointers.count，
// MascotStage 看到第二指落下會立刻取消充電／摸頭（見 mascot_scene.dart）。

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../pages/timer/game/dice_tray.dart' show DiceWorldPainter;
import '../pages/timer/game/dice_world.dart';
import '../pages/timer/game/table_timer_theme.dart';
import '../utils/app_feedback.dart';
import '../utils/app_style.dart';
import '../utils/mascot.dart';
import '../utils/prefs_keys.dart';
import '../utils/sfx_service.dart';
import 'mascot_scene.dart';

/// 兩指長按偵測層：包住兔咪場景區，恰好兩指、都近乎靜止地按滿
/// [holdDuration] 才觸發。任何一指滑動超過 slop、第三指落下或提前
/// 放開都取消；一次觸控最多觸發一次（放光手指才重新武裝）。
///
/// 不論 [enabled] 與否都會把指數同步進 [MascotScenePointers]，
/// 單指互動的互讓（取消充電）不因彩蛋面板開著而失效。
class TwoFingerEggDetector extends StatefulWidget {
  final bool enabled;
  final VoidCallback onTrigger;
  final Widget child;

  /// 彩蛋門檻刻意比一般長按（~0.5s）久，誤觸率趨近零。
  static const Duration holdDuration = Duration(milliseconds: 1800);

  const TwoFingerEggDetector({
    super.key,
    required this.enabled,
    required this.onTrigger,
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

  void _rearm() {
    _disarm();
    if (_firedThisTouch) return;
    if (_origin.length != 2 || _moved.isNotEmpty) return;
    _holdTimer = Timer(TwoFingerEggDetector.holdDuration, () {
      _firedThisTouch = true;
      if (widget.enabled) widget.onTrigger();
    });
  }

  void _disarm() {
    _holdTimer?.cancel();
    _holdTimer = null;
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

/// 對決回合：你擲 → 定格交棒 → 兔咪擲（throwAll 自動）→ 結果。
enum _DuelPhase { player, handoff, bunny, result }

enum _DuelOutcome { playerWin, bunnyWin, tie }

/// 深色骰盤墊面板：蓋在功能卡收合位上（shell 疊 overlay，不動版面）。
/// 自帶進出場動畫；收起時跑完退場再回呼 [onClosed] 讓 shell 移除。
class DiceDuelPanel extends StatefulWidget {
  final VoidCallback onClosed;

  const DiceDuelPanel({super.key, required this.onClosed});

  @override
  State<DiceDuelPanel> createState() => _DiceDuelPanelState();
}

class _DiceDuelPanelState extends State<DiceDuelPanel>
    with TickerProviderStateMixin {
  // 台詞照角色指南：短句、慢熱、真誠；贏了小得意、輸了不氣餒。
  static const List<String> _bunnyWinLines = [
    '我贏了…嘿嘿。',
    '這次是我的。',
    '骰子今天站我這邊。',
  ];
  static const List<String> _playerWinLines = [
    '你贏了…好厲害。',
    '輸了…再來一次好不好？',
    '嗯…下次換我贏。',
  ];
  static const List<String> _tieLines = ['一樣大。', '平手…再來一次。', '嗯？同點。'];

  final math.Random _rng = math.Random();
  final DiceWorld _world = DiceWorld();
  final Map<int, Offset> _pointers = {};

  late final Ticker _ticker;
  Duration _lastTick = Duration.zero;
  bool _settleHandled = false;

  late final AnimationController _slideCtrl;
  late final Animation<Offset> _slide;
  bool _closing = false;

  _DuelPhase _phase = _DuelPhase.player;
  int? _playerValue;
  int? _bunnyValue;
  _DuelOutcome? _outcome;
  Timer? _handoffTimer;
  Timer? _tieTimer;

  String _bunnyName = '兔咪';
  DateTime _lastImpactFeedback = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    _world.onImpact = _handleImpact;
    _world.spawn(1);
    _ticker = createTicker(_onTick)..start();
    _slideCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _slide = Tween(begin: const Offset(0, 1), end: Offset.zero).animate(
      CurvedAnimation(
        parent: _slideCtrl,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      ),
    );
    _slideCtrl.forward();
    SharedPreferences.getInstance().then((p) {
      if (!mounted) return;
      final name = p.getString(PrefsKeys.mascotName)?.trim();
      if (name != null && name.isNotEmpty) setState(() => _bunnyName = name);
    });
  }

  @override
  void dispose() {
    _handoffTimer?.cancel();
    _tieTimer?.cancel();
    _ticker.dispose();
    _slideCtrl.dispose();
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
        _handoffTimer = Timer(const Duration(milliseconds: 900), () {
          if (!mounted) return;
          setState(() => _phase = _DuelPhase.bunny);
          playFeedback(SfxCue.gameDice);
          _world.throwAll();
        });
      case _DuelPhase.bunny:
        _bunnyValue = _world.total;
        _finishRound();
      case _DuelPhase.handoff:
      case _DuelPhase.result:
        break;
    }
  }

  String _pick(List<String> lines) => lines[_rng.nextInt(lines.length)];

  void _finishRound() {
    final p = _playerValue!;
    final b = _bunnyValue!;
    final outcome = p == b
        ? _DuelOutcome.tie
        : (b > p ? _DuelOutcome.bunnyWin : _DuelOutcome.playerWin);
    _outcome = outcome;
    setState(() => _phase = _DuelPhase.result);
    switch (outcome) {
      case _DuelOutcome.bunnyWin:
        playHaptic(HapticLevel.medium);
        // 星星泡泡＋歡呼聲＋雙手高舉，跟充電爆發同一組演出語彙。
        MascotPersona.setForContext(
          MascotEmotion.popHappy.assetPath,
          MascotContext.energize,
          speech: _pick(_bunnyWinLines),
          force: true,
        );
      case _DuelOutcome.playerWin:
        playHaptic(HapticLevel.light);
        // 輸了不難過（sad 太重），圓眼期待「再來一次」＋問號泡泡。
        MascotPersona.setForContext(
          MascotEmotion.expect.assetPath,
          MascotContext.tapReaction,
          speech: _pick(_playerWinLines),
          force: true,
        );
      case _DuelOutcome.tie:
        playHaptic(HapticLevel.light);
        MascotPersona.setForContext(
          MascotEmotion.question.assetPath,
          MascotContext.tapReaction,
          speech: _pick(_tieLines),
          force: true,
        );
        _tieTimer = Timer(const Duration(milliseconds: 1300), () {
          if (mounted) _startRound();
        });
    }
  }

  void _startRound() {
    _handoffTimer?.cancel();
    _tieTimer?.cancel();
    _playerValue = null;
    _bunnyValue = null;
    _outcome = null;
    _world.spawn(1);
    setState(() => _phase = _DuelPhase.player);
  }

  void _close() {
    if (_closing) return;
    _closing = true;
    _handoffTimer?.cancel();
    _tieTimer?.cancel();
    playHaptic(HapticLevel.light);
    _slideCtrl.reverse().whenComplete(widget.onClosed);
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

  String get _statusText => switch (_phase) {
    _DuelPhase.player => '換你——按住骰子，甩出去！',
    _DuelPhase.handoff => '你骰出 $_playerValue 點…換$_bunnyName了',
    _DuelPhase.bunny => '$_bunnyName擲骰中…',
    _DuelPhase.result => '你 $_playerValue 點・$_bunnyName $_bunnyValue 點',
  };

  String get _resultLabel => switch (_outcome!) {
    _DuelOutcome.playerWin => '你贏了！',
    _DuelOutcome.bunnyWin => '$_bunnyName贏了！',
    _DuelOutcome.tie => '平手，再來！',
  };

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).padding.bottom;
    return SlideTransition(
      position: _slide,
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        child: DecoratedBox(
          // 沒有桌布 CG 墊底，直接畫深色墊：中央受光、四周收暗。
          decoration: const BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(0, -0.4),
              radius: 1.5,
              colors: [Color(0xFF33251A), Color(0xFF1A120C)],
            ),
          ),
          child: LayoutBuilder(
            builder: (context, box) {
              // 面板高度依機型浮動（SE 超緊湊 ~260px 也要能玩），
              // 骰子尺寸跟著高度縮、物理牆避開頂部狀態行與底部按鈕列。
              final die = (box.maxHeight * 0.22).clamp(50.0, 84.0);
              _world.setBounds(
                Rect.fromLTRB(
                  10,
                  52,
                  box.maxWidth - 10,
                  box.maxHeight - bottomPad - 78,
                ),
                die,
              );
              return Stack(
                fit: StackFit.expand,
                children: [
                  // 物理場：你的回合整面都能按住吸骰子、甩出去。
                  IgnorePointer(
                    ignoring: _phase != _DuelPhase.player,
                    child: Listener(
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
                  // 頂部：狀態行＋收起。
                  Positioned(
                    top: 4,
                    left: 20,
                    right: 6,
                    height: 44,
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            _statusText,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: TableTheme.inkStrong,
                              fontFamily: AppType.digits().fontFamily,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: _close,
                          icon: const Icon(Icons.close_rounded),
                          color: TableTheme.inkSoft,
                          tooltip: '收起',
                        ),
                      ],
                    ),
                  ),
                  // 結果：中央偏上浮現。
                  if (_phase == _DuelPhase.result)
                    Align(
                      alignment: const Alignment(0, -0.5),
                      child: IgnorePointer(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xCC3C2D21),
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(color: TableTheme.hairline),
                          ),
                          child: Text(
                            _resultLabel,
                            style: AppType.digits(
                              fontSize: 24,
                              fontWeight: FontWeight.w800,
                              color: TableTheme.inkStrong,
                            ),
                          ),
                        ),
                      ),
                    ),
                  // 底部：回合按鈕（交棒/兔咪擲骰中留空，避免誤觸）。
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: bottomPad + 14,
                    child: Center(
                      child: switch (_phase) {
                        _DuelPhase.player => _pillButton(
                          icon: Icons.casino_rounded,
                          label: '擲骰子',
                          onTap: () {
                            playFeedback(SfxCue.gameDice);
                            _world.throwAll();
                          },
                        ),
                        _DuelPhase.result
                            when _outcome != _DuelOutcome.tie =>
                          _pillButton(
                            icon: Icons.replay_rounded,
                            label: '再來一場',
                            onTap: _startRound,
                          ),
                        _ => const SizedBox(height: 48),
                      },
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _pillButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return Material(
      color: TableTheme.warn,
      shape: const StadiumBorder(),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 176,
          height: 48,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 22, color: const Color(0xFF241A12)),
              const SizedBox(width: 8),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF241A12),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
