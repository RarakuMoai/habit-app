import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/app_localizations.dart';
import '../utils/account_service.dart';
import '../utils/app_entry_intent.dart';
import '../utils/app_feedback.dart';
import '../utils/app_style.dart';
import '../utils/entry_audio.dart';
import '../utils/parent_pin.dart';
import '../utils/preference_write_guard.dart';
import '../utils/prefs_keys.dart';
import '../widgets/app_language_sheet.dart';
import '../widgets/audio_control_button.dart';
import '../widgets/entry_controls.dart';
import '../widgets/entry_scenery.dart';
import 'account_backup_page.dart';
import 'settings_page.dart';

/// The real app's cold-start cover. Identity and local journey are independent.
class AppEntryPage extends StatefulWidget {
  const AppEntryPage({
    super.key,
    required this.onboardingDone,
    this.requiresLocalReview = false,
  });
  final bool onboardingDone;
  final bool requiresLocalReview;
  @override
  State<AppEntryPage> createState() => _AppEntryPageState();
}

class _AppEntryPageState extends State<AppEntryPage> {
  late final EntryAudioScope _audio = EntryAudio.instance.open();
  final _account = AccountService.instance;
  bool _busy = false;
  bool _failed = false;
  bool _familyLocked = false;
  bool _accountReady = false;
  bool _identityFailed = false;

