// 兔咪頁面 scaffold：把「上半兔咪場景 + 可拖曳功能卡」這個共用版型抽出來。
//
// 用法：
//   MascotPageShell(
//     accent: pageAccent,
//     scene: yourSceneWidget,   // 兔咪 + 背景 + 對話框
//     child: yourPageContent,   // 卡片內部的功能 UI
//   )
//
// 內部會處理：
//   - LayoutBuilder 計算 dragExtent
//   - ValueListenableBuilder 監聽 MascotPanelPrefs.openValue（全 app 共用）
//   - 上方場景固定高度；下方卡 top 隨 openValue 浮動
//   - 卡片 1:1 共用同樣的圓角、陰影、MascotToggleBar 把手
//
// 場景區高度預設走「寬度錨點」（見 home/room_metrics.dart）：只跟螢幕寬等比，
// 跟背景圖 cover-by-width 同參考系，任何機型地板線/卡片線才會對齊；
// 14 Pro Max（寬 430）時與舊的 5/11×可用高逐位元相同＝零位移。
// peekHeight 預設 20，剛好蓋住兔咪場景中的對話框（對話框 top:30）。

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../pages/game/snake_arcade/snake_arcade_page.dart';
import '../pages/home/room_metrics.dart';

import '../utils/mascot.dart';
import 'dice_duel_panel.dart';
import 'mascot_panel.dart';
import 'mascot_scene.dart';

abstract final class MascotVisualActivity {
  static final ValueNotifier<int> _tick = ValueNotifier<int>(0);

  static Listenable get listenable => _tick;

  static void markActive() {
    _tick.value++;
  }
}

class MascotPageShell extends StatefulWidget {
  /// 上方兔咪場景（兔咪本體 + 對話框）。
  final Widget scene;

  /// 下方卡片內容（不需自己包白底/圓角/陰影/把手，shell 會處理）。
  final Widget child;

  /// 把手 & 陰影主色，依頁面切換。
  final Color accent;

  /// 兔咪場景區固定高度（px）。七個兔咪頁一律傳
  /// [sceneRegionHeightAnchored]（頁面 context 的寬度＋狀態列高），讓卡片
  /// 頂緣／兔咪腳在每台機器都對齊背景圖同一條地毯線。傳 null 時退回純寬度
  /// 錨點 [homeSceneRegionHeight]（不含 chrome 修正；shell 在 SafeArea 內
  /// 量不到狀態列，只能由頁面傳入）。見 home/room_metrics.dart。
  final double? sceneHeight;

  /// 收合時保留的「偷看」高度，預設 20。
  final double peekHeight;

  /// 無操作後暫停上方兔咪場景 ticker，避免長時間停在頁面時持續重繪。
  final bool autoPauseScene;
  final Duration sceneIdleDelay;

  /// 三指長按場景彩蛋的覆寫回呼。一般頁面不傳時由 shell 以全螢幕
  /// root overlay 掛上 [SnakeArcadeEgg]（菜園小蛇）。
  final VoidCallback? onThreeFingerEggTrigger;

  const MascotPageShell({
    super.key,
    required this.scene,
    required this.child,
    required this.accent,
    this.sceneHeight,
    this.peekHeight = 20,
    this.autoPauseScene = true,
    this.sceneIdleDelay = const Duration(seconds: 20),
    this.onThreeFingerEggTrigger,
  });

  @override
  State<MascotPageShell> createState() => _MascotPageShellState();
}

class _MascotPageShellState extends State<MascotPageShell> {
  Timer? _sceneIdleTimer;
  bool _sceneIdle = false;

  // 隱藏彩蛋：兩指長按場景 → 骰子對決（見 dice_duel_panel.dart）。
  // 面板要蓋住功能卡「與底部分頁列」，所以掛在 root overlay 而不是
  // shell 自己的 Stack（shell 在分頁列上方的頁面區內，蓋不到）。
  OverlayEntry? _diceDuelEntry;
  OverlayEntry? _snakeArcadeEntry;
  double _sceneRegionHeight = 0; // build 時記下，開彩蛋算面板頂緣用

  bool get _anyEggOpen => _diceDuelEntry != null || _snakeArcadeEntry != null;
  bool get _snakeEggOpen => _snakeArcadeEntry != null;

