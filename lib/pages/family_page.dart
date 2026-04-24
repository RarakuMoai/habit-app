// 育兒模式主頁面
// 包含：小孩選擇畫面、小孩主頁（三 Tab）、家長管理頁面、PIN 驗證
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'settings_page.dart';

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

// 積分重置模式的顯示文字
const Map<String, String> _resetModeLabels = {
  'none': '不重置',
  'weekly': '每週一',
  'monthly': '每月1號',
  'manual': '手動重置',
};

// ── PIN 輸入對話框（供本檔案內部使用）──
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
            hintText: '請輸入 $digits 位數字 PIN',
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

// ── 家庭主頁（小孩選擇畫面）──

class FamilyPage extends StatefulWidget {
  const FamilyPage({super.key});

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

  // 點擊「家長管理」：驗證 PIN 後進入
  Future<void> _enterParentManagement() async {
    final prefs = await SharedPreferences.getInstance();
    final savedPin = prefs.getString('parent_pin');
    if (!mounted) return;

    if (savedPin == null || savedPin.isEmpty) {
      // 尚未設定 PIN，直接進入並提示建議設定
      final changed = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => const ParentManagementPage(noPinWarning: true),
        ),
      );
      if (changed == true) _loadChildren();
    } else {
      // 需要輸入 PIN 才能進入
      final digits = prefs.getInt('pin_digits') ?? 4;
      final entered = await _showPinDialog(
        context,
        digits: digits,
        title: '請輸入家長 PIN',
      );
      if (!mounted) return;
      if (entered == savedPin) {
        final changed = await Navigator.of(context).push<bool>(
          MaterialPageRoute(
            builder: (_) => const ParentManagementPage(noPinWarning: false),
          ),
        );
        if (changed == true) _loadChildren();
      } else if (entered != null) {
        // 輸入了內容但不正確
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('PIN 錯誤，請再試一次')),
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
                MaterialPageRoute(builder: (_) => const SettingsPage()),
              );
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
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
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
                MaterialPageRoute(builder: (_) => const SettingsPage()),
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
        body: const TabBarView(
          children: [
            _ComingSoonTab(label: '習慣'),
            _ComingSoonTab(label: '積分紀錄'),
            _ComingSoonTab(label: '獎勵'),
          ],
        ),
      ),
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
  // 是否要顯示「建議設定 PIN」的提示
  final bool noPinWarning;

  const ParentManagementPage({super.key, required this.noPinWarning});

  @override
  State<ParentManagementPage> createState() => _ParentManagementPageState();
}

class _ParentManagementPageState extends State<ParentManagementPage> {
  List<ChildData> _children = [];
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
    _loadChildren();

    // 尚未設定 PIN 時顯示建議提示
    if (widget.noPinWarning && mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('建議至設定頁設定 PIN 以保護家長管理'),
            duration: Duration(seconds: 3),
          ),
        );
      });
    }
  }

  void _loadChildren() {
    final raw = _prefs?.getString('children');
    setState(() {
      _children = raw == null
          ? []
          : (jsonDecode(raw) as List)
              .map((e) => ChildData.fromJson(e as Map<String, dynamic>))
              .toList();
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

    // 用毫秒時間戳作為唯一 ID（不依賴 uuid 套件）
    final id = DateTime.now().millisecondsSinceEpoch.toString();
    _children.add(
      ChildData(id: id, name: name, points: 0, resetMode: 'none'),
    );
    await _saveChildren();
    setState(() {});
  }

  // 刪除小孩（含二次確認）
  Future<void> _deleteChild(int index) async {
    final childName = _children[index].name;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('刪除小孩'),
        content: Text('確定要刪除「$childName」嗎？所有積分紀錄將一起刪除。'),
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
    setState(() {});
  }

  // 設定單一小孩的積分重置模式
  Future<void> _setResetMode(int index) async {
    final current = _children[index].resetMode;
    final selected = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text('${_children[index].name} 的積分重置'),
        children: [
          // Flutter 3.32+ 用 RadioGroup 管理群組狀態
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

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // 攔截系統返回，確保無論哪種返回方式都能帶回 _changed
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        // didPop=false 代表系統返回被攔截；直接呼叫 Navigator.pop 帶回結果
        // didPop=true 代表已由 BackButton.onPressed 主動 pop，不重複操作
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
                : _buildList(),
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

  Widget _buildList() {
    final primary = Theme.of(context).colorScheme.primary;
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      itemCount: _children.length,
      itemBuilder: (_, i) {
        final child = _children[i];
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 頂部：頭像 + 名字積分 + 刪除按鈕
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
                      icon: const Icon(Icons.delete_outline, color: Colors.red),
                      tooltip: '刪除',
                      onPressed: () => _deleteChild(i),
                    ),
                  ],
                ),
                const Divider(height: 20, thickness: 1),
                // 底部：積分重置設定
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
                      onPressed: () => _setResetMode(i),
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
      },
    );
  }
}
