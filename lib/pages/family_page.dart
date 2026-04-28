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

// 獎勵項目
class RewardItem {
  final String id;
  String name;
  int pointsCost;
  List<String> childIds;
  String limitType; // 'none' | 'daily' | 'weekly'（使用次數上限）
  int limitCount;
  String expiryType; // 'none' | 'days' | 'date'
  int expiryDays;
  String expiryDate; // yyyy-MM-dd，僅 expiryType=='date' 時使用

  RewardItem({
    required this.id,
    required this.name,
    required this.pointsCost,
    required this.childIds,
    this.limitType = 'daily',
    this.limitCount = 1,
    this.expiryType = 'none',
    this.expiryDays = 7,
    this.expiryDate = '',
  });

  factory RewardItem.fromJson(Map<String, dynamic> json) => RewardItem(
    id: json['id'] as String,
    name: json['name'] as String,
    pointsCost: (json['points_cost'] as int?) ?? 0,
    childIds:
        (json['child_ids'] as List?)?.map((e) => e as String).toList() ?? [],
    limitType: (json['limit_type'] as String?) ?? 'daily',
    limitCount: (json['limit_count'] as int?) ?? 1,
    expiryType: (json['expiry_type'] as String?) ?? 'none',
    expiryDays: (json['expiry_days'] as int?) ?? 7,
    expiryDate: (json['expiry_date'] as String?) ?? '',
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'points_cost': pointsCost,
    'child_ids': childIds,
    'limit_type': limitType,
    'limit_count': limitCount,
    'expiry_type': expiryType,
    'expiry_days': expiryDays,
    'expiry_date': expiryDate,
  };

  // 計算此次兌換的到期日（空字串 = 無到期）
  String computeVoucherExpiry() {
    if (expiryType == 'none') return '';
    if (expiryType == 'date') return expiryDate;
    final expiry = DateTime.now().add(Duration(days: expiryDays));
    return '${expiry.year}-${expiry.month.toString().padLeft(2, '0')}-${expiry.day.toString().padLeft(2, '0')}';
  }
}

// 票券紀錄（兌換後產生，need 使用才算消耗）
class VoucherLog {
  final String id;
  final String rewardId;
  final String childId;
  final String redeemedAt; // yyyy-MM-dd HH:mm
  bool used;
  String usedAt; // 空字串 = 尚未使用
  String expiryDate; // 空字串 = 無到期，yyyy-MM-dd

  VoucherLog({
    required this.id,
    required this.rewardId,
    required this.childId,
    required this.redeemedAt,
    this.used = false,
    this.usedAt = '',
    this.expiryDate = '',
  });

