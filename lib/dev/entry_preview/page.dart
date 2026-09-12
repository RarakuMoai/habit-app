import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/app_localizations.dart';
import '../../utils/app_style.dart';
import '../../utils/tab_catalog.dart';
import 'model.dart';

/// Presentation-only prototype. It cannot navigate into production pages.
class EntryPreviewPage extends StatefulWidget {
  const EntryPreviewPage({
    super.key,
    required this.model,
    this.onAudio,
    this.onVoice,
    this.coverAsset = 'assets/scenes/home/home_day.webp',
    this.coverContainsMascot = false,
  });
  final EntryPreviewModel model;
  final Future<void> Function(bool enabled, bool room)? onAudio;
  final VoidCallback? onVoice;
  final String coverAsset;
  final bool coverContainsMascot;
  @override
  State<EntryPreviewPage> createState() => _EntryPreviewPageState();
}

class _EntryPreviewPageState extends State<EntryPreviewPage> {
  EntryPreviewModel get m => widget.model;
  AppLocalizations get l => AppLocalizations.of(context);
  int? _loadingEpoch;
  bool _sound = false;
  bool _done = false;
  EntryStage? _previousStage;
  final _name = TextEditingController();
  final _insideScroll = ScrollController();

  @override
  void initState() {
    super.initState();
    m.addListener(_changed);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _initialize();
    });
  }

  void _changed() {
    if (!mounted) return;
    if (m.stage == EntryStage.initializing) {
      _done = false;
      _name.text = m.nickname;
      _initialize();
    }
    if (_previousStage != m.stage) {
      // A new indoor scene starts at its own top, even when large text made
      // the preceding skip/name control require scrolling.
      if (_insideScroll.hasClients) _insideScroll.jumpTo(0);
      if (m.stage == EntryStage.meeting && _sound) widget.onVoice?.call();
      if (_sound &&
          (m.stage == EntryStage.cover || m.stage == EntryStage.room)) {
        unawaited(widget.onAudio?.call(true, m.stage == EntryStage.room));
      }
    }
    _previousStage = m.stage;
    setState(() {});
  }

  Future<void> _initialize() async {
    if (m.stage != EntryStage.initializing || _loadingEpoch == m.epoch) return;
    final epoch = m.epoch;
    _loadingEpoch = epoch;
    var failed = false;
    try {
      for (final asset in [
        widget.coverAsset,
        'assets/scenes/home/home_day.webp',
        'assets/mascot/core/tumi_neutral_front.png',
      ]) {
        if (!mounted) return;
        await precacheImage(
          AssetImage(asset),
          context,
          onError: (e, st) {
            failed = true;
          },
        );
      }
    } catch (_) {
      failed = true;
    }
    if (mounted) m.initialized(epoch, failed: failed);
  }

  @override
  void dispose() {
    m.removeListener(_changed);
    _name.dispose();
    _insideScroll.dispose();
    super.dispose();
  }

  bool get reduce => MediaQuery.of(context).disableAnimations;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) m.back();
      },
      child: Scaffold(
        backgroundColor: AppSurfaces.card,
        resizeToAvoidBottomInset: false,
        body: AnimatedSwitcher(
          duration: reduce ? Duration.zero : const Duration(milliseconds: 360),
          child: m.stage == EntryStage.initializing
              ? Image.asset(
                  'assets/scenes/onboarding/entry_preview_launch.png',
                  key: const ValueKey('initializing'),
                  fit: BoxFit.cover,
                  width: double.infinity,
                  height: double.infinity,
                )
              : Column(
                  key: const ValueKey('experience'),
                  children: [
                    SafeArea(
                      bottom: false,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                        child: _toolbar(),
                      ),
                    ),
                    if ((m.stage == EntryStage.cover ||
                            m.stage == EntryStage.restore) &&
                        (m.offline || m.notice != PreviewNotice.none))
                      Padding(
                        padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
                        child: _notice(),
                      ),
                    Expanded(
                      child: AnimatedSwitcher(
                        // The default switcher loosens constraints and centers
                        // short scenes. Keep the art anchored across states.
                        layoutBuilder: (current, previous) => Stack(
                          fit: StackFit.expand,
                          children: [...previous, ?current],
                        ),
                        duration: reduce
                            ? Duration.zero
                            : const Duration(milliseconds: 360),
                        switchInCurve: Curves.easeOutCubic,
                        child: switch (m.stage) {
                          EntryStage.initializationFailed => _failure(),
                          EntryStage.meeting ||
                          EntryStage.nickname ||
                          EntryStage.room => _inside(),
                          _ => _cover(),
                        },
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _toolbar() => Row(
    key: const ValueKey('preview-toolbar'),
    children: [
      Expanded(
        child: Text(
          l.previewBadge,
          style: const TextStyle(
            fontSize: 10,
            color: AppInk.strong,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      _tool(Icons.language_rounded, l.previewLanguage, _languages, 'language'),
      _tool(
        _sound ? Icons.volume_up_rounded : Icons.volume_off_rounded,
        l.previewSound,
        () {
          setState(() => _sound = !_sound);
          unawaited(widget.onAudio?.call(_sound, m.stage == EntryStage.room));
        },
        'sound',
      ),
      _tool(Icons.tune_rounded, l.previewTools, _tools, 'scenarios'),
    ],
  );
  Widget _tool(IconData icon, String label, VoidCallback action, String key) =>
      Padding(
        padding: const EdgeInsets.only(left: 4),
        child: Material(
          color: AppSurfaces.card.withValues(alpha: .95),
          shape: const CircleBorder(),
          child: IconButton(
            key: ValueKey(key),
            tooltip: label,
            onPressed: action,
            icon: Icon(icon, size: 20, color: AppInk.strong),
          ),
        ),
      );

  Widget _cover() => LayoutBuilder(
    key: const ValueKey('cover'),
    builder: (context, constraints) {
      final safe = MediaQuery.paddingOf(context);
      final largeText = MediaQuery.textScalerOf(context).scale(1) > 1.4;
      // The art owns its own region. Long copy grows the scrollable panel instead
      // of covering Tumi's face, shrinking controls or extending under the keyboard.
      final artHeight = (constraints.maxHeight * (largeText ? .42 : .53)).clamp(
        230.0,
        540.0,
      );
      return SingleChildScrollView(
        key: const ValueKey('cover-scroll'),
        child: Column(
          children: [
            SizedBox(
              key: const ValueKey('cover-art'),
              height: artHeight,
              width: double.infinity,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.asset(
                    widget.coverAsset,
                    fit: BoxFit.cover,
                    alignment: const Alignment(0, .12),
                  ),
                  if (!widget.coverContainsMascot)
                    Align(
                      alignment: const Alignment(.18, .7),
                      child: Image.asset(
                        'assets/mascot/core/tumi_neutral_front.png',
                        key: const ValueKey('cover-mascot'),
                        height: artHeight * .57,
                      ),
                    ),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Color(0xCCFFFDF9),
                          Color(0x00FFFDF9),
                          Color(0x00FFFDF9),
                          AppSurfaces.card,
                        ],
                        stops: [0, .22, .86, 1],
                      ),
                    ),
                  ),
                  if (!largeText)
                    Positioned(
                      top: 18,
                      left: 24,
                      right: 24,
                      child: _branding(),
                    ),
                ],
              ),
            ),
            if (largeText)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
                child: _branding(),
              ),
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 540),
                child: Padding(
                  padding: EdgeInsets.fromLTRB(24, 4, 24, safe.bottom + 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (m.stage == EntryStage.restore)
                        ..._restoreContent()
                      else if (m.stage == EntryStage.authorizing) ...[
                        _title(l.previewAuthWaiting),
                        Text(l.previewAuthBody),
                        const SizedBox(height: 12),
                        _button(
                          l.previewAuthCancel,
                          m.back,
                          'cancel-auth',
                          secondary: true,
                        ),
                      ] else if (m.hasJourney) ...[
                        _title(l.previewReturning),
                        _body(
                          m.hasCredential
                              ? l.previewLocalSignedIn
                              : l.previewLocalGuest,
                        ),
                        const SizedBox(height: 18),
                        _button(
                          l.previewContinue,
                          m.continueJourney,
                          'continue',
                        ),
                      ] else if (m.hasCredential) ...[
                        _title(l.previewRestoreTitle),
                        _body(l.previewRestoreBody),
                        const SizedBox(height: 16),
                        _button(
                          l.previewRestoreAction,
                          m.openRestore,
                          'open-restore',
                        ),
                        const SizedBox(height: 8),
                        _body(l.previewRestoreNote),
                      ] else ...[
                        _title(l.previewStartTitle),
                        _body(l.previewStartBody),
                        const SizedBox(height: 16),
                        _providerButton(
                          l.previewApple,
                          Icons.apple,
                          () => _auth('Apple'),
                          'apple',
                        ),
                        const SizedBox(height: 10),
                        _providerButton(
                          l.previewGoogle,
                          Icons.login_rounded,
                          () => _auth('Google'),
                          'google',
                        ),
                        const SizedBox(height: 10),
                        _button(
                          l.previewGuest,
                          m.startGuest,
                          'guest',
                          secondary: true,
                        ),
                      ],
                      if (m.stage == EntryStage.cover)
                        TextButton(
                          key: const ValueKey('account'),
                          onPressed: _account,
                          child: Text(l.previewAccount),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    },
  );

  Widget _branding() => Column(
    key: const ValueKey('cover-branding'),
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        l.previewTitle,
        style: const TextStyle(
          fontSize: 36,
          fontWeight: FontWeight.w800,
          color: AppInk.strong,
        ),
      ),
      Text(
        l.previewSubtitle,
        style: const TextStyle(
          fontSize: 14,
          color: AppInk.strong,
          fontWeight: FontWeight.w600,
        ),
      ),
    ],
  );

  Widget _providerButton(
    String text,
    IconData icon,
    VoidCallback tap,
    String key,
  ) => OutlinedButton.icon(
    key: ValueKey(key),
    onPressed: tap,
    icon: Icon(icon, size: 22),
    label: Text(text, textAlign: TextAlign.center),
    style: OutlinedButton.styleFrom(
      foregroundColor: AppInk.strong,
      backgroundColor: Colors.white,
      minimumSize: const Size(double.infinity, 50),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      side: const BorderSide(color: AppSurfaces.dragHandle),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppCardStyle.radius),
      ),
    ),
  );
  Widget _title(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(
      text,
      style: const TextStyle(
        fontSize: 23,
        height: 1.25,
        fontWeight: FontWeight.w800,
        color: AppInk.strong,
      ),
    ),
  );
  Widget _body(String text) => Text(
    text,
    style: const TextStyle(fontSize: 15, height: 1.5, color: AppInk.soft),
  );
  Widget _button(
    String label,
    VoidCallback onTap,
    String key, {
    bool secondary = false,
  }) => _PressButton(
    key: ValueKey(key),
    label: label,
    onTap: onTap,
    secondary: secondary,
    reduce: reduce,
  );

  Widget _notice() {
    final text = m.offline
        ? l.previewOffline
        : switch (m.notice) {
            PreviewNotice.canceled => l.previewCanceled,
            PreviewNotice.loginFailed => l.previewLoginFailed,
            PreviewNotice.offline => l.previewOffline,
            PreviewNotice.restoreFailed => l.previewRestoreFailed,
            PreviewNotice.simulatedRestored => l.previewRestored,
            PreviewNotice.none => '',
          };
    return Semantics(
      liveRegion: true,
      child: Container(
        key: const ValueKey('notice'),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppSurfaces.fill,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          text,
          style: const TextStyle(
            fontSize: 14,
            height: 1.4,
            color: AppInk.strong,
          ),
        ),
      ),
    );
  }

  List<Widget> _restoreContent() => [
    _title(l.previewRestoreTitle),
    _body(l.previewRestoreBody),
    const SizedBox(height: 12),
    _body(l.previewRestoreNote),
    const SizedBox(height: 18),
    _button(
      l.previewRestoreAction,
      () => m.restore(success: true),
      'restore-success',
    ),
    TextButton(
      key: const ValueKey('restore-failure'),
      onPressed: () => m.restore(success: false),
      child: Text(l.previewRestoreFailureAction),
    ),
    TextButton(onPressed: m.back, child: Text(l.previewBack)),
  ];

  Widget _inside() => LayoutBuilder(
    key: const ValueKey('inside'),
    builder: (context, box) {
      final safe = MediaQuery.paddingOf(context);
      final keyboard = MediaQuery.viewInsetsOf(context).bottom;
      final large = MediaQuery.textScalerOf(context).scale(1) > 1.4;
      final artHeight = keyboard > 0
          ? 160.0
          : (box.maxHeight * (large ? .38 : .53)).clamp(230.0, 530.0);
      return SingleChildScrollView(
        key: const ValueKey('inside-scroll'),
        controller: _insideScroll,
        padding: EdgeInsets.only(bottom: keyboard),
        child: Column(
          children: [
            SizedBox(
              height: artHeight,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.asset(
                    'assets/scenes/home/home_day.webp',
                    fit: BoxFit.cover,
                    alignment: Alignment.topCenter,
                  ),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Color(0xBBFFFDF9),
                          Color(0x00FFFDF9),
                          AppSurfaces.card,
                        ],
                        stops: [0, .35, 1],
                      ),
                    ),
                  ),
                  if (keyboard == 0)
                    Align(
                      alignment: const Alignment(0, .8),
                      child: Image.asset(
                        'assets/mascot/core/tumi_neutral_front.png',
                        height: artHeight * .63,
                      ),
                    ),
                ],
              ),
            ),
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 540),
                child: Padding(
                  padding: EdgeInsets.fromLTRB(24, 8, 24, safe.bottom + 16),
                  child: AnimatedSwitcher(
                    duration: reduce
                        ? Duration.zero
                        : const Duration(milliseconds: 240),
                    child: Column(
                      key: ValueKey(m.stage),
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (m.stage == EntryStage.meeting) ...[
                          _body(l.previewMeetLabel),
                          const SizedBox(height: 12),
                          _title(l.previewMeetText),
                          const SizedBox(height: 20),
                          _button(
                            l.previewMeetContinue,
                            () => m.finishMeeting(),
                            'meet-next',
                          ),
                          TextButton(
                            key: const ValueKey('skip-meeting'),
                            onPressed: () => m.finishMeeting(skip: true),
                            child: Text(l.previewSkip),
                          ),
                          TextButton(
                            onPressed: m.back,
                            child: Text(l.previewBack),
                          ),
                        ] else if (m.stage == EntryStage.nickname) ...[
                          _title(l.previewNameTitle),
                          _body(l.previewNameBody),
                          const SizedBox(height: 18),
                          TextField(
                            key: const ValueKey('nickname'),
                            controller: _name,
                            maxLength: 24,
                            decoration: InputDecoration(
                              labelText: l.previewNameLabel,
                              border: const OutlineInputBorder(),
                            ),
                            onSubmitted: (v) => m.finishName(v),
                          ),
                          const SizedBox(height: 14),
                          _button(l.previewNameContinue, () {
                            FocusManager.instance.primaryFocus?.unfocus();
                            m.finishName(_name.text);
                          }, 'name-next'),
                          TextButton(
                            key: const ValueKey('skip-name'),
                            onPressed: () {
                              FocusManager.instance.primaryFocus?.unfocus();
                              m.finishName('');
                            },
                            child: Text(l.previewNameSkip),
                          ),
                        ] else ...[
                          _title(l.previewRoomTitle),
                          _body(l.previewRoomBody),
                          const SizedBox(height: 16),
                          _button(
                            _done ? l.previewRoomDone : l.previewRoomAction,
                            () => setState(() => _done = !_done),
                            'room-action',
                            secondary: _done,
                          ),
                          const SizedBox(height: 12),
                          _body(l.previewRoomNote),
                          if (m.notice == PreviewNotice.simulatedRestored) ...[
                            const SizedBox(height: 10),
                            _notice(),
                          ],
                          const SizedBox(height: 20),
                          Wrap(
                            alignment: WrapAlignment.center,
                            spacing: 4,
                            runSpacing: 4,
                            children: [
                              for (final tab in kTabCatalog)
                                TextButton(
                                  onPressed: () => _message(
                                    l.previewRoomNote,
                                    l.previewTabNote,
                                  ),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(tab.icon, size: 22),
                                      Text(tabLabel(context, tab.id)),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                          TextButton(
                            onPressed: _account,
                            child: Text(l.previewAccount),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    },
  );

  Widget _failure() => SafeArea(
    key: const ValueKey('init-failure'),
    child: Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(28, 90, 28, 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.refresh_rounded, size: 42, color: AppInk.soft),
              const SizedBox(height: 24),
              _title(l.previewInitError),
              _body(l.previewInitErrorBody),
              const SizedBox(height: 24),
              _button(
                l.previewRetry,
                () => m.coldLaunch(retry: true),
                'init-retry',
              ),
            ],
          ),
        ),
      ),
    ),
  );

  Future<void> _auth(String provider) async {
    final operation = m.beginAuth(provider);
    if (operation == null) return;
    final result = await showModalBottomSheet<PreviewAuthResult>(
      context: context,
      isScrollControlled: true,
      sheetAnimationStyle: reduce ? AnimationStyle.noAnimation : null,
      builder: (context) => _sheet(
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _title(l.previewAuthTitle),
            _body(l.previewAuthBody),
            const SizedBox(height: 14),
            for (final item in <(PreviewAuthResult, String, String)>[
              (PreviewAuthResult.successNew, l.previewAuthNew, 'auth-new'),
              (
                PreviewAuthResult.successExisting,
                l.previewAuthExisting,
                'auth-existing',
              ),
              (PreviewAuthResult.canceled, l.previewAuthCancel, 'auth-cancel'),
              (PreviewAuthResult.failed, l.previewAuthFailure, 'auth-failed'),
              (PreviewAuthResult.offline, l.previewAuthOffline, 'auth-offline'),
            ])
              TextButton(
                key: ValueKey(item.$3),
                onPressed: () => Navigator.pop(context, item.$1),
                child: Text(item.$2),
              ),
          ],
        ),
      ),
    );
    m.completeAuth(operation, result ?? PreviewAuthResult.canceled);
  }

  Widget _sheet(Widget child) => SafeArea(
    child: SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        24,
        24,
        24,
        MediaQuery.viewInsetsOf(context).bottom + 20,
      ),
      child: child,
    ),
  );
  Future<void> _message(String title, String body) => showDialog<void>(
    context: context,
    animationStyle: reduce ? AnimationStyle.noAnimation : null,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l.previewClose),
        ),
      ],
    ),
  );
  void _account() =>
      unawaited(_message(l.previewAccount, l.previewAccountBody));
  Future<void> _languages() => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    sheetAnimationStyle: reduce ? AnimationStyle.noAnimation : null,
    builder: (context) => _sheet(
      Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _title(l.previewLanguage),
          for (final item in [
            ('system', l.previewSystem),
            ('zh', '繁體中文'),
            ('en', 'English'),
          ])
            ListTile(
              key: ValueKey('locale-${item.$1}'),
              title: Text(item.$2),
              trailing: m.language == item.$1 ? const Icon(Icons.check) : null,
              onTap: () {
                m.setLanguage(item.$1);
                Navigator.pop(context);
              },
            ),
          _body(l.previewLanguageNote),
        ],
      ),
    ),
  );
  Future<void> _tools() => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    sheetAnimationStyle: reduce ? AnimationStyle.noAnimation : null,
    builder: (context) => _sheet(
      Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _title(l.previewTools),
          _body(l.previewToolsNote),
          for (final item in <(EntryScenario, String)>[
            (EntryScenario.firstUse, l.previewFirst),
            (EntryScenario.returningSignedIn, l.previewReturningSignedIn),
            (EntryScenario.returningGuest, l.previewReturningGuest),
            (EntryScenario.credentialsOnly, l.previewCredentialOnly),
            (EntryScenario.offline, l.previewOfflineScenario),
            (EntryScenario.initializationFailed, l.previewFailureScenario),
          ])
            ListTile(
              key: ValueKey('scenario-${item.$1.name}'),
              title: Text(item.$2),
              onTap: () {
                Navigator.pop(context);
                m.selectScenario(item.$1);
              },
            ),
          SwitchListTile(
            key: const ValueKey('reduce-motion'),
            title: Text(l.previewMotion),
            value: m.reduceMotion,
            onChanged: (v) {
              m.setAccessibility(motion: v, scale: m.textScale);
              Navigator.pop(context);
            },
          ),
          SwitchListTile(
            key: const ValueKey('large-text'),
            title: Text(l.previewLargeText),
            value: m.textScale != null,
            onChanged: (v) {
              m.setAccessibility(scale: v ? 2 : null);
              Navigator.pop(context);
            },
          ),
          TextButton(
            key: const ValueKey('cold-launch'),
            onPressed: () {
              Navigator.pop(context);
              m.coldLaunch();
            },
            child: Text(l.previewColdLaunch),
          ),
        ],
      ),
    ),
  );
}

