// 育兒模式主頁面
// 包含：小孩選擇畫面、小孩主頁（三 Tab）、家長管理頁面、密碼驗證
// 修改2段：習慣系統、積分系統、扣分項目、家長 Session
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'settings_page.dart';

// ── 家長 Session（全域）──
// 驗證密碼成功後設為 true；切換離開家庭頁籤時設為 false
bool parentSessionActive = false;

// ── 資料模型 ──

class ChildData {
  final String id;
  String name;
  int points;
  String resetMode; // 'none' | 'weekly' | 'monthly' | 'manual'

  ChildData({
    required this.id,
    required this.name,
    required this.points,
    required this.resetMode,
  });

  factory ChildData.fromJson(Map<String, dynamic> json) => ChildData(
        id: json['id'] as String,
        name: json['name'] as String,
        points: (json['points'] as int?) ?? 0,
        resetMode: (json['reset_mode'] as String?) ?? 'none',
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'points': points,
        'reset_mode': resetMode,
      };
}

// 小孩習慣
class ChildHabit {
  final String id;
  final String childId;
  String name;
  int points; // 完成可得積分
  String completedDate; // 最後打卡日期，格式 yyyy-MM-dd；空字串表示尚未打卡

  ChildHabit({
    required this.id,
    required this.childId,
    required this.name,
    required this.points,
    this.completedDate = '',
  });

  factory ChildHabit.fromJson(Map<String, dynamic> json) => ChildHabit(
        id: json['id'] as String,
        childId: json['child_id'] as String,
        name: json['name'] as String,
        points: (json['points'] as int?) ?? 0,
        completedDate: (json['completed_date'] as String?) ?? '',
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'child_id': childId,
        'name': name,
        'points': points,
        'completed_date': completedDate,
      };
}

// 扣分項目
class DeductionItem {
  final String id;
  final String childId;
  String name;
  int points; // 扣幾分（正整數，扣分時取負）
  String deductedDate; // 最後扣分日期，格式 yyyy-MM-dd；空字串表示今日未扣

  DeductionItem({
    required this.id,
    required this.childId,
    required this.name,
    required this.points,
    this.deductedDate = '',
  });

  factory DeductionItem.fromJson(Map<String, dynamic> json) => DeductionItem(
        id: json['id'] as String,
        childId: json['child_id'] as String,
        name: json['name'] as String,
        points: (json['points'] as int?) ?? 0,
        deductedDate: (json['deducted_date'] as String?) ?? '',
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'child_id': childId,
        'name': name,
        'points': points,
        'deducted_date': deductedDate,
      };
}

// 積分紀錄
class PointRecord {
  final String id;
  final String childId;
  final String time; // 格式 yyyy-MM-dd HH:mm
  final String reason;
  final int delta; // 正數加分、負數扣分
  final int total; // 變動後累積總分

  PointRecord({
    required this.id,
    required this.childId,
    required this.time,
    required this.reason,
    required this.delta,
    required this.total,
  });

  factory PointRecord.fromJson(Map<String, dynamic> json) => PointRecord(
        id: json['id'] as String,
        childId: json['child_id'] as String,
        time: json['time'] as String,
        reason: json['reason'] as String,
        delta: (json['delta'] as int?) ?? 0,
        total: (json['total'] as int?) ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'child_id': childId,
        'time': time,
        'reason': reason,
        'delta': delta,
        'total': total,
      };
}

// 積分重置模式的顯示文字
const Map<String, String> _resetModeLabels = {
  'none': '不重置',
  'weekly': '每週一',
  'monthly': '每月1號',
  'manual': '手動重置',
};

// 今日日期字串（yyyy-MM-dd）
String _todayStr() {
  final now = DateTime.now();
  return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
}

// 產生唯一 ID（毫秒時間戳 + 隨機後綴，避免同毫秒碰撞）
String _genId() =>
    '${DateTime.now().millisecondsSinceEpoch}_${Object().hashCode}';

// 格式化現在時間為 yyyy-MM-dd HH:mm
String _nowStr() {
  final now = DateTime.now();
  final date =
      '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  final time =
      '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
  return '$date $time';
}

// ── 共用：讀寫各類資料的輔助方法 ──

Future<List<ChildHabit>> _loadHabits(SharedPreferences prefs) async {
  final raw = prefs.getString('child_habits');
  if (raw == null) return [];
  return (jsonDecode(raw) as List)
      .map((e) => ChildHabit.fromJson(e as Map<String, dynamic>))
      .toList();
}

Future<void> _saveHabits(
    SharedPreferences prefs, List<ChildHabit> habits) async {
  await prefs.setString(
      'child_habits', jsonEncode(habits.map((h) => h.toJson()).toList()));
}

Future<List<DeductionItem>> _loadDeductions(SharedPreferences prefs) async {
  final raw = prefs.getString('deduction_items');
  if (raw == null) return [];
  return (jsonDecode(raw) as List)
      .map((e) => DeductionItem.fromJson(e as Map<String, dynamic>))
      .toList();
}

