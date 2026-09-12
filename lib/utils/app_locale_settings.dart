import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'preference_write_guard.dart';
import 'prefs_keys.dart';

enum AppLanguagePreference { automatic, traditionalChinese }

/// One device preference shared by the cover and the actual application root.
/// The available set describes finished UI, not every generated ARB delegate.
class AppLocaleSettings extends ChangeNotifier {
  AppLocaleSettings({SharedPreferences? prefs}) : _prefs = prefs;

  static final AppLocaleSettings instance = AppLocaleSettings();
  static const supportedLocales = [Locale('zh', 'TW')];

  SharedPreferences? _prefs;
  Future<void> _tail = Future<void>.value();
  AppLanguagePreference _preference = AppLanguagePreference.automatic;

  AppLanguagePreference get preference => _preference;

  /// Automatic resolution is restricted to [supportedLocales] by MaterialApp.
  /// Unsupported system languages fall back to the completed Traditional Chinese.
  Locale? get locale => _preference == AppLanguagePreference.automatic
      ? null
      : supportedLocales.first;

  Future<void> load() => _serialize(() async {
    final prefs = _prefs ??= await SharedPreferences.getInstance();
    await PreferenceWriteGuard.ensureHealthy(prefs);
    await prefs.reload();
    final next = prefs.get(PrefsKeys.appLanguage) == 'zh-TW'
        ? AppLanguagePreference.traditionalChinese
        : AppLanguagePreference.automatic;
    _publish(next);
  });

  Future<void> select(AppLanguagePreference next) => _serialize(() async {
    final prefs = _prefs ??= await SharedPreferences.getInstance();
    final code = next == AppLanguagePreference.automatic ? 'auto' : 'zh-TW';
    await PreferenceWriteGuard.write(
      prefs,
      () => prefs.setString(PrefsKeys.appLanguage, code),
      PrefsKeys.appLanguage,
    );
    // Do not let an optimistic legacy preference cache update the live locale.
    _publish(next);
  });

  void _publish(AppLanguagePreference next) {
    if (_preference == next) return;
    _preference = next;
    notifyListeners();
  }

  Future<void> _serialize(Future<void> Function() action) {
    final result = _tail.then((_) => action());
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }
}
