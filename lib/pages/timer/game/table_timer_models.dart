// 桌遊計時器（遊戲模式）資料模型。
//
// clean-room 重建：與已移除的舊版無任何資料相容關係。
// 唯一持久化的物件是 [TableTimerConfig]（整包 JSON 存
// PrefsKeys.gameTableConfig）；對局進行中的狀態（輪到誰、剩幾秒）
// 是一次性的，不落地——牌局中途殺 app 就重開一局，符合實體桌遊直覺。
import 'dart:convert';

import '../../../l10n/app_localizations.dart';

/// 遊戲模式。
/// - [party]：多人桌遊輪流（2–6 人，整面點擊換下一位）。
/// - [chess]：二人棋鐘（上下分割，點自己那半換對方）。
/// - [free]：自由輪流（不倒數，只記錄輪到誰與想了多久）。
enum TableGameMode { party, chess, free }

extension TableGameModeLabel on TableGameMode {
  /// 玩法全名（i18n）。
  String labelOf(AppLocalizations l10n) => switch (this) {
    TableGameMode.party => l10n.tableModePartyFull,
    TableGameMode.chess => l10n.tableModeChessFull,
    TableGameMode.free => l10n.tableModeFreeFull,
  };

  /// 玩法短名（切換膠囊、常用組合預設名共用）。
  String shortLabelOf(AppLocalizations l10n) => switch (this) {
    TableGameMode.party => l10n.tableModePartyShort,
    TableGameMode.chess => l10n.tableModeChessShort,
    TableGameMode.free => l10n.tableModeFreeShort,
  };

  // 舊版自動命名比對用的繁中全名（_legacyDefaultName），不做顯示。
  String get _legacyZhLabel => switch (this) {
    TableGameMode.party => '多人桌遊',
    TableGameMode.chess => '二人棋鐘',
    TableGameMode.free => '自由輪流',
  };
}

/// 一位本局玩家。色彩不存色值，存「座位色 index」（0–5），
/// 由 TableTheme.seatColor(index) 對應到固定色盤——色盤日後調整
/// 時舊設定自動跟上。
class TablePlayer {
  final String name;
  final int colorIndex;

  const TablePlayer({required this.name, required this.colorIndex});

  TablePlayer copyWith({String? name, int? colorIndex}) => TablePlayer(
    name: name ?? this.name,
    colorIndex: colorIndex ?? this.colorIndex,
  );

  Map<String, Object?> toJson() => {'name': name, 'color': colorIndex};

  static TablePlayer? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final name = raw['name'];
    final color = raw['color'];
    if (name is! String || name.isEmpty) return null;
    return TablePlayer(
      name: name,
      colorIndex: (color is int ? color : 0).clamp(0, 5),
    );
  }
}

/// 桌遊計時器設定（唯一持久化物件）。
class TableTimerConfig {
  static const int minPlayers = 2;
  static const int maxPlayers = 6;
  static const int minTurnSeconds = 10;
  static const int maxTurnSeconds = 30 * 60;
  static const int minBankSeconds = 30;
  static const int maxBankSeconds = 60 * 60;
  static const int maxIncrementSeconds = 60;
  static const int minWarnSeconds = 3;
  static const int maxWarnSeconds = 60;

  final TableGameMode mode;
  final List<TablePlayer> players;

  /// 每回合秒數（free 模式忽略、只正數計時）。
  final int turnSeconds;

  /// 剩幾秒開始「明顯提醒」（琥珀警示）。加強提醒固定取
  /// min(5, warnSeconds) 秒，不另設一個欄位。
  final int warnSeconds;

  /// 超時後自動換下一位；false = 進入超時狀態等人點。
  /// （棋鐘總時間制不適用：時間用盡＝旗倒終局。）
  final bool autoAdvance;

  /// 二人棋鐘的計時制：false = 每回合制（沿用 turnSeconds）、
  /// true = 總時間制（每人一個時間庫 [bankSeconds]，可 Fischer 加秒）。
  final bool chessUseBank;

  /// 總時間制：每人總時間。
  final int bankSeconds;

  /// 總時間制：走完一手加回幾秒（Fischer；0 = 不加）。
  final int incrementSeconds;

  const TableTimerConfig({
    required this.mode,
    required this.players,
    required this.turnSeconds,
    required this.warnSeconds,
    required this.autoAdvance,
    this.chessUseBank = false,
    this.bankSeconds = 300,
    this.incrementSeconds = 0,
  });

