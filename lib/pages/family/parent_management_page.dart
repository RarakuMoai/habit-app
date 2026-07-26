import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../l10n/app_localizations.dart';
import '../../utils/app_style.dart';
import '../../utils/parent_pin.dart';
import '../../utils/prefs_keys.dart';
import '../settings_page.dart';
import 'add_children_sheet.dart';
import 'deduction_sheets.dart';
import 'family_models.dart';
import 'family_store.dart';
import 'family_widgets.dart';
import 'habit_sheets.dart';
import 'reward_sheets.dart';

// ── 家長管理頁面 ──

class ParentManagementPage extends StatefulWidget {
  // 是否要顯示「建議設定密碼」的提示
  final bool noPinWarning;

  const ParentManagementPage({super.key, required this.noPinWarning});

  @override
  State<ParentManagementPage> createState() => _ParentManagementPageState();
}

class _ParentManagementPageState extends State<ParentManagementPage> {
  AppLocalizations get _l10n => AppLocalizations.of(context);

  List<ChildData> _children = [];
  List<ChildHabit> _habits = [];
  List<DeductionItem> _deductions = [];
  List<RewardItem> _rewards = [];
  bool _loaded = false;
  SharedPreferences? _prefs;

  // 追蹤是否有異動，回傳給上層以決定是否重新載入
  bool _changed = false;