  void _openDiceDuel() {
    if (_anyEggOpen || !mounted) return;
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return;
    // 面板頂緣＝場景區下緣的螢幕座標；蓋掉場景以下的一切。
    final top = box.localToGlobal(Offset.zero).dy + _sceneRegionHeight;
    // 把功能卡吸到收合位，面板退場時下方不會露出半開的卡。
    MascotPanelPrefs.requestExpanded();
    _markSceneActive();
    final entry = OverlayEntry(
      builder: (_) => Positioned(
        top: top,
        left: 0,
        right: 0,
        bottom: 0,
        child: DiceDuelEgg(
          onClosed: _closeDiceDuel,
          onActivity: _markSceneActive,
        ),
      ),
    );
    _diceDuelEntry = entry;
    Overlay.of(context, rootOverlay: true).insert(entry);
    setState(() {}); // 更新彩蛋偵測層的 enabled 門檻
  }

  void _closeDiceDuel() {
    _diceDuelEntry?.remove();
    _diceDuelEntry = null;
    if (mounted) setState(() {});
  }

  void _openThreeFingerEgg() {
    final callback = widget.onThreeFingerEggTrigger;
    if (callback != null) {
      callback();
      return;
    }
    _openSnakeArcade();
  }

  /// 菜園小蛇是全螢幕彩蛋：蓋掉場景、AppBar 與分頁列，並把目前兔咪縮進
  /// 遊戲操作台陪玩。關閉 overlay 即回到觸發前的頁面與狀態。
  void _openSnakeArcade() {
    if (_snakeEggOpen || !mounted) return;
    final switchingFromDice = _diceDuelEntry != null;
    _markSceneActive();
    final entry = OverlayEntry(
      builder: (_) => Positioned.fill(
        child: SnakeArcadeEgg(
          onClosed: _closeSnakeArcade,
          onCovered: switchingFromDice ? _closeDiceDuel : null,
        ),
      ),
    );
    _snakeArcadeEntry = entry;
    Overlay.of(context, rootOverlay: true).insert(entry);
    setState(() {});
  }

  void _closeSnakeArcade() {
    _snakeArcadeEntry?.remove();
    _snakeArcadeEntry = null;
    if (!mounted) return;
    _markSceneActive(); // 遊戲期間場景可能已閒置凍結，回來先喚醒
    setState(() {});
  }

  @override
  void initState() {
    super.initState();
    MascotPersona.current.addListener(_handleMascotActivity);
    _markSceneActive();
  }