  factory VoucherLog.fromJson(Map<String, dynamic> json) => VoucherLog(
    id: json['id'] as String,
    rewardId: json['reward_id'] as String,
    childId: json['child_id'] as String,
    redeemedAt:
        (json['redeemed_at'] as String?) ??
        (json['time'] as String? ?? ''), // 向下相容舊格式
    used: (json['used'] as bool?) ?? false,
    usedAt: (json['used_at'] as String?) ?? '',
    expiryDate: (json['expiry_date'] as String?) ?? '',
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'reward_id': rewardId,
    'child_id': childId,
    'redeemed_at': redeemedAt,
    'used': used,
    'used_at': usedAt,
    'expiry_date': expiryDate,
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

// ── 常用選項預設資料 ──

class _Preset {
  final String name;
  final int value;
  final String emoji;
  const _Preset(this.name, this.value, [this.emoji = '']);
}

const List<_Preset> _kHabitPresets = [
  _Preset('刷牙', 5, '🦷'),
  _Preset('寫作業', 10, '📚'),
  _Preset('整理房間', 10, '🧹'),
  _Preset('閱讀 15 分鐘', 10, '📖'),
  _Preset('早起', 10, '🌅'),
  _Preset('運動 30 分鐘', 15, '🏃'),
  _Preset('喝足夠的水', 5, '💧'),
];

const List<_Preset> _kDeductionPresets = [
  _Preset('罵髒話', 10, '🤬'),
  _Preset('不寫作業', 15, '📵'),
  _Preset('頂嘴不聽話', 10, '😤'),
  _Preset('睡過頭', 10, '😴'),
  _Preset('說謊', 20, '🤥'),
  _Preset('亂發脾氣', 10, '💢'),
  _Preset('打架動手', 30, '👊'),
];

const List<_Preset> _kRewardPresets = [
  _Preset('看電視 30 分鐘', 30, '📺'),
  _Preset('玩遊戲 30 分鐘', 30, '🎮'),
  _Preset('選今晚的晚餐', 50, '🍽️'),
  _Preset('買零食一樣', 50, '🍬'),
  _Preset('延後睡覺 30 分鐘', 40, '🌙'),
  _Preset('看一部電影', 100, '🎬'),
  _Preset('買一個小玩具', 150, '🧸'),
];

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
  SharedPreferences prefs,
  List<ChildHabit> habits,
) async {
  await prefs.setString(
    'child_habits',
    jsonEncode(habits.map((h) => h.toJson()).toList()),
  );
}

Future<List<DeductionItem>> _loadDeductions(SharedPreferences prefs) async {
  final raw = prefs.getString('deduction_items');
  if (raw == null) return [];
  return (jsonDecode(raw) as List)
      .map((e) => DeductionItem.fromJson(e as Map<String, dynamic>))
      .toList();
}

Future<void> _saveDeductions(
  SharedPreferences prefs,
  List<DeductionItem> items,
) async {
  await prefs.setString(
    'deduction_items',
    jsonEncode(items.map((d) => d.toJson()).toList()),
  );
}

Future<List<RewardItem>> _loadRewards(SharedPreferences prefs) async {
  final raw = prefs.getString('reward_items');
  if (raw == null) return [];
  return (jsonDecode(raw) as List)
      .map((e) => RewardItem.fromJson(e as Map<String, dynamic>))
      .toList();
}

Future<void> _saveRewards(
  SharedPreferences prefs,
  List<RewardItem> rewards,
) async {
  await prefs.setString(
    'reward_items',
    jsonEncode(rewards.map((r) => r.toJson()).toList()),
  );
}

Future<List<VoucherLog>> _loadVouchers(SharedPreferences prefs) async {
  final raw =
      prefs.getString('voucher_logs') ?? prefs.getString('redemption_logs');
  if (raw == null) return [];
  return (jsonDecode(raw) as List)
      .map((e) => VoucherLog.fromJson(e as Map<String, dynamic>))
      .toList();
}

Future<void> _saveVouchers(
  SharedPreferences prefs,
  List<VoucherLog> logs,
) async {
  await prefs.setString(
    'voucher_logs',
    jsonEncode(logs.map((l) => l.toJson()).toList()),
  );
}

Future<List<PointRecord>> _loadRecords(SharedPreferences prefs) async {
  final raw = prefs.getString('point_records');
  if (raw == null) return [];
  return (jsonDecode(raw) as List)
      .map((e) => PointRecord.fromJson(e as Map<String, dynamic>))
      .toList();
}

Future<void> _saveRecords(
  SharedPreferences prefs,
  List<PointRecord> records,
) async {
  await prefs.setString(
    'point_records',
    jsonEncode(records.map((r) => r.toJson()).toList()),
  );
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

  final newPoints = children[idx].points + delta;
  children[idx].points = newPoints;
  child.points = newPoints; // 同步更新傳入的物件

  await prefs.setString(
    'children',
    jsonEncode(children.map((c) => c.toJson()).toList()),
  );

  // 寫入積分紀錄
  final records = await _loadRecords(prefs);
  records.insert(
    0,
    PointRecord(
      id: _genId(),
      childId: child.id,
      time: _nowStr(),
      reason: reason,
      delta: delta,
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
  ScaffoldMessenger.of(
    context,
  ).showSnackBar(const SnackBar(content: Text('密碼錯誤')));
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
            builder: (_) => const ParentManagementPage(noPinWarning: false),
          ),
        );
        if (changed == true) _loadChildren();
      } else if (entered != null) {
        // 輸入了內容但不正確
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('密碼錯誤，請再試一次')));
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
                builder: (_) =>
                    _ChildHomePage(children: _children, initialIndex: i),
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
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 20,
          vertical: 12,
        ),
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

  const _ChildHomePage({required this.children, required this.initialIndex});

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
                PageRouteBuilder(
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
            _HabitTab(child: _current, onPointsChanged: _onPointsChanged),
            // 積分紀錄 Tab
            _PointRecordTab(child: _current),
            // 獎勵 Tab
            _RewardTab(child: _current, onPointsChanged: _onPointsChanged),
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
      _deductions = deductions
          .where((d) => d.childId == widget.child.id)
          .toList();
      _loaded = true;
    });
  }

  // 判斷習慣今日是否已打卡
  bool _isDoneToday(ChildHabit habit) => habit.completedDate == _todayStr();

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
      reason: '撤銷完成：${habit.name}',
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

  // ── 特殊積分（需家長密碼）──
  static const _kAddPresets = [
    _Preset('幫忙做家事', 10, '🏠'),
    _Preset('表現良好', 10, '😊'),
    _Preset('考試進步', 20, '📈'),
    _Preset('幫助別人', 10, '🤝'),
    _Preset('準時完成作業', 15, '⏰'),
    _Preset('主動學習', 15, '📚'),
  ];

  // 特殊積分預設子選單（勾選 + 個別調整分數）
  Future<Map<String, int>?> _showSpecialPresetSubSheet({
    required List<_Preset> available,
    required Map<String, int> initial,
    required String title,
    required Color accentColor,
    required String badgePrefix,
    required String dialogLabel,
  }) {
    final selected = Map<String, int>.from(initial);
    return showModalBottomSheet<Map<String, int>>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (_, setS) => DraggableScrollableSheet(
          initialChildSize: 0.55,
          maxChildSize: 0.9,
          minChildSize: 0.4,
          expand: false,
          builder: (_, scrollCtrl) => Column(
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 12, bottom: 4),
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                child: Row(
                  children: [
                    Icon(Icons.auto_awesome, size: 18, color: accentColor),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    if (selected.isNotEmpty)
                      Text(
                        '${selected.length} 項已選',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade500,
                        ),
                      ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView.builder(
                  controller: scrollCtrl,
                  itemCount: available.length,
                  itemBuilder: (_, i) {
                    final p = available[i];
                    final sel = selected.containsKey(p.name);
                    final pts = selected[p.name] ?? p.value;
                    return InkWell(
                      onTap: () => setS(() {
                        if (sel) {
                          selected.remove(p.name);
                        } else {
                          selected[p.name] = p.value;
                        }
                      }),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 14,
                        ),
                        decoration: BoxDecoration(
                          color: sel
                              ? accentColor.withValues(alpha: 0.08)
                              : Colors.white,
                          border: Border(
                            bottom: BorderSide(color: Colors.grey.shade100),
                          ),
                        ),
                        child: Row(
                          children: [
                            Text(p.emoji, style: const TextStyle(fontSize: 22)),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Text(
                                p.name,
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: sel
                                      ? FontWeight.w600
                                      : FontWeight.normal,
                                  color: sel ? accentColor : Colors.black87,
                                ),
                              ),
                            ),
                            GestureDetector(
                              onTap: () async {
                                if (!sel) {
                                  setS(() => selected[p.name] = p.value);
                                }
                                final ctrl = TextEditingController(
                                  text: '$pts',
                                );
                                final newPts = await showDialog<int>(
                                  context: ctx,
                                  builder: (dCtx) => AlertDialog(
                                    title: Text('調整分數：${p.name}'),
                                    content: TextField(
                                      controller: ctrl,
                                      keyboardType: TextInputType.number,
                                      inputFormatters: [
                                        FilteringTextInputFormatter.digitsOnly,
                                      ],
                                      decoration: InputDecoration(
                                        labelText: dialogLabel,
                                      ),
                                      autofocus: true,
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () => Navigator.pop(dCtx),
                                        child: Text(
                                          '取消',
                                          style: TextStyle(
                                            color: Colors.grey.shade600,
                                          ),
                                        ),
                                      ),
                                      TextButton(
                                        onPressed: () => Navigator.pop(
                                          dCtx,
                                          int.tryParse(ctrl.text) ?? pts,
                                        ),
                                        child: const Text('確認'),
                                      ),
                                    ],
                                  ),
                                );
                                if (newPts != null && newPts > 0) {
                                  setS(() => selected[p.name] = newPts);
                                }
                              },
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 150),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: sel
                                      ? accentColor
                                      : Colors.grey.shade100,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      '$badgePrefix$pts',
                                      style: TextStyle(
                                        color: sel
                                            ? Colors.white
                                            : Colors.grey.shade600,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                      ),
                                    ),
                                    if (sel) ...[
                                      const SizedBox(width: 3),
                                      const Icon(
                                        Icons.edit,
                                        size: 10,
                                        color: Colors.white,
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 150),
                              width: 24,
                              height: 24,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: sel ? accentColor : Colors.transparent,
                                border: Border.all(
                                  color: sel
                                      ? accentColor
                                      : Colors.grey.shade300,
                                  width: 2,
                                ),
                              ),
                              child: sel
                                  ? const Icon(
                                      Icons.check,
                                      size: 14,
                                      color: Colors.white,
                                    )
                                  : null,
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(
                  20,
                  12,
                  20,
                  MediaQuery.of(ctx).viewInsets.bottom + 24,
                ),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(ctx, selected),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: accentColor,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: Text(
                      selected.isEmpty
                          ? '確認（未選取）'
                          : '確認選取 (${selected.length} 項)',
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _giveSpecialPoints() async {
    if (!mounted) return;
    final ok = await _verifyParentPinIfNeeded(context);
    if (!ok || !mounted) return;

    bool isAdd = true;
    final reasonCtrl = TextEditingController();
    final pointCtrl = TextEditingController();
    final selectedAddPresets = <String, int>{};
    final selectedDeductItems = <String, int>{};

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (_, setS) {
          final customReason = reasonCtrl.text.trim();
          final customPts = int.tryParse(pointCtrl.text.trim()) ?? 0;
          final hasCustom = customReason.isNotEmpty;
          final selectedPresets = isAdd
              ? selectedAddPresets
              : selectedDeductItems;
          final canConfirm =
              selectedPresets.isNotEmpty || (hasCustom && customPts > 0);

          return Padding(
            padding: EdgeInsets.fromLTRB(
              20,
              16,
              20,
              MediaQuery.of(ctx).viewInsets.bottom + 32,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    '特殊積分',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 14),

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
                    onSelectionChanged: (s) => setS(() {
                      isAdd = s.first;
                      selectedAddPresets.clear();
                      selectedDeductItems.clear();
                      reasonCtrl.clear();
                      pointCtrl.clear();
                    }),
                    style: SegmentedButton.styleFrom(
                      selectedBackgroundColor: isAdd
                          ? Colors.green.shade50
                          : Colors.red.shade50,
                      selectedForegroundColor: isAdd
                          ? Colors.green
                          : Colors.red,
                    ),
                  ),
                  const SizedBox(height: 14),

                  // 快速理由 / 扣分項目 子選單按鈕
                  InkWell(
                    onTap: () async {
                      if (isAdd) {
                        final result = await _showSpecialPresetSubSheet(
                          available: _kAddPresets.toList(),
                          initial: Map.from(selectedAddPresets),
                          title: '快速理由',
                          accentColor: Colors.green.shade600,
                          badgePrefix: '+',
                          dialogLabel: '加幾分',
                        );
                        if (result != null) {
                          setS(() {
                            selectedAddPresets.clear();
                            selectedAddPresets.addAll(result);
                          });
                        }
                      } else {
                        if (_deductions.isEmpty) return;
                        final result = await _showSpecialPresetSubSheet(
                          available: _deductions
                              .map((d) => _Preset(d.name, d.points))
                              .toList(),
                          initial: Map.from(selectedDeductItems),
                          title: '扣分項目',
                          accentColor: Colors.red.shade600,
                          badgePrefix: '-',
                          dialogLabel: '扣幾分',
                        );
                        if (result != null) {
                          setS(() {
                            selectedDeductItems.clear();
                            selectedDeductItems.addAll(result);
                          });
                        }
                      }
                    },
                    borderRadius: BorderRadius.circular(12),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      decoration: BoxDecoration(
                        color: selectedPresets.isEmpty
                            ? Colors.grey.shade50
                            : (isAdd
                                  ? Colors.green.shade50
                                  : Colors.red.shade50),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: selectedPresets.isEmpty
                              ? Colors.grey.shade300
                              : (isAdd
                                    ? Colors.green.shade300
                                    : Colors.red.shade300),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.auto_awesome,
                            size: 18,
                            color: selectedPresets.isEmpty
                                ? Colors.grey.shade500
                                : (isAdd
                                      ? Colors.green.shade600
                                      : Colors.red.shade600),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              selectedPresets.isEmpty
                                  ? (isAdd ? '從快速理由選取' : '從扣分項目選取')
                                  : '已選 ${selectedPresets.length} 項',
                              style: TextStyle(
                                color: selectedPresets.isEmpty
                                    ? Colors.grey.shade600
                                    : (isAdd
                                          ? Colors.green.shade700
                                          : Colors.red.shade700),
                                fontSize: 14,
                              ),
                            ),
                          ),
                          Icon(
                            selectedPresets.isEmpty
                                ? Icons.chevron_right
                                : Icons.check_circle,
                            size: 20,
                            color: selectedPresets.isEmpty
                                ? Colors.grey.shade400
                                : (isAdd
                                      ? Colors.green.shade600
                                      : Colors.red.shade600),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),

                  // 自訂原因
                  TextField(
                    controller: reasonCtrl,
                    onChanged: (_) => setS(() {}),
                    decoration: InputDecoration(
                      hintText: isAdd ? '自訂原因...' : '自訂原因...',
                      filled: true,
                      fillColor: Colors.grey.shade50,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      prefixIcon: const Icon(Icons.edit_outlined, size: 18),
                    ),
                  ),

                  // 自訂分數（有輸入原因才顯示）
                  if (hasCustom) ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: pointCtrl,
                      onChanged: (_) => setS(() {}),
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: InputDecoration(
                        labelText: isAdd ? '自訂加分數' : '自訂扣分數',
                        filled: true,
                        fillColor: Colors.grey.shade50,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                        prefixIcon: Icon(
                          isAdd
                              ? Icons.add_circle_outline
                              : Icons.remove_circle_outline,
                          size: 18,
                          color: isAdd ? Colors.green : Colors.red,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),

                  // 確認按鈕
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: canConfirm
                          ? () async {
                              Navigator.pop(ctx);
                              final prefs = _prefs!;
                              int latestPts = widget.child.points;
                              final presets = isAdd
                                  ? selectedAddPresets
                                  : selectedDeductItems;
                              for (final entry in presets.entries) {
                                final delta = isAdd
                                    ? entry.value
                                    : -entry.value;
                                latestPts = await _applyPoints(
                                  prefs: prefs,
                                  child: widget.child,
                                  delta: delta,
                                  reason: '特殊積分：${entry.key}',
                                );
                              }
                              final customReason = reasonCtrl.text.trim();
                              final customPts =
                                  int.tryParse(pointCtrl.text.trim()) ?? 0;
                              if (customReason.isNotEmpty && customPts > 0) {
                                final delta = isAdd ? customPts : -customPts;
                                latestPts = await _applyPoints(
                                  prefs: prefs,
                                  child: widget.child,
                                  delta: delta,
                                  reason: '特殊積分：$customReason',
                                );
                              }
                              setState(() => widget.child.points = latestPts);
                              widget.onPointsChanged();
                              if (!mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    '已更新 ${widget.child.name} 的積分，目前共 $latestPts 分',
                                  ),
                                ),
                              );
                            }
                          : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isAdd ? Colors.green : Colors.red,
                        disabledBackgroundColor: Colors.grey.shade200,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: Text(
                        isAdd ? '確認加分' : '確認扣分',
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
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
            ..._habits.map(
              (habit) => _HabitItem(
                habit: habit,
                doneToday: _isDoneToday(habit),
                onCheckIn: () => _checkIn(habit),
                onUndo: () => _undoCheckIn(habit),
              ),
            ),

          const SizedBox(height: 24),

          OutlinedButton.icon(
            onPressed: _giveSpecialPoints,
            icon: const Icon(Icons.star_outline, size: 16),
            label: const Text('特殊積分'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.purple,
              side: BorderSide(color: Colors.purple.withValues(alpha: 0.5)),
              padding: const EdgeInsets.symmetric(vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          const SizedBox(height: 8),
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
    child: Text(
      text,
      style: TextStyle(color: Colors.grey.shade400, fontSize: 13),
    ),
  );
}

// 習慣列表項目
class _HabitItem extends StatefulWidget {
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
  State<_HabitItem> createState() => _HabitItemState();
}

class _HabitItemState extends State<_HabitItem>
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
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.75), weight: 25),
      TweenSequenceItem(tween: Tween(begin: 0.75, end: 1.20), weight: 45),
      TweenSequenceItem(tween: Tween(begin: 1.20, end: 1.0), weight: 30),
    ]).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _handleTap() {
    _ctrl.forward(from: 0);
    if (widget.doneToday) {
      widget.onUndo?.call();
    } else {
      widget.onCheckIn();
    }
  }

  @override
  Widget build(BuildContext context) {
    final doneToday = widget.doneToday;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        elevation: doneToday ? 0 : 2,
        shadowColor: Colors.black12,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  width: 5,
                  color: doneToday
                      ? Colors.green.shade400
                      : Colors.orange.shade300,
                ),
                Expanded(
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 2,
                    ),
                    leading: GestureDetector(
                      onTap: _handleTap,
                      child: ScaleTransition(
                        scale: _scale,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 250),
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: doneToday
                                ? Colors.green.shade400
                                : Colors.transparent,
                            border: doneToday
                                ? null
                                : Border.all(
                                    color: Colors.grey.shade300,
                                    width: 2,
                                  ),
                            shape: BoxShape.circle,
                          ),
                          child: doneToday
                              ? const Icon(
                                  Icons.check,
                                  color: Colors.white,
                                  size: 18,
                                )
                              : null,
                        ),
                      ),
                    ),
                    title: AnimatedDefaultTextStyle(
                      duration: const Duration(milliseconds: 250),
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        decoration: doneToday
                            ? TextDecoration.lineThrough
                            : TextDecoration.none,
                        color: doneToday
                            ? Colors.grey.shade400
                            : Colors.black87,
                      ),
                      child: Text(widget.habit.name),
                    ),
                    subtitle: Text(
                      '+${widget.habit.points} 分',
                      style: TextStyle(
                        fontSize: 12,
                        color: doneToday ? Colors.grey.shade400 : Colors.orange,
                      ),
                    ),
                    trailing: doneToday
                        ? TextButton(
                            onPressed: widget.onUndo,
                            style: TextButton.styleFrom(
                              padding: EdgeInsets.zero,
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            child: Text(
                              '撤銷',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade400,
                              ),
                            ),
                          )
                        : null,
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
  // 'week' | 'month' | 'custom' | 'all'；預設本週
  String _filter = 'week';
  DateTimeRange? _customRange;

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
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    return _records.where((r) {
      final dateStr = r.time.split(' ').first;
      final dt = DateTime.tryParse(dateStr);
      if (dt == null) return false;
      final day = DateTime(dt.year, dt.month, dt.day);

      switch (_filter) {
        case 'week':
          return !day.isBefore(today.subtract(const Duration(days: 6)));
        case 'month':
          return dt.year == now.year && dt.month == now.month;
        case 'custom':
          final r = _customRange;
          if (r == null) return false;
          return !day.isBefore(r.start) && !day.isAfter(r.end);
        default: // 'all'
          return true;
      }
    }).toList();
  }

  // 打開日期範圍選擇器
  Future<void> _pickCustomRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 2),
      lastDate: now,
      initialEntryMode: DatePickerEntryMode.input,
      initialDateRange:
          _customRange ??
          DateTimeRange(start: now.subtract(const Duration(days: 6)), end: now),
      locale: const Locale('zh', 'TW'),
    );
    if (picked != null) {
      setState(() {
        _customRange = picked;
        _filter = 'custom';
      });
    }
  }

  String _customLabel() {
    final r = _customRange;
    if (r == null) return '自訂';
    String fmt(DateTime d) => '${d.month}/${d.day}';
    return '${fmt(r.start)}–${fmt(r.end)}';
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
      side: BorderSide(color: selected ? primary : Colors.grey.shade300),
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
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _filterChip('本週', 'week'),
                const SizedBox(width: 8),
                _filterChip('本月', 'month'),
                const SizedBox(width: 8),
                // 自訂：點擊開啟日期選擇器
                GestureDetector(
                  onTap: _pickCustomRange,
                  child: _CustomRangeChip(
                    label: _customLabel(),
                    selected: _filter == 'custom',
                    primary: Theme.of(context).colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 8),
                _filterChip('全部', 'all'),
              ],
            ),
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
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 4,
                    ),
                    title: Text(
                      r.reason,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    subtitle: Text(
                      r.time,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade500,
                      ),
                    ),
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
                            fontSize: 11,
                            color: Colors.grey.shade400,
                          ),
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

