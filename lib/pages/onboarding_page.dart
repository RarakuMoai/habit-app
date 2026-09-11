import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/app_localizations.dart';
import '../utils/app_style.dart';
import '../utils/bgm_service.dart';
import '../utils/input_formatters.dart';
import '../utils/logical_date.dart';
import '../utils/logical_day_coordinator.dart';
import '../utils/mascot.dart';
import '../utils/onboarding_setup.dart';
import '../utils/onboarding_story.dart';
import '../utils/prefs_keys.dart';
import '../utils/scene_time.dart';
import '../utils/wardrobe_catalog.dart';
import '../utils/wardrobe_store.dart';
import '../widgets/app_waiting.dart';
import '../widgets/audio_control_button.dart';
import '../widgets/mascot_scene.dart';
import '../widgets/onboarding_room_scene.dart';
import '../widgets/scene_rooms.dart';

/// A quiet first meeting, also used by preview and the first memory.
/// Only normal setup may save names or initialize a new household.
class OnboardingPage extends StatefulWidget {
  const OnboardingPage({
    super.key,
    this.preview = false,
    this.onReplayFinished,
  });

  final bool preview;
  final Future<bool> Function(bool skipped)? onReplayFinished;

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage>
    with WidgetsBindingObserver {
  final _setup = OnboardingSetup();
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
  bool get _last => _index == onboardingStoryScenes.length - 1;

  @override
  void initState() {
    super.initState();
    _foreground =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
    _loadNames();
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
      unawaited(BgmService.instance.play('sounds/bgm_main.m4a'));
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
    final scene = onboardingStoryScenes[_index];
    final keyboard = mq.viewInsets.bottom > 0;
    return PopScope(
      canPop: !_busy && _index == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !_busy && _index > 0) _back();
      },
      child: Scaffold(
        key: const ValueKey('onboarding-story'),
        backgroundColor: AppSurfaces.canvas,
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 680),
              child: Column(
                children: [
                  SizedBox(
                    height: 56,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Row(
                        children: [
                          IconButton(
                            key: const ValueKey('onboarding-back'),
                            tooltip: _index == 0 && !_normal
                                ? l.csClose
                                : l.csBack,
                            constraints: const BoxConstraints.tightFor(
                              width: 48,
                              height: 48,
                            ),
                            onPressed:
                                _busy ||
                                    (_index == 0 &&
                                        !Navigator.of(context).canPop())
                                ? null
                                : _back,
                            icon: Icon(
                              _index == 0 && !_normal
                                  ? Icons.close_rounded
                                  : Icons.arrow_back_rounded,
                            ),
                          ),
                          if (_normal)
                            IgnorePointer(
                              ignoring: _busy,
                              child: AudioControlButton(
                                style: AudioControlStyle.onboarding,
                                accent: AppPalette.habitInk,
                                onBeforeOpen: () => FocusManager
                                    .instance
                                    .primaryFocus
                                    ?.unfocus(),
                                onMusicEnabled: () => BgmService.instance
                                    .ensurePlaying('sounds/bgm_onboarding.m4a'),
                              ),
                            )
                          else
                            Expanded(
                              child: Text(
                                widget.preview ? l.csPreview : l.csReplay,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.labelMedium
                                    ?.copyWith(color: AppInk.soft),
                              ),
                            ),
                          if (_normal) const Spacer(),
                          IconButton(
                            key: const ValueKey('onboarding-skip'),
                            tooltip: l.csSkip,
                            constraints: const BoxConstraints.tightFor(
                              width: 48,
                              height: 48,
                            ),
                            onPressed: !_ready || _busy
                                ? null
                                : () => _finish(skipped: true),
                            icon: const Icon(
                              Icons.skip_next_rounded,
                              color: AppInk.soft,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
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
                        : LayoutBuilder(
                            builder: (context, box) {
                              // Scaffold has already removed the keyboard. Reserve usable
                              // reading space from these real constraints, never from screen height.
                              final readingReserve = keyboard
                                  ? box.maxHeight
                                  : mq.textScaler
                                        .scale(180)
                                        .clamp(180.0, 330.0);
                              final sceneHeight = math.min(
                                390.0,
                                math.min(
                                  box.maxHeight * 0.60,
                                  math.max(0.0, box.maxHeight - readingReserve),
                                ),
                              );
                              return Column(
                                children: [
                                  if (sceneHeight > 0)
                                    SizedBox(
                                      key: const ValueKey('onboarding-room'),
                                      width: double.infinity,
                                      height: sceneHeight,
                                      child: _room(
                                        scene,
                                        reduce: reduce,
                                        active: active,
                                      ),
                                    ),
                                  Expanded(
                                    child: Scrollbar(
                                      controller: _scroll,
                                      child: SingleChildScrollView(
                                        key: const ValueKey(
                                          'onboarding-reading',
                                        ),
                                        controller: _scroll,
                                        keyboardDismissBehavior:
                                            ScrollViewKeyboardDismissBehavior
                                                .onDrag,
                                        padding: EdgeInsets.fromLTRB(
                                          28,
                                          keyboard ? 12 : 20,
                                          28,
                                          16,
                                        ),
                                        child: AnimatedSwitcher(
                                          duration: reduce
                                              ? Duration.zero
                                              : AppMotion.settle,
                                          layoutBuilder: (current, previous) =>
                                              Stack(
                                                alignment: Alignment.topCenter,
                                                children: [
                                                  ...previous,
                                                  ?current,
                                                ],
                                              ),
                                          child: _words(
                                            scene,
                                            l,
                                            language,
                                            keyboard,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_saveFailed)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Text(
                              l.csSaveError,
                              key: const ValueKey('onboarding-error'),
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: AppInk.danger),
                            ),
                          ),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                            key: const ValueKey('onboarding-primary'),
                            style: FilledButton.styleFrom(
                              backgroundColor: AppPalette.habitInk,
                              foregroundColor: AppSurfaces.card,
                              minimumSize: const Size(48, 56),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 14,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(22),
                              ),
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
                      ],
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
        if (scene.showMascot && !keyboard) ...[
          Text(
            _mascot.text.trim().isEmpty
                ? l.mascotDefaultName
                : _mascot.text.trim(),
            style: Theme.of(
              context,
            ).textTheme.labelLarge?.copyWith(color: AppPalette.habitInk),
          ),
          const SizedBox(height: 10),
        ],
        Text(
          text,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
            fontSize: 19,
            height: 1.65,
            color: AppInk.strong,
          ),
        ),
        if (isName && !_readOnly) ...[
          const SizedBox(height: 22),
          TextField(
            key: ValueKey(
              isMascotName ? 'onboarding-mascot-name' : 'onboarding-nickname',
            ),
            controller: controller,
            enabled: !_busy,
            textInputAction: TextInputAction.done,
            maxLength: isMascotName ? null : 12,
            inputFormatters: isMascotName
                ? const [DisplayWidthLimitingFormatter(kMascotNameMaxUnits)]
                : [LengthLimitingTextInputFormatter(12)],
            onSubmitted: (_) => _move(_index + 1),
            scrollPadding: const EdgeInsets.only(top: 16, bottom: 24),
            decoration: InputDecoration(
              label: Text(
                isMascotName ? l.obStoryNameLabel : l.obStoryUserLabel,
                maxLines: 2,
              ),
              hintText: isMascotName ? l.mascotDefaultName : l.obStoryUserHint,
              floatingLabelBehavior: FloatingLabelBehavior.always,
              filled: true,
              fillColor: AppSurfaces.card,
              counterText: '',
              contentPadding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: AppSurfaces.divider),
              ),
            ),
          ),
        ],
        if (isName && _readOnly && controller.text.trim().isNotEmpty) ...[
          const SizedBox(height: 20),
          Text(
            isMascotName ? l.obStoryNameLabel : l.obStoryUserLabel,
            style: Theme.of(
              context,
            ).textTheme.labelMedium?.copyWith(color: AppInk.soft),
          ),
          const SizedBox(height: 6),
          Text(
            controller.text.trim(),
            key: const ValueKey('onboarding-saved-name'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ],
        if (_last) ...[
          const SizedBox(height: 26),
          Text(
            _normal
                ? '${l.obStoryFeaturesNote}\n${l.obStoryMemoryNote}'
                : l.obStoryMemoryNote,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: AppInk.soft, height: 1.6),
          ),
        ],
      ],
    );
  }

  Widget _room(
    OnboardingStoryScene scene, {
    required bool reduce,
    required bool active,
  }) => ListenableBuilder(
    listenable: WardrobeStore.selectedOutfit,
    builder: (_, _) => OnboardingRoomScene(
      asset: scene.showMascot
          ? skinnedMascotAsset(
              scene.emotion.assetPath,
              WardrobeStore.currentOutfit.skinKey,
            )
          : null,
      reduceMotion: reduce,
      paused: !active,
      lighting: mascotLightingForScene(
        SceneTimeState.fromHour(13),
        FourPeriodRoom.home.light,
      ),
    ),
  );
}
