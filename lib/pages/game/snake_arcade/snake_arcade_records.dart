// 菜園小蛇的本機排行榜與署名資料。
//
// 完全本機、無網路。單一版本化 JSON 存在 PrefsKeys.snakeArcadeData；
// version 欄位留給未來 schema 演進，讀到未知版本就整包重來（彩蛋成績
// 不做向前相容的複雜遷移）。
//
// 排行榜規則（設計解讀定案）：
// - 今日／本週（週一起算）／歷史三榜，各取前 10 顯示。
// - 同分先達成者在前。
// - 署名隨成績固定保存；之後改 app 暱稱不影響舊成績。
// - 修剪：保留歷史前 50 名，加上最近 8 天內的成績（照顧今日/本週榜），
//   兩者聯集，避免家庭裝置無限累積。

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../../utils/prefs_keys.dart';

class SnakeArcadeScore {
  final String name;
  final int score;
  final int carrots;
  final int maxLength;
  final DateTime time;

  const SnakeArcadeScore({
    required this.name,
    required this.score,
    required this.carrots,
    required this.maxLength,
    required this.time,
  });

  Map<String, Object> toJson() => {
    'n': name,
    's': score,
    'c': carrots,
    'l': maxLength,
    't': time.millisecondsSinceEpoch,
  };

  static SnakeArcadeScore? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final name = raw['n'];
    final score = raw['s'];
    final carrots = raw['c'];
    final maxLength = raw['l'];
    final time = raw['t'];
    if (name is! String ||
        score is! int ||
        carrots is! int ||
        maxLength is! int ||
        time is! int) {
      return null;
    }
    return SnakeArcadeScore(
      name: name,
      score: score,
      carrots: carrots,
      maxLength: maxLength,
      time: DateTime.fromMillisecondsSinceEpoch(time),
    );
  }
}

enum SnakeArcadeBoard { today, week, allTime }

class SnakeArcadeRecords {
  static const int schemaVersion = 1;
  static const int boardSize = 10;
  static const int keepAllTime = 50;
  static const int keepRecentDays = 8;
  static const int maxRecentNames = 6;

  final List<SnakeArcadeScore> _entries;
  String lastPlayerName;
  final List<String> _recentNames;

  SnakeArcadeRecords._(this._entries, this.lastPlayerName, this._recentNames);

  SnakeArcadeRecords.empty() : this._([], '', []);

  List<SnakeArcadeScore> get entries => List.unmodifiable(_entries);
  List<String> get recentNames => List.unmodifiable(_recentNames);

  // ── 讀寫 ───────────────────────────────────────────────

  static SnakeArcadeRecords load(SharedPreferences prefs) {
    final raw = prefs.getString(PrefsKeys.snakeArcadeData);
    if (raw == null) return SnakeArcadeRecords.empty();
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map || decoded['version'] != schemaVersion) {
        return SnakeArcadeRecords.empty();
      }
      final entries = <SnakeArcadeScore>[];
      final rawEntries = decoded['entries'];
      if (rawEntries is List) {
        for (final item in rawEntries) {
          final entry = SnakeArcadeScore.fromJson(item);
          if (entry != null) entries.add(entry);
        }
      }
      final lastName = decoded['lastName'];
      final recent = decoded['recent'];
      return SnakeArcadeRecords._(
        entries,
        lastName is String ? lastName : '',
        recent is List ? recent.whereType<String>().toList() : [],
      );
    } on FormatException {
      return SnakeArcadeRecords.empty();
    }
  }

  Future<void> save(SharedPreferences prefs) async {
    await prefs.setString(
      PrefsKeys.snakeArcadeData,
      jsonEncode({
        'version': schemaVersion,
        'entries': [for (final e in _entries) e.toJson()], // units-ok
        'lastName': lastPlayerName,
        'recent': _recentNames,
      }),
    );
  }

  // ── 榜單 ───────────────────────────────────────────────

  /// 指定榜的顯示名單：分數高在前，同分先達成者在前。
  List<SnakeArcadeScore> board(SnakeArcadeBoard kind, DateTime now) {
    final filtered = _entries.where((e) => _inBoard(e, kind, now)).toList()
      ..sort(_compare);
    return filtered.take(boardSize).toList();
  }

  static int _compare(SnakeArcadeScore a, SnakeArcadeScore b) {
    if (a.score != b.score) return b.score.compareTo(a.score);
    return a.time.compareTo(b.time);
  }

  static bool _inBoard(
    SnakeArcadeScore e,
    SnakeArcadeBoard kind,
    DateTime now,
  ) {
    switch (kind) {
      case SnakeArcadeBoard.today:
        return e.time.year == now.year &&
            e.time.month == now.month &&
            e.time.day == now.day;
      case SnakeArcadeBoard.week:
        return !e.time.isBefore(weekStart(now));
      case SnakeArcadeBoard.allTime:
        return true;
    }
  }

  /// 本週起點：週一 00:00（台灣家庭慣例）。
  static DateTime weekStart(DateTime now) {
    final day = DateTime(now.year, now.month, now.day);
    return day.subtract(Duration(days: day.weekday - DateTime.monday));
  }

  /// 這個分數是否進得了任何一榜的前 10。同分不擠掉先達成者。
  bool qualifies(int score, DateTime now) {
    if (score <= 0) return false;
    for (final kind in SnakeArcadeBoard.values) {
      final list = board(kind, now);
      if (list.length < boardSize) return true;
      if (score > list.last.score) return true;
    }
    return false;
  }

  /// 登錄一筆成績並更新署名記憶；呼叫端負責 save()。
  SnakeArcadeScore addEntry({
    required String name,
    required int score,
    required int carrots,
    required int maxLength,
    required DateTime now,
  }) {
    final trimmed = name.trim().isEmpty ? '玩家' : name.trim();
    final entry = SnakeArcadeScore(
      name: trimmed,
      score: score,
      carrots: carrots,
      maxLength: maxLength,
      time: now,
    );
    _entries.add(entry);
    lastPlayerName = trimmed;
    _recentNames
      ..remove(trimmed)
      ..insert(0, trimmed);
    if (_recentNames.length > maxRecentNames) {
      _recentNames.removeRange(maxRecentNames, _recentNames.length);
    }
    _prune(now);
    return entry;
  }

  void _prune(DateTime now) {
    if (_entries.length <= keepAllTime) return;
    final ranked = List<SnakeArcadeScore>.from(_entries)..sort(_compare);
    final keep = ranked.take(keepAllTime).toSet();
    final recentCutoff = now.subtract(const Duration(days: keepRecentDays));
    for (final entry in _entries) {
      if (entry.time.isAfter(recentCutoff)) keep.add(entry);
    }
    _entries
      ..removeWhere((e) => !keep.contains(e))
      ..sort((a, b) => a.time.compareTo(b.time));
  }
}