  @override
  void initState() {
    super.initState();
    _audio;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_audio.playIntro());
      unawaited(_loadAccount());
      if (AppEntryIntent.consumeBackup()) unawaited(_openAccount());
    });
  }

  Future<void> _loadAccount() async {
    if (mounted) {
      setState(() {
        _accountReady = false;
        _identityFailed = false;
      });
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      if (mounted) {
        setState(
          () => _familyLocked =
              prefs.getBool(PrefsKeys.familyRestoreNeedsPin) ?? false,
        );
      }
      final loaded = await _account.initialize(force: true);
      final revision = AppEntryIntent.restoringRevision;
      if (revision != null && loaded) {
        final sameUser = AppEntryIntent.restoringUid == _account.user?.uid;
        final sameRevision = _account.latestBackup?.revision == revision;
        final confirmed =
            (sameUser && sameRevision) &&
            await _account.confirmCloudRestored(revision);
        if (confirmed ||
            !sameUser ||
            (_account.cloudReadConfirmed && !sameRevision)) {
          AppEntryIntent.restoringRevision = null;
          AppEntryIntent.restoringUid = null;
        }
      }
      if (mounted) {
        setState(() {
          _accountReady = true;
          _identityFailed = !loaded;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _accountReady = true;
          _identityFailed = true;
        });
      }
    }
  }

  @override
  void dispose() {
    unawaited(_audio.close());
    super.dispose();
  }

  Future<void> _openAccount() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => const AccountBackupPage(atEntry: true)),
    );
    if (mounted) await _loadAccount();
  }

  Future<void> _enter({bool guest = false}) async {
    if (_busy || widget.requiresLocalReview) return;
    setState(() {
      _busy = true;
      _failed = false;
    });
    playHaptic(HapticLevel.light);
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(PrefsKeys.familyRestoreNeedsPin) ?? false) {
        await prefs.reload();
        if (!await ParentPin.hasPin(prefs)) {
          if (!mounted) return;
          await Navigator.of(context).push<void>(
            MaterialPageRoute(
              builder: (_) => const SettingsPage(openPinSettingsOnLoad: true),
            ),
          );
        }
        if (!mounted) return;
        await prefs.reload();
        if (!await ParentPin.hasPin(prefs)) {
          if (mounted) setState(() => _busy = false);
          return;
        }
        await PreferenceWriteGuard.write(
          prefs,
          () => prefs.remove(PrefsKeys.familyRestoreNeedsPin),
          PrefsKeys.familyRestoreNeedsPin,
        );
        if (mounted) setState(() => _familyLocked = false);
      }
      // Only an explicit new-guest choice writes this marker. Returning local
      // saves and signed-in users retain their actual identity and preferences.
      if (guest && !widget.onboardingDone) {
        await PreferenceWriteGuard.write(
          prefs,
          () => prefs.setBool(PrefsKeys.accountGuestChosen, true),
          PrefsKeys.accountGuestChosen,
        );
      }
      if (!mounted) return;
      if (widget.onboardingDone) unawaited(_audio.enterHome());
      unawaited(
        Navigator.of(context).pushReplacementNamed(
          widget.onboardingDone ? '/home' : '/onboarding',
          arguments: 'entry-arrival',
        ),
      );
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _failed = true;
        });
      }
    }
  }

  Future<void> _chooseStart() => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    isDismissible: false,
    enableDrag: false,
    useSafeArea: true,
    showDragHandle: false,
    builder: (sheetContext) => ListenableBuilder(
      listenable: _account,
      builder: (context, _) {
        final l = AppLocalizations.of(context);
        final restoring = _account.user != null;
        final busy = _account.busy;
        void accountPage() {
          Navigator.pop(sheetContext);
          unawaited(_openAccount());
        }

        void enter({bool guest = false}) {
          Navigator.pop(sheetContext);
          unawaited(_enter(guest: guest));
        }

        Future<void> signIn(AccountProvider provider) async {
          final success = await _account.signIn(provider);
          if (!sheetContext.mounted ||
              !(ModalRoute.of(sheetContext)?.isCurrent ?? false)) {
            return;
          }
          if (success &&
              _account.cloudReadConfirmed &&
              _account.latestBackup == null) {
            enter();
          }
        }

        Widget provider(AccountProvider provider) {
          final apple = provider == AccountProvider.apple;
          return OutlinedButton(
            key: ValueKey('entry-${provider.name}'),
            style: OutlinedButton.styleFrom(
              backgroundColor: AppSurfaces.card,
              minimumSize: const Size(double.infinity, 52),
            ),
            onPressed: busy || !_account.availableProviders.contains(provider)
                ? null
                : () => signIn(provider),
            child: Row(
              children: [
                if (apple)
                  const Icon(Icons.apple, size: 24)
                else
                  Image.asset(
                    'assets/icon/ui/google_sign_in.png',
                    width: 22,
                    height: 22,
                  ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    apple ? l.accountApple : l.accountGoogle,
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(width: 34),
              ],
            ),
          );
        }

        return PopScope(
          canPop: !busy,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * .82,
              maxWidth: 600,
            ),
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                24,
                16,
                24,
                MediaQuery.paddingOf(context).bottom + 16,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Align(
                    alignment: Alignment.centerRight,
                    child: IconButton(
                      tooltip: l.commonClose,
                      onPressed: busy
                          ? null
                          : () => Navigator.pop(sheetContext),
                      icon: const Icon(Icons.close),
                    ),
                  ),
                  Text(
                    restoring ? l.entryRestoreTitle : l.entryChooseTitle,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    restoring
                        ? !_account.cloudReadConfirmed
                              ? l.entryRestoreUnknown
                              : _account.latestBackup != null
                              ? l.entryRestoreFound
                              : l.entryRestoreEmpty
                        : l.entryChooseNote,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: AppInk.soft, height: 1.5),
                  ),
                  const SizedBox(height: 24),
                  if (!restoring) ...[
                    provider(AccountProvider.apple),
                    const SizedBox(height: 12),
                    provider(AccountProvider.google),
                    const SizedBox(height: 12),
                    if (!_account.configured)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Text(
                          l.entryProviderUnavailable,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: AppInk.soft,
                            fontSize: 12,
                            height: 1.5,
                          ),
                        ),
                      ),
                    EntryPrimaryAction(
                      key: const ValueKey('entry-guest'),
                      label: l.entryGuest,
                      onPressed: busy ? null : () => enter(guest: true),
                    ),
                  ] else ...[
                    if (!_account.cloudReadConfirmed)
                      FilledButton(
                        key: const ValueKey('entry-restore-retry'),
                        onPressed: busy ? null : _account.refreshBackup,
                        child: Text(l.csRetry),
                      ),
                    if (_account.cloudReadConfirmed &&
                        _account.latestBackup != null)
                      EntryPrimaryAction(
                        key: const ValueKey('entry-restore-account'),
                        label: l.entryRestore,
                        onPressed: busy ? null : accountPage,
                      ),
                    if (_account.cloudReadConfirmed &&
                        _account.latestBackup == null)
                      EntryPrimaryAction(
                        key: const ValueKey('entry-new-signed'),
                        label: l.entryStartNew,
                        onPressed: busy ? null : enter,
                      ),
                  ],
                  if (busy)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        l.entryIdentityChecking,
                        textAlign: TextAlign.center,
                      ),
                    ),
                  if (_account.errorCode != null &&
                      _account.errorCode != 'cancelled' &&
                      !restoring)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        l.accountError,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: AppInk.danger),
                      ),
                    ),
                  const SizedBox(height: 8),
                  TextButton(
                    key: const ValueKey('entry-sheet-account'),
                    onPressed: busy ? null : accountPage,
                    child: Text(l.entryAccountData),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    ),
  );

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final reduce =
        MediaQuery.disableAnimationsOf(context) ||
        MediaQuery.accessibleNavigationOf(context);
    return Scaffold(
      key: const ValueKey('app-entry'),
      backgroundColor: AppSurfaces.canvas,
      body: Stack(
        fit: StackFit.expand,
        children: [
          const EntryScenery(topScrim: true, bottomScrim: true),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, box) => Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 540),
                  child: SingleChildScrollView(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(minHeight: box.maxHeight),
                      child: IntrinsicHeight(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: Column(
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  const AppLanguageButton(),
                                  AudioControlButton(
                                    style: AudioControlStyle.onboarding,
                                    accent: AppInk.strong,
                                    onMusicEnabled: () => _audio.playIntro(),
                                  ),
                                ],
                              ),
                              SizedBox(height: box.maxHeight < 650 ? 12 : 24),
                              Text(
                                l.appTitle,
                                textAlign: TextAlign.center,
                                style: Theme.of(context)
                                    .textTheme
                                    .headlineMedium
                                    ?.copyWith(
                                      fontSize: 30,
                                      letterSpacing: 3,
                                      fontWeight: FontWeight.w900,
                                      shadows: [
                                        Shadow(
                                          color: AppSurfaces.canvas.withValues(
                                            alpha: .8,
                                          ),
                                          blurRadius: 16,
                                        ),
                                      ],
                                    ),
                              ),
                              const Spacer(),
                              if (_familyLocked ||
                                  widget.requiresLocalReview ||
                                  _failed)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 12),
                                  child: Text(
                                    widget.requiresLocalReview
                                        ? l.entryReviewLocal
                                        : _failed
                                        ? l.csSaveError
                                        : l.backupFamilyPinRequired,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: _failed
                                          ? AppInk.danger
                                          : AppInk.strong,
                                    ),
                                  ),
                                ),
                              TweenAnimationBuilder<double>(
                                duration: reduce
                                    ? Duration.zero
                                    : AppMotion.enter,
                                tween: Tween(begin: 0, end: 1),
                                curve: AppMotion.curve,
                                builder: (context, value, child) =>
                                    Opacity(opacity: value, child: child),
                                child: EntryPrimaryAction(
                                  key: const ValueKey('entry-primary'),
                                  label: widget.requiresLocalReview
                                      ? l.entryAccountData
                                      : _busy
                                      ? l.entryPrepareRoom
                                      : widget.onboardingDone
                                      ? l.entryContinue
                                      : l.entryTapStart,
                                  onPressed: _busy
                                      ? null
                                      : widget.requiresLocalReview
                                      ? _openAccount
                                      : widget.onboardingDone
                                      ? _enter
                                      : !_accountReady
                                      ? null
                                      : _chooseStart,
                                ),
                              ),
                              if (!_accountReady && !widget.onboardingDone)
                                Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: Text(l.entryIdentityChecking),
                                ),
                              if (_identityFailed && !widget.onboardingDone)
                                TextButton(
                                  onPressed: _loadAccount,
                                  child: Text(l.csRetry),
                                ),
                              TextButton(
                                key: const ValueKey('entry-account'),
                                onPressed: _busy ? null : _openAccount,
                                child: Text(
                                  l.entryAccountData,
                                  style: const TextStyle(color: AppInk.strong),
                                ),
                              ),
                              const SizedBox(height: 8),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
