import 'dart:async';

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../utils/app_feedback.dart';
import '../utils/app_style.dart';
import '../utils/mascot.dart';
import '../utils/roommate_dialogue.dart';
import '../utils/roommate_voice.dart';
import '../utils/scene_time.dart';
import '../utils/wardrobe_catalog.dart';
import '../utils/wardrobe_store.dart';
import 'mascot_scene.dart';
import 'scene_rooms.dart';

/// 一段由使用者推進的室友對話。sceneHeight 由正式 shell 的 LayoutBuilder 傳入，
/// 不另猜螢幕比例。全域 persona 與原功能頁保留，這裡只持有自己的演出與 MI。
class RoommateDialogue extends StatefulWidget {
  final double sceneHeight;

  /// 房間底圖在選項區內還剩多少高度；漸層必須在底圖結束前成為不透明。
  final double roomFadeHeight;
  final Color accent;
  final VoidCallback onClose;
  final RoommateVoiceOutput? voice;

  const RoommateDialogue({
    super.key,
    required this.sceneHeight,
    this.roomFadeHeight = 0,
    required this.accent,
    required this.onClose,
    this.voice,
  });

  @override
  State<RoommateDialogue> createState() => _RoommateDialogueState();
}

class _RoommateDialogueState extends State<RoommateDialogue>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  // 每句先留一拍給姿勢，再同步字幕與 MI；其後只揭字，不重複發聲。
  static const _notice = 180;
  static const _letter = 42;
  static const _panelEntrance = Duration(milliseconds: 280);
  final _dialogue = RoommateDialogueController();
  late final AnimationController _beat;
  late final RoommateVoiceOutput _voice;
  String _text = '';
  List<String> _letters = [];
  RoommateNode? _preparedNode;
  bool _voiced = false;
  bool _foreground = true;
  bool _visible = true;
  bool _reduce = false;
  bool _configured = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _foreground =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    _voice = widget.voice ?? RoommateVoice();
    _beat = AnimationController(vsync: this)..addListener(_onBeat);
    _dialogue.addListener(_onDialogue);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final mq = MediaQuery.of(context);
    final reduce = mq.disableAnimations || mq.accessibleNavigation;
    final visible =
        TickerMode.valuesOf(context).enabled &&
        (ModalRoute.isCurrentOf(context) ?? true);
    final text = _dialogue.node.subtitle(AppLocalizations.of(context));
    final needsPrepare = !_configured || text != _text;
    final changed = visible != _visible || reduce != _reduce;
    _configured = true;
    _visible = visible;
    _reduce = reduce;
    if (needsPrepare) {
      _prepare();
    } else if (changed) {
      _syncPlayback();
    }
  }

  void _prepare() {
    final sameNode = _preparedNode == _dialogue.node;
    _preparedNode = _dialogue.node;
    _text = _dialogue.node.subtitle(AppLocalizations.of(context));
    _letters = _text.characters.toList();
    if (!sameNode) _voiced = false;
    _beat.duration = Duration(
      milliseconds: _notice + _letter * _letters.length,
    );
    _beat.value = 0;
    // dependency/build 階段不能通知父樹。第一幀之後才開始這句。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _syncPlayback();
    });
  }

  bool get _canPlay => _visible && _foreground;

  void _syncPlayback() {
    if (!_canPlay) {
      _beat.stop();
      _voice.stop();
      return;
    }
    if (_reduce || _dialogue.ready) {
      _beat.value = 1;
    } else {
      _beat.forward();
    }
  }

  void _onBeat() {
    if (!_configured) return;
    final elapsed = _beat.value * (_beat.duration?.inMilliseconds ?? 0);
    if (_canPlay && !_voiced && (elapsed >= _notice || _reduce)) {
      _voiced = true;
      unawaited(_voice.play(_dialogue.node.voice));
    }
    if (_beat.isCompleted) _dialogue.reveal();
    if (mounted) setState(() {});
  }

  void _onDialogue() {
    if (_dialogue.finished) {
      widget.onClose();
      return;
    }
    if (_preparedNode != _dialogue.node) {
      _voice.stop();
      _prepare();
    }
    if (mounted) setState(() {});
  }

  void _completeLine() {
    if (!_canPlay || _dialogue.ready) return;
    _beat.value = 1;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _syncPlayback();
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _dialogue.removeListener(_onDialogue);
    _dialogue.dispose();
    _beat.dispose();
    _voice.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final node = _dialogue.node;
    final replies = node.replies(l);
    final elapsed = _beat.value * (_beat.duration?.inMilliseconds ?? 0);
    final count = _reduce || _dialogue.ready
        ? _letters.length
        : ((elapsed - _notice) / _letter).floor().clamp(0, _letters.length);
    final shown = _letters.take(count).join();
    final caption = _subtitle(shown);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) widget.onClose();
      },
      child: Column(
        key: const ValueKey('roommate_dialogue'),
        children: [
          SizedBox(
            height: widget.sceneHeight,
            child: Stack(
              fit: StackFit.expand,
              children: [
                ListenableBuilder(
                  listenable: Listenable.merge([
                    WardrobeStore.selectedOutfit,
                    SceneTimeController.instance,
                  ]),
                  builder: (_, _) => IgnorePointer(
                    child: MascotScene(
                      asset: skinnedMascotAsset(
                        node.emotion.assetPath,
                        WardrobeStore.currentOutfit.skinKey,
                      ),
                      accent: widget.accent,
                      speech: null,
                      reduceMotion: _reduce,
                      poseTransition: _reduce
                          ? MascotPoseTransition.cut
                          : MascotPoseTransition.crossFade,
                      paused: !_canPlay,
                      lighting: mascotLightingForScene(
                        SceneTimeController.instance.state,
                        FourPeriodRoom.home.light,
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: 12,
                  left: 24,
                  right: 24,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: widget.sceneHeight * 0.45,
                    ),
                    child: caption,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: _reduce ? 1 : 0, end: 1),
              duration: _reduce ? Duration.zero : _panelEntrance,
              builder: (_, value, child) => Opacity(
                opacity: value,
                child: Transform.translate(
                  offset: Offset(0, _reduce ? 0 : 12 * (1 - value)),
                  child: child,
                ),
              ),
              child: _replyPanel(l, node, replies),
            ),
          ),
        ],
      ),
    );
  }

  /// 回應是房間前的獨立卡片；底部柔和漸層承接房間背景，沒有整片面板邊框。
  /// 選項區在足夠空間時置中、字級放大時捲動，離開入口不跟著捲走。
  Widget _replyPanel(
    AppLocalizations l,
    RoommateNode node,
    List<RoommateReply> replies,
  ) {
    return LayoutBuilder(
      builder: (_, panelConstraints) => DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppSurfaces.card.withValues(alpha: 0), AppSurfaces.card],
            stops: [
              0,
              (widget.roomFadeHeight / panelConstraints.maxHeight).clamp(0, 1),
            ],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
          child: Column(
            children: [
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    return SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minHeight: (constraints.maxHeight - 32).clamp(
                            0,
                            double.infinity,
                          ),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Semantics(
                              header: true,
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Divider(
                                      color: widget.accent.withValues(
                                        alpha: 0.24,
                                      ),
                                    ),
                                  ),
                                  Flexible(
                                    flex: 3,
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 16,
                                      ),
                                      child: Text(
                                        l.rdYourReply,
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(
                                          fontSize: 13,
                                          color: AppInk.soft,
                                          letterSpacing: 1,
                                        ),
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    child: Divider(
                                      color: widget.accent.withValues(
                                        alpha: 0.24,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 20),
                            for (final reply in replies) ...[
                              AnimatedOpacity(
                                opacity: _dialogue.ready ? 1 : 0.64,
                                duration: _reduce
                                    ? Duration.zero
                                    : const Duration(milliseconds: 160),
                                child: _ReplyPressFeedback(
                                  key: ValueKey(
                                    'reply_press_${node.name}_${reply.id}',
                                  ),
                                  enabled: _dialogue.ready && _canPlay,
                                  reduceMotion: _reduce,
                                  builder: (states, pressed) => DecoratedBox(
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(
                                        AppCardStyle.radius,
                                      ),
                                      boxShadow: AppShadows.flat,
                                    ),
                                    child: OutlinedButton(
                                      key: ValueKey(
                                        'roommate_reply_${reply.id}',
                                      ),
                                      statesController: states,
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: AppInk.strong,
                                        disabledForegroundColor: AppInk.soft,
                                        backgroundColor: pressed
                                            ? Color.lerp(
                                                AppSurfaces.card,
                                                widget.accent,
                                                AppPressMotion.tint,
                                              )
                                            : AppSurfaces.card,
                                        side: BorderSide(
                                          color: widget.accent.withValues(
                                            alpha: pressed ? 0.55 : 0.28,
                                          ),
                                        ),
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 20,
                                          vertical: 20,
                                        ),
                                        minimumSize: const Size.fromHeight(64),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            AppCardStyle.radius,
                                          ),
                                        ),
                                      ),
                                      onPressed: _dialogue.ready && _canPlay
                                          ? () {
                                              if (_dialogue.choose(
                                                reply,
                                                expectedNode: node,
                                                l10n: l,
                                              )) {
                                                playHaptic(
                                                  HapticLevel.selection,
                                                );
                                              }
                                            }
                                          : null,
                                      child: Row(
                                        children: [
                                          Icon(
                                            Icons.chat_bubble_outline_rounded,
                                            size: 18,
                                            color: widget.accent,
                                          ),
                                          const SizedBox(width: 14),
                                          Expanded(
                                            child: Text(
                                              reply.label,
                                              style: const TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Icon(
                                            reply.next == null
                                                ? Icons.arrow_forward_rounded
                                                : Icons.chevron_right_rounded,
                                            size: 18,
                                            color: widget.accent,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 14),
                            ],
                            // 留住提示的高度，字幕補全時選項不會上下挪動。
                            Visibility(
                              visible: !_dialogue.ready,
                              maintainState: true,
                              maintainAnimation: true,
                              maintainSize: true,
                              child: Text(
                                l.rdRevealHint,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: AppInk.soft,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              TextButton.icon(
                key: const ValueKey('roommate_exit'),
                onPressed: widget.onClose,
                style: TextButton.styleFrom(
                  foregroundColor: AppInk.soft,
                  minimumSize: const Size(48, 48),
                ),
                icon: const Icon(Icons.close_rounded, size: 16),
                label: Text(l.rdLater),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _subtitle(String shown) {
    return Semantics(
      label: '${MascotName.value}：$_text',
      button: !_dialogue.ready,
      onTap: _dialogue.ready ? null : _completeLine,
      child: ExcludeSemantics(
        child: Material(
          color: const Color(0xFFFFFDF9),
          borderRadius: BorderRadius.circular(AppCardStyle.radius),
          child: InkWell(
            key: const ValueKey('roommate_subtitle'),
            borderRadius: BorderRadius.circular(AppCardStyle.radius),
            onTap: _completeLine,
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    MascotName.value,
                    style: TextStyle(
                      color: widget.accent,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  // 全文佔位讓逐字出現時高度固定，長字幕可捲動，無限放大字也不裁掉意思。
                  Stack(
                    children: [
                      Opacity(
                        opacity: 0,
                        child: Text(_text, style: _subtitleStyle),
                      ),
                      Text(shown.isEmpty ? ' ' : shown, style: _subtitleStyle),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  static const _subtitleStyle = TextStyle(
    fontSize: 18,
    height: 1.5,
    fontWeight: FontWeight.w600,
    color: AppInk.strong,
  );
}

/// Only reads the native button's states: no competing gesture recognizer,
/// extra feedback call, delayed selection or enlarged layout/hit-test bounds.
class _ReplyPressFeedback extends StatefulWidget {
  const _ReplyPressFeedback({
    super.key,
    required this.enabled,
    required this.reduceMotion,
    required this.builder,
  });

  final bool enabled;
  final bool reduceMotion;
  final Widget Function(WidgetStatesController states, bool pressed) builder;

  @override
  State<_ReplyPressFeedback> createState() => _ReplyPressFeedbackState();
}

class _ReplyPressFeedbackState extends State<_ReplyPressFeedback> {
  late final WidgetStatesController _states;
  bool _pressed = false;
  bool _updateQueued = false;

  @override
  void initState() {
    super.initState();
    _states = WidgetStatesController()..addListener(_syncPressed);
  }

  void _syncPressed() {
    // ButtonStyleButton may notify while rebuilding its disabled state. Read
    // the latest value after that frame, never setState during its build.
    if (_updateQueued) return;
    _updateQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _updateQueued = false;
      if (!mounted) return;
      final pressed = _states.value.contains(WidgetState.pressed);
      if (_pressed != pressed) setState(() => _pressed = pressed);
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  @override
  void dispose() {
    _states.removeListener(_syncPressed);
    _states.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pressed = widget.enabled && _pressed;
    return TweenAnimationBuilder<double>(
      tween: Tween(
        begin: 1,
        end: pressed && !widget.reduceMotion ? AppPressMotion.scale : 1,
      ),
      duration: widget.reduceMotion || !widget.enabled
          ? Duration.zero
          : pressed
          ? AppPressMotion.down
          : AppPressMotion.release,
      curve: AppPressMotion.curve,
      // Paint within the original hit area; edge touches still belong to the
      // same button while its visual contracts under the finger.
      child: widget.builder(_states, pressed),
      builder: (_, scale, child) =>
          Transform.scale(scale: scale, transformHitTests: false, child: child),
    );
  }
}
