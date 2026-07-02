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
import 'family/family_widgets.dart';
import 'family/parent_management_page.dart';
import 'family/parent_pin_recovery.dart';
import 'home/room_ambient_overlay.dart';
import 'home/room_metrics.dart';

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
        // 忘記密碼：答對救援問題重設、或清空重來。成功重設會設好 parentSession，
        // 使用者再點一次家長管理即可直接進入；清空則整個 app 重啟。
        onForgotPassword: () async {
          await showForgotParentPin(context);
        },
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
                // 場景背景：延伸到 AppBar 後面，高度跟首頁同一套「寬度錨點」
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  height: roomSceneHeight(MediaQuery.of(context).size.width),
                  child: const MascotSceneBackground(
                    'assets/scenes/family/family_bg.png',
                    ambience: SceneAmbience(
                      tint: true,
                      glasslessAsset:
                          'assets/scenes/family/family_bg_glassless.png',
                      windowRect: Rect.fromLTRB(0.004, 0.0, 0.166, 0.258),
                    ),
                  ),
                ),
                SafeArea(
                  child: MascotPageShell(
                    accent: Theme.of(context).colorScheme.primary,
                    // 空狀態不再縮小場景（舊 0.40 特例）：所有分頁統一同一條
                    // 卡片線，空狀態內容是可捲動的邀請卡，不需要額外高度。
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
      // 空狀態不顯示：唯一動作「新增小孩」本來就走 PIN 驗證，管理頁也無物可管；
      // 小螢幕（SE）空狀態卡片較矮，FAB 會疊到邀請卡的按鈕。
      floatingActionButton: _children.isNotEmpty && _activeChildIndex == null
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
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(18, 2, 18, 102),
      child: Align(
        alignment: Alignment.topCenter,
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.0, end: 1.0),
          duration: const Duration(milliseconds: 450),
          curve: Curves.easeOut,
          builder: (_, v, child) => Opacity(
            opacity: v,
            child: Transform.translate(
              offset: Offset(0, 10 * (1 - v)),
              child: child,
            ),
          ),
          child: FamilyEmptyInvite(accent: accent, onAdd: _addChildAction),
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
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
      itemCount: _children.length + 2,
      itemBuilder: (_, i) {
        if (i == 0) {
          return _FamilyRosterHeader(childCount: _children.length);
        }
        final childIndex = i - 1;
        if (childIndex == _children.length) {
          return Padding(
            padding: const EdgeInsets.only(top: 2),
            child: TextButton.icon(
              onPressed: _addChildAction,
              icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
              label: const Text('新增小孩'),
              style: TextButton.styleFrom(foregroundColor: AppInk.soft),
            ),
          );
        }
        final child = _children[childIndex];
        return _ChildCard(
          child: child,
          onTap: () => setState(() => _activeChildIndex = childIndex),
        );
      },
    );
  }
}

// ── 小孩選擇卡片元件 ──

class _FamilyRosterHeader extends StatelessWidget {
  final int childCount;

  const _FamilyRosterHeader({required this.childCount});

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 2, 2, 14),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.11),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(Icons.family_restroom_rounded, color: accent, size: 21),
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '家庭任務',
                  style: TextStyle(
                    color: AppInk.strong,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  '今天也一起慢慢累積',
                  style: TextStyle(
                    color: AppInk.soft,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          _RosterStatPill(
            icon: Icons.group_rounded,
            label: '$childCount',
            color: accent,
          ),
        ],
      ),
    );
  }
}

class _RosterStatPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _RosterStatPill({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: 9),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.10)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: AppType.digits(
              color: color,
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _ChildCard extends StatelessWidget {
  final ChildData child;
  final VoidCallback onTap;

  const _ChildCard({required this.child, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final pointColor = Colors.amber.shade700;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppCardStyle.radius),
          boxShadow: AppShadows.card,
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
                colors: [Color(0xFFFFFFFF), Color(0xFFFFF8F1)],
              ),
              borderRadius: BorderRadius.circular(AppCardStyle.radius),
              border: AppCardStyle.hairline,
            ),
            child: InkWell(
              onTap: onTap,
              splashColor: accent.withValues(alpha: 0.10),
              highlightColor: accent.withValues(alpha: 0.05),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 13, 12, 13),
                child: Row(
                  children: [
                    Container(
                      width: 56,
                      height: 56,
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
                        child.avatar.isNotEmpty ? child.avatar : '🐼',
                        style: const TextStyle(fontSize: 28),
                      ),
                    ),
                    const SizedBox(width: 13),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            child.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppInk.strong,
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Icon(
                                Icons.auto_awesome_rounded,
                                size: 14,
                                color: pointColor.withValues(alpha: 0.86),
                              ),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  '今天也慢慢累積',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: AppInk.soft.withValues(alpha: 0.92),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    _ChildPointBadge(points: child.points, color: pointColor),
                    const SizedBox(width: 8),
                    Icon(
                      Icons.chevron_right_rounded,
                      color: accent.withValues(alpha: 0.55),
                      size: 24,
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

class _ChildPointBadge extends StatelessWidget {
  final int points;
  final Color color;

  const _ChildPointBadge({required this.points, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 58),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.11),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.11)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.stars_rounded, size: 14, color: color),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              '$points',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppType.digits(
                color: color,
                fontSize: 14,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
