import 'package:flutter/material.dart';

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

class _HabitCardState extends State<HabitCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale;

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
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
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

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: done ? const Color(0xFFF1F8E9) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        elevation: done ? 0 : 1.5,
        shadowColor: Colors.orange.withValues(alpha: 0.18),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
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
                constraints: const BoxConstraints(minHeight: 66),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      width: 5,
                      color: done
                          ? Colors.green.shade400
                          : widget.isLinked
                          ? Colors.blue.shade400
                          : Colors.orange.shade400,
                    ),
                    Expanded(
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
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
                              color: done ? null : Colors.grey.shade50,
                              border: done
                                  ? null
                                  : Border.all(
                                      color: Colors.grey.shade300,
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
                                ? const Icon(
                                    Icons.check_rounded,
                                    color: Colors.white,
                                    size: 20,
                                  )
                                : null,
                          ),
                        ),
                        title: AnimatedDefaultTextStyle(
                          duration: const Duration(milliseconds: 250),
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            decoration: done
                                ? TextDecoration.lineThrough
                                : TextDecoration.none,
                            color: done ? Colors.grey.shade400 : Colors.black87,
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
                            color: Colors.grey.shade400,
                          ),
                          itemBuilder: (_) => const [
                            PopupMenuItem(value: 'edit', child: Text('編輯')),
                            PopupMenuItem(
                              value: 'delete',
                              child: Text(
                                '刪除',
                                style: TextStyle(color: Colors.red),
                              ),
                            ),
                          ],
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
    );
  }

  Widget _buildWeeklyCard() {
    final done = widget.weeklyCount >= widget.weeklyTarget;
    final name = widget.habit['name'] as String;
    final todayCount = widget.todayCount;
    final inProgress = widget.weeklyCount > 0 && !done;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: done
            ? const Color(0xFFF1F8E9)
            : inProgress
            ? const Color(0xFFF3F2FB)
            : Colors.white,
        borderRadius: BorderRadius.circular(16),
        elevation: done ? 0 : 1.5,
        shadowColor: Colors.indigo.withValues(alpha: 0.18),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: IntrinsicHeight(
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 66),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 左邊條
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    width: 5,
                    color: done
                        ? Colors.green.shade400
                        : Colors.indigo.shade300,
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
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                  color: todayCount > 0
                                      ? Colors.indigo.shade700
                                      : Colors.grey.shade400,
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
                          fontWeight: FontWeight.w600,
                          decoration: done
                              ? TextDecoration.lineThrough
                              : TextDecoration.none,
                          color: done ? Colors.grey.shade400 : Colors.black87,
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
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
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
                      color: Colors.grey.shade400,
                    ),
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'edit', child: Text('編輯')),
                      PopupMenuItem(
                        value: 'delete',
                        child: Text('刪除', style: TextStyle(color: Colors.red)),
                      ),
                    ],
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
