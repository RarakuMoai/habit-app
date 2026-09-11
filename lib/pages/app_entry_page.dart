import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/app_localizations.dart';
import '../utils/account_service.dart';
import '../utils/app_entry_intent.dart';
import '../utils/app_style.dart';
import '../utils/entry_audio.dart';
import '../utils/parent_pin.dart';
import '../utils/preference_write_guard.dart';
import '../utils/prefs_keys.dart';
import '../widgets/audio_control_button.dart';
import 'account_backup_page.dart';
import 'settings_page.dart';

/// A quiet stopping place before the daily app. The first meeting stays a
/// deliberate choice; returning users never have to replay the introduction.
class AppEntryPage extends StatefulWidget {
  const AppEntryPage({super.key, required this.onboardingDone});
  final bool onboardingDone;
  @override
  State<AppEntryPage> createState() => _AppEntryPageState();
}

class _AppEntryPageState extends State<AppEntryPage> {
  late final EntryAudioScope _audio = EntryAudio.instance.open();
  bool _busy = false;
  bool _failed = false;
  bool _familyLocked = false;

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
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(
        () => _familyLocked =
            prefs.getBool(PrefsKeys.familyRestoreNeedsPin) ?? false,
      );
    }
    final account = AccountService.instance;
    await account.initialize(force: true);
    final revision = AppEntryIntent.restoringRevision;
    if (revision != null &&
        AppEntryIntent.restoringUid == account.user?.uid &&
        account.latestBackup?.revision == revision) {
      await account.confirmCloudRestored(revision);
    }
    AppEntryIntent.restoringRevision = null;
    AppEntryIntent.restoringUid = null;
  }

  @override
  void dispose() {
    unawaited(_audio.close());
    super.dispose();
  }

  Future<void> _openAccount() async {
    final proceed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => AccountBackupPage(
          atEntry: true,
          offerContinue: !widget.onboardingDone,
        ),
      ),
    );
    if (proceed == true && mounted) await _enter();
  }

  Future<void> _enter() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _failed = false;
    });
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(PrefsKeys.familyRestoreNeedsPin) ?? false) {
        // The legacy cache can contain an optimistic PIN after a failed native
        // write. Family protection may only be released for a durable PIN.
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
      await PreferenceWriteGuard.write(
        prefs,
        () => prefs.setBool(PrefsKeys.accountGuestChosen, true),
        PrefsKeys.accountGuestChosen,
      );
      if (!mounted) return;
      if (widget.onboardingDone) unawaited(_audio.enterHome());
      unawaited(
        Navigator.of(
          context,
        ).pushReplacementNamed(widget.onboardingDone ? '/home' : '/onboarding'),
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

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      key: const ValueKey('app-entry'),
      backgroundColor: AppSurfaces.canvas,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            'assets/scenes/onboarding/entry_home_v1.png',
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => Image.asset(
              'assets/scenes/onboarding/onboarding_bg_v3.png',
              fit: BoxFit.cover,
            ),
          ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0x50FFF8ED),
                  Color(0x00FFF8ED),
                  Color(0xCCFFF8ED),
                  AppSurfaces.canvas,
                ],
                stops: [0, 0.45, 0.70, 1],
              ),
            ),
          ),
          SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 540),
                child: LayoutBuilder(
                  builder: (context, box) => SingleChildScrollView(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(minHeight: box.maxHeight),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 28),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    AudioControlButton(
                                      style: AudioControlStyle.onboarding,
                                      accent: AppPalette.habitInk,
                                      onMusicEnabled: () => _audio.playIntro(),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  l.appTitle,
                                  textAlign: TextAlign.center,
                                  style: Theme.of(context)
                                      .textTheme
                                      .headlineLarge
                                      ?.copyWith(
                                        color: AppInk.strong,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: 3,
                                      ),
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  l.entryTagline,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: AppInk.soft,
                                    fontSize: 15,
                                    height: 1.6,
                                  ),
                                ),
                              ],
                            ),
                            SizedBox(
                              height: (box.maxHeight * .27).clamp(80.0, 250.0),
                            ),
                            Padding(
                              padding: const EdgeInsets.only(bottom: 18),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Text(
                                    widget.onboardingDone
                                        ? l.entryReady
                                        : l.entryWelcome,
                                    textAlign: TextAlign.center,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleLarge
                                        ?.copyWith(fontWeight: FontWeight.w800),
                                  ),
                                  const SizedBox(height: 10),
                                  Text(
                                    _familyLocked
                                        ? l.backupFamilyPinRequired
                                        : widget.onboardingDone
                                        ? l.entryLocalNote
                                        : l.entryAccountNote,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      color: AppInk.soft,
                                      height: 1.5,
                                    ),
                                  ),
                                  const SizedBox(height: 22),
                                  FilledButton(
                                    key: const ValueKey('entry-primary'),
                                    style: FilledButton.styleFrom(
                                      minimumSize: const Size(48, 56),
                                    ),
                                    onPressed: _busy
                                        ? null
                                        : widget.onboardingDone
                                        ? _enter
                                        : _openAccount,
                                    child: Text(
                                      widget.onboardingDone
                                          ? l.entryReturn
                                          : l.entryBegin,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  TextButton(
                                    key: const ValueKey('entry-guest'),
                                    onPressed: _busy
                                        ? null
                                        : widget.onboardingDone
                                        ? _openAccount
                                        : _enter,
                                    child: Text(
                                      widget.onboardingDone
                                          ? l.accountTitle
                                          : l.entryGuest,
                                    ),
                                  ),
                                  if (!widget.onboardingDone)
                                    TextButton(
                                      onPressed: _busy ? null : _openAccount,
                                      child: Text(l.entryRestore),
                                    ),
                                  if (_failed)
                                    Text(
                                      l.csSaveError,
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        color: AppInk.danger,
                                      ),
                                    ),
                                  const SizedBox(height: 6),
                                  Text(
                                    l.entryFootnote,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      color: AppInk.soft,
                                      fontSize: 12,
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
              ),
            ),
          ),
        ],
      ),
    );
  }
}