// 自訂日期範圍篩選 Chip（顯示日期標籤，含日曆圖示）
class _CustomRangeChip extends StatelessWidget {
  final String label;
  final bool selected;
  final Color primary;

  const _CustomRangeChip({
    required this.label,
    required this.selected,
    required this.primary,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: selected ? primary.withValues(alpha: 0.15) : Colors.transparent,
        border: Border.all(color: selected ? primary : Colors.grey.shade300),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.date_range,
            size: 14,
            color: selected ? primary : Colors.grey.shade600,
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: selected ? primary : Colors.grey.shade600,
              fontWeight: selected ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }
}

// ── 獎勵 Tab ──

class _RewardTab extends StatefulWidget {
  final ChildData child;
  final VoidCallback onPointsChanged;

  const _RewardTab({required this.child, required this.onPointsChanged});

  @override
  State<_RewardTab> createState() => _RewardTabState();
}

class _RewardTabState extends State<_RewardTab> {
  List<RewardItem> _rewards = [];
  List<VoucherLog> _vouchers = [];
  bool _loaded = false;
  SharedPreferences? _prefs;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    _prefs = await SharedPreferences.getInstance();
    final allRewards = await _loadRewards(_prefs!);
    final allVouchers = await _loadVouchers(_prefs!);
    setState(() {
      _rewards = allRewards
          .where((r) => r.childIds.contains(widget.child.id))
          .toList();
      _vouchers = allVouchers
          .where((v) => v.childId == widget.child.id)
          .toList();
      _loaded = true;
    });
  }

  String _rewardName(String rewardId) {
    final r = _rewards.where((r) => r.id == rewardId).firstOrNull;
    return r?.name ?? '已刪除的獎勵';
  }

  // 使用次數統計（以 usedAt 為準）
  int _todayUsageCount(String rewardId) {
    final today = _todayStr();
    return _vouchers
        .where(
          (v) => v.rewardId == rewardId && v.used && v.usedAt.startsWith(today),
        )
        .length;
  }

  int _weekUsageCount(String rewardId) {
    final now = DateTime.now();
    final weekStart = DateTime(
      now.year,
      now.month,
      now.day,
    ).subtract(const Duration(days: 6));
    return _vouchers.where((v) {
      if (v.rewardId != rewardId || !v.used) return false;
      final d = DateTime.tryParse(v.usedAt.split(' ').first);
      return d != null && !d.isBefore(weekStart);
    }).length;
  }

  bool _canUse(RewardItem r) {
    if (r.limitType == 'daily') return _todayUsageCount(r.id) < r.limitCount;
    if (r.limitType == 'weekly') return _weekUsageCount(r.id) < r.limitCount;
    return true;
  }

  // 正數 = 剩餘天數，0 = 今天到期，負數 = 已超過幾天
  int? _daysUntilExpiry(String expiryDate) {
    if (expiryDate.isEmpty) return null;
    final exp = DateTime.tryParse(expiryDate);
    if (exp == null) return null;
    final today = DateTime.now();
    final todayOnly = DateTime(today.year, today.month, today.day);
    return exp.difference(todayOnly).inDays;
  }

