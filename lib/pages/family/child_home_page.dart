import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../utils/app_style.dart';
import '../../widgets/audio_control_button.dart';
import '../../widgets/mascot_page_shell.dart';
import '../../widgets/mascot_scene.dart';
import '../../widgets/scene_rooms.dart';
import '../home/room_metrics.dart';
import '../settings_page.dart';
import 'family_models.dart';
import 'habit_tab.dart';
import 'point_record_tab.dart';
import 'reward_tab.dart';

// ── 小孩主頁（三個 Tab）──

class ChildHomePage extends StatelessWidget {
  final List<ChildData> children;
  final int initialIndex;

  const ChildHomePage({
    super.key,
    required this.children,
    required this.initialIndex,
  });

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: const Color(0xFFFFFBF7),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        systemOverlayStyle: SystemUiOverlayStyle.dark,
        leading: Padding(
          padding: const EdgeInsets.only(left: 8),
          child: _GlassIconButton(
            icon: Icons.arrow_back_ios_new_rounded,
            tooltip: '返回',
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
        actions: [
          AudioControlButton(style: AudioControlStyle.appBar, accent: accent),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: _GlassIconButton(
              icon: Icons.settings_outlined,
              tooltip: '設定',
              onPressed: () => Navigator.of(context).push(
                PageRouteBuilder<void>(
                  pageBuilder: (context, animation, secondaryAnimation) =>
                      const SettingsPage(),
                  transitionsBuilder:
                      (context, animation, secondaryAnimation, child) {
                        const begin = Offset(1.0, 0.0);
                        const end = Offset.zero;
                        final tween = Tween(
                          begin: begin,
                          end: end,
                        ).chain(CurveTween(curve: Curves.easeInOut));
                        return SlideTransition(
                          position: animation.drive(tween),
                          child: child,
                        );
                      },
                ),
              ),
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: roomSceneHeight(MediaQuery.of(context).size.width),
            child: const FourPeriodRoomScene(room: FourPeriodRoom.family),
          ),
          SafeArea(
            child: MascotPageShell(
              accent: accent,
              sceneHeight: sceneRegionHeightAnchored(
                MediaQuery.of(context).size.width,
                MediaQuery.of(context).padding.top,
              ),
              scene: PersonaScene(
                accent: accent,
                lightGeometry: FourPeriodRoom.family.light,
              ),
              child: ChildHomePanel(
                children: children,
                initialIndex: initialIndex,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ChildHomePanel extends StatefulWidget {
  final List<ChildData> children;
  final int initialIndex;
  final VoidCallback? onBack;

  const ChildHomePanel({
    super.key,
    required this.children,
    required this.initialIndex,
    this.onBack,
  });

  @override
  State<ChildHomePanel> createState() => _ChildHomePanelState();
}

class _ChildHomePanelState extends State<ChildHomePanel> {
  late int _selectedIndex;

  @override
  void initState() {
    super.initState();
    _selectedIndex = _validIndex(widget.initialIndex);
  }

  @override
  void didUpdateWidget(covariant ChildHomePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.children.isEmpty) {
      _selectedIndex = 0;
    } else if (_selectedIndex >= widget.children.length) {
      _selectedIndex = widget.children.length - 1;
    }
  }

  int _validIndex(int index) {
    if (widget.children.isEmpty) return 0;
    return index.clamp(0, widget.children.length - 1);
  }

  ChildData get _current => widget.children[_selectedIndex];

  // 積分異動後重新整理頁面
  void _onPointsChanged() => setState(() {});

  // 點擊名字旁的下拉箭頭，從底部彈出切換清單
  void _showChildPicker() {
    final primary = Theme.of(context).colorScheme.primary;
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => ListView.builder(
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: widget.children.length,
        itemBuilder: (_, i) {
          final c = widget.children[i];
          return ListTile(
            leading: CircleAvatar(
              backgroundColor: primary.withValues(alpha: 0.12),
              child: Text(
                c.name.isNotEmpty ? c.name[0] : '?',
                style: TextStyle(color: primary, fontWeight: FontWeight.bold),
              ),
            ),
            title: Text(c.name),
            subtitle: Text('積分：${c.points}'),
            selected: i == _selectedIndex,
            selectedColor: primary,
            onTap: () {
              setState(() => _selectedIndex = i);
              Navigator.pop(context);
            },
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.children.isEmpty) return const SizedBox.shrink();

    final accent = Theme.of(context).colorScheme.primary;
    return DefaultTabController(
      length: 3,
      child: Column(
        children: [
          _childHeader(accent),
          _ChildSegmentedTabs(accent: accent),
          Expanded(
            child: TabBarView(
              children: [
                HabitTab(
                  key: ValueKey('habit_${_current.id}'),
                  child: _current,
                  onPointsChanged: _onPointsChanged,
                ),
                PointRecordTab(
                  key: ValueKey('record_${_current.id}'),
                  child: _current,
                ),
                RewardTab(
                  key: ValueKey('reward_${_current.id}'),
                  child: _current,
                  onPointsChanged: _onPointsChanged,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _childHeader(Color accent) {
    final canSwitch = widget.children.length > 1;
    final pointColor = Colors.amber.shade700;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppCardStyle.radius),
          boxShadow: AppShadows.flat,
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(AppCardStyle.radius),
          clipBehavior: Clip.antiAlias,
          child: Ink(
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFFFFFFFF), Color(0xFFFFF8F2)],
              ),
              borderRadius: BorderRadius.circular(AppCardStyle.radius),
              border: AppCardStyle.hairline,
            ),
            child: InkWell(
              onTap: canSwitch ? _showChildPicker : null,
              splashColor: accent.withValues(alpha: 0.10),
              highlightColor: accent.withValues(alpha: 0.05),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                child: Row(
                  children: [
                    if (widget.onBack != null) ...[
                      _PanelBackButton(onPressed: widget.onBack!),
                      const SizedBox(width: 9),
                    ],
                    _HeaderAvatar(avatar: _current.avatar, accent: accent),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: AnimatedSwitcher(
                                  duration: const Duration(milliseconds: 180),
                                  switchInCurve: Curves.easeOutCubic,
                                  switchOutCurve: Curves.easeInCubic,
                                  child: Text(
                                    _current.name,
                                    key: ValueKey(_current.id),
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: AppInk.strong,
                                      fontSize: 18,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                              ),
                              if (canSwitch) ...[
                                const SizedBox(width: 2),
                                Icon(
                                  Icons.keyboard_arrow_down_rounded,
                                  color: accent,
                                  size: 20,
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Icon(
                                Icons.auto_awesome_rounded,
                                size: 14,
                                color: pointColor.withValues(alpha: 0.86),
                              ),
                              const SizedBox(width: 5),
                              Flexible(
                                child: Text(
                                  '今天也慢慢累積',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: AppInk.soft.withValues(alpha: 0.94),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    _HeaderPointBadge(
                      points: _current.points,
                      color: pointColor,
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
}

class _HeaderAvatar extends StatelessWidget {
  final String avatar;
  final Color accent;

  const _HeaderAvatar({required this.avatar, required this.accent});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 50,
      height: 50,
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.10),
        shape: BoxShape.circle,
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.92),
          width: 3,
        ),
        boxShadow: AppShadows.flat,
      ),
      alignment: Alignment.center,
      child: Text(
        avatar.isNotEmpty ? avatar : '🐼',
        style: const TextStyle(fontSize: 25),
      ),
    );
  }
}

class _HeaderPointBadge extends StatelessWidget {
  final int points;
  final Color color;

  const _HeaderPointBadge({required this.points, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 64, maxWidth: 98),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.11),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.11)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.stars_rounded, size: 15, color: color),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              '$points',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppType.digits(
                color: color,
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChildSegmentedTabs extends StatelessWidget {
  final Color accent;

  const _ChildSegmentedTabs({required this.accent});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Container(
        height: 44,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: accent.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: accent.withValues(alpha: 0.09)),
        ),
        child: TabBar(
          dividerColor: Colors.transparent,
          indicatorSize: TabBarIndicatorSize.tab,
          labelColor: accent,
          unselectedLabelColor: AppInk.soft,
          labelPadding: EdgeInsets.zero,
          indicator: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(13),
            boxShadow: AppShadows.flat,
          ),
          tabs: const [
            Tab(
              height: 38,
              child: _SegmentTab(icon: Icons.task_alt_rounded, label: '習慣'),
            ),
            Tab(
              height: 38,
              child: _SegmentTab(icon: Icons.history_rounded, label: '積分紀錄'),
            ),
            Tab(
              height: 38,
              child: _SegmentTab(
                icon: Icons.card_giftcard_rounded,
                label: '獎勵',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SegmentTab extends StatelessWidget {
  final IconData icon;
  final String label;

  const _SegmentTab({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15),
          const SizedBox(width: 4),
          DefaultTextStyle.merge(
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
            child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }
}

class _PanelBackButton extends StatelessWidget {
  final VoidCallback onPressed;

  const _PanelBackButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 36,
      child: Material(
        color: const Color(0xFFF8F0EA),
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: IconButton(
          padding: EdgeInsets.zero,
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 17),
          color: AppInk.soft,
          tooltip: '返回小孩列表',
          onPressed: onPressed,
        ),
      ),
    );
  }
}

class _GlassIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  const _GlassIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.88),
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF8D6E63).withValues(alpha: 0.22),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: IconButton(
          icon: Icon(icon, color: AppInk.strong),
          tooltip: tooltip,
          onPressed: onPressed,
        ),
      ),
    );
  }
}
