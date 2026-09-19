import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/app_localizations.dart';
import '../utils/app_locale_settings.dart';
import '../utils/app_style.dart';
import '../utils/entry_audio.dart';
import '../utils/preference_write_guard.dart';
import '../utils/prefs_keys.dart';
import '../utils/user_validators.dart';
import '../widgets/app_waiting.dart';
import '../widgets/beta_information_sheet.dart';
import '../widgets/birthday_picker.dart';
import '../widgets/entry_controls.dart';
import 'app_entry_page.dart';
import 'onboarding_page.dart';

/// Preparation is device-local and does not complete/award the first story.
/// Existing completed saves continue directly from the cover to their home.
class OnboardingPreparationPage extends StatefulWidget {
  const OnboardingPreparationPage({super.key, this.localeSettings});
  final AppLocaleSettings? localeSettings;

  @override
  State<OnboardingPreparationPage> createState() => _PreparationState();
}

class _PreparationState extends State<OnboardingPreparationPage> {
  static const _receiptVersion = 'beta-2026-09-18';
  late final _locale = widget.localeSettings ?? AppLocaleSettings.instance;
  late final EntryAudioScope _audio = EntryAudio.instance.open(
    asset: EntryAudio.coverAsset,
  );
  SharedPreferences? _prefs;
  AppLanguagePreference _language = AppLanguagePreference.automatic;
  DateTime? _birthday;
  int _step = 0;
  bool _ready = false;
  bool _busy = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    unawaited(_audio.playIntro());
    unawaited(_load());
  }

  @override
  void dispose() {
    unawaited(_audio.close());
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _failed = false);
    try {
      final prefs = await SharedPreferences.getInstance();
      await PreferenceWriteGuard.ensureHealthy(prefs);
      await prefs.reload();
      await _locale.load();
      if (!mounted) return;
      _prefs = prefs;
      final receipt = prefs.getString(PrefsKeys.onboardingPreparationReceipt);
      // A malformed checkpoint must never bypass the preparation screens.
      Object? decoded;
      try {
        decoded = receipt == null ? null : jsonDecode(receipt);
      } catch (_) {
        decoded = null;
      }
      if (decoded is Map &&
          decoded['version'] == _receiptVersion &&
          DateTime.tryParse('${decoded['continuedAt']}') != null) {
        _beginStory();
        return;
      }
      final storedBirthday = DateTime.tryParse(
        prefs.getString(PrefsKeys.userBirthday) ?? '',
      );
      setState(() {
        _step = (prefs.getInt(PrefsKeys.onboardingPreparationStep) ?? 0).clamp(
          0,
          2,
        );
        _language = _locale.preference;
        _birthday =
            UserValidators.birthday(
                  AppLocalizations.of(context),
                  storedBirthday,
                ) ==
                null
            ? storedBirthday
            : null;
        _ready = true;
      });
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  void _beginStory() {
    unawaited(
      Navigator.of(context).pushReplacement<void, void>(
        EntryPageRoute(
          builder: (_) => const OnboardingPage(compactEntry: true),
        ),
      ),
    );
  }

  Future<void> _next() async {
    if (!_ready || _busy) {
      return;
    }
    setState(() {
      _busy = true;
      _failed = false;
    });
    try {
      final prefs = _prefs!;
      if (_step == 0) {
        await _locale.select(_language);
      } else if (_step == 1 && _birthday != null) {
        final date = _birthday!.toIso8601String().substring(0, 10);
        await PreferenceWriteGuard.write(
          prefs,
          () => prefs.setString(PrefsKeys.userBirthday, date),
          PrefsKeys.userBirthday,
        );
      }
      if (_step < 2) {
        await PreferenceWriteGuard.write(
          prefs,
          () => prefs.setInt(PrefsKeys.onboardingPreparationStep, _step + 1),
          PrefsKeys.onboardingPreparationStep,
        );
        if (mounted) {
          setState(() {
            _step++;
            _busy = false;
          });
        }
      } else {
        // This checkpoint records journey progress, never data-collection consent.
        final receipt = jsonEncode({
          'version': _receiptVersion,
          'continuedAt': DateTime.now().toUtc().toIso8601String(),
        });
        await PreferenceWriteGuard.write(
          prefs,
          () =>
              prefs.setString(PrefsKeys.onboardingPreparationReceipt, receipt),
          PrefsKeys.onboardingPreparationReceipt,
        );
        if (mounted) _beginStory();
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _failed = true;
        });
      }
    }
  }

  void _back() {
    if (!_ready || _busy) return;
    if (_step > 0) {
      setState(() => _step--);
    } else {
      unawaited(
        Navigator.of(context).pushReplacement<void, void>(
          MaterialPageRoute(
            builder: (_) => const AppEntryPage(onboardingDone: false),
          ),
        ),
      );
    }
  }

  Future<void> _pickBirthday() async {
    final now = DateTime.now();
    final picked = await showBirthdayPicker(
      context,
      initial: _birthday,
      firstDate: DateTime(now.year - UserRanges.birthdayMaxAgeYears),
      lastDate: DateTime(now.year, now.month, now.day),
      accent: AppPalette.habitInk,
    );
    if (picked != null && mounted) setState(() => _birthday = picked);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final mq = MediaQuery.of(context);
    final reduce = mq.disableAnimations || mq.accessibleNavigation;
    final titles = [
      l.prepLanguageTitle,
      l.prepBirthdayTitle,
      l.prepAgreementTitle,
    ];
    final notes = [l.prepLanguageNote, l.prepBirthdayNote, l.prepAgreementNote];
    final labels = [
      l.prepStepLanguage,
      l.prepStepBirthday,
      l.prepStepAgreement,
    ];
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Scaffold(
        key: const ValueKey('onboarding-preparation'),
        backgroundColor: AppSurfaces.canvas,
        body: Stack(
          fit: StackFit.expand,
          children: [
            ExcludeSemantics(
              child: Image.asset(
                'assets/scenes/onboarding/onboarding_bg_v3.png',
                fit: BoxFit.cover,
                alignment: Alignment.topCenter,
              ),
            ),
            SafeArea(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 8, 24, 0),
                        child: Row(
                          children: [
                            IconButton(
                              key: const ValueKey('preparation-back'),
                              tooltip: l.csBack,
                              onPressed: !_ready || _busy ? null : _back,
                              icon: const Icon(Icons.arrow_back_rounded),
                            ),
                            Expanded(
                              child: Text(
                                l.prepEyebrow,
                                textAlign: TextAlign.end,
                                style: const TextStyle(
                                  color: AppInk.soft,
                                  letterSpacing: 3,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: !_ready
                            ? Center(
                                child: _failed
                                    ? TextButton(
                                        onPressed: _load,
                                        child: Text(l.csRetry),
                                      )
                                    : const AppPageWaiting(),
                              )
                            : LayoutBuilder(
                                builder: (context, box) =>
                                    SingleChildScrollView(
                                      key: const ValueKey('preparation-scroll'),
                                      padding: const EdgeInsets.fromLTRB(
                                        24,
                                        12,
                                        24,
                                        24,
                                      ),
                                      child: ConstrainedBox(
                                        constraints: BoxConstraints(
                                          minHeight: (box.maxHeight - 36).clamp(
                                            0,
                                            double.infinity,
                                          ),
                                        ),
                                        child: Column(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            _InvitationMark(
                                              step: _step,
                                              reduce: reduce,
                                            ),
                                            const SizedBox(height: 26),
                                            AnimatedSwitcher(
                                              duration: reduce
                                                  ? Duration.zero
                                                  : AppMotion.enter,
                                              switchInCurve:
                                                  Curves.easeOutCubic,
                                              switchOutCurve:
                                                  Curves.easeInCubic,
                                              layoutBuilder:
                                                  (current, previous) => Stack(
                                                    alignment:
                                                        Alignment.topCenter,
                                                    children: [
                                                      for (final child
                                                          in previous)
                                                        ExcludeSemantics(
                                                          child: IgnorePointer(
                                                            child: child,
                                                          ),
                                                        ),
                                                      ?current,
                                                    ],
                                                  ),
                                              transitionBuilder:
                                                  (child, animation) =>
                                                      FadeTransition(
                                                        opacity: animation,
                                                        child: SlideTransition(
                                                          position: Tween(
                                                            begin: Offset(
                                                              0,
                                                              reduce ? 0 : .035,
                                                            ),
                                                            end: Offset.zero,
                                                          ).animate(animation),
                                                          child: child,
                                                        ),
                                                      ),
                                              child: Column(
                                                key: ValueKey(
                                                  'preparation-step-$_step',
                                                ),
                                                children: [
                                                  Text(
                                                    titles[_step],
                                                    textAlign: TextAlign.center,
                                                    style: Theme.of(context)
                                                        .textTheme
                                                        .headlineSmall
                                                        ?.copyWith(
                                                          color: AppInk.strong,
                                                          fontSize: 25,
                                                          fontWeight:
                                                              FontWeight.w800,
                                                          height: 1.5,
                                                        ),
                                                  ),
                                                  const SizedBox(height: 12),
                                                  Text(
                                                    notes[_step],
                                                    textAlign: TextAlign.center,
                                                    style: const TextStyle(
                                                      color: AppInk.soft,
                                                      height: 1.7,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 28),
                                                  _paper(
                                                    child: switch (_step) {
                                                      0 => _languages(l),
                                                      1 => _birthdayCard(l),
                                                      _ => _agreements(l),
                                                    },
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
                      Padding(
                        padding: const EdgeInsets.fromLTRB(24, 8, 24, 18),
                        child: Column(
                          children: [
                            if (_failed && _ready)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: Text(
                                  l.csSaveError,
                                  key: const ValueKey('preparation-error'),
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(color: AppInk.danger),
                                ),
                              ),
                            EntryPrimaryAction(
                              key: const ValueKey('preparation-next'),
                              label: _busy
                                  ? l.entryPrepareRoom
                                  : _step == 2
                                  ? l.prepStartStory
                                  : _step == 1 && _birthday == null
                                  ? l.prepBirthdayLater
                                  : l.csContinue,
                              onPressed: !_ready || _busy ? null : _next,
                            ),
                            const SizedBox(height: 20),
                            Row(
                              children: [
                                for (var i = 0; i < 3; i++)
                                  Expanded(
                                    child: Column(
                                      children: [
                                        AnimatedContainer(
                                          duration: reduce
                                              ? Duration.zero
                                              : AppMotion.quick,
                                          height: 4,
                                          margin: const EdgeInsets.symmetric(
                                            horizontal: 5,
                                          ),
                                          decoration: BoxDecoration(
                                            color: i <= _step
                                                ? AppPalette.habitInk
                                                : AppSurfaces.divider,
                                            borderRadius: BorderRadius.circular(
                                              4,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(height: 7),
                                        Text(
                                          labels[i],
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: i == _step
                                                ? AppInk.strong
                                                : AppInk.soft,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _paper({required Widget child}) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: AppSurfaces.card.withValues(alpha: .94),
      borderRadius: BorderRadius.circular(AppCardStyle.radius),
      border: Border.all(color: AppSurfaces.card),
      boxShadow: AppShadows.card,
    ),
    child: Material(type: MaterialType.transparency, child: child),
  );

  Widget _languages(AppLocalizations l) => Column(
    children: [
      for (final value in AppLanguagePreference.values) ...[
        if (value != AppLanguagePreference.values.first)
          const SizedBox(height: 10),
        Semantics(
          selected: _language == value,
          child: ListTile(
            key: ValueKey('preparation-language-${value.name}'),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 5,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            tileColor: _language == value
                ? AppPalette.habitLight
                : AppSurfaces.fill,
            title: Text(
              value == AppLanguagePreference.automatic
                  ? l.appLanguageAutomatic
                  : l.appLanguageTraditionalChinese,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            subtitle: value == AppLanguagePreference.automatic
                ? Text(l.appLanguageAutomaticNote)
                : null,
            trailing: Icon(
              _language == value
                  ? Icons.check_circle_rounded
                  : Icons.circle_outlined,
              color: AppPalette.habitInk,
            ),
            onTap: _busy ? null : () => setState(() => _language = value),
          ),
        ),
      ],
      const SizedBox(height: 16),
      Text(
        l.prepLanguageAvailability,
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 12, height: 1.6, color: AppInk.soft),
      ),
    ],
  );

  Widget _birthdayCard(AppLocalizations l) => Column(
    children: [
      Text(l.birthdayLabel, style: const TextStyle(color: AppInk.soft)),
      const SizedBox(height: 12),
      OutlinedButton(
        key: const ValueKey('preparation-birthday'),
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(double.infinity, 72),
          backgroundColor: AppSurfaces.fill,
          side: const BorderSide(color: AppSurfaces.divider),
        ),
        onPressed: _busy ? null : _pickBirthday,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            children: [
              const Icon(
                Icons.calendar_month_rounded,
                color: AppPalette.habitInk,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _birthday == null
                      ? l.prepBirthdayChoose
                      : '${_birthday!.year} / ${_birthday!.month.toString().padLeft(2, '0')} / ${_birthday!.day.toString().padLeft(2, '0')}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppInk.strong,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              const Icon(Icons.edit_outlined, size: 19, color: AppInk.soft),
            ],
          ),
        ),
      ),
      const SizedBox(height: 14),
      Text(
        l.prepBirthdayHint,
        style: const TextStyle(color: AppInk.soft, letterSpacing: 2),
      ),
    ],
  );

  Widget _agreements(AppLocalizations l) => Column(
    children: [
      _document(l.prepUseTitle, l.prepUseBody, Icons.menu_book_rounded, 'use'),
      const Divider(height: 16),
      _document(
        l.prepDataTitle,
        l.prepDataBody,
        Icons.lock_outline_rounded,
        'data',
      ),
      const SizedBox(height: 12),
      Text(
        l.prepReviewNote,
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 12, height: 1.6, color: AppInk.soft),
      ),
    ],
  );

  Widget _document(String title, String body, IconData icon, String id) =>
      ListTile(
        key: ValueKey('preparation-document-$id'),
        contentPadding: EdgeInsets.zero,
        leading: Icon(icon, color: AppPalette.habitInk),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: _busy
            ? null
            : () => showPreparationDocument(context, title: title, body: body),
      );
}

/// A small invitation: no character reveal before the first meeting.
/// The finite entrance stops naturally and never runs an idle background ticker.
class _InvitationMark extends StatelessWidget {
  const _InvitationMark({required this.step, required this.reduce});
  final int step;
  final bool reduce;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    key: ValueKey(step),
    tween: Tween(begin: reduce ? 1 : 0, end: 1),
    duration: reduce ? Duration.zero : const Duration(milliseconds: 650),
    curve: Curves.easeOutCubic,
    builder: (_, value, child) => Opacity(
      opacity: value,
      child: Transform.translate(
        offset: Offset(0, reduce ? 0 : 12 * (1 - value)),
        child: child,
      ),
    ),
    child: SizedBox(
      width: 132,
      height: 104,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Transform.rotate(
            angle: -.08,
            child: Container(
              width: 102,
              height: 82,
              decoration: BoxDecoration(
                color: AppPalette.habitLight,
                borderRadius: BorderRadius.circular(22),
              ),
            ),
          ),
          Transform.rotate(
            angle: .045,
            child: Container(
              width: 102,
              height: 82,
              decoration: BoxDecoration(
                color: AppSurfaces.card,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: AppSurfaces.divider),
                boxShadow: AppShadows.flat,
              ),
              child: Icon(
                [
                  Icons.language_rounded,
                  Icons.cake_outlined,
                  Icons.favorite_border_rounded,
                ][step],
                color: AppPalette.habitInk,
                size: 38,
              ),
            ),
          ),
          Positioned(
            right: 1,
            bottom: 0,
            child: ExcludeSemantics(
              child: Image.asset(
                'assets/icon/ui/paw_footprint_coin_round.png',
                width: 38,
                height: 38,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