  Future<void> _redeem(RewardItem r) async {
    if (!mounted) return;
    if (widget.child.points < r.pointsCost) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('積分不足，無法兌換')));
      return;
    }

    int qty = 1;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (_, setS) => AlertDialog(
          title: Text('兌換「${r.name}」'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '每張票券需 ${r.pointsCost} 分',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    onPressed: qty > 1 ? () => setS(() => qty--) : null,
                    icon: const Icon(Icons.remove_circle_outline),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      '$qty 張',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: widget.child.points >= r.pointsCost * (qty + 1)
                        ? () => setS(() => qty++)
                        : null,
                    icon: const Icon(Icons.add_circle_outline),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                '共需 ${r.pointsCost * qty} 分（剩餘 ${widget.child.points - r.pointsCost * qty} 分）',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
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
              child: const Text('確認兌換'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted) return;

    final prefs = _prefs!;
    final newPoints = await _applyPoints(
      prefs: prefs,
      child: widget.child,
      delta: -(r.pointsCost * qty),
      reason: '兌換票券：${r.name} x$qty',
    );
    final allVouchers = await _loadVouchers(prefs);
    final now = _nowStr();
    final expiry = r.computeVoucherExpiry();
    for (var i = 0; i < qty; i++) {
      final v = VoucherLog(
        id: _genId(),
        rewardId: r.id,
        childId: widget.child.id,
        redeemedAt: now,
        expiryDate: expiry,
      );
      allVouchers.add(v);
      _vouchers.add(v);
    }
    await _saveVouchers(prefs, allVouchers);
    setState(() => widget.child.points = newPoints);
    widget.onPointsChanged();
  }

  Future<void> _useVoucher(VoucherLog v) async {
    if (!mounted) return;
    final rewardName = _rewardName(v.rewardId);
    final reward = _rewards.where((r) => r.id == v.rewardId).firstOrNull;

    // 使用次數上限檢查
    if (reward != null && !_canUse(reward)) {
      final hint = reward.limitType == 'daily'
          ? '今日使用已達 ${reward.limitCount} 次上限'
          : '本週使用已達 ${reward.limitCount} 次上限';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(hint)));
      return;
    }

    final days = _daysUntilExpiry(v.expiryDate);
    String confirmMsg = '確定使用「$rewardName」這張票券嗎？';
    if (days != null && days < 0) {
      confirmMsg += '\n\n⚠️ 此票券已逾期 ${-days} 天，仍要使用嗎？';
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('使用票券'),
        content: Text(confirmMsg),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('取消', style: TextStyle(color: Colors.grey.shade600)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('確認使用'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    v.used = true;
    v.usedAt = _nowStr();
    final prefs = _prefs!;
    final allVouchers = await _loadVouchers(prefs);
    final idx = allVouchers.indexWhere((x) => x.id == v.id);
    if (idx >= 0) {
      allVouchers[idx].used = true;
      allVouchers[idx].usedAt = v.usedAt;
    }
    await _saveVouchers(prefs, allVouchers);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const Center(child: CircularProgressIndicator());

    final pendingVouchers = _vouchers.where((v) => !v.used).toList()
      ..sort((a, b) => b.redeemedAt.compareTo(a.redeemedAt));
    final usedVouchers = _vouchers.where((v) => v.used).toList()
      ..sort((a, b) => b.usedAt.compareTo(a.usedAt));

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── 我的票券 ──
          _SectionHeader(
            icon: Icons.confirmation_num_outlined,
            label: '我的票券',
            color: Colors.purple.shade400,
            trailing: pendingVouchers.isEmpty
                ? null
                : '${pendingVouchers.length} 張',
          ),
          if (pendingVouchers.isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Text(
                '目前沒有票券',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade400),
              ),
            )
          else
            ...pendingVouchers.map((v) {
              final reward = _rewards
                  .where((r) => r.id == v.rewardId)
                  .firstOrNull;
              final canUse = reward == null || _canUse(reward);
              String? limitHint;
              if (reward != null && !canUse) {
                limitHint = reward.limitType == 'daily'
                    ? '今日已達使用上限'
                    : '本週已達使用上限';
              }
              return _VoucherCard(
                voucher: v,
                rewardName: _rewardName(v.rewardId),
                daysUntilExpiry: _daysUntilExpiry(v.expiryDate),
                canUse: canUse,
                limitHint: limitHint,
                onUse: () => _useVoucher(v),
              );
            }),

          const SizedBox(height: 8),

          // ── 可兌換獎勵 ──
          _SectionHeader(
            icon: Icons.card_giftcard_outlined,
            label: '可兌換獎勵',
            color: Colors.amber.shade700,
          ),
          if (_rewards.isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Text(
                '尚無獎勵，請家長至家長管理新增',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade400),
              ),
            )
          else
            ..._rewards.map((r) {
              final canAfford = widget.child.points >= r.pointsCost;
              return _RewardCard(
                reward: r,
                canAfford: canAfford,
                onRedeem: () => _redeem(r),
              );
            }),

          const SizedBox(height: 8),

          // ── 兌換紀錄（已使用票券） ──
          if (usedVouchers.isNotEmpty)
            Theme(
              data: Theme.of(
                context,
              ).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                leading: Icon(
                  Icons.history,
                  color: Colors.grey.shade500,
                  size: 20,
                ),
                title: Text(
                  '兌換紀錄（${usedVouchers.length} 張）',
                  style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
                ),
                tilePadding: EdgeInsets.zero,
                childrenPadding: EdgeInsets.zero,
                children: usedVouchers.map((v) {
                  return ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      Icons.check_circle_outline,
                      size: 18,
                      color: Colors.green.shade400,
                    ),
                    title: Text(
                      _rewardName(v.rewardId),
                      style: const TextStyle(fontSize: 13),
                    ),
                    subtitle: Text(
                      '兌換 ${v.redeemedAt}　使用 ${v.usedAt}',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade400,
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final String? trailing;

  const _SectionHeader({
    required this.icon,
    required this.label,
    required this.color,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Icon(icon, size: 17, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                trailing!,
                style: TextStyle(fontSize: 11, color: color),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _VoucherCard extends StatelessWidget {
  final VoucherLog voucher;
  final String rewardName;
  final int? daysUntilExpiry;
  final bool canUse;
  final String? limitHint;
  final VoidCallback onUse;

  const _VoucherCard({
    required this.voucher,
    required this.rewardName,
    required this.daysUntilExpiry,
    required this.canUse,
    required this.limitHint,
    required this.onUse,
  });

  @override
  Widget build(BuildContext context) {
    final days = daysUntilExpiry;
    final isExpired = days != null && days < 0;
    final isAlmostExpired = days != null && days >= 0 && days <= 3;

    Color? borderColor;
    if (isExpired) borderColor = Colors.red.shade300;
    if (isAlmostExpired) borderColor = Colors.orange.shade400;

    String? expiryLabel;
    if (days == null) {
      expiryLabel = null;
    } else if (isExpired) {
      expiryLabel = '已逾期 ${-days} 天';
    } else if (days == 0) {
      expiryLabel = '今天到期';
    } else {
      expiryLabel = '$days 天後到期';
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: borderColor != null
            ? BorderSide(color: borderColor, width: 1.5)
            : BorderSide.none,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            Icon(
              Icons.confirmation_num,
              size: 32,
              color: isExpired
                  ? Colors.red.shade300
                  : isAlmostExpired
                  ? Colors.orange.shade400
                  : Colors.purple.shade300,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    rewardName,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '兌換於 ${voucher.redeemedAt}',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                  ),
                  if (expiryLabel != null)
                    Text(
                      expiryLabel,
                      style: TextStyle(
                        fontSize: 11,
                        color: isExpired
                            ? Colors.red.shade400
                            : Colors.orange.shade600,
                      ),
                    ),
                ],
              ),
            ),
            ElevatedButton(
              onPressed: canUse ? onUse : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.purple.shade400,
                foregroundColor: Colors.white,
                disabledBackgroundColor: Colors.grey.shade200,
                disabledForegroundColor: Colors.grey.shade400,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 6,
                ),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                textStyle: const TextStyle(fontSize: 13),
              ),
              child: Text(limitHint ?? '使用'),
            ),
          ],
        ),
      ),
    );
  }
}

class _RewardCard extends StatelessWidget {
  final RewardItem reward;
  final bool canAfford;
  final VoidCallback onRedeem;

