import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'prefs_keys.dart';

class AudioSettingsService {
  AudioSettingsService._();
  static final AudioSettingsService instance = AudioSettingsService._();

  static final ValueNotifier<bool> musicMuted = ValueNotifier(false);
  static final ValueNotifier<bool> sfxMuted = ValueNotifier(false);

  static const String _musicKey = PrefsKeys.musicMuted;
  static const String _sfxKey = PrefsKeys.sfxMuted;
  static const String _legacyBgmKey = PrefsKeys.legacyBgmMuted;

  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;
    final prefs = await SharedPreferences.getInstance();
    final legacyMuted = prefs.getBool(_legacyBgmKey);
    musicMuted.value = prefs.getBool(_musicKey) ?? legacyMuted ?? false;
    sfxMuted.value = prefs.getBool(_sfxKey) ?? legacyMuted ?? false;
    _initialized = true;
  }

  Future<void> setMusicMuted(bool value) async {
    if (!_initialized) await init();
    if (musicMuted.value == value) return;
    musicMuted.value = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_musicKey, value);
    await prefs.setBool(_legacyBgmKey, value);
  }

  Future<void> setSfxMuted(bool value) async {
    if (!_initialized) await init();
    if (sfxMuted.value == value) return;
    sfxMuted.value = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_sfxKey, value);
  }

  Future<void> setAllMuted(bool value) async {
    await setMusicMuted(value);
    await setSfxMuted(value);
  }
}
