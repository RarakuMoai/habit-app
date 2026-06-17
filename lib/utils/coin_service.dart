// 金幣服務：餘額、帳本、發放/撤銷、每日登入等級。
//
// 設計（2026-06-12 定案）：
// - `coin_balance` 是唯一真相來源；帳本只留最近 N 筆給明細頁/除錯。
// - 防作弊走「防君子」原則：每日一次型來源用 per-day key 擋重複領取、
//   打卡類用對稱 revoke 擋來回切刷幣。不做時間竄改偵測（單機 app）。
// - 每日登入等級曲線與寬限規則見 [CoinConfig]（輕鬆不嚴格：缺席一天
//   寬限、超過只降 [CoinConfig.loginLevelDrop] 級不歸零）。
//
// 數值都在 coin_config.dart，這裡只有機制。

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'coin_config.dart';
import 'prefs_keys.dart';

/// 每日一次型來源（award 內建 per-day 防重複）
const Set<CoinSource> _dailyOnceSources = {
  CoinSource.dailyLogin,
  CoinSource.allHabitsDone,
  CoinSource.waterGoal,
  CoinSource.weeklyStreak,
};

/// 帳本單筆紀錄
class CoinEntry {
  final DateTime at;
  final String source;
  final int amount; // 正 = 入帳、負 = 撤銷/扣款
  final String? note;

  const CoinEntry({
    required this.at,
    required this.source,
    required this.amount,
    this.note,
  });

  Map<String, dynamic> toJson() => {
    'at': at.toIso8601String(),
    'src': source,
    'amt': amount,
    if (note != null) 'note': note,
  };

  static CoinEntry fromJson(Map<String, dynamic> json) => CoinEntry(
    at: DateTime.tryParse(json['at'] as String? ?? '') ?? DateTime.now(),
    source: json['src'] as String? ?? '',
    amount: (json['amt'] as num?)?.toInt() ?? 0,
    note: json['note'] as String?,
  );
}

/// claimDailyLogin 的結果
class LoginReward {
  /// 領取後的連續等級（1 ~ [CoinConfig.loginMaxLevel]）
  final int level;

  /// 本次入帳金幣
  final int amount;

  /// 這次有沒有用到寬限（昨天缺席但等級保住）—— 給兔咪台詞用
  final bool graceUsed;

  const LoginReward({
    required this.level,
    required this.amount,
    required this.graceUsed,
  });
}

class CoinService {
  /// 目前餘額（UI 用 ValueListenableBuilder 監聽）。
  /// app 啟動時呼叫 [load] 同步一次，之後每筆異動都會更新。
  static final ValueNotifier<int> notifier = ValueNotifier<int>(0);

  static String _dateStr(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// app 啟動時呼叫：把存檔餘額載進 notifier
  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    notifier.value = prefs.getInt(PrefsKeys.coinBalance) ?? 0;
  }