class _PressButton extends StatefulWidget {
  const _PressButton({
    super.key,
    required this.label,
    required this.onTap,
    required this.secondary,
    required this.reduce,
  });
  final String label;
  final VoidCallback onTap;
  final bool secondary, reduce;
  @override
  State<_PressButton> createState() => _PressButtonState();
}

class _PressButtonState extends State<_PressButton> {
  bool down = false;
  @override
  Widget build(BuildContext context) => Listener(
    onPointerDown: (_) => setState(() => down = true),
    onPointerUp: (_) => setState(() => down = false),
    onPointerCancel: (_) => setState(() => down = false),
    child: AnimatedScale(
      scale: down && !widget.reduce ? AppPressMotion.scale : 1,
      duration: widget.reduce
          ? Duration.zero
          : down
          ? AppPressMotion.down
          : AppPressMotion.release,
      curve: AppPressMotion.curve,
      child: FilledButton(
        onPressed: () {
          unawaited(HapticFeedback.selectionClick());
          widget.onTap();
        },
        style: FilledButton.styleFrom(
          backgroundColor: widget.secondary ? AppSurfaces.fill : AppInk.strong,
          foregroundColor: widget.secondary ? AppInk.strong : AppSurfaces.card,
          minimumSize: const Size(double.infinity, 52),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppCardStyle.radius),
          ),
        ),
        child: Text(
          widget.label,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),
    ),
  );
}