Future<void> _saveDeductions(
    SharedPreferences prefs, List<DeductionItem> items) async {
  await prefs.setString(
      'deduction_items', jsonEncode(items.map((d) => d.toJson()).toList()));
}

Future<List<PointRecord>> _loadRecords(SharedPreferences prefs) async {
  final raw = prefs.getString('point_records');
  if (raw == null) return [];
  return (jsonDecode(raw) as List)
      .map((e) => PointRecord.fromJson(e as Map<String, dynamic>))
      .toList();
}

Future<void> _saveRecords(
    SharedPreferences prefs, List<PointRecord> records) async {
  await prefs.setString(
      'point_records', jsonEncode(records.map((r) => r.toJson()).toList()));
}

// 更新小孩積分並寫入積分紀錄；回傳更新後積分
// delta 可為正（加分）或負（扣分），扣分不會低於 0
Future<int> _applyPoints({
  required SharedPreferences prefs,
  required ChildData child,
  required int delta,
  required String reason,
}) async {
  // 讀取最新小孩清單
  final raw = prefs.getString('children');
  final children = raw == null
      ? <ChildData>[]
      : (jsonDecode(raw) as List)
          .map((e) => ChildData.fromJson(e as Map<String, dynamic>))
          .toList();

  // 找到對應小孩並更新積分
  final idx = children.indexWhere((c) => c.id == child.id);
  if (idx == -1) return child.points;

  int newPoints = children[idx].points + delta;
  if (newPoints < 0) newPoints = 0; // 積分不能為負
  children[idx].points = newPoints;
  child.points = newPoints; // 同步更新傳入的物件

  await prefs.setString(
      'children', jsonEncode(children.map((c) => c.toJson()).toList()));

  // 寫入積分紀錄
  final records = await _loadRecords(prefs);
  records.insert(
    0,
    PointRecord(
      id: _genId(),
      childId: child.id,
      time: _nowStr(),
      reason: reason,
      delta: delta < 0 ? -(children[idx].points - newPoints).abs() : delta,
      total: newPoints,
    ),
  );
  await _saveRecords(prefs, records);

  return newPoints;
}

// ── 密碼輸入對話框（供本檔案內部使用）──
// 回傳使用者輸入的字串；取消回傳 null
Future<String?> _showPinDialog(
  BuildContext context, {
  required int digits,
  required String title,
}) async {
  final controller = TextEditingController();
  bool obscure = true;
  return showDialog<String>(
    context: context,
    builder: (dialogCtx) => StatefulBuilder(
      builder: (_, setS) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          obscureText: obscure,
          maxLength: digits,
          autofocus: true,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(
            hintText: '請輸入 $digits 位數字密碼',
            counterText: '',
            suffixIcon: IconButton(
              icon: Icon(obscure ? Icons.visibility_off : Icons.visibility),
              onPressed: () => setS(() => obscure = !obscure),
            ),
          ),
          onChanged: (v) {
            if (v.length == digits) Navigator.pop(dialogCtx, v);
          },
          onSubmitted: (v) => Navigator.pop(dialogCtx, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: Text('取消', style: TextStyle(color: Colors.grey.shade600)),
          ),
        ],
      ),
    ),
  );
}