  // 「尚未設定密碼」橫幅是否已被使用者關閉（取代原本會黏住的 SnackBar）
  bool _pinWarnDismissed = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    _prefs = await SharedPreferences.getInstance();
    await _loadAll();
  }

  // 一次讀取所有資料
  Future<void> _loadAll() async {
    final prefs = _prefs!;
    final raw = prefs.getString(PrefsKeys.children);
    final children = raw == null
        ? <ChildData>[]
        : (jsonDecode(raw) as List)
              .map((e) => ChildData.fromJson(e as Map<String, dynamic>))
              .toList();
    final habits = await loadHabits(prefs);
    final deductions = await loadDeductions(prefs);
    final rewards = await loadRewards(prefs);
    setState(() {
      _children = children;
      _habits = habits;
      _deductions = deductions;
      _rewards = rewards;
      _loaded = true;
    });
  }

  // 儲存小孩清單
  Future<void> _saveChildren() async {
    final encoded = jsonEncode(_children.map((c) => c.toJson()).toList());
    await _prefs?.setString(PrefsKeys.children, encoded);
    _changed = true;
  }

  // 新增小孩
  Future<void> _addChild() async {
    final inputs = await showAddChildrenSheet(context);
    if (inputs == null || inputs.isEmpty || !mounted) return;
    final prefs = _prefs!;
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
    await _saveChildren();
    await saveHabits(prefs, habits);
    await _loadAll();
  }

  // 刪除小孩（含二次確認，同步刪除習慣、扣分項目、積分紀錄）
  Future<void> _deleteChild(int index) async {
    final childName = _children[index].name;
    final childId = _children[index].id;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(_l10n.pmDeleteChildTitle),
        content: Text(_l10n.pmDeleteChildMessage(childName)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              _l10n.commonCancel,
              style: TextStyle(color: AppInk.soft),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              _l10n.pmDeleteConfirm,
              style: const TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    _children.removeAt(index);
    await _saveChildren();

    // 同步刪除相關習慣、扣分項目、積分紀錄、兌換紀錄
    final prefs = _prefs!;
    final habits = await loadHabits(prefs);
    await saveHabits(prefs, habits.where((h) => h.childId != childId).toList());
    final deductions = await loadDeductions(prefs);
    await saveDeductions(
      prefs,
      deductions.where((d) => d.childId != childId).toList(),
    );
    final records = await loadRecords(prefs);
    await saveRecords(
      prefs,
      records.where((r) => r.childId != childId).toList(),
    );
    // 獎勵：移除該小孩；若某獎勵所有小孩都被移除則刪除整個獎勵
    final rewards = await loadRewards(prefs);
    for (final r in rewards) {
      r.childIds.remove(childId);
    }
    await saveRewards(
      prefs,
      rewards.where((r) => r.childIds.isNotEmpty).toList(),
    );
    // 票券紀錄
    final vouchers = await loadVouchers(prefs);
    await saveVouchers(
      prefs,
      vouchers.where((l) => l.childId != childId).toList(),
    );

    await _loadAll();
  }

  // 清空指定小孩的所有歷史資料（積分歸零、紀錄與票券清除、習慣完成日期清空）
  Future<void> _clearChildData(int index) async {
    final child = _children[index];
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_l10n.pmClearDataTitle(child.name)),
        content: Text(_l10n.pmClearDataMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              _l10n.commonCancel,
              style: TextStyle(color: AppInk.soft),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              _l10n.pmClearDataConfirm,
              style: const TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final prefs = _prefs!;
    final childId = child.id;

    _children[index].points = 0;
    await _saveChildren();

    final records = await loadRecords(prefs);
    await saveRecords(
      prefs,
      records.where((r) => r.childId != childId).toList(),
    );

    final vouchers = await loadVouchers(prefs);
    await saveVouchers(
      prefs,
      vouchers.where((v) => v.childId != childId).toList(),
    );

    final habits = await loadHabits(prefs);
    for (final h in habits) {
      if (h.childId == childId) {
        h.completedDate = '';
        h.weeklyDates.clear();
      }
    }
    await saveHabits(prefs, habits);

    await _loadAll();
  }

  // ── 修改小孩名稱 ──
  Future<void> _editChildName(int index) async {
    final child = _children[index];
    final nameCtrl = TextEditingController(text: child.name);
    var selectedAvatar = child.avatar;

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: Text(_l10n.pmEditChildTitle),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              GestureDetector(
                onTap: () async {
                  final picked = await showAvatarPickerDialog(
                    ctx,
                    selectedAvatar,
                  );
                  if (picked != null) setS(() => selectedAvatar = picked);
                },
                child: CircleAvatar(
                  radius: 32,
                  backgroundColor: AppSurfaces.fill,
                  child: Text(
                    selectedAvatar,
                    style: const TextStyle(fontSize: 32),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _l10n.pmTapToChangeAvatar,
                style: TextStyle(fontSize: 11, color: AppInk.soft),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: nameCtrl,
                autofocus: true,
                decoration: InputDecoration(labelText: _l10n.pmChildNameLabel),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(
                _l10n.commonCancel,
                style: TextStyle(color: AppInk.soft),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(_l10n.commonSave),
            ),
          ],
        ),
      ),
    );

    if (result != true) return;
    final name = nameCtrl.text.trim();
    if (name.isEmpty) return;

    _children[index].name = name;
    _children[index].avatar = selectedAvatar;
    await _saveChildren();
    _changed = true;
    setState(() {});
  }

  // ── 新增習慣 ──
  Future<void> _addHabit() async {
    if (_children.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_l10n.pmNeedChildFirst)));
      return;
    }
    await showAddHabitSheet(
      context,
      prefs: _prefs!,
      children: _children,
      existingHabits: _habits,
      onSaved: () async {
        _changed = true;
        await _loadAll();
      },
    );
  }

  // ── 刪除習慣 ──
  Future<void> _deleteHabit(ChildHabit habit) async {
    final prefs = _prefs!;
    final habits = await loadHabits(prefs);
    habits.removeWhere((h) => h.id == habit.id);
    await saveHabits(prefs, habits);
    _changed = true;
    await _loadAll();
  }

  // ── 編輯習慣 ──
  Future<void> _editHabit(ChildHabit habit) async {
    await showEditHabitSheet(
      context,
      prefs: _prefs!,
      habit: habit,
      onSaved: () async {
        _changed = true;
        if (mounted) await _loadAll();
      },
    );
  }

  // ── 新增扣分項目 ──
  Future<void> _addDeduction() async {
    if (_children.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_l10n.pmNeedChildFirst)));
      return;
    }
    await showAddDeductionSheet(
      context,
      prefs: _prefs!,
      children: _children,
      existingDeductions: _deductions,
      onSaved: () async {
        _changed = true;
        await _loadAll();
      },
    );
  }

  // ── 刪除扣分項目 ──
  Future<void> _deleteDeduction(DeductionItem item) async {
    final prefs = _prefs!;
    final deductions = await loadDeductions(prefs);
    deductions.removeWhere((d) => d.id == item.id);
    await saveDeductions(prefs, deductions);
    _changed = true;
    await _loadAll();
  }

  // ── 編輯扣分項目 ──
  Future<void> _editDeduction(DeductionItem item) async {
    await showEditDeductionSheet(
      context,
      prefs: _prefs!,
      item: item,
      onSaved: () async {
        _changed = true;
        if (mounted) await _loadAll();
      },
    );
  }

  // ── 新增獎勵 ──
  Future<void> _addReward() async {
    if (_children.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_l10n.pmNeedChildFirst)));
      return;
    }
    await showAddRewardSheet(
      context,
      prefs: _prefs!,
      children: _children,
      existingRewards: _rewards,
      onSaved: () async {
        _changed = true;
        await _loadAll();
      },
    );
  }

  // ── 刪除獎勵 ──
  Future<void> _deleteReward(RewardItem reward) async {
    final prefs = _prefs!;
    final rewards = await loadRewards(prefs);
    rewards.removeWhere((r) => r.id == reward.id);
    await saveRewards(prefs, rewards);
    _changed = true;
    await _loadAll();
  }

  // ── 編輯獎勵 ──
  Future<void> _editReward(RewardItem reward) async {
    await showEditRewardSheet(
      context,
      prefs: _prefs!,
      reward: reward,
      children: _children,
      onSaved: () async {
        _changed = true;
        if (mounted) await _loadAll();
      },
    );
  }

  // ── 共用刪除確認 ──
  Future<void> _confirmDelete({
    required String title,
    required String name,
    required Future<void> Function() onConfirm,
  }) async {
    if (!mounted) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: Text(_l10n.pmDeleteNamedMessage(name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              _l10n.commonCancel,
              style: TextStyle(color: AppInk.soft),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              _l10n.commonDelete,
              style: const TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
    if (confirm == true) await onConfirm();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // 攔截系統返回，確保無論哪種返回方式都能帶回 _changed
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop(_changed);
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFFFFBF7),
        appBar: AppBar(
          title: Text(
            _l10n.famParentManage,
            style: const TextStyle(
              color: AppInk.strong,
              fontWeight: FontWeight.w800,
            ),
          ),
          centerTitle: true,
          backgroundColor: const Color(0xFFFFFBF7),
          foregroundColor: AppInk.strong,
          elevation: 0,
          scrolledUnderElevation: 0,
          surfaceTintColor: Colors.transparent,
          leading: IconButton(
            // M3 IconButton 不吃 AppBar iconTheme，會用淺灰 onSurfaceVariant
            // 導致返回鍵淡到看不見，明確指定深色。
            color: AppInk.strong,
            icon: const Icon(Icons.arrow_back_ios_new_rounded),
            tooltip: _l10n.commonBack,
            onPressed: () => Navigator.of(context).pop(_changed),
          ),
          actions: [
            IconButton(
              color: AppInk.strong,
              icon: const Icon(Icons.person_add_alt_1_rounded),
              tooltip: _l10n.famAddChild,
              onPressed: _addChild,
            ),
          ],
        ),
        body: !_loaded
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  if (widget.noPinWarning && !_pinWarnDismissed)
                    _buildPinWarningBanner(),
                  Expanded(
                    child: _children.isEmpty ? _buildEmpty() : _buildContent(),
                  ),
                ],
              ),
      ),
    );
  }

  // 尚未設定密碼時的頁內橫幅（可「去設定」或「關閉」）。
  // 原本用 6 秒 SnackBar，會出現黏住不消失的情況，改成可控的頁內提示。
  Widget _buildPinWarningBanner() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF3E0),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.orange.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Icon(
            Icons.lock_open_rounded,
            color: Colors.orange.shade700,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _l10n.pmNoPinWarning,
              style: const TextStyle(
                fontSize: 13,
                height: 1.35,
                fontWeight: FontWeight.w600,
                color: Color(0xFF6F4A1F),
              ),
            ),
          ),
          TextButton(
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              minimumSize: const Size(0, 36),
            ),
            onPressed: () async {
              await Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) =>
                      const SettingsPage(openPinSettingsOnLoad: true),
                ),
              );
              // 設定完回來：若已設密碼就把橫幅收掉
              if (!mounted || _prefs == null) return;
              final hasPin = await ParentPin.hasPin(_prefs!);
              if (mounted && hasPin) setState(() => _pinWarnDismissed = true);
            },
            child: Text(
              _l10n.pmGoToSettings,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
          IconButton(
            tooltip: _l10n.commonClose,
            visualDensity: VisualDensity.compact,
            onPressed: () => setState(() => _pinWarnDismissed = true),
            icon: Icon(
              Icons.close_rounded,
              size: 18,
              color: Colors.orange.shade700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty() {
    final accent = Colors.orange.shade700;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 32),
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
          child: FamilyEmptyInvite(accent: accent, onAdd: _addChild),
        ),
      ),
    );
  }

  Widget _buildOverview() {
    final assignedRewards = _rewards
        .where((reward) => reward.childIds.isNotEmpty)
        .length;
    return Container(
      margin: const EdgeInsets.only(bottom: 18),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(AppCardStyle.radius),
        border: AppCardStyle.hairline,
        boxShadow: AppShadows.flat,
      ),
      child: Row(
        children: [
          _overviewStat(
            icon: Icons.child_care_rounded,
            label: _l10n.pmTabChildren,
            value: '${_children.length}',
            color: Colors.orange.shade700,
          ),
          _overviewDivider(),
          _overviewStat(
            icon: Icons.check_circle_outline,
            label: _l10n.pmTabHabits,
            value: '${_habits.length}',
            color: Colors.green.shade700,
          ),
          _overviewDivider(),
          _overviewStat(
            icon: Icons.remove_circle_outline,
            label: _l10n.pmTabDeductions,
            value: '${_deductions.length}',
            color: Colors.red.shade600,
          ),
          _overviewDivider(),
          _overviewStat(
            icon: Icons.card_giftcard_outlined,
            label: _l10n.pmTabRewards,
            value: '$assignedRewards',
            color: Colors.amber.shade800,
          ),
        ],
      ),
    );
  }

  Widget _overviewDivider() {
    return Container(
      width: 1,
      height: 36,
      margin: const EdgeInsets.symmetric(horizontal: 10),
      color: const Color(0x0F000000),
    );
  }

  Widget _overviewStat({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Expanded(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(height: 4),
          Text(
            value,
            style: AppType.digits(
              color: AppInk.strong,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          Text(
            label,
            style: const TextStyle(
              color: AppInk.soft,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
      children: [
        _buildOverview(),

        // ── 小孩管理區塊 ──
        _sectionTitle(
          _l10n.pmChildrenSection,
          Icons.child_care_rounded,
          Colors.orange,
          trailing: _l10n.pmCountChildren(_children.length),
        ),
        ..._children.asMap().entries.map((entry) {
          final i = entry.key;
          final child = entry.value;
          return _buildChildCard(child, i);
        }),
        _addButton(
          _l10n.famAddChild,
          Icons.person_add_alt_1_rounded,
          Colors.orange,
          _addChild,
        ),

        const SizedBox(height: 24),

        // ── 習慣管理區塊 ──
        _sectionTitle(
          _l10n.pmHabitsSection,
          Icons.check_circle_outline,
          Colors.green,
          trailing: _l10n.pmCountItems(_habits.length),
        ),
        const SizedBox(height: 8),
        ..._buildHabitSection(),
        _addButton(_l10n.pmAddHabit, Icons.add, Colors.green, _addHabit),

        const SizedBox(height: 24),

        // ── 扣分項目區塊 ──
        _sectionTitle(
          _l10n.pmDeductionsSection,
          Icons.remove_circle_outline,
          Colors.red,
          trailing: _l10n.pmCountItems(_deductions.length),
        ),
        const SizedBox(height: 8),
        ..._buildDeductionSection(),
        _addButton(_l10n.pmAddDeduction, Icons.add, Colors.red, _addDeduction),

        const SizedBox(height: 24),

        // ── 獎勵管理區塊 ──
        _sectionTitle(
          _l10n.pmRewardsSection,
          Icons.card_giftcard_outlined,
          Colors.amber.shade700,
          trailing: _l10n.pmCountItems(_rewards.length),
        ),
        const SizedBox(height: 8),
        ..._buildRewardSection(),
        _addButton(
          _l10n.pmAddReward,
          Icons.add,
          Colors.amber.shade700,
          _addReward,
        ),
      ],
    );
  }

  // 區塊標題
  Widget _sectionTitle(
    String title,
    IconData icon,
    Color color, {
    String? trailing,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 17, color: color),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: AppInk.strong,
              ),
            ),
          ),
          if (trailing != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                trailing,
                style: TextStyle(
                  color: color,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
        ],
      ),
    );
  }

  // 新增按鈕
  Widget _addButton(
    String label,
    IconData icon,
    Color color,
    VoidCallback onTap,
  ) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 16),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        foregroundColor: color,
        backgroundColor: Colors.white.withValues(alpha: 0.82),
        side: BorderSide(color: color.withValues(alpha: 0.28)),
        padding: const EdgeInsets.symmetric(vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontWeight: FontWeight.w800),
      ),
    );
  }

  // 小孩卡片（含名稱、積分、重置、刪除）
  Widget _buildChildCard(ChildData child, int index) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(AppCardStyle.radius),
        border: AppCardStyle.hairline,
        boxShadow: AppShadows.flat,
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: AppSurfaces.fill,
                  child: Text(
                    child.avatar.isNotEmpty ? child.avatar : '🐼',
                    style: const TextStyle(fontSize: 20),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        child.name,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: AppInk.strong,
                        ),
                      ),
                      Text(
                        _l10n.chPoints(child.points),
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppInk.soft,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.edit_outlined, color: AppInk.soft),
                  tooltip: _l10n.pmRenameTooltip,
                  onPressed: () => _editChildName(index),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                  tooltip: _l10n.commonDelete,
                  onPressed: () => _deleteChild(index),
                ),
              ],
            ),
            const Divider(height: 16, thickness: 1),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () => _clearChildData(index),
                icon: Icon(
                  Icons.cleaning_services_outlined,
                  size: 14,
                  color: Colors.red.shade400,
                ),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                label: Text(
                  _l10n.pmClearData,
                  style: TextStyle(fontSize: 12, color: Colors.red.shade400),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 習慣列表（依小孩分組，右滑刪除）
  List<Widget> _buildHabitSection() {
    if (_habits.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            _l10n.pmNoHabits,
            style: TextStyle(color: AppInk.faint, fontSize: 13),
          ),
        ),
      ];
    }

    // 依小孩分組
    final grouped = <String, List<ChildHabit>>{};
    for (final h in _habits) {
      grouped.putIfAbsent(h.childId, () => []).add(h);
    }

    final widgets = <Widget>[];
    for (final child in _children) {
      final habits = grouped[child.id] ?? [];
      if (habits.isEmpty) continue;

      widgets.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 4, top: 4),
          child: Text(
            child.name,
            style: TextStyle(
              fontSize: 13,
              color: AppInk.soft,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      );

      for (final habit in habits) {
        widgets.add(
          Card(
            key: ValueKey(habit.id),
            elevation: 0,
            color: Colors.white.withValues(alpha: 0.94),
            margin: const EdgeInsets.only(bottom: 6),
            shape: RoundedRectangleBorder(
              side: const BorderSide(color: Color(0x0A46342B)),
              borderRadius: BorderRadius.circular(12),
            ),
            child: ListTile(
              dense: true,
              title: Text(habit.name, style: const TextStyle(fontSize: 14)),
              subtitle: Text(
                '${_l10n.pmHabitPoints(habit.points)} · '
                '${habit.frequency == 'weekly' ? _l10n.pmHabitWeeklyTimes(habit.weeklyTarget) : _l10n.pmHabitDaily}'
                '${habit.minutes > 0 ? _l10n.pmHabitMinutesSuffix(habit.minutes) : ''}',
                style: TextStyle(fontSize: 12, color: Colors.green.shade700),
              ),
              trailing: PopupMenuButton<String>(
                icon: Icon(Icons.more_vert, size: 20, color: AppInk.faint),
                itemBuilder: (_) => [
                  PopupMenuItem(value: 'edit', child: Text(_l10n.commonEdit)),
                  PopupMenuItem(
                    value: 'delete',
                    child: Text(
                      _l10n.commonDelete,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),
                ],
                onSelected: (action) {
                  if (action == 'edit') {
                    _editHabit(habit);
                  } else {
                    _confirmDelete(
                      title: _l10n.pmDeleteHabitTitle,
                      name: habit.name,
                      onConfirm: () => _deleteHabit(habit),
                    );
                  }
                },
              ),
            ),
          ),
        );
      }
    }
    return widgets;
  }

  // 扣分列表（依小孩分組，右滑刪除）
  List<Widget> _buildDeductionSection() {
    if (_deductions.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            _l10n.pmNoDeductions,
            style: TextStyle(color: AppInk.faint, fontSize: 13),
          ),
        ),
      ];
    }

    final grouped = <String, List<DeductionItem>>{};
    for (final d in _deductions) {
      grouped.putIfAbsent(d.childId, () => []).add(d);
    }

    final widgets = <Widget>[];
    for (final child in _children) {
      final items = grouped[child.id] ?? [];
      if (items.isEmpty) continue;

      widgets.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 4, top: 4),
          child: Text(
            child.name,
            style: TextStyle(
              fontSize: 13,
              color: AppInk.soft,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      );

      for (final item in items) {
        widgets.add(
          Card(
            key: ValueKey(item.id),
            elevation: 0,
            color: Colors.white.withValues(alpha: 0.94),
            margin: const EdgeInsets.only(bottom: 6),
            shape: RoundedRectangleBorder(
              side: const BorderSide(color: Color(0x0A46342B)),
              borderRadius: BorderRadius.circular(12),
            ),
            child: ListTile(
              dense: true,
              title: Text(item.name, style: const TextStyle(fontSize: 14)),
              subtitle: Text(
                _l10n.pmDeductionPoints(item.points),
                style: const TextStyle(fontSize: 12, color: Colors.red),
              ),
              trailing: PopupMenuButton<String>(
                icon: Icon(Icons.more_vert, size: 20, color: AppInk.faint),
                itemBuilder: (_) => [
                  PopupMenuItem(value: 'edit', child: Text(_l10n.commonEdit)),
                  PopupMenuItem(
                    value: 'delete',
                    child: Text(
                      _l10n.commonDelete,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),
                ],
                onSelected: (action) {
                  if (action == 'edit') {
                    _editDeduction(item);
                  } else {
                    _confirmDelete(
                      title: _l10n.pmDeleteDeductionTitle,
                      name: item.name,
                      onConfirm: () => _deleteDeduction(item),
                    );
                  }
                },
              ),
            ),
          ),
        );
      }
    }
    return widgets;
  }

  // 獎勵列表（右滑刪除）
  List<Widget> _buildRewardSection() {
    if (_rewards.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            _l10n.pmNoRewards,
            style: TextStyle(color: AppInk.faint, fontSize: 13),
          ),
        ),
      ];
    }

    final amber = Colors.amber.shade700;
    return _rewards.map((reward) {
      final childNames = _children
          .where((c) => reward.childIds.contains(c.id))
          .map((c) => c.name)
          .join('、');

      return Card(
        key: ValueKey(reward.id),
        elevation: 0,
        color: Colors.white.withValues(alpha: 0.94),
        margin: const EdgeInsets.only(bottom: 6),
        shape: RoundedRectangleBorder(
          side: const BorderSide(color: Color(0x0A46342B)),
          borderRadius: BorderRadius.circular(12),
        ),
        child: ListTile(
          dense: true,
          leading: Icon(Icons.card_giftcard_outlined, color: amber, size: 20),
          title: Text(reward.name, style: const TextStyle(fontSize: 14)),
          subtitle: Text(
            [
              _l10n.pmRewardCost(reward.pointsCost),
              if (childNames.isNotEmpty) childNames,
            ].join(' · '),
            style: TextStyle(fontSize: 11, color: AppInk.soft),
          ),
          trailing: PopupMenuButton<String>(
            icon: Icon(Icons.more_vert, size: 20, color: AppInk.faint),
            itemBuilder: (_) => [
              PopupMenuItem(value: 'edit', child: Text(_l10n.commonEdit)),
              PopupMenuItem(
                value: 'delete',
                child: Text(
                  _l10n.commonDelete,
                  style: const TextStyle(color: Colors.red),
                ),
              ),
            ],
            onSelected: (action) {
              if (action == 'edit') {
                _editReward(reward);
              } else {
                _confirmDelete(
                  title: _l10n.pmDeleteRewardTitle,
                  name: reward.name,
                  onConfirm: () => _deleteReward(reward),
                );
              }
            },
          ),
        ),
      );
    }).toList();
  }
}
