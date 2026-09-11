import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../utils/app_style.dart';
import '../utils/companion_story_catalog.dart';
import '../utils/companion_story_progress.dart';
import '../utils/scene_time.dart';
import '../utils/wardrobe_catalog.dart';
import '../utils/wardrobe_store.dart';
import '../widgets/app_waiting.dart';
import '../widgets/four_period_background.dart';
import '../widgets/mascot_scene.dart';
import '../widgets/scene_rooms.dart';

/// Full-page reader. The caller owns persistence and daily companionship rules.
/// Preview is always local, even if persistence callbacks were accidentally sent.
class CompanionDialoguePage extends StatefulWidget {
  const CompanionDialoguePage({
    super.key,
    required this.episode,
    this.initialCursor,
    this.preview = false,
    this.replay = false,
    this.onSave,
    this.onFinish,
  });

  final CompanionEpisode episode;
  final CompanionCursor? initialCursor;
  final bool preview;
  final bool replay;
  final Future<bool> Function(CompanionCursor)? onSave;
  final Future<bool> Function(bool skipped)? onFinish;

  @override
  State<CompanionDialoguePage> createState() => _CompanionDialoguePageState();
}

class _CompanionDialoguePageState extends State<CompanionDialoguePage>
    with WidgetsBindingObserver {
  late CompanionSession _session;
  final _scroll = ScrollController();
  bool _busy = false;
  bool _saveFailed = false;
  bool _foreground = true;
  VoidCallback? _retry;

  @override
  void initState() {
    super.initState();
    _session = CompanionSession(widget.episode, widget.initialCursor);
    _foreground =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (mounted) {
      setState(() => _foreground = state == AppLifecycleState.resumed);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _persist(
    Future<bool> Function() save,
    VoidCallback apply,
  ) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _saveFailed = false;
      _retry = null;
    });
    var saved = false;
    try {
      saved = await save();
    } catch (_) {
      // A failed write leaves the currently visible line and choices intact.
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _saveFailed = !saved;
      if (!saved) _retry = () => _persist(save, apply);
    });
    if (saved) apply();
  }

  void _show(CompanionCursor cursor) {
    setState(() => _session = CompanionSession(widget.episode, cursor));
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  Future<void> _move(CompanionCursor cursor) => _persist(() async {
    if (widget.preview || widget.replay) return true;
    return await widget.onSave?.call(cursor) ?? true;
  }, () => _show(cursor));

  Future<void> _finish({bool skipped = false}) => _persist(() async {
    if (widget.preview) return true;
    // Archive replay may mark read, but never handles a skipped main story.
    return await widget.onFinish?.call(!widget.replay && skipped) ?? true;
  }, () => Navigator.of(context).pop(true));

  void _next() {
    if (_busy) return;
    if (_session.atEnd) {
      _finish();
    } else {
      _move(_session.advance());
    }
  }

  void _restart() {
    if (_busy || (!widget.preview && !widget.replay)) return;
    setState(() {
      _saveFailed = false;
      _retry = null;
    });
    _show(CompanionSession(widget.episode).cursor);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final language = Localizations.localeOf(context).languageCode;
    final mq = MediaQuery.of(context);
    final reduce = mq.disableAnimations || mq.accessibleNavigation;
    final active =
        _foreground &&
        TickerMode.valuesOf(context).enabled &&
        (ModalRoute.isCurrentOf(context) ?? true);
    final title = widget.episode.title.resolve(language);
    return PopScope(
      // A back gesture while a write is pending must not leave a half-read node.
      canPop: !_busy,
      child: Scaffold(
        key: const ValueKey('companion_dialogue_page'),
        backgroundColor: AppSurfaces.canvas,
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 680),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
                    child: Row(
                      children: [
                        IconButton(
                          key: const ValueKey('companion_close'),
                          tooltip: l.csClose,
                          constraints: const BoxConstraints.tightFor(
                            width: 48,
                            height: 48,
                          ),
                          onPressed: _busy
                              ? null
                              : () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.close_rounded),
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (widget.preview || widget.replay)
                                Text(
                                  widget.preview ? l.csPreview : l.csReplay,
                                  key: const ValueKey('companion_mode'),
                                  style: Theme.of(context).textTheme.labelMedium
                                      ?.copyWith(color: AppPalette.habitInk),
                                ),
                              Text(
                                title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(fontWeight: FontWeight.w800),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 4),
                        if (widget.preview || widget.replay)
                          IconButton(
                            key: const ValueKey('companion_restart'),
                            tooltip: l.csRestart,
                            constraints: const BoxConstraints.tightFor(
                              width: 48,
                              height: 48,
                            ),
                            onPressed: _busy ? null : _restart,
                            icon: const Icon(Icons.replay_rounded),
                          )
                        else
                          IconButton(
                            key: const ValueKey('companion_skip'),
                            tooltip: l.csSkip,
                            constraints: const BoxConstraints.tightFor(
                              width: 48,
                              height: 48,
                            ),
                            onPressed: _busy
                                ? null
                                : () => _finish(skipped: true),
                            icon: const Icon(Icons.skip_next_rounded),
                          ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, box) {
                        // Header and safe-area are already deducted. Keep at
                        // least 200 logical pixels for scrollable text/choices;
                        // large text reduces the scene, never the touch targets.
                        final sceneHeight = math.min(
                          math.min(
                            400.0,
                            box.maxHeight *
                                (box.maxHeight >= 600 ? 0.54 : 0.44),
                          ),
                          math.max(0.0, box.maxHeight - 200),
                        );
                        return Column(
                          children: [
                            if (sceneHeight > 0)
                              SizedBox(
                                key: const ValueKey('companion_room'),
                                height: sceneHeight,
                                width: double.infinity,
                                child: _scene(reduce: reduce, active: active),
                              ),
                            Expanded(
                              child: Scrollbar(
                                controller: _scroll,
                                child: SingleChildScrollView(
                                  key: const ValueKey(
                                    'companion_reading_scroll',
                                  ),
                                  controller: _scroll,
                                  padding: const EdgeInsets.fromLTRB(
                                    24,
                                    20,
                                    24,
                                    24,
                                  ),
                                  child: _reading(l, language),
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _scene({required bool reduce, required bool active}) => ClipRect(
    child: IgnorePointer(
      child: ExcludeSemantics(
        child: Stack(
          fit: StackFit.expand,
          children: [
            FourPeriodBackground(assets: FourPeriodRoom.home.assets),
            ListenableBuilder(
              listenable: Listenable.merge([
                WardrobeStore.selectedOutfit,
                SceneTimeController.instance,
              ]),
              builder: (_, _) => MascotScene(
                asset: skinnedMascotAsset(
                  _session.emotion.assetPath,
                  WardrobeStore.currentOutfit.skinKey,
                ),
                accent: AppPalette.habit,
                speech: null,
                reduceMotion: reduce,
                paused: !active,
                poseTransition: reduce
                    ? MascotPoseTransition.cut
                    : MascotPoseTransition.crossFade,
                lighting: mascotLightingForScene(
                  SceneTimeController.instance.state,
                  FourPeriodRoom.home.light,
                ),
              ),
            ),
            // One soft edge joins the room to paper; no stacked outer frames.
            const Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: 28,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0x00FFF8ED), AppSurfaces.canvas],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _reading(AppLocalizations l, String language) {
    final choices = _session.choices;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.preview) ...[
          Text(
            l.csPreviewNotice,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: AppInk.soft),
          ),
          const SizedBox(height: 16),
        ],
        Semantics(
          liveRegion: true,
          child: Text(
            _session.text.resolve(language),
            key: const ValueKey('companion_line'),
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontSize: 22,
              height: 1.55,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(height: 24),
        if (_saveFailed) ...[
          Semantics(
            liveRegion: true,
            child: Text(
              l.csSaveError,
              key: const ValueKey('companion_save_error'),
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: AppInk.danger),
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            key: const ValueKey('companion_retry'),
            onPressed: _busy ? null : _retry,
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(48, 48),
              padding: const EdgeInsets.all(12),
            ),
            icon: const Icon(Icons.refresh_rounded, size: 20),
            label: Text(l.csRetry),
          ),
          const SizedBox(height: 16),
        ],
        for (final choice in choices) ...[
          OutlinedButton(
            key: ValueKey('companion_choice_${choice.id}'),
            onPressed: _busy ? null : () => _move(_session.choose(choice.id)),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(48, 52),
              backgroundColor: AppSurfaces.card,
              foregroundColor: AppInk.strong,
              side: const BorderSide(color: AppSurfaces.divider),
              alignment: Alignment.centerLeft,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppCardStyle.radius),
              ),
            ),
            child: Text(
              choice.label.resolve(language),
              style: const TextStyle(fontSize: 16, height: 1.45),
            ),
          ),
          const SizedBox(height: 12),
        ],
        if (choices.isEmpty)
          FilledButton(
            key: const ValueKey('companion_next'),
            onPressed: _busy ? null : _next,
            style: FilledButton.styleFrom(
              minimumSize: const Size(48, 52),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            ),
            child: _busy
                ? const SizedBox(
                    height: 20,
                    child: Center(child: AppLoadingBar(width: 40)),
                  )
                : Text(_session.atEnd ? l.csFinish : l.csContinue),
          ),
      ],
    );
  }
}
