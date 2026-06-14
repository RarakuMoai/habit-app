// 育兒模式主頁面（小孩選擇畫面）。
// 其餘部分拆在 family/：小孩主頁三 Tab、家長管理頁、各式 bottom sheet、
// 資料模型與儲存層。
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/app_feedback.dart';
import '../utils/app_style.dart';
import '../utils/mascot.dart';
import '../utils/parent_pin.dart';
import '../utils/prefs_keys.dart';
import '../utils/sfx_service.dart';
import '../widgets/mascot_app_bar.dart';
import '../widgets/mascot_page_shell.dart';
import '../widgets/mascot_scene.dart';
import 'family/add_children_sheet.dart';
import 'family/child_home_page.dart';
import 'family/family_auth.dart';
import 'family/family_models.dart';
import 'family/family_store.dart';
import 'family/parent_management_page.dart';

// ── 家庭主頁（小孩選擇畫面）──

class FamilyPage extends StatefulWidget {
  final VoidCallback? onSettingsChanged;
  const FamilyPage({super.key, this.onSettingsChanged});

  @override
  State<FamilyPage> createState() => _FamilyPageState();
}

class _FamilyPageState extends State<FamilyPage> {
  List<ChildData> _children = [];
  bool _loaded = false;
  int? _activeChildIndex;

  @override
  void initState() {
    super.initState();
    _loadChildren();
  }

  @override
  void deactivate() {
    parentSession.value = false;
    super.deactivate();
  }

