import 'package:flutter/material.dart';

import '../settings_page.dart';
import 'family_models.dart';
import 'habit_tab.dart';
import 'point_record_tab.dart';
import 'reward_tab.dart';

// ── 小孩主頁（三個 Tab）──

class ChildHomePage extends StatefulWidget {
  final List<ChildData> children;
  final int initialIndex;

  const ChildHomePage({
    super.key,
    required this.children,
    required this.initialIndex,
  });

  @override
  State<ChildHomePage> createState() => _ChildHomePageState();
}

class _ChildHomePageState extends State<ChildHomePage> {
  late int _selectedIndex;

  @override
  void initState() {
    super.initState();
    _selectedIndex = widget.initialIndex;
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

  // AppBar 中央的名字 + 積分 + 切換箭頭
  Widget _buildTitle() {
    return GestureDetector(
      onTap: widget.children.length > 1 ? _showChildPicker : null,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _current.name,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
          // 有多個小孩才顯示下拉箭頭
          if (widget.children.length > 1)
            const Icon(Icons.arrow_drop_down, color: Colors.white, size: 22),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              '${_current.points} 分',
              style: const TextStyle(fontSize: 13, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: _buildTitle(),
          centerTitle: true,
          actions: [
            IconButton(
              icon: const Icon(Icons.settings_outlined),
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
          ],
          bottom: const TabBar(
            tabs: [
              Tab(text: '習慣'),
              Tab(text: '積分紀錄'),
              Tab(text: '獎勵'),
            ],
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            indicatorColor: Colors.white,
          ),
        ),
        body: TabBarView(
          children: [
            // 習慣打卡 Tab
            HabitTab(child: _current, onPointsChanged: _onPointsChanged),
            // 積分紀錄 Tab
            PointRecordTab(child: _current),
            // 獎勵 Tab
            RewardTab(child: _current, onPointsChanged: _onPointsChanged),
          ],
        ),
      ),
    );
  }
}
