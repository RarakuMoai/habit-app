import 'package:flutter/material.dart';

import '../../utils/app_style.dart';
import '../../widgets/habit_ui.dart';

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
  });

  @override
  State<HabitCard> createState() => _HabitCardState();
}

class _HabitCardState extends State<HabitCard> with TickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale;
  // 勾勾描繪動畫：done 轉 true 時從 0 畫到 1
  late AnimationController _checkCtrl;
  late Animation<double> _checkAnim;
  late bool _wasDone;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
    );
    _scale = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.78), weight: 25),
      TweenSequenceItem(tween: Tween(begin: 0.78, end: 1.18), weight: 45),
      TweenSequenceItem(tween: Tween(begin: 1.18, end: 1.0), weight: 30),
    ]).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));

    _checkCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );
    _checkAnim = CurvedAnimation(
      parent: _checkCtrl,
      curve: Curves.easeOutCubic,
    );
    // 列表載入時已完成的卡直接顯示完整勾，不重播描繪
    _wasDone = widget.habit['done'] == true;
    _checkCtrl.value = _wasDone ? 1.0 : 0.0;
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _checkCtrl.dispose();
    super.dispose();
  }

  /// habit map 是同一個實例被原地修改，didUpdateWidget 比不出新舊值，
  /// 改在 build 時偵測 done 變化來觸發描繪動畫。
  void _syncCheckAnim(bool done) {
    if (done == _wasDone) return;
    _wasDone = done;
    if (done) {
      _checkCtrl.forward(from: 0);
    } else {
      _checkCtrl.value = 0;
    }
  }

  void _handleTap() {
    _ctrl.forward(from: 0);
    widget.onToggle();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isWeekly) return _buildWeeklyCard();
    return _buildDailyCard();
  }

  Widget _buildDailyCard() {
    final done = widget.habit['done'] as bool;
    final name = widget.habit['name'] as String;
    _syncCheckAnim(done);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        decoration: BoxDecoration(
          color: done ? const Color(0xFFF1F8E9) : Colors.white,
          borderRadius: BorderRadius.circular(AppCardStyle.radius),
          border: done
              ? Border.all(color: Colors.green.withValues(alpha: 0.18))
              : AppCardStyle.hairline,
          boxShadow: done ? AppShadows.flat : AppShadows.card,
        ),
        child: Material(
          color: Colors.transparent,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppCardStyle.radius),
            // 整張卡都可點擊打卡（不只左邊小圓圈），ripple 回饋
            child: InkWell(
              onTap: _handleTap,
              splashColor: (done ? Colors.grey : Colors.green).withValues(
                alpha: 0.12,
              ),
              highlightColor: (done ? Colors.grey : Colors.green).withValues(
                alpha: 0.06,
              ),
              child: IntrinsicHeight(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 68),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // 內縮圓角色條：只表「類別」（橘=一般、藍=連動），
                      // 完成狀態交給圓圈/底色表達，色條僅淡出讓位
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 14, 0, 14),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          width: 4,
                          decoration: BoxDecoration(
                            color:
                                (widget.isLinked
                                        ? Colors.blue.shade400
                                        : Colors.orange.shade400)
                                    .withValues(alpha: done ? 0.30 : 1.0),
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
                          minTileHeight: 68,
                          titleAlignment: ListTileTitleAlignment.center,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 2,
                          ),
                        leading: ScaleTransition(
                          scale: _scale,
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 250),
                            width: 34,
                            height: 34,
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
                              color: done ? null : const Color(0xFFFAF7F2),
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
                                        color: Colors.green.withValues(
                                          alpha: 0.3,
                                        ),
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
                        subtitle: widget.isLinked
                            ? Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.link,
                                      size: 11,
                                      color: Colors.blue.shade400,
                                    ),
                                    const SizedBox(width: 3),
                                    Text(
                                      '連動喝水頁面',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.blue.shade500,
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
                          itemBuilder: (_) => _habitMenuItems(),
                          onSelected: (v) {
                            if (v == 'edit') {
                              widget.onEdit();
                            } else {
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
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppCardStyle.radius),
          child: IntrinsicHeight(
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
                            onTap: todayCount > 0
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
                            onTap: widget.weeklyCount < 20
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
                            done ? Icons.check_rounded : Icons.flag_rounded,
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
                    itemBuilder: (_) => _habitMenuItems(),
                    onSelected: (v) {
                      if (v == 'edit') {
                        widget.onEdit();
                      } else {
                        widget.onDelete();
                      }
                    },
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

// 編輯/刪除選單項目（每日/每週卡共用）：icon + 文字
List<PopupMenuItem<String>> _habitMenuItems() => [
  const PopupMenuItem(
    value: 'edit',
    child: Row(
      children: [
        Icon(Icons.edit_outlined, size: 18, color: AppInk.soft),
        SizedBox(width: 10),
        Text('編輯'),
      ],
    ),
  ),
  PopupMenuItem(
    value: 'delete',
    child: Row(
      children: [
        Icon(Icons.delete_outline_rounded, size: 18, color: Colors.red.shade400),
        const SizedBox(width: 10),
        Text('刪除', style: TextStyle(color: Colors.red.shade400)),
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
