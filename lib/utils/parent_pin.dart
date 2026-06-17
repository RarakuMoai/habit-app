// 家長 PIN 儲存與驗證
// PIN 不落明文：以「隨機鹽 + 迭代 SHA-256」雜湊後存 SharedPreferences，
// 格式 v1:<迭代次數>:<鹽 base64>:<雜湊 base64>。
// 舊版明文 key（parent_pin）讀到時自動雜湊遷移並刪除。
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'prefs_keys.dart';

/// 家長 Session（全域）：驗證密碼成功後設為 true。
/// 離開家庭頁籤、FamilyPage unmount、或 app 退到背景時清除。
/// ValueNotifier 讓「家長管理」按鈕的鎖定狀態能即時跟著變。
final ValueNotifier<bool> parentSession = ValueNotifier<bool>(false);

class ParentPin {
  static const _hashKey = PrefsKeys.parentPinHash;
  static const _legacyKey = PrefsKeys.legacyParentPin;
  static const _questionKey = PrefsKeys.parentPinQuestion;
  static const _answerKey = PrefsKeys.parentPinAnswerHash;
  static const _iterations = 10000;

  /// 是否已設定 PIN（會先處理舊版明文遷移）
  static Future<bool> hasPin(SharedPreferences prefs) async {
    await _migrateIfNeeded(prefs);
    return (prefs.getString(_hashKey) ?? '').isNotEmpty;
  }

  /// 設定新 PIN（覆蓋舊值），並確保舊明文 key 已清除
  static Future<void> save(SharedPreferences prefs, String pin) async {
    await prefs.setString(_hashKey, _encodeHashed(pin));
    await prefs.remove(_legacyKey);
  }

  /// 驗證輸入的 PIN；未設定或格式損毀一律回傳 false
  static Future<bool> verify(SharedPreferences prefs, String entered) async {
    await _migrateIfNeeded(prefs);
    return _matchHashed(prefs.getString(_hashKey), entered);
  }

  // ── 忘記密碼救援：安全提示問題 ──
  // 答案 normalize（去頭尾空白、轉小寫）後以同一套鹽+迭代雜湊存，不落明文。

  /// 是否已設定救援安全問題（問題與答案都在才算）
  static bool hasSecurityQuestion(SharedPreferences prefs) =>
      (prefs.getString(_questionKey) ?? '').isNotEmpty &&
      (prefs.getString(_answerKey) ?? '').isNotEmpty;

  /// 取救援問題文字；未設定回 null
  static String? securityQuestion(SharedPreferences prefs) {
    final q = prefs.getString(_questionKey);
    return (q == null || q.isEmpty) ? null : q;
  }

  /// 設定／更新救援問題與答案
  static Future<void> saveSecurityQuestion(
    SharedPreferences prefs,
    String question,
    String answer,
  ) async {
    await prefs.setString(_questionKey, question.trim());
    await prefs.setString(_answerKey, _encodeHashed(_normalizeAnswer(answer)));
  }

  /// 驗證救援答案；未設定或格式損毀一律回傳 false
  static bool verifySecurityAnswer(SharedPreferences prefs, String answer) =>
      _matchHashed(prefs.getString(_answerKey), _normalizeAnswer(answer));

  /// 清除密碼與救援問答（保留其他資料）。給「移除密碼」或「重設前先清舊值」用。
  static Future<void> clear(SharedPreferences prefs) async {
    await prefs.remove(_hashKey);
    await prefs.remove(_legacyKey);
    await prefs.remove(_questionKey);
    await prefs.remove(_answerKey);
  }

  static String _normalizeAnswer(String answer) => answer.trim().toLowerCase();

  // 產生 `v1:<迭代>:<鹽 base64>:<雜湊 base64>` 字串
  static String _encodeHashed(String input) {
    final salt = _randomSalt();
    return 'v1:$_iterations:${base64Encode(salt)}:'
        '${_hash(input, salt, _iterations)}';
  }

  // 比對輸入與已存雜湊；格式損毀或未設定回 false
  static bool _matchHashed(String? stored, String input) {
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
    return _hash(input, salt, iterations) == parts[3];
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
