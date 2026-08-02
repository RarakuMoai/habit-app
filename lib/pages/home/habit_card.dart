import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../utils/app_style.dart';
import '../../utils/weight_records.dart';
import '../../widgets/habit_ui.dart';
import 'completion_timing.dart';

// 長按進排序的延遲。每週卡「按住綠波紋」的填滿時間與它對齊：波紋填滿整框那
// 一刻剛好進拖曳模式（home_page 的 _HabitDragListener 也用這個常數當 delay）。
const Duration kHabitDragHoldDelay = Duration(seconds: 1);

// 按住要超過這個門檻才開始長出波紋；比這短的純單點完全不出特效。
const Duration _kHoldFillStartDelay = Duration(milliseconds: 130);

/// 勾勾描完的時間＝主衝擊點。**唯一真相在 `completion_timing.dart`**：
/// 觸覺與音效必須落在筆尖抵達的那一刻，兩邊不能各寫一個數字。
const Duration kHabitCheckDrawDuration = kCheckDrawDuration;

/// Reduce Motion：仍然把勾畫出來（語意不能只剩顏色變化），但不拖長。
const Duration kHabitCheckDrawDurationReduced = kCheckDrawDurationReduced;

/// 圓圈按壓回彈的長度；Reduce Motion 下完全不播。
const Duration kHabitCheckPressDuration = Duration(milliseconds: 340);
const Color _kWaterLinkedAccent = Color(0xFF42A5F5);
const Color _kWeightLinkedAccent = Color(0xFF7E57C2);

// ── 習慣卡片（含彈跳動畫）──

class HabitCard extends StatefulWidget {
  final Map<String, dynamic> habit;
  final VoidCallback onToggle;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final bool isWeekly;
  final int weeklyCount;
  final int weeklyTarget;
  final int todayCount;
  final VoidCallback? onDecrement;
  final bool isLinked;
  // 選單「移動」入口；是否處於編輯模式（停用點擊打卡）。
  // 長按拖曳由外層 _HabitDragListener 處理，卡片本身不再攔長按。
  final VoidCallback? onMove;
  final bool isMoving;

  const HabitCard({
    super.key,
    required this.habit,
    required this.onToggle,
    required this.onEdit,
    required this.onDelete,
    this.isWeekly = false,
    this.weeklyCount = 0,
    this.weeklyTarget = 3,
    this.todayCount = 0,
    this.onDecrement,
    this.isLinked = false,
    this.onMove,
    this.isMoving = false,
  });

  @override
  State<HabitCard> createState() => _HabitCardState();
}

class _HabitCardState extends State<HabitCard> with TickerProviderStateMixin {
  AppLocalizations get l10n => AppLocalizations.of(context);

  late AnimationController _ctrl;
  late Animation<double> _scale;
  // 勾勾描繪動畫：done 轉 true 時從 0 畫到 1
  late AnimationController _checkCtrl;
  late Animation<double> _checkAnim;
  late bool _wasDone;

  // 每週卡「按住蓄力」綠波紋：從觸點擴散、填滿即進排序（時間對齊 drag delay）。
  late AnimationController _holdCtrl;
  Offset? _holdOrigin;
  Timer? _holdStartTimer;