  // 從 SharedPreferences 讀取小孩清單
  Future<void> _loadChildren() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(PrefsKeys.children);
    final children = raw == null
        ? <ChildData>[]
        : (jsonDecode(raw) as List)
              .map((e) => ChildData.fromJson(e as Map<String, dynamic>))
              .toList();
    setState(() {
      _children = children;
      if (_activeChildIndex != null && _activeChildIndex! >= _children.length) {
        _activeChildIndex = null;
      }
      _loaded = true;
    });
  }

  // 點擊「家長管理」：有 Session 直接進入，否則驗證密碼
  Future<void> _enterParentManagement() async {
    final prefs = await SharedPreferences.getInstance();
    final hasPin = await ParentPin.hasPin(prefs);
    if (!mounted) return;

    if (parentSession.value || !hasPin) {
      // Session 有效或尚未設定密碼，直接進入
      final changed = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => ParentManagementPage(noPinWarning: !hasPin),
        ),
      );
      if (changed == true) unawaited(_loadChildren());
    } else {
      // 需要輸入密碼才能進入
      final digits = prefs.getInt(PrefsKeys.pinDigits) ?? 4;
      final entered = await showPinDialog(
        context,
        digits: digits,
        title: '請輸入家長密碼',
      );
      if (entered != null && await ParentPin.verify(prefs, entered)) {
        if (!mounted) return;
        // 驗證成功，啟動 Session
        parentSession.value = true;
        final changed = await Navigator.of(context).push<bool>(
          MaterialPageRoute(
            builder: (_) => const ParentManagementPage(noPinWarning: false),
          ),
        );
        if (changed == true) unawaited(_loadChildren());
      } else if (entered != null) {
        // 輸入了內容但不正確
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('密碼錯誤，請再試一次')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: MascotAppBar(
        accent: Theme.of(context).colorScheme.primary,
        onSettingsReturn: () {
          widget.onSettingsChanged?.call();
          _loadChildren();
        },
      ),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              children: [
                // 場景背景：延伸到 AppBar 後面（跟首頁同樣 56% 高度）
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  height: MediaQuery.of(context).size.height * 0.56,
                  child: const MascotSceneBackground(
                    'assets/scenes/family/family_bg.png',
                  ),
                ),
                SafeArea(
                  child: MascotPageShell(
                    accent: Theme.of(context).colorScheme.primary,
                    scene: PersonaScene(
                      accent: Theme.of(context).colorScheme.primary,
                    ),
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 260),
                      switchInCurve: Curves.easeOutCubic,
                      switchOutCurve: Curves.easeInCubic,
                      transitionBuilder: (child, animation) {
                        final offset = Tween<Offset>(
                          begin: const Offset(0.06, 0),
                          end: Offset.zero,
                        ).animate(animation);
                        return FadeTransition(
                          opacity: animation,
                          child: SlideTransition(
                            position: offset,
                            child: child,
                          ),
                        );
                      },
                      child: KeyedSubtree(
                        key: ValueKey(_panelKey),
                        child: _buildPanelContent(),
                      ),
                    ),
                  ),
                ),
              ],
            ),
      // 家長管理按鈕：鎖定狀態用圖示 + 色彩區分（開鎖綠 = 已解鎖 / 上鎖主色），
      // 兩態同一個 label 讓按鈕大小一致、視覺平衡。
      floatingActionButton: _activeChildIndex == null
          ? ValueListenableBuilder<bool>(
              valueListenable: parentSession,
              builder: (_, unlocked, _) => FloatingActionButton.extended(
                heroTag: 'family_manage',
                onPressed: _enterParentManagement,
                icon: Icon(
                  unlocked ? Icons.lock_open_rounded : Icons.lock_outline,
                ),
                label: const Text('家長管理'),
                backgroundColor: unlocked
                    ? Colors.green.shade600
                    : Theme.of(context).colorScheme.primary,
                foregroundColor: Colors.white,
              ),
            )
          : null,
    );
  }

  String get _panelKey {
    if (_children.isEmpty) return 'empty';
    final active = _activeChildIndex;
    if (active == null) return 'list';
    final index = active.clamp(0, _children.length - 1);
    return 'child_${_children[index].id}';
  }

  Widget _buildPanelContent() {
    if (_children.isEmpty) return _buildEmpty();
    final active = _activeChildIndex;
    if (active == null) return _buildChildList();
    final index = active.clamp(0, _children.length - 1);
    return ChildHomePanel(
      children: _children,
      initialIndex: index,
      onBack: () {
        widget.onSettingsChanged?.call();
        setState(() => _activeChildIndex = null);
        unawaited(_loadChildren());
      },
    );
  }

  // 尚無小孩時的空狀態：淡入＋上浮，視覺語言對齊習慣頁
  Widget _buildEmpty() {
    final accent = Theme.of(context).colorScheme.primary;
    return Center(
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0.0, end: 1.0),
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeOut,
        builder: (_, v, child) => Opacity(
          opacity: v,
          child: Transform.translate(
            offset: Offset(0, 12 * (1 - v)),
            child: child,
          ),
        ),
        // FittedBox：兔咪面板展開時卡片高度有限，等比縮小避免 overflow
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(32, 0, 32, 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.10),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.child_care_rounded,
                    size: 32,
                    color: accent,
                  ),
                ),
                const SizedBox(height: 14),
                const Text(
                  '還沒有任何小孩',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: AppInk.strong,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  '新增小孩後，就能一起記小任務、累積積分',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.5,
                    fontWeight: FontWeight.w500,
                    color: AppInk.soft,
                  ),
                ),
                const SizedBox(height: 18),
                FilledButton.icon(
                  onPressed: _addChildAction,
                  icon: const Icon(Icons.person_add_outlined),
                  label: const Text('新增小孩'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _addChildAction() async {
    final ok = await verifyParentPinIfNeeded(context);
    if (!ok || !mounted) return;
    final inputs = await showAddChildrenSheet(context);
    if (inputs == null || inputs.isEmpty || !mounted) return;
    final prefs = await SharedPreferences.getInstance();
    final habits = await loadHabits(prefs);
    for (final inp in inputs) {
      final child = ChildData(
        id: genId(),
        name: inp.name.trim(),
        avatar: inp.avatar,
        points: 0,
      );
      _children.add(child);
      habits.addAll(defaultHabitsForChild(child.id));
    }
    await prefs.setString(
      PrefsKeys.children,
      jsonEncode(_children.map((c) => c.toJson()).toList()),
    );
    await saveHabits(prefs, habits);
    setState(() {});
    playFeedback(SfxCue.success);
    MascotPersona.interact(MascotContext.completedOne);
  }

  // 小孩卡片清單
  Widget _buildChildList() {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      itemCount: _children.length + 1,
      itemBuilder: (_, i) {
        if (i == _children.length) {
          return Padding(
            padding: const EdgeInsets.only(top: 4),
            child: TextButton.icon(
              onPressed: _addChildAction,
              icon: const Icon(Icons.person_add_outlined, size: 18),
              label: const Text('新增小孩'),
              style: TextButton.styleFrom(foregroundColor: AppInk.soft),
            ),
          );
        }
        final child = _children[i];
        return _ChildCard(
          child: child,
          onTap: () => setState(() => _activeChildIndex = i),
        );
      },
    );
  }
}

// ── 小孩選擇卡片元件 ──

class _ChildCard extends StatelessWidget {
  final ChildData child;
  final VoidCallback onTap;

  const _ChildCard({required this.child, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 2,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 20,
          vertical: 12,
        ),
        leading: CircleAvatar(
          radius: 24,
          backgroundColor: const Color(0xFFFAF7F2),
          child: Text(
            child.avatar.isNotEmpty ? child.avatar : '🐼',
            style: const TextStyle(fontSize: 24),
          ),
        ),
        title: Text(
          child.name,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          '積分：${child.points}',
          style: const TextStyle(color: AppInk.soft),
        ),
        trailing: const Icon(Icons.chevron_right, color: AppInk.iconFaint),
        onTap: onTap,
      ),
    );
  }
}