  /// 出廠預設：多人 4 人、每回合 60 秒、剩 10 秒警示、手動換人。
  factory TableTimerConfig.fallback() => TableTimerConfig(
    mode: TableGameMode.party,
    players: [
      for (var i = 0; i < 4; i++)
        TablePlayer(name: '玩家 ${i + 1}', colorIndex: i),
    ],
    turnSeconds: 60,
    warnSeconds: 10,
    autoAdvance: false,
  );

  /// 加強提醒門檻（每秒脈動）。
  int get criticalSeconds => warnSeconds < 5 ? warnSeconds : 5;

  /// 倒數提醒的合法上限：必須嚴格小於每回合時間（總時間制看每人總時間），
  /// 且不超過 [maxWarnSeconds]。
  int get warnCap {
    final base = (usesBank ? bankSeconds : turnSeconds) - 1;
    final cap = base < maxWarnSeconds ? base : maxWarnSeconds;
    return cap < minWarnSeconds ? minWarnSeconds : cap;
  }

  /// 把倒數提醒夾回合法範圍（每回合時間變短時維持 warn < turn 不變量）。
  TableTimerConfig clampWarn() =>
      warnSeconds > warnCap ? copyWith(warnSeconds: warnCap) : this;

  /// 本局實際上場的玩家：棋鐘固定取前兩位，其他模式全上。
  List<TablePlayer> get activePlayers =>
      mode == TableGameMode.chess ? players.take(2).toList() : players;

  /// 是否走棋鐘總時間制（時間庫）。
  bool get usesBank => mode == TableGameMode.chess && chessUseBank;

  /// 時間設定的一句話摘要（入口卡、常用組合副標共用，i18n）。
  String timeSummaryOf(AppLocalizations l10n) {
    if (mode == TableGameMode.free) return l10n.tableTimeFree;
    if (usesBank) {
      final bank = formatDuration(l10n, bankSeconds);
      return incrementSeconds > 0
          ? l10n.tableTimeBankInc(bank, incrementSeconds)
          : l10n.tableTimeBank(bank);
    }
    return l10n.tableTimePerTurn(formatDuration(l10n, turnSeconds));
  }

  /// 秒數 → 「N 秒／N 分／N 分 M 秒」（i18n；設定面板也用）。
  static String formatDuration(AppLocalizations l10n, int s) {
    if (s < 60) return l10n.durSeconds(s);
    final m = s ~/ 60;
    final r = s % 60;
    return r == 0 ? l10n.durMinutes(m) : l10n.durMinSec(m, r);
  }

  // 舊版自動命名比對用（_legacyDefaultName），維持當年的繁中輸出。
  String get _legacyZhTimeSummary {
    if (mode == TableGameMode.free) return '自由計時';
    if (usesBank) {
      final bank = _legacyZhFmtSeconds(bankSeconds);
      return incrementSeconds > 0
          ? '每人 $bank ＋$incrementSeconds 秒'
          : '每人 $bank';
    }
    return '每回合 ${_legacyZhFmtSeconds(turnSeconds)}';
  }

  static String _legacyZhFmtSeconds(int s) {
    if (s < 60) return '$s 秒';
    final m = s ~/ 60;
    final r = s % 60;
    return r == 0 ? '$m 分' : '$m 分 $r 秒';
  }

  TableTimerConfig copyWith({
    TableGameMode? mode,
    List<TablePlayer>? players,
    int? turnSeconds,
    int? warnSeconds,
    bool? autoAdvance,
    bool? chessUseBank,
    int? bankSeconds,
    int? incrementSeconds,
  }) => TableTimerConfig(
    mode: mode ?? this.mode,
    players: players ?? this.players,
    turnSeconds: turnSeconds ?? this.turnSeconds,
    warnSeconds: warnSeconds ?? this.warnSeconds,
    autoAdvance: autoAdvance ?? this.autoAdvance,
    chessUseBank: chessUseBank ?? this.chessUseBank,
    bankSeconds: bankSeconds ?? this.bankSeconds,
    incrementSeconds: incrementSeconds ?? this.incrementSeconds,
  );

  String encode() => jsonEncode({
    'v': 1,
    'mode': mode.name,
    'players': [for (final p in players) p.toJson()], // units-ok
    'turnSeconds': turnSeconds,
    'warnSeconds': warnSeconds,
    'autoAdvance': autoAdvance,
    'chessUseBank': chessUseBank,
    'bankSeconds': bankSeconds,
    'incrementSeconds': incrementSeconds,
  });

