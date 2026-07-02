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
// sceneRatio 預設 5/11，跟首頁原始比例一致。peekHeight 預設 20，剛好蓋住
// 兔咪場景中的對話框（對話框 top:30）。

import 'dart:async';

import 'package:flutter/material.dart';

import '../pages/home/room_ambient_overlay.dart';

import '../utils/mascot.dart';
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

  /// 兔咪場景佔總高度比例。預設 5/11。
  final double sceneRatio;

  /// 兔咪場景區固定高度（px）。傳 null（預設）時沿用 [sceneRatio] 吃可用高度的
  /// 舊行為——其他頁面不傳就完全不受影響。首頁傳入「跟螢幕寬等比」的高度，
  /// 讓卡片頂緣對齊地毯線、兔咪踩在地板上（見 home/room_metrics.dart）。
  final double? sceneHeight;

  /// 收合時保留的「偷看」高度，預設 20。
  final double peekHeight;

  /// 無操作後暫停上方兔咪場景 ticker，避免長時間停在頁面時持續重繪。
  final bool autoPauseScene;
  final Duration sceneIdleDelay;

  const MascotPageShell({
    super.key,
    required this.scene,
    required this.child,
    required this.accent,
    this.sceneRatio = 5 / 11,
    this.sceneHeight,
    this.peekHeight = 20,
    this.autoPauseScene = true,
    this.sceneIdleDelay = const Duration(seconds: 20),
  });

  @override
  State<MascotPageShell> createState() => _MascotPageShellState();
}

class _MascotPageShellState extends State<MascotPageShell> {
  Timer? _sceneIdleTimer;
  bool _sceneIdle = false;

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
        // 傳了 sceneHeight 就用固定高（跟螢幕寬等比，首頁用）；否則沿用舊比例。
        final mascotMaxH =
            widget.sceneHeight ?? constraints.maxHeight * widget.sceneRatio;
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
                    child: pauseScene
                        ? TickerMode(enabled: false, child: scene)
                        : scene,
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

class _AutoPausingTickerMode extends StatefulWidget {
  final Widget child;
  final bool enabled;
  final Duration delay;

  const _AutoPausingTickerMode({
    required this.child,
    required this.enabled,
    required this.delay,
  });

  @override
  State<_AutoPausingTickerMode> createState() => _AutoPausingTickerModeState();
}

class _AutoPausingTickerModeState extends State<_AutoPausingTickerMode> {
  Timer? _timer;
  bool _paused = false;

  @override
  void initState() {
    super.initState();
    MascotVisualActivity.listenable.addListener(_handleActivity);
    _syncTimer();
  }

  @override
  void didUpdateWidget(covariant _AutoPausingTickerMode oldWidget) {
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
/// 傳 [ambience] 並在 [kRoomAmbienceEnabled] 為 true 時，會在背景圖上疊一層
/// 時段光影（晨/暮/夜光束、塵埃、檯燈暈、時段色罩）——跟首頁同一套。
/// 不傳 ambience（或總開關關閉）就是純背景圖，行為與原本完全相同。
class MascotSceneBackground extends StatelessWidget {
  final String assetPath;
  final SceneAmbience? ambience;
  final bool autoPauseAmbience;
  final Duration ambienceIdleDelay;

  const MascotSceneBackground(
    this.assetPath, {
    super.key,
    this.ambience,
    this.autoPauseAmbience = true,
    this.ambienceIdleDelay = const Duration(seconds: 20),
  });

  // 場景圖 wrapper（cover + topCenter）。errorBuilder 讓「去背圖還沒到位」時
  // 安全回退到指定圖，不崩也不破版。
  static Widget _cover(String path, {Widget Function()? fallback}) {
    return ClipRect(
      child: Align(
        alignment: Alignment.topCenter,
        child: Image.asset(
          path,
          height: double.infinity,
          width: double.infinity,
          fit: BoxFit.cover,
          alignment: Alignment.topCenter,
          errorBuilder: fallback == null ? null : (_, _, _) => fallback(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final amb = ambience;
    if (!kRoomAmbienceEnabled || amb == null) return _cover(assetPath);

    // 背景層：有窗景就「動態天空 + 去背圖」，否則純原圖。
    final Widget background;
    if (amb.hasWindow) {
      background = Stack(
        fit: StackFit.expand,
        children: [
          // 後面墊動態時段天空；前面去背圖玻璃透明處露出天空。
          WindowBackdrop(windowRect: amb.windowRect!),
          // 去背圖未到位 → 回退原圖（不透明，蓋住天空＝看起來如常）。
          _cover(amb.glasslessAsset!, fallback: () => _cover(assetPath)),
        ],
      );
    } else {
      background = _cover(assetPath);
    }

    final scene = Stack(
      fit: StackFit.expand,
      children: [
        background,
        RoomAmbientOverlay(lampCenter: amb.lampCenter, tint: amb.tint),
      ],
    );
    return _AutoPausingTickerMode(
      enabled: autoPauseAmbience,
      delay: ambienceIdleDelay,
      child: scene,
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
