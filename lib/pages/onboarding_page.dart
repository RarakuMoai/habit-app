import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/app_localizations.dart';
import '../utils/app_style.dart';
import '../utils/entry_audio.dart';
import '../utils/input_formatters.dart';
import '../utils/logical_date.dart';
import '../utils/logical_day_coordinator.dart';
import '../utils/mascot.dart';
import '../utils/onboarding_setup.dart';
import '../utils/onboarding_story.dart';
import '../utils/prefs_keys.dart';
import '../utils/wardrobe_catalog.dart';
import '../utils/wardrobe_store.dart';
import '../widgets/app_waiting.dart';
import '../widgets/audio_control_button.dart';
import '../widgets/entry_meeting.dart';
import '../widgets/mascot_scene.dart';

/// A quiet first meeting, also used by preview and the first memory.
/// Only normal setup may save names or initialize a new household.
class OnboardingPage extends StatefulWidget {
  const OnboardingPage({
    super.key,
    this.preview = false,
    this.compactEntry = false,
    this.onReplayFinished,
  });

  final bool preview;
  final bool compactEntry;
  final Future<bool> Function(bool skipped)? onReplayFinished;

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage>
    with WidgetsBindingObserver {
  final _setup = OnboardingSetup();
  late final EntryAudioScope _entryAudio;
  final _mascot = TextEditingController();
  final _nickname = TextEditingController();
  final _scroll = ScrollController();
  int _index = 0;
  bool _ready = false;
  bool _readFailed = false;
  bool _busy = false;
  bool _saveFailed = false;
  bool _retrySkipped = false;
  bool _foreground = true;
  int _dayStartHour = LogicalDate.defaultHour;

  bool get _replay => !widget.preview && widget.onReplayFinished != null;
  bool get _readOnly => _replay;
  bool get _normal => !widget.preview && !_replay;
  bool get _compact => widget.compactEntry && _normal;
  List<OnboardingStoryScene> get _scenes => _compact
      ? [onboardingStoryScenes[1], onboardingStoryScenes.last]
      : onboardingStoryScenes;
  bool get _last => _index == _scenes.length - 1;

  @override
  void initState() {
    super.initState();
    _foreground =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
    _entryAudio = EntryAudio.instance.open();
    unawaited(_runAudio(_entryAudio.playIntro()));
    _loadNames();
  }

  Future<void> _runAudio(Future<void> operation) async {
    try {
      await operation;
    } catch (error, stack) {
      debugPrint('Entry audio failed: $error\n$stack');
    }
  }

  Future<void> _loadNames() async {
    setState(() => _readFailed = false);
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      // This deliberately does not call MascotName.load: previews are local.
      _mascot.text = prefs.getString(PrefsKeys.mascotName) ?? '';
      _nickname.text = prefs.getString(PrefsKeys.userNickname) ?? '';
      _dayStartHour = LogicalDate.hourOf(prefs);
      setState(() => _ready = true);
    } catch (_) {
      if (mounted) setState(() => _readFailed = true);
    }
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
    unawaited(_runAudio(_entryAudio.close()));
    _mascot.dispose();
    _nickname.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _move(int index) {
    if (_busy || !_ready) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _index = index;
      _saveFailed = false;
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  void _back() {
    if (_busy) return;
    if (_index > 0) {
      _move(_index - 1);
    } else {
      Navigator.of(context).maybePop();
    }
  }

  Future<void> _finish({bool skipped = false}) async {
    if (_busy || !_ready) return;
    FocusManager.instance.primaryFocus?.unfocus();
    if (widget.preview || (_replay && skipped)) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _busy = true;
      _saveFailed = false;
      _retrySkipped = skipped;
    });
    var saved = false;
    try {
      if (_replay) {
        saved = await widget.onReplayFinished!(false);
      } else {
        await LogicalDayCoordinator.instance.ensureCurrent(
          trigger: LogicalDayTrigger.manual,
        );
        final dayKey =
            LogicalDayCoordinator.instance.stamp.value?.logicalDate ??
            LogicalDate.stringFor(DateTime.now(), _dayStartHour);
        saved = await _setup.finish(
          mascotName: _mascot.text.trim(),
          nickname: _nickname.text.trim(),
          skipped: skipped,
          dayKey: dayKey,
        );
        if (saved) await MascotName.load();
      }
    } catch (_) {
      // Stay on this scene. The setup service will safely retry partial writes.
    }
    if (!mounted) return;
    if (!saved) {
      setState(() {
        _busy = false;
        _saveFailed = true;
      });
      return;
    }
    if (_replay) {
      Navigator.of(context).pop(true);
    } else {
      // Music belongs to the destination; no per-line or completion jingle.
      unawaited(_runAudio(_entryAudio.enterHome()));
      unawaited(
        Navigator.of(
          context,
        ).pushReplacementNamed('/home', arguments: 'onboarding-arrival'),
      );
    }
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
    final scene = _scenes[_index];
    if (_compact) {
      return PopScope(
        canPop: false,
        child: EntryMeeting(
          text: scene.text.resolve(language),
          last: _last,
          ready: _ready,
          failed: _saveFailed || _readFailed,
          busy: _busy,
          onNext: _last ? _finish : () => _move(_index + 1),
          onSkip: () => _finish(skipped: true),
          onRetry: _readFailed
              ? _loadNames
              : () => _finish(skipped: _retrySkipped),
        ),
      );
    }
    final keyboard = mq.viewInsets.bottom > 0;
    return PopScope(
      canPop: !_busy && _index == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !_busy && _index > 0) _back();
      },
      child: Scaffold(
        key: const ValueKey('onboarding-story'),
        backgroundColor: AppSurfaces.canvas,
        // The sky keeps its full-screen camera while the foreground makes room
        // for the keyboard. Neither the picture nor Tumi is stretched smaller.
        resizeToAvoidBottomInset: false,
        body: Stack(
          fit: StackFit.expand,
          children: [
            Positioned.fill(
              child: ExcludeSemantics(
                child: Image.asset(
                  'assets/scenes/onboarding/onboarding_bg_v3.png',
                  key: const ValueKey('onboarding-sky'),
                  fit: BoxFit.cover,
                  alignment: Alignment.topCenter,
                ),
              ),
            ),
            SafeArea(
              child: Padding(
                padding: EdgeInsets.only(bottom: mq.viewInsets.bottom),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 600),
                    child: Column(
                      children: [
                        _header(l),
                        Expanded(
                          child: !_ready
                              ? _readFailed
                                    ? Center(
                                        child: Padding(
                                          padding: const EdgeInsets.all(24),
                                          child: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Text(l.obStoryReadError),
                                              TextButton(
                                                onPressed: _loadNames,
                                                child: Text(l.csRetry),
                                              ),
                                            ],
                                          ),
                                        ),
                                      )
                                    : const AppPageWaiting()
                              : _storyBody(
                                  scene,
                                  l,
                                  language,
                                  keyboard: keyboard,
                                  reduce: reduce,
                                  active: active,
                                ),
                        ),
                        _footer(l, keyboard: keyboard),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header(AppLocalizations l) => SizedBox(
    height: 56,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          IconButton(
            key: const ValueKey('onboarding-back'),
            tooltip: _index == 0 && !_normal ? l.csClose : l.csBack,
            constraints: const BoxConstraints.tightFor(width: 48, height: 48),
            onPressed: _busy || (_index == 0 && !Navigator.of(context).canPop())
                ? null
                : _back,
            icon: Icon(
              _index == 0 && !_normal
                  ? Icons.close_rounded
                  : Icons.arrow_back_rounded,
              color: AppInk.soft,
            ),
          ),
          if (_normal)
            IgnorePointer(
              ignoring: _busy,
              child: AudioControlButton(
                style: AudioControlStyle.onboarding,
                accent: AppPalette.habitInk,
                onBeforeOpen: () =>
                    FocusManager.instance.primaryFocus?.unfocus(),
                onMusicEnabled: () => _runAudio(_entryAudio.playIntro()),
              ),
            )
          else
            Expanded(
              child: Text(
                widget.preview ? l.csPreview : l.csReplay,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.labelMedium?.copyWith(color: AppInk.soft),
              ),
            ),
          if (_normal) const Spacer(),
          IconButton(
            key: const ValueKey('onboarding-skip'),
            tooltip: l.csSkip,
            constraints: const BoxConstraints.tightFor(width: 48, height: 48),
            onPressed: !_ready || _busy ? null : () => _finish(skipped: true),
            icon: const Icon(Icons.skip_next_rounded, color: AppInk.soft),
          ),
        ],
      ),
    ),
  );

  Widget _storyBody(
    OnboardingStoryScene scene,
    AppLocalizations l,
    String language, {
    required bool keyboard,
    required bool reduce,
    required bool active,
  }) => LayoutBuilder(
    builder: (context, box) {
      // Only the width chooses Tumi's square stage. Long text scrolls; it never
      // squeezes the character. At 430pt the stage is 249pt; at 320pt, 186pt.
      // This viewport already excludes safe areas, 56pt header and the actual
      // footer (including large text/errors), so the keyboard has one owner.
      final portraitSide = (box.maxWidth * 0.58).clamp(156.0, 252.0);
      final topSpace = keyboard ? 12.0 : math.min(48.0, box.maxHeight * 0.06);
      return Scrollbar(
        controller: _scroll,
        child: SingleChildScrollView(
          key: const ValueKey('onboarding-reading'),
          controller: _scroll,
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          physics: const ClampingScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: box.maxHeight),
            child: Padding(
              padding: EdgeInsets.fromLTRB(24, topSpace, 24, 24),
              child: Column(
                mainAxisAlignment: scene.showMascot || keyboard
                    ? MainAxisAlignment.start
                    : MainAxisAlignment.center,
                children: [
                  if (scene.showMascot && !keyboard) ...[
                    SizedBox.square(
                      key: const ValueKey('onboarding-portrait'),
                      dimension: portraitSide,
                      child: _portrait(scene, reduce: reduce, active: active),
                    ),
                    const SizedBox(height: 20),
                  ],
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 380),
                    child: AnimatedSwitcher(
                      duration: reduce ? Duration.zero : AppMotion.enter,
                      switchInCurve: Curves.easeIn,
                      switchOutCurve: Curves.easeOut,
                      layoutBuilder: (current, previous) => Stack(
                        alignment: Alignment.topCenter,
                        children: [
                          for (final child in previous)
                            ExcludeSemantics(child: child),
                          ?current,
                        ],
                      ),
                      child: _words(scene, l, language, keyboard),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );

  Widget _footer(AppLocalizations l, {required bool keyboard}) => Padding(
    padding: EdgeInsets.fromLTRB(24, 8, 24, keyboard ? 12 : 24),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_saveFailed)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              l.csSaveError,
              key: const ValueKey('onboarding-error'),
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: AppInk.danger),
            ),
          ),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 300),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton(
              key: const ValueKey('onboarding-primary'),
              style: FilledButton.styleFrom(
                backgroundColor: AppPalette.habitInk,
                foregroundColor: AppSurfaces.card,
                minimumSize: const Size(48, 56),
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 16,
                ),
                shape: const StadiumBorder(),
              ),
              onPressed: !_ready || _busy
                  ? null
                  : _saveFailed
                  ? () => _finish(skipped: _retrySkipped)
                  : _last
                  ? _finish
                  : () => _move(_index + 1),
              child: _busy
                  ? const AppLoadingBar()
                  : Text(
                      _saveFailed
                          ? l.csRetry
                          : _last
                          ? _normal
                                ? l.obStoryBegin
                                : l.csFinish
                          : l.csContinue,
                      textAlign: TextAlign.center,
                    ),
            ),
          ),
        ),
      ],
    ),
  );

  Widget _words(
    OnboardingStoryScene scene,
    AppLocalizations l,
    String language,
    bool keyboard,
  ) {
    final text = (_readOnly ? scene.replayText ?? scene.text : scene.text)
        .resolve(language);
    final isName = scene.prompt != OnboardingNamePrompt.none;
    final isMascotName = scene.prompt == OnboardingNamePrompt.mascot;
    final controller = isMascotName ? _mascot : _nickname;
    return Column(
      key: ValueKey('onboarding-scene-${scene.id}'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!scene.showMascot) ...[
          Text(
            onboardingStoryTitle.resolve(language),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: AppInk.strong,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 28),
        ],
        // The optional question remains in the field label while typing. This
        // frees the short keyboard viewport for the actual answer and action.
        if (!keyboard || !isName)
          Text(
            text,
            key: const ValueKey('onboarding-dialogue'),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              fontSize: 19,
              height: 1.65,
              color: AppInk.strong,
            ),
          ),
        if (isName && !_readOnly) ...[
          if (!keyboard) const SizedBox(height: 26),
          Text(
            isMascotName ? l.obStoryNameLabel : l.obStoryUserLabel,
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.labelLarge?.copyWith(color: AppInk.soft),
          ),
          const SizedBox(height: 10),
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 320),
              child: TextField(
                key: ValueKey(
                  isMascotName
                      ? 'onboarding-mascot-name'
                      : 'onboarding-nickname',
                ),
                controller: controller,
                enabled: !_busy,
                textAlign: TextAlign.center,
                textInputAction: TextInputAction.done,
                maxLength: isMascotName ? null : 12,
                inputFormatters: isMascotName
                    ? const [DisplayWidthLimitingFormatter(kMascotNameMaxUnits)]
                    : [LengthLimitingTextInputFormatter(12)],
                onSubmitted: (_) => _move(_index + 1),
                scrollPadding: const EdgeInsets.only(top: 12, bottom: 16),
                decoration: InputDecoration(
                  hintText: isMascotName
                      ? l.mascotDefaultName
                      : l.obStoryUserHint,
                  filled: true,
                  fillColor: AppSurfaces.card.withValues(alpha: 0.78),
                  counterText: '',
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 18,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppCardStyle.radius),
                    borderSide: BorderSide.none,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppCardStyle.radius),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppCardStyle.radius),
                    borderSide: const BorderSide(color: AppPalette.habitInk),
                  ),
                ),
              ),
            ),
          ),
        ],
        if (isName && _readOnly && controller.text.trim().isNotEmpty) ...[
          const SizedBox(height: 24),
          Text(
            isMascotName ? l.obStoryNameLabel : l.obStoryUserLabel,
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.labelMedium?.copyWith(color: AppInk.soft),
          ),
          const SizedBox(height: 6),
          Text(
            controller.text.trim(),
            key: const ValueKey('onboarding-saved-name'),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ],
        if (_last) ...[
          const SizedBox(height: 26),
          Text(
            _normal
                ? '${l.obStoryFeaturesNote}\n${l.obStoryMemoryNote}'
                : l.obStoryMemoryNote,
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: AppInk.soft, height: 1.6),
          ),
        ],
      ],
    );
  }

  Widget _portrait(
    OnboardingStoryScene scene, {
    required bool reduce,
    required bool active,
  }) => ExcludeSemantics(
    child: IgnorePointer(
      child: ListenableBuilder(
        listenable: WardrobeStore.selectedOutfit,
        builder: (_, _) => FittedBox(
          child: MascotStage(
            asset: skinnedMascotAsset(
              scene.emotion.assetPath,
              WardrobeStore.currentOutfit.skinKey,
            ),
            accent: AppPalette.habit,
            reactionTick: 0,
            onTap: () {},
            reduceMotion: reduce,
            paused: !active,
            poseTransition: reduce
                ? MascotPoseTransition.cut
                : MascotPoseTransition.crossFade,
          ),
        ),
      ),
    ),
  );
}