// 驗證家長密碼（Session 有效或未設密碼時直接通過）
Future<bool> _verifyParentPinIfNeeded(BuildContext context) async {
  if (parentSessionActive) return true;
  final prefs = await SharedPreferences.getInstance();
  final savedPin = prefs.getString('parent_pin');
  if (savedPin == null || savedPin.isEmpty) return true;
  if (!context.mounted) return false;
  final digits = prefs.getInt('pin_digits') ?? 4;
  final entered = await _showPinDialog(
    context,
    digits: digits,
    title: '請輸入家長密碼以撤銷',
  );
  if (!context.mounted) return false;
  if (entered == null) return false;
  if (entered == savedPin) return true;
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(content: Text('密碼錯誤')),
  );
  return false;
}

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

  @override
  void initState() {
    super.initState();
    _loadChildren();
  }

  // 從 SharedPreferences 讀取小孩清單
  Future<void> _loadChildren() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('children');
    setState(() {
      _children = raw == null
          ? []
          : (jsonDecode(raw) as List)
              .map((e) => ChildData.fromJson(e as Map<String, dynamic>))
              .toList();
      _loaded = true;
    });
  }

  // 點擊「家長管理」：有 Session 直接進入，否則驗證密碼
  Future<void> _enterParentManagement() async {
    final prefs = await SharedPreferences.getInstance();
    final savedPin = prefs.getString('parent_pin');
    if (!mounted) return;

    if (parentSessionActive || savedPin == null || savedPin.isEmpty) {
      // Session 有效或尚未設定密碼，直接進入
      final changed = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => ParentManagementPage(
            noPinWarning: savedPin == null || savedPin.isEmpty,
          ),
        ),
      );
      if (changed == true) _loadChildren();
    } else {
      // 需要輸入密碼才能進入
      final digits = prefs.getInt('pin_digits') ?? 4;
      final entered = await _showPinDialog(
        context,
        digits: digits,
        title: '請輸入家長密碼',
      );
      if (!mounted) return;
      if (entered == savedPin) {
        // 驗證成功，啟動 Session
        parentSessionActive = true;
        final changed = await Navigator.of(context).push<bool>(
          MaterialPageRoute(
            builder: (_) =>
                const ParentManagementPage(noPinWarning: false),
          ),
        );
        if (changed == true) _loadChildren();
      } else if (entered != null) {
        // 輸入了內容但不正確
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('密碼錯誤，請再試一次')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('家庭'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: '設定',
            onPressed: () async {
              await Navigator.of(context).push(
                PageRouteBuilder(
                  pageBuilder: (context, animation, secondaryAnimation) =>
                      const SettingsPage(),
                  transitionsBuilder:
                      (context, animation, secondaryAnimation, child) {
                    const begin = Offset(1.0, 0.0);
                    const end = Offset.zero;
                    final tween = Tween(begin: begin, end: end)
                        .chain(CurveTween(curve: Curves.easeInOut));
                    return SlideTransition(
                      position: animation.drive(tween),
                      child: child,
                    );
                  },
                ),
              );
              widget.onSettingsChanged?.call();
              _loadChildren();
            },
          ),
        ],
      ),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : _children.isEmpty
              ? _buildEmpty()
              : _buildChildList(),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _enterParentManagement,
        icon: const Icon(Icons.lock_outline),
        label: const Text('家長管理'),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
      ),
    );
  }

  // 尚無小孩時的空狀態
  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.child_care, size: 72, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Text(
            '還沒有小孩，請家長先新增',
            style: TextStyle(fontSize: 16, color: Colors.grey.shade500),
          ),
        ],
      ),
    );
  }

  // 小孩卡片清單
  Widget _buildChildList() {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      itemCount: _children.length,
      itemBuilder: (_, i) {
        final child = _children[i];
        return _ChildCard(
          child: child,
          onTap: () async {
            // 進入小孩主頁後，回來重新載入（積分等可能異動）
            await Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => _ChildHomePage(
                  children: _children,
                  initialIndex: i,
                ),
              ),
            );
            widget.onSettingsChanged?.call();
            _loadChildren();
          },
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
    final primary = Theme.of(context).colorScheme.primary;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 2,
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        leading: CircleAvatar(
          radius: 24,
          backgroundColor: primary.withValues(alpha: 0.12),
          child: Text(
            child.name.isNotEmpty ? child.name[0] : '?',
            style: TextStyle(
              fontSize: 20,
              color: primary,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        title: Text(
          child.name,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          '積分：${child.points}',
          style: TextStyle(color: Colors.grey.shade600),
        ),
        trailing: Icon(Icons.chevron_right, color: Colors.grey.shade400),
        onTap: onTap,
      ),
    );
  }
}

// ── 小孩主頁（三個 Tab）──

class _ChildHomePage extends StatefulWidget {
  final List<ChildData> children;
  final int initialIndex;

  const _ChildHomePage({
    required this.children,
    required this.initialIndex,
  });

  @override
  State<_ChildHomePage> createState() => _ChildHomePageState();
}

class _ChildHomePageState extends State<_ChildHomePage> {
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
    showModalBottomSheet(
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
                style:
                    TextStyle(color: primary, fontWeight: FontWeight.bold),
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
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
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
                PageRouteBuilder(
                  pageBuilder: (context, animation, secondaryAnimation) =>
                      const SettingsPage(),
                  transitionsBuilder:
                      (context, animation, secondaryAnimation, child) {
                    const begin = Offset(1.0, 0.0);
                    const end = Offset.zero;
                    final tween = Tween(begin: begin, end: end)
                        .chain(CurveTween(curve: Curves.easeInOut));
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
            _HabitTab(child: _current, onPointsChanged: _onPointsChanged),
            // 積分紀錄 Tab
            _PointRecordTab(child: _current),
            // 獎勵（尚未實作）
            const _ComingSoonTab(label: '獎勵'),
          ],
        ),
      ),
    );
  }
}

// ── 習慣打卡 Tab ──

class _HabitTab extends StatefulWidget {
  final ChildData child;
  final VoidCallback onPointsChanged; // 積分異動後通知父層更新 AppBar

  const _HabitTab({required this.child, required this.onPointsChanged});

  @override
  State<_HabitTab> createState() => _HabitTabState();
}

class _HabitTabState extends State<_HabitTab> {
  List<ChildHabit> _habits = [];
  List<DeductionItem> _deductions = [];
  bool _loaded = false;
  SharedPreferences? _prefs;

  @override
  void initState() {
    super.initState();
    _load();
  }

  // 重新載入習慣與扣分項目
  Future<void> _load() async {
    _prefs = await SharedPreferences.getInstance();
    final habits = await _loadHabits(_prefs!);
    final deductions = await _loadDeductions(_prefs!);
    setState(() {
      // 只顯示此小孩的習慣與扣分項目
      _habits = habits.where((h) => h.childId == widget.child.id).toList();
      _deductions =
          deductions.where((d) => d.childId == widget.child.id).toList();
      _loaded = true;
    });
  }