  /// 解析失敗（壞 JSON、玩家不足）一律回 fallback，不讓入口卡開天窗。
  static TableTimerConfig decode(String? raw) {
    if (raw == null || raw.isEmpty) return TableTimerConfig.fallback();
    try {
      final map = jsonDecode(raw);
      if (map is! Map) return TableTimerConfig.fallback();
      final mode = TableGameMode.values.asNameMap()[map['mode']];
      final rawPlayers = map['players'];
      final players = <TablePlayer>[
        if (rawPlayers is List)
          for (final e in rawPlayers) ?TablePlayer.fromJson(e),
      ];
      if (mode == null || players.length < minPlayers) {
        return TableTimerConfig.fallback();
      }
      final turn = map['turnSeconds'];
      final warn = map['warnSeconds'];
      final bank = map['bankSeconds'];
      final inc = map['incrementSeconds'];
      // 舊版 JSON 沒有棋鐘總時間制欄位 → 預設每回合制，向後相容
      return TableTimerConfig(
        mode: mode,
        players: players.take(maxPlayers).toList(),
        turnSeconds: (turn is int ? turn : 60).clamp(
          minTurnSeconds,
          maxTurnSeconds,
        ),
        warnSeconds: (warn is int ? warn : 10).clamp(
          minWarnSeconds,
          maxWarnSeconds,
        ),
        autoAdvance: map['autoAdvance'] == true,
        chessUseBank: map['chessUseBank'] == true,
        bankSeconds: (bank is int ? bank : 300).clamp(
          minBankSeconds,
          maxBankSeconds,
        ),
        incrementSeconds: (inc is int ? inc : 0).clamp(0, maxIncrementSeconds),
      ).clampWarn();
    } catch (_) {
      return TableTimerConfig.fallback();
    }
  }
}

/// 每位玩家的本局統計（結算面資料來源；引擎在每次換人時結算）。
class TurnStats {
  int turns = 0;
  Duration totalThink = Duration.zero;

  Duration get averageThink => turns == 0 ? Duration.zero : totalThink ~/ turns;
}

/// 常用組合：一份帶名字的設定快照，入口卡一鍵帶入。
class TablePreset {
  static const int maxCount = 6;

  final String name;
  final TableTimerConfig config;

  const TablePreset({required this.name, required this.config});

  /// 名稱只負責辨識玩法；人數與時間由 UI 的系統摘要顯示，避免重複。
  /// 是「儲存值的種子」：只在建立常用組合時取一次，存過的名字照原樣顯示。
  static String defaultName(AppLocalizations l10n, TableTimerConfig c) =>
      c.mode.shortLabelOf(l10n);

  // 舊版存檔用當年的繁中自動命名，比對時維持原字串（勿改）。
  static String _legacyDefaultName(TableTimerConfig c) =>
      '${c.mode._legacyZhLabel} ${c.activePlayers.length} 人 · '
      '${c._legacyZhTimeSummary}';

  static String encodeList(List<TablePreset> presets) => jsonEncode({
    'v': 1,
    'items': [
      for (final p in presets)
        {'name': p.name, 'config': p.config.encode()}, // units-ok
    ],
  });

  /// 壞資料整包回空清單；個別壞項目跳過。
  static List<TablePreset> decodeList(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    try {
      final map = jsonDecode(raw);
      if (map is! Map) return const [];
      final items = map['items'];
      if (items is! List) return const [];
      return [
        for (final e in items)
          if (e is Map<Object?, Object?> &&
              e['name'] is String &&
              e['config'] is String)
            _decodePreset(e),
      ].take(maxCount).toList();
    } catch (_) {
      return const [];
    }
  }

  static TablePreset _decodePreset(Map<Object?, Object?> e) {
    final config = TableTimerConfig.decode(e['config'] as String);
    final savedName = e['name'] as String;
    // 偵測到舊版自動名就轉成當年繁中短名（decode 無 context 可用 l10n；
    // 這是一次性資料遷移，維持繁中與舊資料一致）。
    const legacyShortNames = {
      TableGameMode.party: '多人',
      TableGameMode.chess: '二人',
      TableGameMode.free: '自由',
    };
    return TablePreset(
      name: savedName == _legacyDefaultName(config)
          ? legacyShortNames[config.mode]!
          : savedName,
      config: config,
    );
  }
}