  const _RewardCard({
    required this.reward,
    required this.canAfford,
    required this.onRedeem,
  });

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.card_giftcard, color: primary, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    reward.name,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Icon(Icons.star, size: 12, color: Colors.amber.shade600),
                      const SizedBox(width: 2),
                      Text(
                        '${reward.pointsCost} 分',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                      if (reward.limitType == 'daily') ...[
                        const SizedBox(width: 6),
                        Text(
                          '每日限用 ${reward.limitCount} 次',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey.shade400,
                          ),
                        ),
                      ] else if (reward.limitType == 'weekly') ...[
                        const SizedBox(width: 6),
                        Text(
                          '每週限用 ${reward.limitCount} 次',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey.shade400,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            ElevatedButton(
              onPressed: canAfford ? onRedeem : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: primary,
                foregroundColor: Colors.white,
                disabledBackgroundColor: Colors.grey.shade200,
                disabledForegroundColor: Colors.grey.shade400,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 6,
                ),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                textStyle: const TextStyle(fontSize: 13),
              ),
              child: Text(canAfford ? '兌換' : '積分不足'),
            ),
          ],
        ),
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
  List<RewardItem> _rewards = [];
  bool _loaded = false;
  SharedPreferences? _prefs;

  // 獎勵票券預設使用上限
  String _rewardDefaultLimitType = 'daily';
  int _rewardDefaultLimitCount = 1;

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
    final rewards = await _loadRewards(prefs);
    setState(() {
      _children = children;
      _habits = habits;
      _deductions = deductions;
      _rewards = rewards;
      _rewardDefaultLimitType =
          prefs.getString('reward_default_limit_type') ?? 'daily';
      _rewardDefaultLimitCount =
          prefs.getInt('reward_default_limit_count') ?? 1;
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
    _children.add(ChildData(id: id, name: name, points: 0, resetMode: 'none'));
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

    // 同步刪除相關習慣、扣分項目、積分紀錄、兌換紀錄
    final prefs = _prefs!;
    final habits = await _loadHabits(prefs);
    await _saveHabits(
      prefs,
      habits.where((h) => h.childId != childId).toList(),
    );
    final deductions = await _loadDeductions(prefs);
    await _saveDeductions(
      prefs,
      deductions.where((d) => d.childId != childId).toList(),
    );
    final records = await _loadRecords(prefs);
    await _saveRecords(
      prefs,
      records.where((r) => r.childId != childId).toList(),
    );
    // 獎勵：移除該小孩；若某獎勵所有小孩都被移除則刪除整個獎勵
    final rewards = await _loadRewards(prefs);
    for (final r in rewards) {
      r.childIds.remove(childId);
    }
    await _saveRewards(
      prefs,
      rewards.where((r) => r.childIds.isNotEmpty).toList(),
    );
    // 票券紀錄
    final vouchers = await _loadVouchers(prefs);
    await _saveVouchers(
      prefs,
      vouchers.where((l) => l.childId != childId).toList(),
    );

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

  // ── 修改小孩名稱 ──
  Future<void> _editChildName(int index) async {
    final child = _children[index];
    final nameCtrl = TextEditingController(text: child.name);

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('修改名稱'),
        content: TextField(
          controller: nameCtrl,
          autofocus: true,
          decoration: const InputDecoration(labelText: '小孩名稱'),
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
    );

    if (result != true) return;
    final name = nameCtrl.text.trim();
    if (name.isEmpty || name == child.name) return;

    _children[index].name = name;
    await _saveChildren();
    _changed = true;
    setState(() {});
  }

  int _habitPresetPoints(String name) {
    for (final p in _kHabitPresets) {
      if (p.name == name) return p.value;
    }
    return 10;
  }

  int _deductionPresetPoints(String name) {
    for (final p in _kDeductionPresets) {
      if (p.name == name) return p.value;
    }
    return 5;
  }

  int _rewardPresetPoints(String name) {
    for (final p in _kRewardPresets) {
      if (p.name == name) return p.value;
    }
    return 30;
  }

  // 常用選項子選單：可捲動清單，每項可個別調整數值
  Future<Map<String, int>?> _showFamilyPresetSubSheet(
    List<_Preset> available,
    Map<String, int> initial, {
    String title = '常用習慣',
    Color accentColor = Colors.orange,
    String badgePrefix = '+',
    String dialogLabel = '完成可得積分',
  }) {
    final selected = Map<String, int>.from(initial);
    return showModalBottomSheet<Map<String, int>>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (_, setS) => DraggableScrollableSheet(
          initialChildSize: 0.55,
          maxChildSize: 0.9,
          minChildSize: 0.4,
          expand: false,
          builder: (_, scrollCtrl) => Column(
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 12, bottom: 4),
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                child: Row(
                  children: [
                    Icon(Icons.auto_awesome, size: 18, color: accentColor),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    if (selected.isNotEmpty)
                      Text(
                        '${selected.length} 項已選',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade500,
                        ),
                      ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView.builder(
                  controller: scrollCtrl,
                  itemCount: available.length,
                  itemBuilder: (_, i) {
                    final p = available[i];
                    final sel = selected.containsKey(p.name);
                    final pts = selected[p.name] ?? p.value;
                    return InkWell(
                      onTap: () => setS(() {
                        if (sel) {
                          selected.remove(p.name);
                        } else {
                          selected[p.name] = p.value;
                        }
                      }),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 14,
                        ),
                        decoration: BoxDecoration(
                          color: sel
                              ? accentColor.withValues(alpha: 0.08)
                              : Colors.white,
                          border: Border(
                            bottom: BorderSide(color: Colors.grey.shade100),
                          ),
                        ),
                        child: Row(
                          children: [
                            Text(p.emoji, style: const TextStyle(fontSize: 22)),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Text(
                                p.name,
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: sel
                                      ? FontWeight.w600
                                      : FontWeight.normal,
                                  color: sel ? accentColor : Colors.black87,
                                ),
                              ),
                            ),
                            // 積分徽章（點擊可調整）
                            GestureDetector(
                              onTap: () async {
                                if (!sel) {
                                  setS(() => selected[p.name] = p.value);
                                }
                                final ctrl = TextEditingController(
                                  text: '$pts',
                                );
                                final newPts = await showDialog<int>(
                                  context: ctx,
                                  builder: (dCtx) => AlertDialog(
                                    title: Text('調整積分：${p.name}'),
                                    content: TextField(
                                      controller: ctrl,
                                      keyboardType: TextInputType.number,
                                      inputFormatters: [
                                        FilteringTextInputFormatter.digitsOnly,
                                      ],
                                      decoration: InputDecoration(
                                        labelText: dialogLabel,
                                      ),
                                      autofocus: true,
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () => Navigator.pop(dCtx),
                                        child: Text(
                                          '取消',
                                          style: TextStyle(
                                            color: Colors.grey.shade600,
                                          ),
                                        ),
                                      ),
                                      TextButton(
                                        onPressed: () => Navigator.pop(
                                          dCtx,
                                          int.tryParse(ctrl.text) ?? pts,
                                        ),
                                        child: const Text('確認'),
                                      ),
                                    ],
                                  ),
                                );
                                if (newPts != null && newPts > 0) {
                                  setS(() => selected[p.name] = newPts);
                                }
                              },
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 150),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: sel
                                      ? accentColor
                                      : Colors.grey.shade100,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      '$badgePrefix$pts',
                                      style: TextStyle(
                                        color: sel
                                            ? Colors.white
                                            : Colors.grey.shade600,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                      ),
                                    ),
                                    if (sel) ...[
                                      const SizedBox(width: 3),
                                      const Icon(
                                        Icons.edit,
                                        size: 10,
                                        color: Colors.white,
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 150),
                              width: 24,
                              height: 24,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: sel ? accentColor : Colors.transparent,
                                border: Border.all(
                                  color: sel
                                      ? accentColor
                                      : Colors.grey.shade300,
                                  width: 2,
                                ),
                              ),
                              child: sel
                                  ? const Icon(
                                      Icons.check,
                                      size: 14,
                                      color: Colors.white,
                                    )
                                  : null,
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(
                  20,
                  12,
                  20,
                  MediaQuery.of(ctx).viewInsets.bottom + 24,
                ),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(ctx, selected),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: accentColor,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: Text(
                      selected.isEmpty
                          ? '確認（未選取）'
                          : '確認選取 (${selected.length} 項)',
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── 新增習慣 ──
  Future<void> _addHabit() async {
    if (_children.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('請先新增小孩')));
      return;
    }

    final nameCtrl = TextEditingController();
    final pointCtrl = TextEditingController(text: '10');
    final Set<String> selectedIds = {_children.first.id};
    final selectedPresets = <String>{};
    final selectedPresetPts = <String, int>{};

    final existingNames = _habits.map((h) => h.name).toSet();
    final available = _kHabitPresets
        .where((p) => !existingNames.contains(p.name))
        .toList();

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (_, setS) {
          final customName = nameCtrl.text.trim();
          final total =
              (customName.isNotEmpty ? 1 : 0) + selectedPresets.length;
          final pts = int.tryParse(pointCtrl.text.trim()) ?? 0;
          final hasCustom = customName.isNotEmpty;
          final canAdd =
              (hasCustom || selectedPresets.isNotEmpty) &&
              (!hasCustom || pts > 0) &&
              selectedIds.isNotEmpty;

          return Padding(
            padding: EdgeInsets.fromLTRB(
              20,
              16,
              20,
              MediaQuery.of(ctx).viewInsets.bottom + 32,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    '新增習慣',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 14),

                  // 套用小孩
                  Text(
                    '套用小孩',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: _children.map((c) {
                      final sel = selectedIds.contains(c.id);
                      return FilterChip(
                        label: Text(c.name),
                        selected: sel,
                        selectedColor: Colors.orange.shade100,
                        checkmarkColor: Colors.orange,
                        onSelected: (v) => setS(() {
                          if (v) {
                            selectedIds.add(c.id);
                          } else {
                            selectedIds.remove(c.id);
                          }
                        }),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 14),

                  // 從常用習慣選取 按鈕
                  if (available.isNotEmpty) ...[
                    InkWell(
                      onTap: () async {
                        final result = await _showFamilyPresetSubSheet(
                          available,
                          Map.fromEntries(
                            selectedPresets.map(
                              (n) => MapEntry(
                                n,
                                selectedPresetPts[n] ?? _habitPresetPoints(n),
                              ),
                            ),
                          ),
                        );
                        if (result != null) {
                          setS(() {
                            selectedPresets.clear();
                            selectedPresetPts.clear();
                            selectedPresets.addAll(result.keys);
                            selectedPresetPts.addAll(result);
                          });
                        }
                      },
                      borderRadius: BorderRadius.circular(12),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                        decoration: BoxDecoration(
                          color: selectedPresets.isEmpty
                              ? Colors.grey.shade50
                              : Colors.orange.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: selectedPresets.isEmpty
                                ? Colors.grey.shade300
                                : Colors.orange.shade300,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.auto_awesome,
                              size: 18,
                              color: selectedPresets.isEmpty
                                  ? Colors.grey.shade500
                                  : Colors.orange,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                selectedPresets.isEmpty
                                    ? '從常用習慣選取'
                                    : '已選 ${selectedPresets.length} 個常用習慣',
                                style: TextStyle(
                                  color: selectedPresets.isEmpty
                                      ? Colors.grey.shade600
                                      : Colors.orange.shade700,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                            Icon(
                              selectedPresets.isEmpty
                                  ? Icons.chevron_right
                                  : Icons.check_circle,
                              size: 20,
                              color: selectedPresets.isEmpty
                                  ? Colors.grey.shade400
                                  : Colors.orange.shade600,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                  ],

                  // 自訂名稱
                  TextField(
                    controller: nameCtrl,
                    onChanged: (_) => setS(() {}),
                    decoration: InputDecoration(
                      hintText: '自訂習慣名稱...',
                      filled: true,
                      fillColor: Colors.grey.shade50,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      prefixIcon: const Icon(Icons.edit_outlined, size: 18),
                    ),
                  ),

                  // 自訂習慣分數（有輸入名稱才顯示）
                  if (hasCustom) ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: pointCtrl,
                      onChanged: (_) => setS(() {}),
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: InputDecoration(
                        labelText: '自訂習慣分數',
                        filled: true,
                        fillColor: Colors.grey.shade50,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                        prefixIcon: const Icon(Icons.star_outline, size: 18),
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),

                  // 新增按鈕
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: canAdd
                          ? () async {
                              Navigator.pop(ctx);
                              final prefs = _prefs!;
                              final habits = await _loadHabits(prefs);
                              // 常用習慣各自積分
                              for (final presetName in selectedPresets) {
                                final habitPts =
                                    selectedPresetPts[presetName] ??
                                    _habitPresetPoints(presetName);
                                for (final childId in selectedIds) {
                                  habits.add(
                                    ChildHabit(
                                      id: _genId(),
                                      childId: childId,
                                      name: presetName,
                                      points: habitPts,
                                    ),
                                  );
                                }
                              }
                              // 自訂習慣
                              if (customName.isNotEmpty) {
                                final customPts =
                                    int.tryParse(pointCtrl.text.trim()) ?? 10;
                                for (final childId in selectedIds) {
                                  habits.add(
                                    ChildHabit(
                                      id: _genId(),
                                      childId: childId,
                                      name: customName,
                                      points: customPts,
                                    ),
                                  );
                                }
                              }
                              await _saveHabits(prefs, habits);
                              _changed = true;
                              await _loadAll();
                            }
                          : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange,
                        disabledBackgroundColor: Colors.grey.shade200,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: Text(
                        total == 0 ? '請選擇或輸入習慣' : '新增 ($total 項)',
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
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

  // ── 編輯習慣 ──
  Future<void> _editHabit(ChildHabit habit) async {
    final nameCtrl = TextEditingController(text: habit.name);
    final pointCtrl = TextEditingController(text: habit.points.toString());

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('編輯習慣'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
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
    );

    if (result != true) return;
    final name = nameCtrl.text.trim();
    final pts = int.tryParse(pointCtrl.text.trim()) ?? 0;
    if (name.isEmpty || pts <= 0) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('習慣名稱不得為空、分數須大於 0')));
      }
      return;
    }

    final prefs = _prefs!;
    final habits = await _loadHabits(prefs);
    final idx = habits.indexWhere((h) => h.id == habit.id);
    if (idx != -1) {
      habits[idx] = ChildHabit(
        id: habit.id,
        childId: habit.childId,
        name: name,
        points: pts,
      );
    }
    await _saveHabits(prefs, habits);
    _changed = true;
    await _loadAll();
  }

  // ── 新增扣分項目 ──
  Future<void> _addDeduction() async {
    if (_children.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('請先新增小孩')));
      return;
    }

    final nameCtrl = TextEditingController();
    final pointCtrl = TextEditingController(text: '5');
    final Set<String> selectedIds = {_children.first.id};
    final selectedPresets = <String>{};
    final selectedPresetPts = <String, int>{};

    final existingNames = _deductions.map((d) => d.name).toSet();
    final available = _kDeductionPresets
        .where((p) => !existingNames.contains(p.name))
        .toList();

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (_, setS) {
          final customName = nameCtrl.text.trim();
          final total =
              (customName.isNotEmpty ? 1 : 0) + selectedPresets.length;
          final pts = int.tryParse(pointCtrl.text.trim()) ?? 0;
          final hasCustom = customName.isNotEmpty;
          final canAdd =
              (hasCustom || selectedPresets.isNotEmpty) &&
              (!hasCustom || pts > 0) &&
              selectedIds.isNotEmpty;

          return Padding(
            padding: EdgeInsets.fromLTRB(
              20,
              16,
              20,
              MediaQuery.of(ctx).viewInsets.bottom + 32,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    '新增扣分項目',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 14),

                  // 套用小孩
                  Text(
                    '套用小孩',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: _children.map((c) {
                      final sel = selectedIds.contains(c.id);
                      return FilterChip(
                        label: Text(c.name),
                        selected: sel,
                        selectedColor: Colors.red.shade100,
                        checkmarkColor: Colors.red,
                        onSelected: (v) => setS(() {
                          if (v) {
                            selectedIds.add(c.id);
                          } else {
                            selectedIds.remove(c.id);
                          }
                        }),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 14),

                  // 從常用項目選取 按鈕
                  if (available.isNotEmpty) ...[
                    InkWell(
                      onTap: () async {
                        final result = await _showFamilyPresetSubSheet(
                          available,
                          Map.fromEntries(
                            selectedPresets.map(
                              (n) => MapEntry(
                                n,
                                selectedPresetPts[n] ??
                                    _deductionPresetPoints(n),
                              ),
                            ),
                          ),
                          title: '常用扣分項目',
                          accentColor: Colors.red.shade600,
                          badgePrefix: '-',
                          dialogLabel: '扣幾分',
                        );
                        if (result != null) {
                          setS(() {
                            selectedPresets.clear();
                            selectedPresetPts.clear();
                            selectedPresets.addAll(result.keys);
                            selectedPresetPts.addAll(result);
                          });
                        }
                      },
                      borderRadius: BorderRadius.circular(12),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                        decoration: BoxDecoration(
                          color: selectedPresets.isEmpty
                              ? Colors.grey.shade50
                              : Colors.red.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: selectedPresets.isEmpty
                                ? Colors.grey.shade300
                                : Colors.red.shade300,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.auto_awesome,
                              size: 18,
                              color: selectedPresets.isEmpty
                                  ? Colors.grey.shade500
                                  : Colors.red.shade600,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                selectedPresets.isEmpty
                                    ? '從常用項目選取'
                                    : '已選 ${selectedPresets.length} 個常用項目',
                                style: TextStyle(
                                  color: selectedPresets.isEmpty
                                      ? Colors.grey.shade600
                                      : Colors.red.shade700,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                            Icon(
                              selectedPresets.isEmpty
                                  ? Icons.chevron_right
                                  : Icons.check_circle,
                              size: 20,
                              color: selectedPresets.isEmpty
                                  ? Colors.grey.shade400
                                  : Colors.red.shade600,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                  ],

                  // 自訂名稱
                  TextField(
                    controller: nameCtrl,
                    onChanged: (_) => setS(() {}),
                    decoration: InputDecoration(
                      hintText: '自訂扣分項目名稱...',
                      filled: true,
                      fillColor: Colors.grey.shade50,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      prefixIcon: const Icon(Icons.edit_outlined, size: 18),
                    ),
                  ),

                  // 自訂扣分（有輸入名稱才顯示）
                  if (hasCustom) ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: pointCtrl,
                      onChanged: (_) => setS(() {}),
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: InputDecoration(
                        labelText: '自訂扣分數',
                        filled: true,
                        fillColor: Colors.grey.shade50,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                        prefixIcon: const Icon(
                          Icons.remove_circle_outline,
                          size: 18,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),

                  // 新增按鈕
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: canAdd
                          ? () async {
                              Navigator.pop(ctx);
                              final prefs = _prefs!;
                              final deductions = await _loadDeductions(prefs);
                              for (final presetName in selectedPresets) {
                                final deductPts =
                                    selectedPresetPts[presetName] ??
                                    _deductionPresetPoints(presetName);
                                for (final childId in selectedIds) {
                                  deductions.add(
                                    DeductionItem(
                                      id: _genId(),
                                      childId: childId,
                                      name: presetName,
                                      points: deductPts,
                                    ),
                                  );
                                }
                              }
                              if (customName.isNotEmpty) {
                                final customPts =
                                    int.tryParse(pointCtrl.text.trim()) ?? 5;
                                for (final childId in selectedIds) {
                                  deductions.add(
                                    DeductionItem(
                                      id: _genId(),
                                      childId: childId,
                                      name: customName,
                                      points: customPts,
                                    ),
                                  );
                                }
                              }
                              await _saveDeductions(prefs, deductions);
                              _changed = true;
                              await _loadAll();
                            }
                          : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        disabledBackgroundColor: Colors.grey.shade200,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: Text(
                        total == 0 ? '請選擇或輸入項目' : '新增 ($total 項)',
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
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

  // ── 編輯扣分項目 ──
  Future<void> _editDeduction(DeductionItem item) async {
    final nameCtrl = TextEditingController(text: item.name);
    final pointCtrl = TextEditingController(text: item.points.toString());

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('編輯扣分項目'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
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
    );

    if (result != true) return;
    final name = nameCtrl.text.trim();
    final pts = int.tryParse(pointCtrl.text.trim()) ?? 0;
    if (name.isEmpty || pts <= 0) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('項目名稱不得為空、扣分須大於 0')));
      }
      return;
    }

    final prefs = _prefs!;
    final deductions = await _loadDeductions(prefs);
    final idx = deductions.indexWhere((d) => d.id == item.id);
    if (idx != -1) {
      deductions[idx] = DeductionItem(
        id: item.id,
        childId: item.childId,
        name: name,
        points: pts,
      );
    }
    await _saveDeductions(prefs, deductions);
    _changed = true;
    await _loadAll();
  }

  // ── 獎勵票券預設使用上限 ──
  Future<void> _showRewardLimitSettings() async {
    String limitType = _rewardDefaultLimitType;
    int limitCount = _rewardDefaultLimitCount;
    final limitCtrl = TextEditingController(text: '$limitCount');

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (_, setS) => AlertDialog(
          title: const Text('票券預設使用上限'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '新增獎勵時的預設值',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
                const SizedBox(height: 4),
                RadioGroup<String>(
                  groupValue: limitType,
                  onChanged: (v) {
                    if (v != null) setS(() => limitType = v);
                  },
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      RadioListTile<String>(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: const Text(
                          '無上限',
                          style: TextStyle(fontSize: 14),
                        ),
                        value: 'none',
                      ),
                      RadioListTile<String>(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: const Text(
                          '每日限制',
                          style: TextStyle(fontSize: 14),
                        ),
                        value: 'daily',
                      ),
                      RadioListTile<String>(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: const Text(
                          '每週限制',
                          style: TextStyle(fontSize: 14),
                        ),
                        value: 'weekly',
                      ),
                    ],
                  ),
                ),
                if (limitType != 'none') ...[
                  const SizedBox(height: 8),
                  TextField(
                    controller: limitCtrl,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: InputDecoration(
                      labelText: limitType == 'daily' ? '每日最多幾次' : '每週最多幾次',
                    ),
                    onChanged: (v) => limitCount = int.tryParse(v) ?? 1,
                  ),
                ],
              ],
            ),
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

    if (confirmed != true) return;
    final count = limitType == 'none' ? 1 : (int.tryParse(limitCtrl.text) ?? 1);
    await _prefs?.setString('reward_default_limit_type', limitType);
    await _prefs?.setInt('reward_default_limit_count', count);
    setState(() {
      _rewardDefaultLimitType = limitType;
      _rewardDefaultLimitCount = count;
    });
  }

  // ── 新增獎勵 ──
  Future<void> _addReward() async {
    if (_children.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('請先新增小孩')));
      return;
    }

    final nameCtrl = TextEditingController();
    final pointCtrl = TextEditingController();
    final limitCtrl = TextEditingController(text: '$_rewardDefaultLimitCount');
    final expiryDaysCtrl = TextEditingController(text: '7');
    final expiryDateCtrl = TextEditingController();
    final Set<String> selectedIds = Set.from(_children.map((c) => c.id));
    String limitType = _rewardDefaultLimitType;
    String expiryType = 'none';
    final selectedPresets = <String>{};
    final selectedPresetPts = <String, int>{};

    final existingNames = _rewards.map((r) => r.name).toSet();
    final available = _kRewardPresets
        .where((p) => !existingNames.contains(p.name))
        .toList();

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (_, setS) {
          final customName = nameCtrl.text.trim();
          final total =
              (customName.isNotEmpty ? 1 : 0) + selectedPresets.length;
          final pts = int.tryParse(pointCtrl.text.trim()) ?? 0;
          final hasCustom = customName.isNotEmpty;
          final canAdd =
              (hasCustom || selectedPresets.isNotEmpty) &&
              (!hasCustom || pts > 0) &&
              selectedIds.isNotEmpty;

          return Padding(
            padding: EdgeInsets.fromLTRB(
              20,
              16,
              20,
              MediaQuery.of(ctx).viewInsets.bottom + 32,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    '新增獎勵',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 14),

                  // 套用小孩
                  Text(
                    '套用小孩',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: _children.map((c) {
                      final sel = selectedIds.contains(c.id);
                      return FilterChip(
                        label: Text(c.name),
                        selected: sel,
                        selectedColor: Colors.purple.shade100,
                        checkmarkColor: Colors.purple,
                        onSelected: (v) => setS(() {
                          if (v) {
                            selectedIds.add(c.id);
                          } else {
                            selectedIds.remove(c.id);
                          }
                        }),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 14),

                  // 從常用獎勵選取 按鈕
                  if (available.isNotEmpty) ...[
                    InkWell(
                      onTap: () async {
                        final result = await _showFamilyPresetSubSheet(
                          available,
                          Map.fromEntries(
                            selectedPresets.map(
                              (n) => MapEntry(
                                n,
                                selectedPresetPts[n] ?? _rewardPresetPoints(n),
                              ),
                            ),
                          ),
                          title: '常用獎勵',
                          accentColor: Colors.purple.shade600,
                          badgePrefix: '',
                          dialogLabel: '所需積分',
                        );
                        if (result != null) {
                          setS(() {
                            selectedPresets.clear();
                            selectedPresetPts.clear();
                            selectedPresets.addAll(result.keys);
                            selectedPresetPts.addAll(result);
                          });
                        }
                      },
                      borderRadius: BorderRadius.circular(12),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                        decoration: BoxDecoration(
                          color: selectedPresets.isEmpty
                              ? Colors.grey.shade50
                              : Colors.purple.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: selectedPresets.isEmpty
                                ? Colors.grey.shade300
                                : Colors.purple.shade300,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.auto_awesome,
                              size: 18,
                              color: selectedPresets.isEmpty
                                  ? Colors.grey.shade500
                                  : Colors.purple.shade600,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                selectedPresets.isEmpty
                                    ? '從常用獎勵選取'
                                    : '已選 ${selectedPresets.length} 個常用獎勵',
                                style: TextStyle(
                                  color: selectedPresets.isEmpty
                                      ? Colors.grey.shade600
                                      : Colors.purple.shade700,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                            Icon(
                              selectedPresets.isEmpty
                                  ? Icons.chevron_right
                                  : Icons.check_circle,
                              size: 20,
                              color: selectedPresets.isEmpty
                                  ? Colors.grey.shade400
                                  : Colors.purple.shade600,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                  ],

                  // 自訂獎勵名稱
                  TextField(
                    controller: nameCtrl,
                    onChanged: (_) => setS(() {}),
                    decoration: InputDecoration(
                      hintText: '自訂獎勵名稱...',
                      filled: true,
                      fillColor: Colors.grey.shade50,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      prefixIcon: const Icon(
                        Icons.card_giftcard_outlined,
                        size: 18,
                      ),
                    ),
                  ),

                  // 自訂積分（有輸入名稱才顯示）
                  if (hasCustom) ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: pointCtrl,
                      onChanged: (_) => setS(() {}),
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: InputDecoration(
                        labelText: '所需積分',
                        filled: true,
                        fillColor: Colors.grey.shade50,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                        prefixIcon: const Icon(Icons.stars_outlined, size: 18),
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),

                  // 使用上限
                  Text(
                    '使用上限',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                  const SizedBox(height: 4),
                  RadioGroup<String>(
                    groupValue: limitType,
                    onChanged: (v) {
                      if (v != null) setS(() => limitType = v);
                    },
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        RadioListTile<String>(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: const Text(
                            '無上限',
                            style: TextStyle(fontSize: 14),
                          ),
                          value: 'none',
                        ),
                        RadioListTile<String>(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: const Text(
                            '每日限制',
                            style: TextStyle(fontSize: 14),
                          ),
                          value: 'daily',
                        ),
                        RadioListTile<String>(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: const Text(
                            '每週限制',
                            style: TextStyle(fontSize: 14),
                          ),
                          value: 'weekly',
                        ),
                      ],
                    ),
                  ),
                  if (limitType != 'none') ...[
                    const SizedBox(height: 4),
                    TextField(
                      controller: limitCtrl,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: InputDecoration(
                        labelText: limitType == 'daily' ? '每日最多幾次' : '每週最多幾次',
                        filled: true,
                        fillColor: Colors.grey.shade50,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),

                  // 票券有效期
                  Text(
                    '票券有效期',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                  const SizedBox(height: 4),
                  RadioGroup<String>(
                    groupValue: expiryType,
                    onChanged: (v) {
                      if (v != null) setS(() => expiryType = v);
                    },
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        RadioListTile<String>(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: const Text(
                            '永不到期',
                            style: TextStyle(fontSize: 14),
                          ),
                          value: 'none',
                        ),
                        RadioListTile<String>(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: const Text(
                            '兌換後幾天內',
                            style: TextStyle(fontSize: 14),
                          ),
                          value: 'days',
                        ),
                        RadioListTile<String>(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: const Text(
                            '指定日期',
                            style: TextStyle(fontSize: 14),
                          ),
                          value: 'date',
                        ),
                      ],
                    ),
                  ),
                  if (expiryType == 'days') ...[
                    const SizedBox(height: 4),
                    TextField(
                      controller: expiryDaysCtrl,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: InputDecoration(
                        labelText: '有效天數',
                        filled: true,
                        fillColor: Colors.grey.shade50,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ],
                  if (expiryType == 'date') ...[
                    const SizedBox(height: 4),
                    TextField(
                      controller: expiryDateCtrl,
                      keyboardType: TextInputType.datetime,
                      decoration: InputDecoration(
                        labelText: '到期日（yyyy-MM-dd）',
                        hintText: '例：2026-12-31',
                        filled: true,
                        fillColor: Colors.grey.shade50,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),

                  // 新增按鈕
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: canAdd
                          ? () async {
                              Navigator.pop(ctx);
                              final limitCount = limitType == 'none'
                                  ? 1
                                  : (int.tryParse(limitCtrl.text.trim()) ?? 1);
                              final expiryDays =
                                  int.tryParse(expiryDaysCtrl.text.trim()) ?? 7;
                              final expiryDate = expiryDateCtrl.text.trim();
                              final prefs = _prefs!;
                              final rewards = await _loadRewards(prefs);
                              for (final presetName in selectedPresets) {
                                final costPts =
                                    selectedPresetPts[presetName] ??
                                    _rewardPresetPoints(presetName);
                                rewards.add(
                                  RewardItem(
                                    id: _genId(),
                                    name: presetName,
                                    pointsCost: costPts,
                                    childIds: selectedIds.toList(),
                                    limitType: limitType,
                                    limitCount: limitCount,
                                    expiryType: expiryType,
                                    expiryDays: expiryDays,
                                    expiryDate: expiryDate,
                                  ),
                                );
                              }
                              if (customName.isNotEmpty) {
                                final customPts =
                                    int.tryParse(pointCtrl.text.trim()) ?? 0;
                                rewards.add(
                                  RewardItem(
                                    id: _genId(),
                                    name: customName,
                                    pointsCost: customPts,
                                    childIds: selectedIds.toList(),
                                    limitType: limitType,
                                    limitCount: limitCount,
                                    expiryType: expiryType,
                                    expiryDays: expiryDays,
                                    expiryDate: expiryDate,
                                  ),
                                );
                              }
                              await _saveRewards(prefs, rewards);
                              _changed = true;
                              await _loadAll();
                            }
                          : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.purple,
                        disabledBackgroundColor: Colors.grey.shade200,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: Text(
                        total == 0 ? '請選擇或輸入獎勵' : '新增 ($total 項)',
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ── 刪除獎勵 ──
  Future<void> _deleteReward(RewardItem reward) async {
    final prefs = _prefs!;
    final rewards = await _loadRewards(prefs);
    rewards.removeWhere((r) => r.id == reward.id);
    await _saveRewards(prefs, rewards);
    _changed = true;
    await _loadAll();
  }

  // ── 編輯獎勵 ──
  Future<void> _editReward(RewardItem reward) async {
    final nameCtrl = TextEditingController(text: reward.name);
    final pointCtrl = TextEditingController(text: reward.pointsCost.toString());
    final limitCtrl = TextEditingController(text: reward.limitCount.toString());
    final expiryDaysCtrl = TextEditingController(
      text: reward.expiryDays.toString(),
    );
    final expiryDateCtrl = TextEditingController(text: reward.expiryDate);
    final Set<String> selectedIds = Set.from(reward.childIds);
    String limitType = reward.limitType;
    String expiryType = reward.expiryType;

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (_, setS) => AlertDialog(
          title: const Text('編輯獎勵'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '套用小孩',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
                ..._children.map(
                  (c) => CheckboxListTile(
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
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: nameCtrl,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: '獎勵名稱'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: pointCtrl,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(labelText: '所需積分'),
                ),
                const SizedBox(height: 16),
                Text(
                  '使用上限',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
                const SizedBox(height: 4),
                RadioGroup<String>(
                  groupValue: limitType,
                  onChanged: (v) {
                    if (v != null) setS(() => limitType = v);
                  },
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      RadioListTile<String>(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: const Text(
                          '無上限',
                          style: TextStyle(fontSize: 14),
                        ),
                        value: 'none',
                      ),
                      RadioListTile<String>(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: const Text(
                          '每日限制',
                          style: TextStyle(fontSize: 14),
                        ),
                        value: 'daily',
                      ),
                      RadioListTile<String>(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: const Text(
                          '每週限制',
                          style: TextStyle(fontSize: 14),
                        ),
                        value: 'weekly',
                      ),
                    ],
                  ),
                ),
                if (limitType != 'none') ...[
                  const SizedBox(height: 4),
                  TextField(
                    controller: limitCtrl,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: InputDecoration(
                      labelText: limitType == 'daily' ? '每日最多幾次' : '每週最多幾次',
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                Text(
                  '票券有效期',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
                const SizedBox(height: 4),
                RadioGroup<String>(
                  groupValue: expiryType,
                  onChanged: (v) {
                    if (v != null) setS(() => expiryType = v);
                  },
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      RadioListTile<String>(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: const Text(
                          '永不到期',
                          style: TextStyle(fontSize: 14),
                        ),
                        value: 'none',
                      ),
                      RadioListTile<String>(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: const Text(
                          '兌換後幾天內',
                          style: TextStyle(fontSize: 14),
                        ),
                        value: 'days',
                      ),
                      RadioListTile<String>(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: const Text(
                          '指定日期',
                          style: TextStyle(fontSize: 14),
                        ),
                        value: 'date',
                      ),
                    ],
                  ),
                ),
                if (expiryType == 'days') ...[
                  const SizedBox(height: 4),
                  TextField(
                    controller: expiryDaysCtrl,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(labelText: '有效天數'),
                  ),
                ],
                if (expiryType == 'date') ...[
                  const SizedBox(height: 4),
                  TextField(
                    controller: expiryDateCtrl,
                    keyboardType: TextInputType.datetime,
                    decoration: const InputDecoration(
                      labelText: '到期日（yyyy-MM-dd）',
                      hintText: '例：2026-12-31',
                    ),
                  ),
                ],
              ],
            ),
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
    final pts = int.tryParse(pointCtrl.text.trim()) ?? 0;
    final limitCount = limitType == 'none'
        ? 1
        : (int.tryParse(limitCtrl.text.trim()) ?? 1);
    final expiryDays = int.tryParse(expiryDaysCtrl.text.trim()) ?? 7;
    final expiryDate = expiryDateCtrl.text.trim();
    if (name.isEmpty || pts <= 0 || selectedIds.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('請至少選一個小孩，且名稱不得為空、積分須大於 0')),
        );
      }
      return;
    }

    final prefs = _prefs!;
    final rewards = await _loadRewards(prefs);
    final idx = rewards.indexWhere((r) => r.id == reward.id);
    if (idx != -1) {
      rewards[idx] = RewardItem(
        id: reward.id,
        name: name,
        pointsCost: pts,
        childIds: selectedIds.toList(),
        limitType: limitType,
        limitCount: limitCount,
        expiryType: expiryType,
        expiryDays: expiryDays,
        expiryDate: expiryDate,
      );
    }
    await _saveRewards(prefs, rewards);
    _changed = true;
    await _loadAll();
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

  // ── 共用：常用選項 Bottom Sheet ──
  Future<void> _showPresetSheet({
    required String title,
    required IconData titleIcon,
    required Color color,
    required List<_Preset> presets,
    required bool defaultAllChildren,
    required String Function(_Preset p) subtitle,
    required Color subtitleColor,
    required String valueLabel,
    required Future<void> Function(Set<String> childIds, List<_Preset> presets)
    onConfirm,
  }) async {
    if (_children.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('請先新增小孩')));
      return;
    }

    final selectedIdx = <int>{};
    final overrides = <int, _Preset>{};
    final selectedChildIds = defaultAllChildren
        ? Set<String>.from(_children.map((c) => c.id))
        : <String>{_children.first.id};

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (_, setS) => DraggableScrollableSheet(
          initialChildSize: 0.6,
          maxChildSize: 0.9,
          minChildSize: 0.4,
          expand: false,
          builder: (_, scrollCtrl) => Column(
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 12, bottom: 4),
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                child: Row(
                  children: [
                    Icon(titleIcon, size: 18, color: color),
                    const SizedBox(width: 8),
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '套用小孩',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 8,
                      children: _children.map((c) {
                        final sel = selectedChildIds.contains(c.id);
                        return FilterChip(
                          label: Text(
                            c.name,
                            style: const TextStyle(fontSize: 13),
                          ),
                          selected: sel,
                          selectedColor: color.withValues(alpha: 0.15),
                          checkmarkColor: color,
                          onSelected: (v) => setS(() {
                            if (v) {
                              selectedChildIds.add(c.id);
                            } else {
                              selectedChildIds.remove(c.id);
                            }
                          }),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
              const Divider(height: 16),
              Expanded(
                child: ListView.builder(
                  controller: scrollCtrl,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: presets.length,
                  itemBuilder: (_, i) {
                    final p = overrides[i] ?? presets[i];
                    final isEdited = overrides.containsKey(i);
                    final isSelected = selectedIdx.contains(i);
                    return ListTile(
                      dense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                      leading: Checkbox(
                        value: isSelected,
                        activeColor: color,
                        onChanged: (v) => setS(() {
                          if (v == true) {
                            selectedIdx.add(i);
                          } else {
                            selectedIdx.remove(i);
                          }
                        }),
                      ),
                      title: Text(
                        p.name,
                        style: isEdited
                            ? TextStyle(
                                color: color,
                                fontWeight: FontWeight.w500,
                              )
                            : null,
                      ),
                      subtitle: Text(
                        subtitle(p),
                        style: TextStyle(color: subtitleColor, fontSize: 12),
                      ),
                      trailing: IconButton(
                        icon: Icon(
                          Icons.edit_outlined,
                          size: 18,
                          color: isEdited ? color : Colors.grey.shade400,
                        ),
                        tooltip: '編輯',
                        onPressed: () async {
                          final src = overrides[i] ?? presets[i];
                          final nameCtrl = TextEditingController(
                            text: src.name,
                          );
                          final valCtrl = TextEditingController(
                            text: '${src.value}',
                          );
                          await showDialog<void>(
                            context: ctx,
                            builder: (d) => AlertDialog(
                              title: const Text('編輯項目'),
                              content: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  TextField(
                                    controller: nameCtrl,
                                    autofocus: true,
                                    decoration: const InputDecoration(
                                      labelText: '名稱',
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  TextField(
                                    controller: valCtrl,
                                    keyboardType: TextInputType.number,
                                    inputFormatters: [
                                      FilteringTextInputFormatter.digitsOnly,
                                    ],
                                    decoration: InputDecoration(
                                      labelText: valueLabel,
                                    ),
                                  ),
                                ],
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () {
                                    setS(() => overrides.remove(i));
                                    Navigator.pop(d);
                                  },
                                  child: Text(
                                    '還原預設',
                                    style: TextStyle(
                                      color: Colors.grey.shade500,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                                TextButton(
                                  onPressed: () => Navigator.pop(d),
                                  child: Text(
                                    '取消',
                                    style: TextStyle(
                                      color: Colors.grey.shade600,
                                    ),
                                  ),
                                ),
                                TextButton(
                                  onPressed: () {
                                    final name = nameCtrl.text.trim();
                                    final val =
                                        int.tryParse(valCtrl.text) ?? src.value;
                                    if (name.isNotEmpty) {
                                      setS(
                                        () => overrides[i] = _Preset(name, val),
                                      );
                                    }
                                    Navigator.pop(d);
                                  },
                                  child: const Text('確定'),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                      onTap: () => setS(() {
                        if (isSelected) {
                          selectedIdx.remove(i);
                        } else {
                          selectedIdx.add(i);
                        }
                      }),
                    );
                  },
                ),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(
                  20,
                  8,
                  20,
                  MediaQuery.of(ctx).viewInsets.bottom + 16,
                ),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: (selectedIdx.isEmpty || selectedChildIds.isEmpty)
                        ? null
                        : () async {
                            Navigator.pop(ctx);
                            final editedPresets = (selectedIdx.toList()..sort())
                                .map((i) => overrides[i] ?? presets[i])
                                .toList();
                            await onConfirm(selectedChildIds, editedPresets);
                          },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: color,
                      disabledBackgroundColor: Colors.grey.shade200,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      selectedIdx.isEmpty
                          ? '請選擇項目'
                          : '新增所選 (${selectedIdx.length})',
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showRewardPresets() => _showPresetSheet(
    title: '常用獎勵',
    titleIcon: Icons.card_giftcard_outlined,
    color: Colors.amber.shade700,
    presets: _kRewardPresets,
    defaultAllChildren: true,
    subtitle: (p) => '${p.value} 積分',
    subtitleColor: Colors.amber.shade800,
    valueLabel: '所需積分',
    onConfirm: (childIds, selected) async {
      final prefs = _prefs!;
      final rewards = await _loadRewards(prefs);
      for (final p in selected) {
        rewards.add(
          RewardItem(
            id: _genId(),
            name: p.name,
            pointsCost: p.value,
            childIds: childIds.toList(),
            limitType: 'none',
            limitCount: 1,
          ),
        );
      }
      await _saveRewards(prefs, rewards);
      _changed = true;
      await _loadAll();
    },
  );

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
        // 票券預設使用上限設定列
        Container(
          margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: ListTile(
            dense: true,
            leading: Icon(
              Icons.confirmation_num_outlined,
              color: Colors.amber.shade700,
              size: 20,
            ),
            title: const Text(
              '票券預設使用上限',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              _rewardDefaultLimitType == 'none'
                  ? '無上限'
                  : _rewardDefaultLimitType == 'daily'
                  ? '每日 $_rewardDefaultLimitCount 次'
                  : '每週 $_rewardDefaultLimitCount 次',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
            ),
            trailing: Icon(Icons.chevron_right, color: Colors.grey.shade400),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            onTap: _showRewardLimitSettings,
          ),
        ),
        ..._buildRewardSection(),
        _addWithPresetButtons(
          '自訂獎勵',
          Colors.amber.shade700,
          _addReward,
          _showRewardPresets,
        ),
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

  // 新增 + 常用選項 並排按鈕
  Widget _addWithPresetButtons(
    String label,
    Color color,
    VoidCallback onAdd,
    VoidCallback onPreset,
  ) {
    return Row(
      children: [
        Expanded(child: _addButton(label, Icons.add, color, onAdd)),
        const SizedBox(width: 8),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: onPreset,
            icon: const Icon(Icons.lightbulb_outline, size: 16),
            label: const Text('常用選項'),
            style: OutlinedButton.styleFrom(
              foregroundColor: color,
              side: BorderSide(color: color.withValues(alpha: 0.5)),
              padding: const EdgeInsets.symmetric(vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
      ],
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
                      color: primary,
                      fontWeight: FontWeight.bold,
                    ),
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
            const Divider(height: 20, thickness: 1),
            Row(
              children: [
                Icon(Icons.refresh, size: 16, color: Colors.grey.shade500),
                const SizedBox(width: 6),
                Text(
                  '積分重置：',
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                ),
                Text(
                  _resetModeLabels[child.resetMode] ?? '不重置',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () => _setResetMode(index),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
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
                '+${habit.points} 分',
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
      String limitLabel = '';
      if (reward.limitType == 'daily') {
        limitLabel = '每日限用 ${reward.limitCount} 次';
      } else if (reward.limitType == 'weekly') {
        limitLabel = '每週限用 ${reward.limitCount} 次';
      }

      String expiryLabel = '';
      if (reward.expiryType == 'days') {
        expiryLabel = '兌換後 ${reward.expiryDays} 天';
      } else if (reward.expiryType == 'date') {
        expiryLabel = '到期 ${reward.expiryDate}';
      }

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
              if (limitLabel.isNotEmpty) limitLabel,
              if (expiryLabel.isNotEmpty) expiryLabel,
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