  // 判斷習慣今日是否已打卡
  bool _isDoneToday(ChildHabit habit) => habit.completedDate == _todayStr();

  // 判斷扣分項目今日是否已扣
  bool _isDeductedToday(DeductionItem item) => item.deductedDate == _todayStr();

  // 打卡：增加積分、標記日期
  Future<void> _checkIn(ChildHabit habit) async {
    if (_isDoneToday(habit)) return; // 已打卡，不重複
    final prefs = _prefs!;

    final newPoints = await _applyPoints(
      prefs: prefs,
      child: widget.child,
      delta: habit.points,
      reason: '完成習慣：${habit.name}',
    );

    final allHabits = await _loadHabits(prefs);
    final idx = allHabits.indexWhere((h) => h.id == habit.id);
    if (idx != -1) {
      allHabits[idx].completedDate = _todayStr();
      await _saveHabits(prefs, allHabits);
    }

    setState(() {
      habit.completedDate = _todayStr();
      widget.child.points = newPoints;
    });
    widget.onPointsChanged();
  }

  // 撤銷打卡：需家長密碼，扣回積分並清除日期
  Future<void> _undoCheckIn(ChildHabit habit) async {
    if (!_isDoneToday(habit) || !mounted) return;
    final ok = await _verifyParentPinIfNeeded(context);
    if (!ok || !mounted) return;

    final prefs = _prefs!;
    final newPoints = await _applyPoints(
      prefs: prefs,
      child: widget.child,
      delta: -habit.points,
      reason: '撤銷打卡：${habit.name}',
    );

    final allHabits = await _loadHabits(prefs);
    final idx = allHabits.indexWhere((h) => h.id == habit.id);
    if (idx != -1) {
      allHabits[idx].completedDate = '';
      await _saveHabits(prefs, allHabits);
    }

    setState(() {
      habit.completedDate = '';
      widget.child.points = newPoints;
    });
    widget.onPointsChanged();
  }

  // 扣分：減少積分、標記日期，今日已扣則不重複
  Future<void> _deduct(DeductionItem item) async {
    if (_isDeductedToday(item)) return; // 今日已扣，不重複
    final prefs = _prefs!;
    final before = widget.child.points;
    final newPoints = await _applyPoints(
      prefs: prefs,
      child: widget.child,
      delta: -item.points,
      reason: '扣分：${item.name}',
    );

    final allDeductions = await _loadDeductions(prefs);
    final idx = allDeductions.indexWhere((d) => d.id == item.id);
    if (idx != -1) {
      allDeductions[idx].deductedDate = _todayStr();
      await _saveDeductions(prefs, allDeductions);
    }

    setState(() {
      item.deductedDate = _todayStr();
      widget.child.points = newPoints;
    });
    widget.onPointsChanged();

    if (before < item.points && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('積分不足，已扣至 0 分')),
      );
    }
  }

  // 撤銷扣分：需家長密碼，還原積分並清除日期
  Future<void> _undoDeduct(DeductionItem item) async {
    if (!_isDeductedToday(item) || !mounted) return;
    final ok = await _verifyParentPinIfNeeded(context);
    if (!ok || !mounted) return;

    final prefs = _prefs!;
    final newPoints = await _applyPoints(
      prefs: prefs,
      child: widget.child,
      delta: item.points,
      reason: '撤銷扣分：${item.name}',
    );

    final allDeductions = await _loadDeductions(prefs);
    final idx = allDeductions.indexWhere((d) => d.id == item.id);
    if (idx != -1) {
      allDeductions[idx].deductedDate = '';
      await _saveDeductions(prefs, allDeductions);
    }

    setState(() {
      item.deductedDate = '';
      widget.child.points = newPoints;
    });
    widget.onPointsChanged();
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return const Center(child: CircularProgressIndicator());
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── 習慣區塊 ──
          _sectionHeader(Icons.check_circle_outline, '今日習慣', Colors.orange),
          const SizedBox(height: 8),
          if (_habits.isEmpty)
            _emptyHint('尚無習慣，請家長至家長管理新增')
          else
            ..._habits.map((habit) => _HabitItem(
                  habit: habit,
                  doneToday: _isDoneToday(habit),
                  onCheckIn: () => _checkIn(habit),
                  onUndo: () => _undoCheckIn(habit),
                )),

          const SizedBox(height: 24),

          // ── 扣分區塊 ──
          _sectionHeader(Icons.remove_circle_outline, '扣分項目', Colors.red),
          const SizedBox(height: 8),
          if (_deductions.isEmpty)
            _emptyHint('尚無扣分項目')
          else
            ..._deductions.map((item) => _DeductionItem(
                  item: item,
                  deductedToday: _isDeductedToday(item),
                  onDeduct: () => _deduct(item),
                  onUndo: () => _undoDeduct(item),
                )),
        ],
      ),
    );
  }

  // 小節標題列
  Widget _sectionHeader(IconData icon, String title, Color color) {
    return Row(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 6),
        Text(
          title,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _emptyHint(String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Text(text,
            style: TextStyle(color: Colors.grey.shade400, fontSize: 13)),
      );
}

// 習慣列表項目
class _HabitItem extends StatelessWidget {
  final ChildHabit habit;
  final bool doneToday;
  final VoidCallback onCheckIn;
  final VoidCallback? onUndo;

  const _HabitItem({
    required this.habit,
    required this.doneToday,
    required this.onCheckIn,
    this.onUndo,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        leading: Icon(
          doneToday ? Icons.check_circle : Icons.radio_button_unchecked,
          color: doneToday ? Colors.green : Colors.grey.shade400,
          size: 28,
        ),
        title: Text(
          habit.name,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            decoration: doneToday ? TextDecoration.lineThrough : null,
            color: doneToday ? Colors.grey : Colors.black87,
          ),
        ),
        subtitle: Text(
          '+${habit.points} 分',
          style: TextStyle(
            fontSize: 12,
            color: doneToday ? Colors.grey.shade400 : Colors.orange,
          ),
        ),
        trailing: doneToday
            ? GestureDetector(
                onTap: onUndo,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('已完成',
                        style: TextStyle(
                            fontSize: 12, color: Colors.grey.shade400)),
                    Text('點擊撤銷',
                        style: TextStyle(
                            fontSize: 10, color: Colors.grey.shade300)),
                  ],
                ),
              )
            : ElevatedButton(
                onPressed: onCheckIn,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
                child: const Text('打卡', style: TextStyle(fontSize: 13)),
              ),
      ),
    );
  }
}

