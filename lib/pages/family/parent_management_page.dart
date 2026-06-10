import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'add_children_sheet.dart';
import 'deduction_sheets.dart';
import 'family_models.dart';
import 'family_store.dart';
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
  List<ChildData> _children = [];
  List<ChildHabit> _habits = [];
  List<DeductionItem> _deductions = [];
  List<RewardItem> _rewards = [];
  bool _loaded = false;
  SharedPreferences? _prefs;

  // 追蹤是否有異動，回傳給上層以決定是否重新載入
  bool _changed = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    _prefs = await SharedPreferences.getInstance();
    await _loadAll();

    // 尚未設定密碼時顯示建議提示
    if (widget.noPinWarning && mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('建議至設定頁設定密碼以保護家長管理'),
            duration: Duration(seconds: 3),
          ),
        );
      });
    }
  }

  // 一次讀取所有資料
  Future<void> _loadAll() async {
    final prefs = _prefs!;
    final raw = prefs.getString('children');
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
    await _prefs?.setString('children', encoded);
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
        title: const Text('刪除小孩'),
        content: Text('確定要刪除「$childName」嗎？所有習慣、扣分項目與積分紀錄將一起刪除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('取消', style: TextStyle(color: Colors.grey.shade600)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('確定刪除', style: TextStyle(color: Colors.red)),
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
        title: Text('清空「${child.name}」的資料'),
        content: const Text(
          '這將清除以下資料，且無法復原：\n\n'
          '• 目前積分歸零\n'
          '• 所有積分紀錄\n'
          '• 所有票券紀錄\n'
          '• 習慣的完成記錄（習慣本身保留）',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('取消', style: TextStyle(color: Colors.grey.shade600)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('確認清空', style: TextStyle(color: Colors.red)),
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
          title: const Text('編輯小孩'),
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
                  backgroundColor: Colors.grey.shade100,
                  child: Text(
                    selectedAvatar,
                    style: const TextStyle(fontSize: 32),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '點擊更換頭像',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: nameCtrl,
                autofocus: true,
                decoration: const InputDecoration(labelText: '小孩名稱'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('取消', style: TextStyle(color: Colors.grey.shade600)),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('儲存'),
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
      ).showSnackBar(const SnackBar(content: Text('請先新增小孩')));
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
      ).showSnackBar(const SnackBar(content: Text('請先新增小孩')));
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
      ).showSnackBar(const SnackBar(content: Text('請先新增小孩')));
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
        content: Text('確定要刪除「$name」嗎？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('取消', style: TextStyle(color: Colors.grey.shade600)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('刪除', style: TextStyle(color: Colors.red)),
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
        appBar: AppBar(
          title: const Text('家長管理'),
          centerTitle: true,
          leading: BackButton(
            onPressed: () => Navigator.of(context).pop(_changed),
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.person_add_outlined),
              tooltip: '新增小孩',
              onPressed: _addChild,
            ),
          ],
        ),
        body: !_loaded
            ? const Center(child: CircularProgressIndicator())
            : _children.isEmpty
            ? _buildEmpty()
            : _buildContent(),
        floatingActionButton: FloatingActionButton(
          onPressed: _addChild,
          tooltip: '新增小孩',
          child: const Icon(Icons.add),
        ),
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.child_care, size: 72, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Text(
            '尚無小孩，點擊 + 新增',
            style: TextStyle(fontSize: 16, color: Colors.grey.shade500),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
      children: [
        // ── 小孩管理區塊 ──
        _sectionTitle('小孩管理', Icons.child_care, Colors.orange),
        ..._children.asMap().entries.map((entry) {
          final i = entry.key;
          final child = entry.value;
          return _buildChildCard(child, i);
        }),
        _addButton('新增小孩', Icons.person_add_outlined, Colors.orange, _addChild),

        const SizedBox(height: 24),

        // ── 習慣管理區塊 ──
        _sectionTitle('習慣管理', Icons.check_circle_outline, Colors.green),
        const SizedBox(height: 8),
        ..._buildHabitSection(),
        _addButton('新增習慣', Icons.add, Colors.green, _addHabit),

        const SizedBox(height: 24),

        // ── 扣分項目區塊 ──
        _sectionTitle('扣分預設理由', Icons.remove_circle_outline, Colors.red),
        const SizedBox(height: 8),
        ..._buildDeductionSection(),
        _addButton('新增扣分項目', Icons.add, Colors.red, _addDeduction),

        const SizedBox(height: 24),

        // ── 獎勵管理區塊 ──
        _sectionTitle(
          '獎勵管理',
          Icons.card_giftcard_outlined,
          Colors.amber.shade700,
        ),
        const SizedBox(height: 8),
        ..._buildRewardSection(),
        _addButton('新增獎勵', Icons.add, Colors.amber.shade700, _addReward),
      ],
    );
  }

  // 區塊標題
  Widget _sectionTitle(String title, IconData icon, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Text(
            title,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: color,
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
        side: BorderSide(color: color.withValues(alpha: 0.5)),
        padding: const EdgeInsets.symmetric(vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  // 小孩卡片（含名稱、積分、重置、刪除）
  Widget _buildChildCard(ChildData child, int index) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: Colors.grey.shade100,
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
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        '積分：${child.points}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade500,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.edit_outlined, color: Colors.grey.shade500),
                  tooltip: '修改名稱',
                  onPressed: () => _editChildName(index),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                  tooltip: '刪除',
                  onPressed: () => _deleteChild(index),
                ),
              ],
            ),
            const Divider(height: 16, thickness: 1),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => _clearChildData(index),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(
                  '清空資料',
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
            '尚無習慣',
            style: TextStyle(color: Colors.grey.shade400, fontSize: 13),
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
              color: Colors.grey.shade600,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      );

      for (final habit in habits) {
        widgets.add(
          Card(
            key: ValueKey(habit.id),
            margin: const EdgeInsets.only(bottom: 6),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: ListTile(
              dense: true,
              title: Text(habit.name, style: const TextStyle(fontSize: 14)),
              subtitle: Text(
                '+${habit.points} 分 · ${habit.frequency == 'weekly' ? '每週 ${habit.weeklyTarget} 次' : '每日'}${habit.minutes > 0 ? ' · ${habit.minutes}分鐘' : ''}',
                style: TextStyle(fontSize: 12, color: Colors.green.shade700),
              ),
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
                    child: Text('刪除', style: TextStyle(color: Colors.red)),
                  ),
                ],
                onSelected: (action) {
                  if (action == 'edit') {
                    _editHabit(habit);
                  } else {
                    _confirmDelete(
                      title: '刪除習慣',
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
            '尚無扣分項目',
            style: TextStyle(color: Colors.grey.shade400, fontSize: 13),
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
              color: Colors.grey.shade600,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      );

      for (final item in items) {
        widgets.add(
          Card(
            key: ValueKey(item.id),
            margin: const EdgeInsets.only(bottom: 6),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: ListTile(
              dense: true,
              title: Text(item.name, style: const TextStyle(fontSize: 14)),
              subtitle: Text(
                '-${item.points} 分',
                style: const TextStyle(fontSize: 12, color: Colors.red),
              ),
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
                    child: Text('刪除', style: TextStyle(color: Colors.red)),
                  ),
                ],
                onSelected: (action) {
                  if (action == 'edit') {
                    _editDeduction(item);
                  } else {
                    _confirmDelete(
                      title: '刪除扣分項目',
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
            '尚無獎勵',
            style: TextStyle(color: Colors.grey.shade400, fontSize: 13),
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
        margin: const EdgeInsets.only(bottom: 6),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: ListTile(
          dense: true,
          leading: Icon(Icons.card_giftcard_outlined, color: amber, size: 20),
          title: Text(reward.name, style: const TextStyle(fontSize: 14)),
          subtitle: Text(
            [
              '${reward.pointsCost} 分',
              if (childNames.isNotEmpty) childNames,
            ].join(' · '),
            style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
          ),
          trailing: PopupMenuButton<String>(
            icon: Icon(Icons.more_vert, size: 20, color: Colors.grey.shade400),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'edit', child: Text('編輯')),
              PopupMenuItem(
                value: 'delete',
                child: Text('刪除', style: TextStyle(color: Colors.red)),
              ),
            ],
            onSelected: (action) {
              if (action == 'edit') {
                _editReward(reward);
              } else {
                _confirmDelete(
                  title: '刪除獎勵',
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
