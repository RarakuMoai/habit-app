// 桌遊計時器（遊戲模式）資料模型。
//
// clean-room 重建：與已移除的舊版無任何資料相容關係。
// 唯一持久化的物件是 [TableTimerConfig]（整包 JSON 存
// PrefsKeys.gameTableConfig）；對局進行中的狀態（輪到誰、剩幾秒）
// 是一次性的，不落地——牌局中途殺 app 就重開一局，符合實體桌遊直覺。
import 'dart:convert';

/// 遊戲模式。
/// - [party]：多人桌遊輪流（2–6 人，整面點擊換下一位）。
/// - [chess]：二人棋鐘（上下分割，點自己那半換對方）。
/// - [free]：自由輪流（不倒數，只記錄輪到誰與想了多久）。
enum TableGameMode { party, chess, free }

extension TableGameModeLabel on TableGameMode {
  String get label => switch (this) {
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

  final TableGameMode mode;
  final List<TablePlayer> players;

  /// 每回合秒數（free 模式忽略、只正數計時）。
  final int turnSeconds;

  /// 剩幾秒開始「明顯提醒」（琥珀警示）。加強提醒固定取
  /// min(5, warnSeconds) 秒，不另設一個欄位。
  final int warnSeconds;

  /// 超時後自動換下一位；false = 進入超時狀態等人點。
  final bool autoAdvance;

  const TableTimerConfig({
    required this.mode,
    required this.players,
    required this.turnSeconds,
    required this.warnSeconds,
    required this.autoAdvance,
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

  /// 本局實際上場的玩家：棋鐘固定取前兩位，其他模式全上。
  List<TablePlayer> get activePlayers =>
      mode == TableGameMode.chess ? players.take(2).toList() : players;

  TableTimerConfig copyWith({
    TableGameMode? mode,
    List<TablePlayer>? players,
    int? turnSeconds,
    int? warnSeconds,
    bool? autoAdvance,
  }) => TableTimerConfig(
    mode: mode ?? this.mode,
    players: players ?? this.players,
    turnSeconds: turnSeconds ?? this.turnSeconds,
    warnSeconds: warnSeconds ?? this.warnSeconds,
    autoAdvance: autoAdvance ?? this.autoAdvance,
  );

  String encode() => jsonEncode({
    'v': 1,
    'mode': mode.name,
    'players': [
      for (final p in players) p.toJson(),
    ],
    'turnSeconds': turnSeconds,
    'warnSeconds': warnSeconds,
    'autoAdvance': autoAdvance,
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
      return TableTimerConfig(
        mode: mode,
        players: players.take(maxPlayers).toList(),
        turnSeconds: (turn is int ? turn : 60).clamp(
          minTurnSeconds,
          maxTurnSeconds,
        ),
        warnSeconds: (warn is int ? warn : 10).clamp(3, 60),
        autoAdvance: map['autoAdvance'] == true,
      );
    } catch (_) {
      return TableTimerConfig.fallback();
    }
  }
}

/// 每位玩家的本局統計（結算頁鋪路；引擎順手累計，MVP 不展示）。
class TurnStats {
  int turns = 0;
  Duration totalThink = Duration.zero;
}