// 扣分列表項目
class _DeductionItem extends StatelessWidget {
  final DeductionItem item;
  final bool deductedToday;
  final VoidCallback onDeduct;
  final VoidCallback? onUndo;

  const _DeductionItem({
    required this.item,
    required this.deductedToday,
    required this.onDeduct,
    this.onUndo,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        leading: Icon(
          deductedToday
              ? Icons.remove_circle
              : Icons.remove_circle_outline,
          color: deductedToday ? Colors.red.shade200 : Colors.red,
          size: 26,
        ),
        title: Text(
          item.name,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: deductedToday ? Colors.grey : Colors.black87,
          ),
        ),
        subtitle: Text(
          '-${item.points} 分',
          style: TextStyle(
            fontSize: 12,
            color: deductedToday ? Colors.grey.shade400 : Colors.red,
          ),
        ),
        trailing: deductedToday
            ? GestureDetector(
                onTap: onUndo,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('已扣分',
                        style: TextStyle(
                            fontSize: 12, color: Colors.grey.shade400)),
                    Text('點擊撤銷',
                        style: TextStyle(
                            fontSize: 10, color: Colors.grey.shade300)),
                  ],
                ),
              )
            : OutlinedButton(
                onPressed: onDeduct,
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red,
                  side: const BorderSide(color: Colors.red),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
                child: const Text('扣分', style: TextStyle(fontSize: 13)),
              ),
      ),
    );
  }
}

// ── 積分紀錄 Tab ──

class _PointRecordTab extends StatefulWidget {
  final ChildData child;

  const _PointRecordTab({required this.child});

  @override
  State<_PointRecordTab> createState() => _PointRecordTabState();
}

class _PointRecordTabState extends State<_PointRecordTab> {
  List<PointRecord> _records = [];
  bool _loaded = false;
  String _filter = 'all'; // 'all' | 'month' | 'week'

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final all = await _loadRecords(prefs);
    setState(() {
      _records = all.where((r) => r.childId == widget.child.id).toList();
      _loaded = true;
    });
  }

  List<PointRecord> get _filtered {
    if (_filter == 'all') return _records;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return _records.where((r) {
      final dateStr = r.time.split(' ').first;
      final dt = DateTime.tryParse(dateStr);
      if (dt == null) return false;
      if (_filter == 'month') {
        return dt.year == now.year && dt.month == now.month;
      }
      // week：往前 6 天（含今天共 7 天）
      return !dt.isBefore(today.subtract(const Duration(days: 6)));
    }).toList();
  }

  Widget _filterChip(String label, String value) {
    final selected = _filter == value;
    final primary = Theme.of(context).colorScheme.primary;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => setState(() => _filter = value),
      selectedColor: primary.withValues(alpha: 0.15),
      labelStyle: TextStyle(
        color: selected ? primary : Colors.grey.shade600,
        fontWeight: selected ? FontWeight.bold : FontWeight.normal,
        fontSize: 13,
      ),
      side: BorderSide(
        color: selected ? primary : Colors.grey.shade300,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return const Center(child: CircularProgressIndicator());
    }

    final filtered = _filtered;

    return Column(
      children: [
        // ── 篩選列 ──
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            children: [
              _filterChip('全部', 'all'),
              const SizedBox(width: 8),
              _filterChip('本月', 'month'),
              const SizedBox(width: 8),
              _filterChip('本週', 'week'),
            ],
          ),
        ),
        if (filtered.isEmpty)
          Expanded(
            child: Center(
              child: Text(
                _filter == 'all' ? '尚無積分紀錄' : '此期間無積分紀錄',
                style: TextStyle(color: Colors.grey.shade400, fontSize: 15),
              ),
            ),
          )
        else
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
              child: ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: filtered.length,
                separatorBuilder: (_, _) =>
                    const Divider(height: 1, thickness: 0.5),
                itemBuilder: (_, i) {
                  final r = filtered[i];
                  final isPlus = r.delta >= 0;
                  return ListTile(
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                    title: Text(r.reason,
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w500)),
                    subtitle: Text(r.time,
                        style: TextStyle(
                            fontSize: 12, color: Colors.grey.shade500)),
                    trailing: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '${isPlus ? '+' : ''}${r.delta} 分',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: isPlus ? Colors.green : Colors.red,
                          ),
                        ),
                        Text(
                          '共 ${r.total} 分',
                          style: TextStyle(
                              fontSize: 11, color: Colors.grey.shade400),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
      ],
    );
  }
}