  static Future<int> balance() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(PrefsKeys.coinBalance) ?? 0;
  }

  /// 最近的帳本紀錄（新到舊）
  static Future<List<CoinEntry>> ledger() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(PrefsKeys.coinLedger);
    if (raw == null) return const [];
    return (jsonDecode(raw) as List)
        .map((e) => CoinEntry.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// 發放金幣。回傳實際入帳金額；每日一次型來源當日已領回 0。
  ///
  /// [amount] 不傳就用 [CoinConfig.amountOf]。[now] 供測試注入時間。
  static Future<int> award(
    CoinSource source, {
    int? amount,
    String? note,
    DateTime? now,
  }) async {
    // 暫停中的來源不發放（呼叫端保留，集中由 enabledSources 控制）
    if (!CoinConfig.enabledSources.contains(source)) return 0;

    final prefs = await SharedPreferences.getInstance();
    final ts = now ?? DateTime.now();

    if (_dailyOnceSources.contains(source)) {
      final claimKey = PrefsKeys.coinClaim(source.name, _dateStr(ts));
      if (prefs.getBool(claimKey) ?? false) return 0;
      await prefs.setBool(claimKey, true);
    }

    final amt = amount ?? CoinConfig.amountOf(source);
    await _apply(prefs, ts, source.name, amt, note);
    return amt;
  }

  /// 花費金幣（購買造型 / 音樂等）。餘額足夠才扣款並回傳 true；
  /// 不足回傳 false 不動帳。[note] 會寫進帳本明細。
  static Future<bool> spend(int amount, {required String note}) async {
    if (amount <= 0) return true;
    final prefs = await SharedPreferences.getInstance();
    final cur = prefs.getInt(PrefsKeys.coinBalance) ?? 0;
    if (cur < amount) return false;
    await _apply(prefs, DateTime.now(), 'purchase', -amount, note);
    return true;
  }

  /// 開發測試用：直接加減金幣（不走來源 gating）；負數會扣到地板 0。
  /// 僅供 debug 測試頁呼叫，release 進不到入口。
  static Future<void> debugAdd(int amount) async {
    if (amount == 0) return;
    final prefs = await SharedPreferences.getInstance();
    await _apply(prefs, DateTime.now(), 'debug', amount, '測試調整');
  }

  /// 撤銷（打卡取消用）：對稱扣回，餘額地板 0。
  static Future<void> revoke(
    CoinSource source, {
    int? amount,
    String? note,
    DateTime? now,
  }) async {
    // 與 award 對稱：暫停中的來源沒發過，也就不撤銷
    if (!CoinConfig.enabledSources.contains(source)) return;

    final prefs = await SharedPreferences.getInstance();
    final cur = prefs.getInt(PrefsKeys.coinBalance) ?? 0;
    // 餘額不足就只扣到 0（理論上只在使用者已花掉金幣時發生）
    final amt = -(amount ?? CoinConfig.amountOf(source)).clamp(0, cur);
    await _apply(prefs, now ?? DateTime.now(), source.name, amt, note);
  }

  /// 領取每日登入獎勵。今天已領回 null。
  ///
  /// 等級規則（[CoinConfig]）：
  /// - 第一次領 / 連續：等級 +1（封頂 [CoinConfig.loginMaxLevel]）
  /// - 缺席 <= [CoinConfig.loginGraceDays]：等級保住不動（寬限）
  /// - 缺席更久：等級 - [CoinConfig.loginLevelDrop]（最低 1）
  static Future<LoginReward?> claimDailyLogin({DateTime? now}) async {
    final prefs = await SharedPreferences.getInstance();
    final ts = now ?? DateTime.now();
    final today = _dateStr(ts);

    final last = prefs.getString(PrefsKeys.coinLastLoginDate);
    if (last == today) return null;

    final oldLevel = prefs.getInt(PrefsKeys.coinLoginLevel) ?? 0;
    int level;
    var graceUsed = false;
    if (last == null || oldLevel < 1) {
      level = 1;
    } else {
      final lastDate = DateTime.tryParse(last);
      final missed = lastDate == null
          ? 0
          : DateTime(ts.year, ts.month, ts.day)
                    .difference(
                      DateTime(lastDate.year, lastDate.month, lastDate.day),
                    )
                    .inDays -
                1;
      if (missed <= 0) {
        level = (oldLevel + 1).clamp(1, CoinConfig.loginMaxLevel);
      } else if (missed <= CoinConfig.loginGraceDays) {
        level = oldLevel.clamp(1, CoinConfig.loginMaxLevel);
        graceUsed = true;
      } else {
        level = (oldLevel - CoinConfig.loginLevelDrop).clamp(
          1,
          CoinConfig.loginMaxLevel,
        );
      }
    }

    final amount = CoinConfig.loginRewardAt(level);
    await prefs.setString(PrefsKeys.coinLastLoginDate, today);
    await prefs.setInt(PrefsKeys.coinLoginLevel, level);
    // 登入獎勵也走 award 的 per-day claim（雙保險）；金額用等級算好的
    final awarded = await award(
      CoinSource.dailyLogin,
      amount: amount,
      note: '連續 Lv.$level',
      now: ts,
    );
    if (awarded == 0) return null;
    return LoginReward(level: level, amount: amount, graceUsed: graceUsed);
  }

  // 入帳 + 記帳 + 廣播
  static Future<void> _apply(
    SharedPreferences prefs,
    DateTime at,
    String source,
    int amount,
    String? note,
  ) async {
    if (amount == 0) return;
    final next = ((prefs.getInt(PrefsKeys.coinBalance) ?? 0) + amount).clamp(
      0,
      1 << 31,
    );
    await prefs.setInt(PrefsKeys.coinBalance, next);

    final raw = prefs.getString(PrefsKeys.coinLedger);
    final list = raw == null ? <dynamic>[] : jsonDecode(raw) as List;
    list.insert(
      0,
      CoinEntry(at: at, source: source, amount: amount, note: note).toJson(),
    );
    if (list.length > CoinConfig.ledgerMaxEntries) {
      list.removeRange(CoinConfig.ledgerMaxEntries, list.length);
    }
    await prefs.setString(PrefsKeys.coinLedger, jsonEncode(list));

    notifier.value = next;
  }
}
