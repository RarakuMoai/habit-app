// 「遊戲」計時入口卡：遊戲桌的準備畫面與底部設定選單。
//
// 狀態定位（2026-07 UX 改版）：
// - 預設＝與專注／運動／節拍器一致的準備畫面：看設定、一鍵開局。
// - 點右上「設定」後，從下方展開與其他計時工具一致的完整設定選單。
// - 完整遊玩體驗在 push 進去的全螢幕桌面模式（TableStagePage）。
// - 不開對局也能「只骰骰子」：直達兔咪骰子屋（DiceTrayPage）。
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../utils/app_feedback.dart';
import '../../utils/app_style.dart';
import '../../utils/sfx_service.dart';
import '../../widgets/timer_mode_frame.dart';
import 'game/dice_tray.dart';
import 'game/table_setup_panel.dart';
import 'game/table_stage_page.dart';
import 'game/table_store.dart';
import 'game/table_timer_models.dart';
import 'game/table_timer_theme.dart';

export 'game/table_timer_theme.dart' show kGameAccent;

class GameTimer extends StatefulWidget {
  const GameTimer({super.key});

  @override
  State<GameTimer> createState() => _GameTimerState();
}

class _GameTimerState extends State<GameTimer> {
  SharedPreferences? _prefs;
  TableTimerConfig _config = TableTimerConfig.fallback();

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((p) {
      if (!mounted) return;
      setState(() {
        _prefs = p;
        _config = TableStore.loadConfig(p);
      });
    });
  }

  Future<void> _startGame() async {
    if (_prefs == null) return;
    playFeedback(SfxCue.success, haptic: HapticLevel.medium);
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => TableStagePage(config: _config),
      ),
    );
  }

  /// 不開對局、只想骰骰子：直達兔咪骰子屋。
  Future<void> _openDice() async {
    playFeedback(SfxCue.tap, haptic: HapticLevel.selection);
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => const DiceTrayPage(),
      ),
    );
  }

  /// 準備畫面上的快速調整（玩法切換、人數增減）共用：即改即存。
  void _applyConfig(TableTimerConfig next) {
    final prefs = _prefs;
    if (prefs == null) return;
    setState(() => _config = next);
    TableStore.saveConfig(prefs, next);
  }

  /// 快速切玩法：只動 mode，人數與時間設定保留（倒數提醒夾回合法範圍）。
  void _selectMode(TableGameMode mode) {
    if (mode == _config.mode) return;
    playFeedback(SfxCue.tap, haptic: HapticLevel.selection);
    _applyConfig(_config.copyWith(mode: mode).clampWarn());
  }

  /// 快速調人數：補到 n 位（預設名＋未用座位色）或從尾端收到 n 位。
  /// 與設定面板的加人邏輯同一套，只是批次版。
  void _setPlayerCount(int n) {
    final players = List.of(_config.players);
    while (players.length > n && players.length > TableTimerConfig.minPlayers) {
      players.removeLast();
    }
    while (players.length < n && players.length < TableTimerConfig.maxPlayers) {
      final used = {for (final p in players) p.colorIndex};
      var color = players.length % TableTheme.seatColors.length;
      for (var i = 0; i < TableTheme.seatColors.length; i++) {
        if (!used.contains(i)) {
          color = i;
          break;
        }
      }
      players.add(
        TablePlayer(name: '玩家 ${players.length + 1}', colorIndex: color),
      );
    }
    playFeedback(SfxCue.tap, haptic: HapticLevel.selection);
    _applyConfig(_config.copyWith(players: players));
  }

  /// 「玩家」快調選單：今天幾位上桌，點了即改即存。
  /// 名字與顏色的細部調整仍在右上「設定」裡。
  Future<void> _openPlayerCountSheet() async {
    playFeedback(SfxCue.tap);
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: kGameAccent.withValues(alpha: 0.18),
                blurRadius: 24,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFE8DDD4),
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                '今天幾位上桌？',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                  color: AppInk.strong,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                '名字與顏色可到右上「設定」細調',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: AppInk.soft,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (
                    var n = TableTimerConfig.minPlayers;
                    n <= TableTimerConfig.maxPlayers;
                    n++
                  ) ...[
                    if (n > TableTimerConfig.minPlayers)
                      const SizedBox(width: 10),
                    _playerCountButton(n, sheetContext),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _playerCountButton(int n, BuildContext sheetContext) {
    final selected = _config.players.length == n;
    return Material(
      color: selected ? kGameAccent : Colors.white,
      shape: CircleBorder(
        side: selected
            ? BorderSide.none
            : BorderSide(color: kGameAccent.withValues(alpha: 0.28)),
      ),
      elevation: selected ? 2 : 0,
      shadowColor: kGameAccent.withValues(alpha: 0.3),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: () {
          _setPlayerCount(n);
          Navigator.pop(sheetContext);
        },
        child: SizedBox.square(
          dimension: 46,
          child: Center(
            child: Text(
              '$n',
              style: AppType.digits(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: selected ? Colors.white : kGameAccentDark,
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 從下方展開完整設定；一般調整即時儲存，關閉後由準備畫面顯示新摘要。
  Future<void> _openSettingsSheet() async {
    final prefs = _prefs;
    if (prefs == null) return;
    playFeedback(SfxCue.tap);
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.86,
          ),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: kGameAccent.withValues(alpha: 0.18),
                  blurRadius: 24,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                // 把手列＋右上關閉：關閉鈕固定在整張面板的右上角，
                // 與其他三份設定「右上角關閉」同一個視覺位置。
                SizedBox(
                  height: 44,
                  child: Stack(
                    alignment: Alignment.topCenter,
                    children: [
                      Positioned(
                        top: 10,
                        child: Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: const Color(0xFFE8DDD4),
                            borderRadius: BorderRadius.circular(99),
                          ),
                        ),
                      ),
                      Positioned(
                        top: 0,
                        right: 6,
                        child: IconButton(
                          tooltip: '關閉',
                          icon: const Icon(
                            Icons.close_rounded,
                            color: AppInk.iconFaint,
                          ),
                          onPressed: () => Navigator.pop(sheetContext),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: TableSetupPanel(
                    prefs: prefs,
                    onConfigChanged: (c) {
                      if (mounted) setState(() => _config = c);
                    },
                  ),
                ),
                Container(
                  padding: const EdgeInsets.fromLTRB(20, 10, 20, 18),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    border: Border(top: BorderSide(color: AppSurfaces.divider)),
                  ),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: kGameAccent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      onPressed: () {
                        playFeedback(SfxCue.tap, haptic: HapticLevel.selection);
                        Navigator.pop(sheetContext);
                      },
                      icon: const Icon(Icons.check_rounded, size: 19),
                      label: const Text(
                        '完成',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String get _oneLineSummary =>
      '${_config.mode.label} · ${_config.activePlayers.length} 人 · '
      '${_config.timeSummary}';

  @override
  Widget build(BuildContext context) {
    return _buildReady();
  }

  // ── 共用準備畫面 ─────────────────────────────────────────

  Widget _buildReady() {
    return TimerModeFrame(
      heroBuilder: (context, size) => _tableHero(size),
      status: const TimerStatusPill(
        stateKey: 'ready',
        color: kGameAccent,
        icon: Icons.groups_rounded,
        label: '準備開局',
      ),
      // 玩家色點已內建在圓桌座位上，這裡不再重複一排（槽位留白保持
      // 四模式垂直節奏一致）。
      progress: const SizedBox.shrink(),
      controls: TimerControlCluster(
        accent: kGameAccent,
        primaryIcon: Icons.play_arrow_rounded,
        onPrimary: _prefs == null ? null : _startGame,
        // 左「玩家」是真快調（彈人數選單即改即存，不進設定）；
        // 右「骰子」是不開局也常用的工具。棋鐘固定 2 位上場，人數鈕停用。
        leading: TimerSecondaryAction(
          icon: Icons.groups_rounded,
          label: '玩家',
          onTap: _prefs == null || _config.mode == TableGameMode.chess
              ? null
              : _openPlayerCountSheet,
        ),
        trailing: TimerSecondaryAction(
          icon: Icons.casino_rounded,
          label: '骰子',
          onTap: _openDice,
        ),
      ),
      statusLine: Text(
        _oneLineSummary,
        style: const TextStyle(
          color: AppInk.soft,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
      quickPicker: _configBar(),
      topAction: TimerSettingsAction(
        color: kGameAccent,
        onTap: _prefs == null ? null : _openSettingsSheet,
      ),
    );
  }

  Widget _tableHero(double size) {
    // 專屬「圓桌俯視」盤面：外徑與專注／運動的圓環同一套光學幾何，
    // 但畫的是遊戲桌本體——暖奶油桌面＋鼠尾草桌沿，座位色點沿桌沿
    // 均分、即時反映本局玩家數與顏色。
    return SizedBox.square(
      dimension: size,
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: kGameAccent.withValues(alpha: 0.16),
              blurRadius: 24,
              spreadRadius: 2,
            ),
          ],
        ),
        child: CustomPaint(
          painter: _TableTopPainter(
            seats: [
              for (final p in _config.activePlayers)
                TableTheme.seatColor(p.colorIndex),
            ],
          ),
          child: Padding(
            padding: EdgeInsets.all(size * 0.2),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 玩法圖示直接放在桌面上（不加圓底——圓底＋輪轉箭頭
                  // 會有「載入中」的既視感）。
                  Icon(
                    _modeIcon(_config.mode),
                    size: 30,
                    color: kGameAccent.withValues(alpha: 0.75),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    '遊戲桌',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: AppInk.strong,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${_config.activePlayers.length} 位玩家',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: kGameAccentDark,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // 下方快速切換：三種玩法即點即換（其他設定保留），與專注方案／
  // 運動類別的「膠囊快切」同構；人數與時間細節在 statusLine 與設定內。
  Widget _configBar() {
    return SizedBox(
      height: 52,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (final mode in TableGameMode.values) ...[
                  if (mode != TableGameMode.values.first)
                    const SizedBox(width: 8),
                  _modeChip(mode),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _modeChip(TableGameMode mode) {
    final selected = _config.mode == mode;
    return GestureDetector(
      onTap: _prefs == null ? null : () => _selectMode(mode),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        constraints: const BoxConstraints(minWidth: 76),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? kGameAccent : Colors.white.withValues(alpha: 0.86),
          borderRadius: BorderRadius.circular(16),
          border: selected ? null : AppCardStyle.hairline,
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: kGameAccent.withValues(alpha: 0.24),
                    blurRadius: 13,
                    offset: const Offset(0, 5),
                  ),
                ]
              : AppShadows.flat,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _modeIcon(mode),
              size: 16,
              color: selected ? Colors.white : kGameAccent,
            ),
            const SizedBox(height: 1),
            Text(
              mode.label,
              maxLines: 1,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
                color: selected ? Colors.white : AppInk.strong,
              ),
            ),
          ],
        ),
      ),
    );
  }

  static IconData _modeIcon(TableGameMode mode) => switch (mode) {
    TableGameMode.party => Icons.rotate_right_rounded,
    TableGameMode.chess => Icons.grid_view_rounded,
    TableGameMode.free => Icons.all_inclusive_rounded,
  };
}

/// 圓桌俯視盤面：暖奶油桌面＋鼠尾草桌沿＋沿桌沿均分的玩家座位色點。
/// 外徑幾何刻意與 TimerRingPainter 一致（stroke = max(8, 4.8%)、
/// 外緣內縮 stroke×0.8），四個模式的主視覺光學大小才會相同。
class _TableTopPainter extends CustomPainter {
  final List<Color> seats;

  const _TableTopPainter({required this.seats});

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final shortest = math.min(size.width, size.height);
    final stroke = math.max(8.0, shortest * 0.048);
    final rimRadius = shortest / 2 - stroke * 0.8;

    // 1) 桌面：中心受光的奶油紙面，收到鼠尾草桌邊（沿用對局面配色）。
    final feltRect = Rect.fromCircle(center: center, radius: rimRadius);
    canvas.drawCircle(
      center,
      rimRadius,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.34, -0.42),
          radius: 1.05,
          colors: [
            Colors.white.withValues(alpha: 0.97),
            TableTheme.feltCenter,
            TableTheme.feltEdge,
          ],
          stops: const [0.0, 0.45, 1.0],
        ).createShader(feltRect),
    );

    // 2) 桌面高光（與圓環內盤同一個光源方向）。
    canvas.drawOval(
      Rect.fromCenter(
        center: center + Offset(-rimRadius * 0.34, -rimRadius * 0.30),
        width: rimRadius * 0.42,
        height: rimRadius * 0.20,
      ),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.55)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
    );

    // 3) 桌沿：單層鼠尾草環（雙層細邊會有「雙框」感），
    //    視覺重量對齊進度環的軌道。
    canvas.drawCircle(
      center,
      rimRadius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = kGameAccent.withValues(alpha: 0.20),
    );

    // 4) 座位色點：從頂位開始沿桌沿均分；白墊圈讓色點浮在桌沿上，
    //    畫法與進度環的弧端旋鈕同語彙。
    for (var i = 0; i < seats.length; i++) {
      final a = -math.pi / 2 + i * 2 * math.pi / seats.length;
      final pos =
          center + Offset(math.cos(a) * rimRadius, math.sin(a) * rimRadius);
      canvas.drawCircle(
        pos,
        stroke * 0.78,
        Paint()
          ..color = kGameAccent.withValues(alpha: 0.22)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
      );
      canvas.drawCircle(pos, stroke * 0.66, Paint()..color = Colors.white);
      canvas.drawCircle(pos, stroke * 0.46, Paint()..color = seats[i]);
    }
  }

  @override
  bool shouldRepaint(_TableTopPainter old) => !listEquals(old.seats, seats);
}
