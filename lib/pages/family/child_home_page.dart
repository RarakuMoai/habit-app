import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../utils/app_style.dart';
import '../../widgets/audio_control_button.dart';
import '../../widgets/mascot_page_shell.dart';
import '../../widgets/mascot_scene.dart';
import '../home/room_ambient_overlay.dart';
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
            height: MediaQuery.of(context).size.height * 0.56,
            child: const MascotSceneBackground(
              'assets/scenes/family/family_bg.png',
              ambience: SceneAmbience(
                tint: true,
                glasslessAsset: 'assets/scenes/family/family_bg_glassless.png',
                windowRect: Rect.fromLTRB(0.012, 0.0, 0.27, 0.34),
              ),
            ),
          ),
          SafeArea(
            child: MascotPageShell(
              accent: accent,
              scene: PersonaScene(accent: accent),
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
          TabBar(
            labelColor: accent,
            unselectedLabelColor: AppInk.soft,
            indicatorColor: accent,
            indicatorWeight: 3,
            tabs: const [
              Tab(text: '習慣'),
              Tab(text: '積分紀錄'),
              Tab(text: '獎勵'),
            ],
          ),
          const Divider(height: 1, color: Color(0x14000000)),
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
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
      child: Material(
        color: Colors.white.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          onTap: canSwitch ? _showChildPicker : null,
          borderRadius: BorderRadius.circular(18),
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: AppCardStyle.hairline,
              boxShadow: AppShadows.flat,
            ),
            child: Row(
              children: [
                if (widget.onBack != null) ...[
                  _PanelBackButton(onPressed: widget.onBack!),
                  const SizedBox(width: 8),
                ],
                CircleAvatar(
                  radius: 23,
                  backgroundColor: accent.withValues(alpha: 0.10),
                  child: Text(
                    _current.avatar.isNotEmpty ? _current.avatar : '🐼',
                    style: const TextStyle(fontSize: 23),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              _current.name,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: AppInk.strong,
                                fontSize: 17,
                                fontWeight: FontWeight.w800,
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
                      const SizedBox(height: 2),
                      Text(
                        '今天也慢慢累積',
                        style: TextStyle(
                          color: AppInk.soft.withValues(alpha: 0.92),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '${_current.points} 分',
                    style: AppType.digits(
                      color: accent,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
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
              color: Colors.black.withValues(alpha: 0.10),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: IconButton(
          icon: Icon(icon, color: Colors.grey.shade800),
          tooltip: tooltip,
          onPressed: onPressed,
        ),
      ),
    );
  }
}
