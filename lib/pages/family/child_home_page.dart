import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/app_localizations.dart';
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
    final accent = AppPalette.family;
    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: AppSurfaces.canvas,
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
            tooltip: AppLocalizations.of(context).commonBack,
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
        actions: [
          AudioControlButton(style: AudioControlStyle.appBar, accent: accent),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: _GlassIconButton(
              icon: Icons.settings_outlined,
              tooltip: AppLocalizations.of(context).chSettings,
              // 這裡原本是自訂 PageRouteBuilder + SlideTransition，看起來像系統
              // 轉場但**不走 theme 的 pageTransitionsTheme**，等於默默拿掉 iOS
              // 的邊緣滑回手勢。小朋友模式更需要滑得回去，改回平台路由。
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const SettingsPage()),
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
    final primary = AppPalette.family;
    showModalBottomSheet<void>(
      context: context,
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
            subtitle: Text(AppLocalizations.of(context).chPoints(c.points)),
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

    final accent = AppPalette.family;
    return DefaultTabController(
      length: 3,
      animationDuration: AppMotion.duration(context, AppMotion.settle),
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Material(
        color: AppSurfaces.card,
        borderRadius: BorderRadius.circular(AppCardStyle.radius),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: canSwitch ? _showChildPicker : null,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                if (widget.onBack != null) ...[
                  _PanelBackButton(onPressed: widget.onBack!),
                  const SizedBox(width: 8),
                ],
                _HeaderAvatar(avatar: _current.avatar, accent: accent),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: AnimatedSwitcher(
                              duration: AppMotion.duration(
                                context,
                                AppMotion.quick,
                              ),
                              layoutBuilder: (current, previous) => Stack(
                                alignment: Alignment.centerLeft,
                                children: [...previous, ?current],
                              ),
                              child: Text(
                                _current.name,
                                key: ValueKey(_current.id),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: AppInk.strong,
                                  fontSize: 19,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ),
                          if (canSwitch)
                            Icon(
                              Icons.keyboard_arrow_down_rounded,
                              color: accent,
                              size: 20,
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      _HeaderPointBadge(points: _current.points, color: accent),
                    ],
                  ),
                ),
              ],
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
      constraints: const BoxConstraints(minWidth: 54, maxWidth: 128),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
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
            child: FittedBox(
              fit: BoxFit.scaleDown,
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
        height: 48,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: AppSurfaces.fill,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: accent.withValues(alpha: 0.09)),
        ),
        child: TabBar(
          dividerColor: Colors.transparent,
          indicatorSize: TabBarIndicatorSize.tab,
          labelColor: accent,
          unselectedLabelColor: AppInk.soft,
          labelPadding: EdgeInsets.zero,
          indicator: BoxDecoration(
            color: AppSurfaces.card,
            borderRadius: BorderRadius.circular(16),
            boxShadow: AppShadows.flat,
          ),
          tabs: [
            Tab(
              height: 38,
              child: _SegmentTab(
                icon: Icons.task_alt_rounded,
                label: AppLocalizations.of(context).chTabHabits,
              ),
            ),
            Tab(
              height: 38,
              child: _SegmentTab(
                icon: Icons.history_rounded,
                label: AppLocalizations.of(context).chTabRecords,
              ),
            ),
            Tab(
              height: 38,
              child: _SegmentTab(
                icon: Icons.card_giftcard_rounded,
                label: AppLocalizations.of(context).chTabRewards,
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
          Flexible(
            child: DefaultTextStyle.merge(
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
              child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
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
      dimension: 44,
      child: Material(
        color: const Color(0xFFF8F0EA),
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: IconButton(
          padding: EdgeInsets.zero,
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 17),
          color: AppInk.soft,
          tooltip: AppLocalizations.of(context).chBackToList,
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
