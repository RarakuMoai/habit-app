// 家長 PIN 儲存與驗證
// PIN 不落明文：以「隨機鹽 + 迭代 SHA-256」雜湊後存 SharedPreferences，
// 格式 v1:<迭代次數>:<鹽 base64>:<雜湊 base64>。
// 舊版明文 key（parent_pin）讀到時自動雜湊遷移並刪除。
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 家長 Session（全域）：驗證密碼成功後設為 true。
/// 離開家庭頁籤、FamilyPage unmount、或 app 退到背景時清除。
bool parentSessionActive = false;

class ParentPin {
  static const _hashKey = 'parent_pin_hash';
  static const _legacyKey = 'parent_pin';
  static const _iterations = 10000;

  /// 是否已設定 PIN（會先處理舊版明文遷移）
  static Future<bool> hasPin(SharedPreferences prefs) async {
    await _migrateIfNeeded(prefs);
    return (prefs.getString(_hashKey) ?? '').isNotEmpty;
  }

  /// 設定新 PIN（覆蓋舊值），並確保舊明文 key 已清除
  static Future<void> save(SharedPreferences prefs, String pin) async {
    final salt = _randomSalt();
    await prefs.setString(
      _hashKey,
      'v1:$_iterations:${base64Encode(salt)}:${_hash(pin, salt, _iterations)}',
    );
    await prefs.remove(_legacyKey);
  }

  /// 驗證輸入的 PIN；未設定或格式損毀一律回傳 false
  static Future<bool> verify(SharedPreferences prefs, String entered) async {
    await _migrateIfNeeded(prefs);
    final stored = prefs.getString(_hashKey);
    if (stored == null || stored.isEmpty) return false;
    final parts = stored.split(':');
    if (parts.length != 4 || parts[0] != 'v1') return false;
    final iterations = int.tryParse(parts[1]);
    if (iterations == null) return false;
    final List<int> salt;
    try {
      salt = base64Decode(parts[2]);
    } on FormatException {
      return false;
    }
    return _hash(entered, salt, iterations) == parts[3];
  }

  static Future<void> _migrateIfNeeded(SharedPreferences prefs) async {
    final legacy = prefs.getString(_legacyKey);
    if (legacy == null) return;
    if (legacy.isNotEmpty && (prefs.getString(_hashKey) ?? '').isEmpty) {
      await save(prefs, legacy);
    } else {
      await prefs.remove(_legacyKey);
    }
  }

  static List<int> _randomSalt() {
    final rng = Random.secure();
    return List<int>.generate(16, (_) => rng.nextInt(256));
  }

  static String _hash(String pin, List<int> salt, int iterations) {
    var digest = sha256.convert([...salt, ...utf8.encode(pin)]).bytes;
    for (var i = 1; i < iterations; i++) {
      digest = sha256.convert([...digest, ...salt]).bytes;
    }
    return base64Encode(digest);
  }
}