  @override
  void didUpdateWidget(covariant MascotPageShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.autoPauseScene != widget.autoPauseScene ||
        oldWidget.sceneIdleDelay != widget.sceneIdleDelay) {
      _markSceneActive();
    }
  }

  @override
  void dispose() {
    MascotPersona.current.removeListener(_handleMascotActivity);
    _sceneIdleTimer?.cancel();
    _diceDuelEntry?.remove();
    _diceDuelEntry = null;
    _snakeArcadeEntry?.remove();
    _snakeArcadeEntry = null;
    super.dispose();
  }

  void _handleMascotActivity() {
    _markSceneActive();
  }

  void _markSceneActive() {
    MascotVisualActivity.markActive();
    _sceneIdleTimer?.cancel();
    if (!widget.autoPauseScene) {
      if (_sceneIdle && mounted) setState(() => _sceneIdle = false);
      return;
    }
    if (_sceneIdle && mounted) {
      setState(() => _sceneIdle = false);
    }
    _sceneIdleTimer = Timer(widget.sceneIdleDelay, _goSceneIdle);
  }

  void _goSceneIdle() {
    if (!mounted || _sceneIdle || !widget.autoPauseScene) return;
    setState(() => _sceneIdle = true);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (ctx, constraints) {
        // 場景高走「寬度錨點」（14PM 時 == 舊的 5/11×可用高，零位移）；
        // 再套 kSceneRegionMaxFraction 護欄，避免「寬>高」的退化面把卡片推出畫面。
        final anchored =
            widget.sceneHeight ??
            homeSceneRegionHeight(MediaQuery.of(ctx).size.width);
        final mascotMaxH = math.min(
          anchored,
          constraints.maxHeight * kSceneRegionMaxFraction,
        );
        _sceneRegionHeight = mascotMaxH;
        final dragExtent = mascotMaxH - widget.peekHeight;
        return ValueListenableBuilder<double>(
          valueListenable: MascotPanelPrefs.openValue,
          builder: (_, openValue, _) {
            final pauseScene = widget.autoPauseScene && _sceneIdle;
            final scene = MascotIdleScope(
              paused: pauseScene,
              child: RepaintBoundary(child: widget.scene),
            );
            return Listener(
              behavior: HitTestBehavior.translucent,
              onPointerDown: (_) => _markSceneActive(),
              onPointerSignal: (_) => _markSceneActive(),
              child: Stack(
                children: [
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    height: mascotMaxH,
                    // 拖曳面板時場景/兔咪本身不變，獨立圖層避免被連帶重繪。
                    // 彩蛋偵測層只包場景區：兩指長按觸發、指數同步給
                    // MascotStage 做單指互動互讓；功能卡展開時不觸發。
                    child: TwoFingerEggDetector(
                      enabled: !_anyEggOpen && openValue > 0.85,
                      onTrigger: _openDiceDuel,
                      // 骰子面板只蓋場景下方；骰子開著時仍允許在上方
                      // 以三指長按切進小蛇。小蛇窗簾蓋滿後才卸骰子，無閃屏。
                      threeFingerEnabled: !_snakeEggOpen && openValue > 0.85,
                      onThreeFingerTrigger: _openThreeFingerEgg,
                      child: pauseScene
                          ? TickerMode(enabled: false, child: scene)
                          : scene,
                    ),
                  ),
                  Positioned(
                    top: widget.peekHeight + dragExtent * openValue,
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: _MascotCard(
                      accent: widget.accent,
                      dragExtent: dragExtent,
                      child: widget.child,
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

/// 閒置自動凍結：一段時間沒有互動（MascotVisualActivity 沒被戳）就用
/// TickerMode 把子樹動畫全停（0fps），一有互動立刻恢復。
/// 場景層（四時段空氣層等）共用這一套省電規則。
class AutoPausingTickerMode extends StatefulWidget {
  final Widget child;
  final bool enabled;
  final Duration delay;

  const AutoPausingTickerMode({
    super.key,
    required this.child,
    this.enabled = true,
    this.delay = const Duration(seconds: 20),
  });

  @override
  State<AutoPausingTickerMode> createState() => _AutoPausingTickerModeState();
}

class _AutoPausingTickerModeState extends State<AutoPausingTickerMode> {
  Timer? _timer;
  bool _paused = false;

  @override
  void initState() {
    super.initState();
    MascotVisualActivity.listenable.addListener(_handleActivity);
    _syncTimer();
  }

  @override
  void didUpdateWidget(covariant AutoPausingTickerMode oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.enabled != widget.enabled ||
        oldWidget.delay != widget.delay) {
      _paused = false;
      _syncTimer();
    }
  }

  @override
  void dispose() {
    MascotVisualActivity.listenable.removeListener(_handleActivity);
    _timer?.cancel();
    super.dispose();
  }

  void _handleActivity() {
    _timer?.cancel();
    if (!widget.enabled) {
      if (_paused && mounted) setState(() => _paused = false);
      return;
    }
    if (_paused && mounted) {
      setState(() => _paused = false);
    }
    _timer = Timer(widget.delay, () {
      if (mounted) setState(() => _paused = true);
    });
  }

  void _syncTimer() {
    _timer?.cancel();
    if (!widget.enabled) return;
    _timer = Timer(widget.delay, () {
      if (mounted) setState(() => _paused = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_paused) return widget.child;
    return TickerMode(enabled: false, child: widget.child);
  }
}

/// 場景背景圖 wrapper：BoxFit.cover + 從頂部對齊（兔咪會疊在中下方，
/// 場景上方比較重要要露出來）。給 [MascotPageShell.sceneBackground] 用。
///
/// 沒有四時段圖組的房間（衣櫃/體重）用這個單圖版；有四時段圖組的
/// 房間改用 widgets/scene_rooms.dart 的 [FourPeriodRoomScene]。
class MascotSceneBackground extends StatelessWidget {
  final String assetPath;

  const MascotSceneBackground(this.assetPath, {super.key});

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: Align(
        alignment: Alignment.topCenter,
        child: Image.asset(
          assetPath,
          height: double.infinity,
          width: double.infinity,
          fit: BoxFit.cover,
          alignment: Alignment.topCenter,
        ),
      ),
    );
  }
}

class _MascotCard extends StatelessWidget {
  final Color accent;
  final double dragExtent;
  final Widget child;

  const _MascotCard({
    required this.accent,
    required this.dragExtent,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        // 暖白卡面 + 雙層上拋陰影（ambient 大模糊淡 + contact 貼邊），
        // 讓卡片跟場景的交界更柔和精緻
        color: const Color(0xFFFFFDF9).withValues(alpha: 0.97),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.14),
            blurRadius: 26,
            offset: const Offset(0, -8),
          ),
          BoxShadow(
            color: accent.withValues(alpha: 0.10),
            blurRadius: 6,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Column(
        children: [
          MascotToggleBar(accent: accent, dragExtent: dragExtent),
          Expanded(child: child),
        ],
      ),
    );
  }
}
