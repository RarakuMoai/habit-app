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
  final Color accent;
  final VoidCallback onClose;
  final RoommateVoiceOutput? voice;

  const RoommateDialogue({
    super.key,
    required this.sceneHeight,
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
              child: Material(
                color: const Color(0xFFFFFDF9),
                borderRadius: BorderRadius.vertical(
                  top: Radius.circular(AppCardStyle.sheetRadius),
                ),
                clipBehavior: Clip.antiAlias,
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 12, 8, 0),
                        child: Row(
                          children: [
                            Icon(
                              Icons.chat_bubble_outline_rounded,
                              size: 18,
                              color: widget.accent,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                l.rdTitle,
                                style: const TextStyle(
                                  color: AppInk.strong,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            IconButton(
                              tooltip: l.rdLater,
                              onPressed: widget.onClose,
                              icon: const Icon(
                                Icons.close_rounded,
                                color: AppInk.soft,
                                size: 20,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              l.rdYourReply,
                              style: const TextStyle(
                                fontSize: 13,
                                color: AppInk.soft,
                              ),
                            ),
                            const SizedBox(height: 12),
                            for (final reply in replies) ...[
                              AnimatedOpacity(
                                opacity: _dialogue.ready ? 1 : 0.48,
                                duration: _reduce
                                    ? Duration.zero
                                    : const Duration(milliseconds: 160),
                                child: OutlinedButton(
                                  key: ValueKey('roommate_reply_${reply.id}'),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: AppInk.strong,
                                    disabledForegroundColor: AppInk.soft,
                                    backgroundColor: widget.accent.withValues(
                                      alpha: 0.06,
                                    ),
                                    side: BorderSide(
                                      color: widget.accent.withValues(
                                        alpha: 0.22,
                                      ),
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 18,
                                      vertical: 16,
                                    ),
                                    minimumSize: const Size.fromHeight(56),
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
                                            playHaptic(HapticLevel.selection);
                                          }
                                        }
                                      : null,
                                  child: Row(
                                    children: [
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
                              const SizedBox(height: 12),
                            ],
                            if (!_dialogue.ready)
                              Text(
                                l.rdRevealHint,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: AppInk.soft,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
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