  @override
  void initState() {
    super.initState();
    // 門檻後才開始長，扣掉門檻時間讓波紋剛好在 kHabitDragHoldDelay 填滿。
    _holdCtrl = AnimationController(
      vsync: this,
      duration: kHabitDragHoldDelay - _kHoldFillStartDelay,
    );
    // 打卡圓圈：克制的按壓＋回彈。舊版 0.78→1.18 是 UI 等比彈跳的語彙，
    // 幅度大到會把注意力從勾勾本身搶走；改成「按下去有回應」的量級即可。
    _ctrl = AnimationController(
      vsync: this,
      duration: kHabitCheckPressDuration,
    );
    _scale = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.92), weight: 22),
      TweenSequenceItem(tween: Tween(begin: 0.92, end: 1.06), weight: 44),
      TweenSequenceItem(tween: Tween(begin: 1.06, end: 1.0), weight: 34),
    ]).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));

    // 勾勾描繪：筆尖落點就是整段演出的主衝擊，時間對齊
    // CompletionPresentationController.kImpactDelay。easeOutCubic 太前傾，
    // 會讓勾在 40ms 就幾乎畫完、觸覺與音效反而變成「後補」。
    //
    // animationBehavior 必須是 preserve：預設的 normal 在系統開啟
    // Disable Animations 時會把 duration 直接壓成 5%，勾在約 7ms 就描完，
    // 而衝擊點（觸覺＋音效）仍然照 140ms 的 Timer 走——兩邊脫拍。
    // Reduce Motion 該縮短多少由 [_syncCheckAnim] 決定（140ms，與編排器
    // 共用同一個常數），不交給 framework 再自作主張縮一次。
    _checkCtrl = AnimationController(
      vsync: this,
      duration: kHabitCheckDrawDuration,
      animationBehavior: AnimationBehavior.preserve,
    );
    _checkAnim = CurvedAnimation(
      parent: _checkCtrl,
      curve: Curves.easeInOutCubic,
    );
    // 列表載入時已完成的卡直接顯示完整勾，不重播描繪
    _wasDone = widget.habit['done'] == true;
    _checkCtrl.value = _wasDone ? 1.0 : 0.0;
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _checkCtrl.dispose();
    _holdStartTimer?.cancel();
    _holdCtrl.dispose();
    super.dispose();
  }

  // 按下：過門檻才開始長波紋（純單點更短 → 不觸發 → 無特效）。
  void _onHoldDown(Offset localPos) {
    _holdOrigin = localPos;
    _holdStartTimer?.cancel();
    _holdStartTimer = Timer(_kHoldFillStartDelay, () {
      if (mounted) _holdCtrl.forward(from: 0);
    });
  }

  // 放開 / 取消：未過門檻直接清掉（單點無痕）；已長出來就淡出收回。
  void _onHoldEnd() {
    _holdStartTimer?.cancel();
    if (_holdCtrl.value > 0) {
      _holdCtrl.reverse();
    } else {
      _holdCtrl.value = 0;
    }
  }

  @override
  void didUpdateWidget(HabitCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 波紋填滿那刻整個清單進抖動排序：清掉填色，免得被抬起的卡還蓋著綠。
    if (widget.isMoving && !oldWidget.isMoving) {
      _holdStartTimer?.cancel();
      _holdCtrl.value = 0;
    }
  }

  // 按住蓄力綠波紋的填色層（疊在卡片最上層、不吃手勢、被 ClipRRect 切圓角）。
  Widget _buildHoldFill() {
    return Positioned.fill(
      child: IgnorePointer(
        child: AnimatedBuilder(
          animation: _holdCtrl,
          builder: (_, _) {
            final t = _holdCtrl.value;
            if (t == 0) return const SizedBox.shrink();
            return CustomPaint(
              painter: _HoldFillPainter(progress: t, origin: _holdOrigin),
            );
          },
        ),
      ),
    );
  }

  /// 系統的 Reduce Motion／Disable Animations。取消位移類演出，但保留
  /// 「已完成」的所有語意（勾、顏色、狀態）。
  bool get _reduceMotion {
    final mq = MediaQuery.maybeOf(context);
    return mq?.disableAnimations == true || mq?.accessibleNavigation == true;
  }

  /// habit map 是同一個實例被原地修改，didUpdateWidget 比不出新舊值，
  /// 改在 build 時偵測 done 變化來觸發描繪動畫。
  void _syncCheckAnim(bool done) {
    if (done == _wasDone) return;
    _wasDone = done;
    if (done) {
      _checkCtrl.duration = _reduceMotion
          ? kHabitCheckDrawDurationReduced
          : kHabitCheckDrawDuration;
      _checkCtrl.forward(from: 0);
    } else {
      _checkCtrl.value = 0;
    }
  }

  void _handleTap() {
    // Reduce Motion：圓圈不彈跳（勾＋底色已經把「完成」講清楚了）。
    if (!_reduceMotion) _ctrl.forward(from: 0);
    widget.onToggle();
  }

  Color _linkedAccentFor(String name) =>
      isWeightHabitName(name) ? _kWeightLinkedAccent : _kWaterLinkedAccent;

  @override
  Widget build(BuildContext context) {
    if (widget.isWeekly) return _buildWeeklyCard();
    return _buildDailyCard();
  }

  Widget _buildDailyCard() {
    final done = widget.habit['done'] as bool;
    final name = widget.habit['name'] as String;
    final linkedAccent = _linkedAccentFor(name);
    final cardRadius = BorderRadius.circular(AppCardStyle.radius);
    _syncCheckAnim(done);

    // 完成卡「洩氣」壓縮（68→52）：把視覺重量讓給還沒做的事
    final minH = done ? 52.0 : 68.0;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      // VoiceOver：整張卡是打卡開關，念出名稱與完成狀態
      child: Semantics(
        button: true,
        toggled: done,
        label: l10n.hcHabitSemantics(
          name,
          done ? l10n.hcStateDone : l10n.hcStateNotDone,
        ),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          decoration: BoxDecoration(
            color: done ? const Color(0xFFF1F8E9) : Colors.white,
            borderRadius: cardRadius,
            border: done
                ? Border.all(color: Colors.green.withValues(alpha: 0.18))
                : AppCardStyle.hairline,
            boxShadow: done ? AppShadows.flat : AppShadows.card,
          ),
          child: Material(
            color: Colors.transparent,
            borderRadius: cardRadius,
            clipBehavior: Clip.antiAlias,
            child: ClipRRect(
              borderRadius: cardRadius,
              // 整張卡都可點擊打卡（不只左邊小圓圈），ripple 回饋
              child: InkWell(
                borderRadius: cardRadius,
                onTap: widget.isMoving ? null : _handleTap,
                splashColor: (done ? AppInk.faint : Colors.green).withValues(
                  alpha: 0.12,
                ),
                highlightColor: (done ? AppInk.faint : Colors.green).withValues(
                  alpha: 0.06,
                ),
                child: Stack(
                  children: [
                    AnimatedSize(
                      duration: const Duration(milliseconds: 340),
                      curve: Curves.easeOutCubic,
                      child: IntrinsicHeight(
                        child: ConstrainedBox(
                          constraints: BoxConstraints(minHeight: minH),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              // 內縮圓角色條：一般用橘；連動習慣用功能來源色。
                              // 完成狀態交給圓圈/底色表達，色條僅淡出讓位
                              Padding(
                                padding: EdgeInsets.fromLTRB(
                                  12,
                                  done ? 10 : 14,
                                  0,
                                  done ? 10 : 14,
                                ),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 300),
                                  width: 4,
                                  decoration: BoxDecoration(
                                    color:
                                        (widget.isLinked
                                                ? linkedAccent
                                                : Colors.orange.shade400)
                                            .withValues(
                                              alpha: done ? 0.30 : 1.0,
                                            ),
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                ),
                              ),
                              Expanded(
                                child: ListTile(
                                  // ListTile 對 leading 的置中是用「內部算出的內容高度」
                                  // （單行=56），不是被外層撐開後的實際高度（68），
                                  // 所以要用 minTileHeight 讓內外高度一致圓圈才會置中；
                                  // titleAlignment 再保證有副標（連動喝水）時也走同一規則
                                  minTileHeight: minH,
                                  titleAlignment: ListTileTitleAlignment.center,
                                  contentPadding: EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: done ? 0 : 2,
                                  ),
                                  leading: ScaleTransition(
                                    scale: _scale,
                                    child: AnimatedContainer(
                                      duration: const Duration(
                                        milliseconds: 250,
                                      ),
                                      width: done ? 28 : 34,
                                      height: done ? 28 : 34,
                                      decoration: BoxDecoration(
                                        gradient: done
                                            ? LinearGradient(
                                                colors: [
                                                  Colors.green.shade400,
                                                  Colors.green.shade500,
                                                ],
                                                begin: Alignment.topLeft,
                                                end: Alignment.bottomRight,
                                              )
                                            : null,
                                        color: done
                                            ? null
                                            : const Color(0xFFFAF7F2),
                                        border: done
                                            ? null
                                            : Border.all(
                                                color: const Color(0xFFDDD0C4),
                                                width: 1.8,
                                              ),
                                        shape: BoxShape.circle,
                                        boxShadow: done
                                            ? [
                                                BoxShadow(
                                                  color: Colors.green
                                                      .withValues(alpha: 0.3),
                                                  blurRadius: 6,
                                                  offset: const Offset(0, 2),
                                                ),
                                              ]
                                            : null,
                                      ),
                                      child: done
                                          ? AnimatedBuilder(
                                              animation: _checkAnim,
                                              builder: (_, _) => CustomPaint(
                                                painter: _CheckDrawPainter(
                                                  _checkAnim.value,
                                                ),
                                              ),
                                            )
                                          : null,
                                    ),
                                  ),
                                  title: AnimatedDefaultTextStyle(
                                    duration: const Duration(milliseconds: 250),
                                    style: TextStyle(
                                      fontSize: done ? 13.5 : 15,
                                      height: 1.3,
                                      fontWeight: FontWeight.w600,
                                      decoration: done
                                          ? TextDecoration.lineThrough
                                          : TextDecoration.none,
                                      decorationColor: AppInk.faint,
                                      color: done
                                          ? AppInk.faint
                                          : AppInk.strong,
                                    ),
                                    child: Text(
                                      name,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  subtitle: widget.isLinked
                                      ? Padding(
                                          padding: const EdgeInsets.only(
                                            top: 2,
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(
                                                Icons.link,
                                                size: 11,
                                                color: linkedAccent,
                                              ),
                                              const SizedBox(width: 3),
                                              Text(
                                                isWeightHabitName(name)
                                                    ? l10n.hcLinkedWeight
                                                    : l10n.hcLinkedWater,
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  color: linkedAccent,
                                                ),
                                              ),
                                            ],
                                          ),
                                        )
                                      : null,
                                  trailing: PopupMenuButton<String>(
                                    icon: Icon(
                                      Icons.more_vert,
                                      size: 20,
                                      color: AppInk.iconFaint,
                                    ),
                                    itemBuilder: (_) => _habitMenuItems(l10n),
                                    onSelected: (v) {
                                      switch (v) {
                                        case 'move':
                                          widget.onMove?.call();
                                        case 'edit':
                                          widget.onEdit();
                                        case 'delete':
                                          widget.onDelete();
                                      }
                                    },
                                  ),
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
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildWeeklyCard() {
    final done = widget.weeklyCount >= widget.weeklyTarget;
    final name = widget.habit['name'] as String;
    final todayCount = widget.todayCount;
    final inProgress = widget.weeklyCount > 0 && !done;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      // VoiceOver：念出名稱與本週進度（點擊 = 累加一次）
      child: Semantics(
        button: true,
        label: l10n.hcWeeklySemantics(
          name,
          widget.weeklyCount,
          widget.weeklyTarget,
          done ? l10n.hcStateReached : '',
        ),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          decoration: BoxDecoration(
            color: done
                ? const Color(0xFFF1F8E9)
                : inProgress
                ? const Color(0xFFF5F4FC)
                : Colors.white,
            borderRadius: BorderRadius.circular(AppCardStyle.radius),
            border: done
                ? Border.all(color: Colors.green.withValues(alpha: 0.18))
                : AppCardStyle.hairline,
            boxShadow: done ? AppShadows.flat : AppShadows.card,
          ),
          child: Listener(
            // opaque：整張卡（含透明空隙）都算命中，否則按在留白處不會觸發。
            // 子層按鈕/選單仍先被命中、照常運作；拖曳辨識器是祖先也不受影響。
            behavior: HitTestBehavior.opaque,
            // 按住蓄力波紋；isMoving（已在排序模式）時即時拖曳、不需蓄力。
            onPointerDown: widget.isMoving
                ? null
                : (e) => _onHoldDown(e.localPosition),
            onPointerUp: widget.isMoving ? null : (_) => _onHoldEnd(),
            onPointerCancel: widget.isMoving ? null : (_) => _onHoldEnd(),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppCardStyle.radius),
              child: Stack(
                children: [
                  _buildHoldFill(),
                  IntrinsicHeight(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 68),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // 內縮圓角色條：只表類別（靛=每週），完成時淡出
                          Padding(
                            padding: const EdgeInsets.fromLTRB(12, 14, 0, 14),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 300),
                              width: 4,
                              decoration: BoxDecoration(
                                color: Colors.indigo.shade300.withValues(
                                  alpha: done ? 0.30 : 1.0,
                                ),
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ),
                          // ⊖ n ⊕ 計數區（取代 checkbox）
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            child: Center(
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  WeeklyAdjustBtn(
                                    icon: Icons.remove_rounded,
                                    onTap: !widget.isMoving && todayCount > 0
                                        ? () {
                                            widget.onDecrement?.call();
                                          }
                                        : null,
                                  ),
                                  const SizedBox(width: 4),
                                  ScaleTransition(
                                    scale: _scale,
                                    child: SizedBox(
                                      width: 24,
                                      child: Text(
                                        '$todayCount',
                                        textAlign: TextAlign.center,
                                        style: AppType.digits(
                                          fontSize: 17,
                                          fontWeight: FontWeight.w800,
                                          color: todayCount > 0
                                              ? Colors.indigo.shade700
                                              : AppInk.faint,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  WeeklyAdjustBtn(
                                    icon: Icons.add_rounded,
                                    onTap:
                                        !widget.isMoving &&
                                            widget.weeklyCount < 20
                                        ? () {
                                            _ctrl.forward(from: 0);
                                            widget.onToggle();
                                          }
                                        : null,
                                  ),
                                ],
                              ),
                            ),
                          ),
                          // 習慣名稱
                          Expanded(
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: AnimatedDefaultTextStyle(
                                duration: const Duration(milliseconds: 250),
                                style: TextStyle(
                                  fontSize: 15,
                                  height: 1.3,
                                  fontWeight: FontWeight.w600,
                                  decoration: done
                                      ? TextDecoration.lineThrough
                                      : TextDecoration.none,
                                  decorationColor: AppInk.faint,
                                  color: done ? AppInk.faint : AppInk.strong,
                                ),
                                child: Text(
                                  name,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                          ),
                          // 本週 N/M 膠囊
                          Center(
                            child: Container(
                              margin: const EdgeInsets.symmetric(horizontal: 4),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 5,
                              ),
                              decoration: BoxDecoration(
                                color: done
                                    ? Colors.green.shade100
                                    : Colors.indigo.shade50,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    done
                                        ? Icons.check_rounded
                                        : Icons.flag_rounded,
                                    size: 11,
                                    color: done
                                        ? Colors.green.shade700
                                        : Colors.indigo.shade400,
                                  ),
                                  const SizedBox(width: 3),
                                  Text(
                                    '${widget.weeklyCount}/${widget.weeklyTarget}',
                                    style: AppType.digits(
                                      color: done
                                          ? Colors.green.shade700
                                          : Colors.indigo.shade500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          // 選單
                          PopupMenuButton<String>(
                            icon: Icon(
                              Icons.more_vert,
                              size: 20,
                              color: AppInk.iconFaint,
                            ),
                            itemBuilder: (_) => _habitMenuItems(l10n),
                            onSelected: (v) {
                              switch (v) {
                                case 'move':
                                  widget.onMove?.call();
                                case 'edit':
                                  widget.onEdit();
                                case 'delete':
                                  widget.onDelete();
                              }
                            },
                          ),
                        ],
                      ),
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
}

// 每週卡「按住蓄力」綠波紋：從觸點圓形擴散填滿整框，視覺對齊每日卡的綠
// splash（同樣的綠、~0.13 透明度）。被外層 ClipRRect 切成卡片圓角。
class _HoldFillPainter extends CustomPainter {
  final double progress; // 0..1，填滿即進排序
  final Offset? origin; // 觸點；null 時退回中心
  const _HoldFillPainter({required this.progress, this.origin});

  @override
  void paint(Canvas canvas, Size size) {
    final o = origin ?? Offset(size.width / 2, size.height / 2);
    // 取到最遠角落的距離，半徑長到這就蓋滿整框
    final maxR = [
      o.distance,
      (o - Offset(size.width, 0)).distance,
      (o - Offset(0, size.height)).distance,
      (o - Offset(size.width, size.height)).distance,
    ].reduce(math.max);
    final p = progress.clamp(0.0, 1.0);
    final r = maxR * Curves.easeOut.transform(p);
    // 起步前 1/4 快速淡入避免一按就「啪」一塊綠
    final alpha = 0.13 * math.min(1.0, p * 4);
    canvas.drawCircle(
      o,
      r,
      Paint()..color = Colors.green.withValues(alpha: alpha),
    );
  }

  @override
  bool shouldRepaint(_HoldFillPainter old) =>
      old.progress != progress || old.origin != origin;
}

// 移動/編輯/刪除選單項目（每日/每週卡共用）：icon + 文字。
// 「移動」是讓使用者發現拖曳排序功能的入口（長按之外的明示路徑）。
List<PopupMenuItem<String>> _habitMenuItems(AppLocalizations l10n) => [
  PopupMenuItem(
    value: 'move',
    child: Row(
      children: [
        const Icon(Icons.open_with_rounded, size: 18, color: AppInk.soft),
        const SizedBox(width: 10),
        Text(l10n.commonMove),
      ],
    ),
  ),
  PopupMenuItem(
    value: 'edit',
    child: Row(
      children: [
        const Icon(Icons.edit_outlined, size: 18, color: AppInk.soft),
        const SizedBox(width: 10),
        Text(l10n.commonEdit),
      ],
    ),
  ),
  PopupMenuItem(
    value: 'delete',
    child: Row(
      children: [
        Icon(
          Icons.delete_outline_rounded,
          size: 18,
          color: Colors.red.shade400,
        ),
        const SizedBox(width: 10),
        Text(l10n.commonDelete, style: TextStyle(color: Colors.red.shade400)),
      ],
    ),
  ),
];

// 勾勾描繪 painter：照筆順從左到右畫出白色圓頭勾
class _CheckDrawPainter extends CustomPainter {
  final double t;
  const _CheckDrawPainter(this.t);

  @override
  void paint(Canvas canvas, Size size) {
    if (t <= 0) return;
    final paint = Paint()
      ..color = Colors.white
      ..strokeWidth = 2.6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    final path = Path()
      ..moveTo(size.width * 0.26, size.height * 0.53)
      ..lineTo(size.width * 0.44, size.height * 0.70)
      ..lineTo(size.width * 0.75, size.height * 0.33);
    final metric = path.computeMetrics().first;
    canvas.drawPath(metric.extractPath(0, metric.length * t), paint);
  }

  @override
  bool shouldRepaint(_CheckDrawPainter oldDelegate) => oldDelegate.t != t;
}