// 尚未實作的 Tab 佔位畫面
class _ComingSoonTab extends StatelessWidget {
  final String label;
  const _ComingSoonTab({required this.label});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.construction, size: 52, color: Colors.grey.shade300),
          const SizedBox(height: 12),
          Text(
            '$label — 即將推出',
            style: TextStyle(fontSize: 16, color: Colors.grey.shade400),
          ),
        ],
      ),
    );
  }
}

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
    final habits = await _loadHabits(prefs);
    final deductions = await _loadDeductions(prefs);
    setState(() {
      _children = children;
      _habits = habits;
      _deductions = deductions;
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
    final nameCtrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('新增小孩'),
        content: TextField(
          controller: nameCtrl,
          autofocus: true,
          decoration: const InputDecoration(hintText: '請輸入小孩名字'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('取消', style: TextStyle(color: Colors.grey.shade600)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, nameCtrl.text.trim()),
            child: const Text('新增'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;

    final id = _genId();
    _children.add(
      ChildData(id: id, name: name, points: 0, resetMode: 'none'),
    );
    await _saveChildren();
    setState(() {});
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

    // 同步刪除相關習慣、扣分項目、積分紀錄
    final prefs = _prefs!;
    final habits = await _loadHabits(prefs);
    await _saveHabits(prefs, habits.where((h) => h.childId != childId).toList());
    final deductions = await _loadDeductions(prefs);
    await _saveDeductions(
        prefs, deductions.where((d) => d.childId != childId).toList());
    final records = await _loadRecords(prefs);
    await _saveRecords(
        prefs, records.where((r) => r.childId != childId).toList());

    await _loadAll();
  }

  // 設定積分重置模式
  Future<void> _setResetMode(int index) async {
    final current = _children[index].resetMode;
    final selected = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text('${_children[index].name} 的積分重置'),
        children: [
          RadioGroup<String>(
            groupValue: current,
            onChanged: (v) {
              if (v != null) Navigator.pop(ctx, v);
            },
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: _resetModeLabels.entries.map((e) {
                return RadioListTile<String>(
                  title: Text(e.value),
                  value: e.key,
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
    if (selected == null || selected == current) return;
    _children[index].resetMode = selected;
    await _saveChildren();
    setState(() {});
  }

  // ── 新增習慣 ──
  Future<void> _addHabit() async {
    if (_children.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('請先新增小孩')),
      );
      return;
    }

    final nameCtrl = TextEditingController();
    final pointCtrl = TextEditingController();
    // 預設勾選第一個小孩
    final Set<String> selectedIds = {_children.first.id};

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (_, setS) => AlertDialog(
          title: const Text('新增習慣'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 多選小孩
                Text('套用小孩',
                    style: TextStyle(
                        fontSize: 12, color: Colors.grey.shade600)),
                ..._children.map((c) => CheckboxListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(c.name),
                      value: selectedIds.contains(c.id),
                      onChanged: (v) => setS(() {
                        if (v == true) {
                          selectedIds.add(c.id);
                        } else {
                          selectedIds.remove(c.id);
                        }
                      }),
                    )),
                const SizedBox(height: 8),
                TextField(
                  controller: nameCtrl,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: '習慣名稱'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: pointCtrl,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(labelText: '完成可得分數'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child:
                  Text('取消', style: TextStyle(color: Colors.grey.shade600)),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('新增'),
            ),
          ],
        ),
      ),
    );

    if (result != true) return;
    final name = nameCtrl.text.trim();
    final pts = int.tryParse(pointCtrl.text.trim()) ?? 0;
    if (name.isEmpty || pts <= 0 || selectedIds.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('請至少選一個小孩，且習慣名稱不得為空、分數須大於 0')),
        );
      }
      return;
    }

    final prefs = _prefs!;
    final habits = await _loadHabits(prefs);
    for (final childId in selectedIds) {
      habits.add(ChildHabit(
        id: _genId(),
        childId: childId,
        name: name,
        points: pts,
      ));
    }
    await _saveHabits(prefs, habits);
    _changed = true;
    await _loadAll();
  }

  // ── 刪除習慣 ──
  Future<void> _deleteHabit(ChildHabit habit) async {
    final prefs = _prefs!;
    final habits = await _loadHabits(prefs);
    habits.removeWhere((h) => h.id == habit.id);
    await _saveHabits(prefs, habits);
    _changed = true;
    await _loadAll();
  }

  // ── 新增扣分項目 ──
  Future<void> _addDeduction() async {
    if (_children.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('請先新增小孩')),
      );
      return;
    }

    final nameCtrl = TextEditingController();
    final pointCtrl = TextEditingController();
    // 預設勾選第一個小孩
    final Set<String> selectedIds = {_children.first.id};

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (_, setS) => AlertDialog(
          title: const Text('新增扣分項目'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 多選小孩
                Text('套用小孩',
                    style: TextStyle(
                        fontSize: 12, color: Colors.grey.shade600)),
                ..._children.map((c) => CheckboxListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(c.name),
                      value: selectedIds.contains(c.id),
                      onChanged: (v) => setS(() {
                        if (v == true) {
                          selectedIds.add(c.id);
                        } else {
                          selectedIds.remove(c.id);
                        }
                      }),
                    )),
                const SizedBox(height: 8),
                TextField(
                  controller: nameCtrl,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: '扣分項目名稱'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: pointCtrl,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(labelText: '扣幾分'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child:
                  Text('取消', style: TextStyle(color: Colors.grey.shade600)),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('新增'),
            ),
          ],
        ),
      ),
    );

    if (result != true) return;
    final name = nameCtrl.text.trim();
    final pts = int.tryParse(pointCtrl.text.trim()) ?? 0;
    if (name.isEmpty || pts <= 0 || selectedIds.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('請至少選一個小孩，且項目名稱不得為空、扣分須大於 0')),
        );
      }
      return;
    }

    final prefs = _prefs!;
    final deductions = await _loadDeductions(prefs);
    for (final childId in selectedIds) {
      deductions.add(DeductionItem(
        id: _genId(),
        childId: childId,
        name: name,
        points: pts,
      ));
    }
    await _saveDeductions(prefs, deductions);
    _changed = true;
    await _loadAll();
  }

  // ── 刪除扣分項目 ──
  Future<void> _deleteDeduction(DeductionItem item) async {
    final prefs = _prefs!;
    final deductions = await _loadDeductions(prefs);
    deductions.removeWhere((d) => d.id == item.id);
    await _saveDeductions(prefs, deductions);
    _changed = true;
    await _loadAll();
  }

  // ── 特殊積分 ──
  Future<void> _giveSpecialPoints() async {
    if (_children.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('請先新增小孩')),
      );
      return;
    }

    final reasonCtrl = TextEditingController();
    final pointCtrl = TextEditingController();
    String selectedChildId = _children.first.id;
    bool isAdd = true; // true = 加分, false = 扣分

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (_, setS) => AlertDialog(
          title: const Text('特殊積分'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: selectedChildId,
                decoration: const InputDecoration(labelText: '選擇小孩'),
                items: _children
                    .map((c) => DropdownMenuItem(
                          value: c.id,
                          child: Text(c.name),
                        ))
                    .toList(),
                onChanged: (v) => setS(() => selectedChildId = v!),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: reasonCtrl,
                autofocus: true,
                decoration: const InputDecoration(labelText: '原因'),
              ),
              const SizedBox(height: 12),
              // 加分 / 扣分 切換
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(
                    value: true,
                    label: Text('加分'),
                    icon: Icon(Icons.add_circle_outline),
                  ),
                  ButtonSegment(
                    value: false,
                    label: Text('扣分'),
                    icon: Icon(Icons.remove_circle_outline),
                  ),
                ],
                selected: {isAdd},
                onSelectionChanged: (s) => setS(() => isAdd = s.first),
                style: SegmentedButton.styleFrom(
                  selectedBackgroundColor: isAdd
                      ? Colors.green.shade50
                      : Colors.red.shade50,
                  selectedForegroundColor: isAdd ? Colors.green : Colors.red,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: pointCtrl,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(
                  labelText: '分數',
                  prefixText: isAdd ? '+' : '-',
                  prefixStyle: TextStyle(
                    color: isAdd ? Colors.green : Colors.red,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child:
                  Text('取消', style: TextStyle(color: Colors.grey.shade600)),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('確認'),
            ),
          ],
        ),
      ),
    );

    if (result != true) return;
    final reason = reasonCtrl.text.trim();
    final pts = int.tryParse(pointCtrl.text.trim()) ?? 0;
    if (reason.isEmpty || pts <= 0) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('原因不得為空，且分數須大於 0')),
        );
      }
      return;
    }

    final delta = isAdd ? pts : -pts;

    final childIdx = _children.indexWhere((c) => c.id == selectedChildId);
    if (childIdx == -1) return;
    final child = _children[childIdx];

    final before = child.points;
    final newPoints = await _applyPoints(
      prefs: _prefs!,
      child: child,
      delta: delta,
      reason: '特殊積分：$reason',
    );

    _changed = true;
    await _loadAll();

    if (!mounted) return;
    if (delta < 0 && before + delta < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('積分不足，已扣至 0 分')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              '已給予${child.name} ${delta > 0 ? '+' : ''}$delta 分，目前共 $newPoints 分'),
        ),
      );
    }
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

        const SizedBox(height: 24),

        // ── 習慣管理區塊 ──
        _sectionTitle('習慣管理', Icons.check_circle_outline, Colors.green),
        const SizedBox(height: 8),
        ..._buildHabitSection(),
        _addButton('新增習慣', Icons.add, Colors.green, _addHabit),

        const SizedBox(height: 24),

        // ── 扣分項目區塊 ──
        _sectionTitle('扣分項目', Icons.remove_circle_outline, Colors.red),
        const SizedBox(height: 8),
        ..._buildDeductionSection(),
        _addButton('新增扣分項目', Icons.add, Colors.red, _addDeduction),

        const SizedBox(height: 24),

        // ── 特殊積分區塊 ──
        _sectionTitle('特殊積分', Icons.star_outline, Colors.purple),
        const SizedBox(height: 8),
        _addButton('給予特殊積分', Icons.star, Colors.purple, _giveSpecialPoints),
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
      String label, IconData icon, Color color, VoidCallback onTap) {
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
    final primary = Theme.of(context).colorScheme.primary;
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
                  backgroundColor: primary.withValues(alpha: 0.12),
                  child: Text(
                    child.name.isNotEmpty ? child.name[0] : '?',
                    style: TextStyle(
                        color: primary, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(child.name,
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w600)),
                      Text('積分：${child.points}',
                          style: TextStyle(
                              fontSize: 12, color: Colors.grey.shade500)),
                    ],
                  ),
                ),
                IconButton(
                  icon:
                      const Icon(Icons.delete_outline, color: Colors.red),
                  tooltip: '刪除',
                  onPressed: () => _deleteChild(index),
                ),
              ],
            ),
            const Divider(height: 20, thickness: 1),
            Row(
              children: [
                Icon(Icons.refresh, size: 16, color: Colors.grey.shade500),
                const SizedBox(width: 6),
                Text('積分重置：',
                    style: TextStyle(
                        fontSize: 13, color: Colors.grey.shade600)),
                Text(
                  _resetModeLabels[child.resetMode] ?? '不重置',
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w500),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () => _setResetMode(index),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 4),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text('修改'),
                ),
              ],
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
          child: Text('尚無習慣',
              style:
                  TextStyle(color: Colors.grey.shade400, fontSize: 13)),
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

      widgets.add(Padding(
        padding: const EdgeInsets.only(bottom: 4, top: 4),
        child: Text(child.name,
            style: TextStyle(
                fontSize: 13,
                color: Colors.grey.shade600,
                fontWeight: FontWeight.w500)),
      ));

      for (final habit in habits) {
        widgets.add(Dismissible(
          key: ValueKey(habit.id),
          direction: DismissDirection.endToStart,
          background: Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 16),
            decoration: BoxDecoration(
              color: Colors.red.shade100,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.delete_outline, color: Colors.red),
          ),
          onDismissed: (_) => _deleteHabit(habit),
          child: Card(
            margin: const EdgeInsets.only(bottom: 6),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
            child: ListTile(
              dense: true,
              title: Text(habit.name,
                  style: const TextStyle(fontSize: 14)),
              subtitle: Text('+${habit.points} 分',
                  style: TextStyle(
                      fontSize: 12, color: Colors.green.shade700)),
              trailing: Icon(Icons.drag_handle,
                  size: 18, color: Colors.grey.shade300),
            ),
          ),
        ));
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
          child: Text('尚無扣分項目',
              style:
                  TextStyle(color: Colors.grey.shade400, fontSize: 13)),
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

      widgets.add(Padding(
        padding: const EdgeInsets.only(bottom: 4, top: 4),
        child: Text(child.name,
            style: TextStyle(
                fontSize: 13,
                color: Colors.grey.shade600,
                fontWeight: FontWeight.w500)),
      ));

      for (final item in items) {
        widgets.add(Dismissible(
          key: ValueKey(item.id),
          direction: DismissDirection.endToStart,
          background: Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 16),
            decoration: BoxDecoration(
              color: Colors.red.shade100,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.delete_outline, color: Colors.red),
          ),
          onDismissed: (_) => _deleteDeduction(item),
          child: Card(
            margin: const EdgeInsets.only(bottom: 6),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
            child: ListTile(
              dense: true,
              title: Text(item.name,
                  style: const TextStyle(fontSize: 14)),
              subtitle: Text('-${item.points} 分',
                  style: const TextStyle(
                      fontSize: 12, color: Colors.red)),
              trailing: Icon(Icons.drag_handle,
                  size: 18, color: Colors.grey.shade300),
            ),
          ),
        ));
      }
    }
    return widgets;
  }
}
