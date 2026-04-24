import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'profile_edit_page.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _waterEnabled = true;
  bool _timerEnabled = true;
  bool _weightTrackingEnabled = false;
  bool _loaded = false;

  // PIN 相關狀態
  String? _parentPin;   // null 表示尚未設定
  int _pinDigits = 4;   // 4 或 6 位

  SharedPreferences? _prefs;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    _prefs = await SharedPreferences.getInstance();
    setState(() {
      _waterEnabled = _prefs!.getBool('water_enabled') ?? true;
      _timerEnabled = _prefs!.getBool('timer_enabled') ?? true;
      _weightTrackingEnabled = _prefs!.getBool('weight_tracking_enabled') ?? false;
      _parentPin = _prefs!.getString('parent_pin');
      _pinDigits = _prefs!.getInt('pin_digits') ?? 4;
      _loaded = true;
    });
  }

  Future<void> _saveBool(String key, bool value) async {
    await _prefs?.setBool(key, value);
  }

  Future<void> _clearHabits() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('清除習慣紀錄'),
        content: const Text('確定要清除所有習慣紀錄嗎？暱稱、設定等資料會保留。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('取消', style: TextStyle(color: Colors.grey.shade600)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('確定清除', style: TextStyle(color: Colors.orange)),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await _prefs?.remove('habits');
    }
  }

  Future<void> _clearAll() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('清除所有資料'),
        content: const Text('確定要清除所有資料嗎？這將回到初始狀態，重新進行引導流程。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('取消', style: TextStyle(color: Colors.grey.shade600)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('確定清除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirm == true && mounted) {
      // 在 async 操作前先取得 navigator，避免跨 async gap 使用 BuildContext
      final nav = Navigator.of(context);
      await _prefs?.clear();
      nav.pushNamedAndRemoveUntil('/onboarding', (_) => false);
    }
  }

  // 區塊標題（顏色跟隨當前主題主色）
  Widget _sectionTitle(String title, IconData icon) {
    final color = Theme.of(context).colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 8, 0, 12),
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

  // 功能開關列
  Widget _toggleTile({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: SwitchListTile(
        secondary: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: iconColor.withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: iconColor, size: 20),
        ),
        title: Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle, style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
        value: value,
        activeThumbColor: Colors.orange,
        activeTrackColor: Colors.orange.shade200,
        onChanged: onChanged,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }

  // 危險操作按鈕（清除類）
  Widget _dangerButton({
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 18),
        label: Text(label),
        style: OutlinedButton.styleFrom(
          foregroundColor: color,
          side: BorderSide(color: color.withValues(alpha: 0.5)),
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
    );
  }

  // PIN 設定入口：底部彈出，含位數切換 + 設定/修改 PIN
  Future<void> _showPinSettings() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _PinSettingsSheet(
        currentPin: _parentPin,
        currentDigits: _pinDigits,
        onSaved: (newPin, newDigits) async {
          await _prefs?.setString('parent_pin', newPin);
          await _prefs?.setInt('pin_digits', newDigits);
          setState(() {
            _parentPin = newPin;
            _pinDigits = newDigits;
          });
        },
        onDigitsChanged: (digits) async {
          await _prefs?.setInt('pin_digits', digits);
          setState(() => _pinDigits = digits);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('設定'),
        centerTitle: true,
      ),
      body: _loaded
          ? ListView(
              padding: const EdgeInsets.all(24),
              children: [
                // ── 區塊1：基本資料（進入子頁面編輯）──
                _sectionTitle('基本資料', Icons.person_outline),

                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: ListTile(
                    leading: Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: Colors.orange.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.edit_outlined, color: Colors.orange, size: 20),
                    ),
                    title: const Text('基本資料', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                    subtitle: Text('暱稱、吉祥物名字、身高體重…', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                    trailing: Icon(Icons.chevron_right, color: Colors.grey.shade400),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const ProfileEditPage()),
                      );
                    },
                  ),
                ),

                const Divider(height: 32, thickness: 1),

                // ── 區塊2：功能開關 ──
                _sectionTitle('功能開關', Icons.tune_outlined),

                // 喝水記錄開關
                _toggleTile(
                  icon: Icons.water_drop_outlined,
                  iconColor: Colors.blue,
                  title: '喝水記錄',
                  subtitle: '顯示底部喝水頁籤',
                  value: _waterEnabled,
                  onChanged: (v) async {
                    setState(() => _waterEnabled = v);
                    await _saveBool('water_enabled', v);
                  },
                ),

                // 番茄鐘開關
                _toggleTile(
                  icon: Icons.timer_outlined,
                  iconColor: Colors.red.shade400,
                  title: '番茄鐘',
                  subtitle: '顯示底部番茄鐘頁籤',
                  value: _timerEnabled,
                  onChanged: (v) async {
                    setState(() => _timerEnabled = v);
                    await _saveBool('timer_enabled', v);
                  },
                ),

                // 體重紀錄開關
                _toggleTile(
                  icon: Icons.monitor_weight_outlined,
                  iconColor: Colors.green.shade600,
                  title: '體重紀錄習慣',
                  subtitle: '在習慣清單顯示體重紀錄項目',
                  value: _weightTrackingEnabled,
                  onChanged: (v) async {
                    setState(() => _weightTrackingEnabled = v);
                    await _saveBool('weight_tracking_enabled', v);
                  },
                ),

                const Divider(height: 32, thickness: 1),

                // ── 安全性區塊：PIN 設定 ──
                _sectionTitle('安全性', Icons.security_outlined),

                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: ListTile(
                    leading: Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: Colors.indigo.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.lock_outline, color: Colors.indigo, size: 20),
                    ),
                    title: const Text('PIN 設定', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                    // 依是否設定 PIN 顯示不同狀態文字
                    subtitle: Text(
                      (_parentPin?.isNotEmpty ?? false)
                          ? '已設定（$_pinDigits 位）'
                          : '目前未設定',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                    ),
                    trailing: Icon(Icons.chevron_right, color: Colors.grey.shade400),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    onTap: _showPinSettings,
                  ),
                ),

                const Divider(height: 32, thickness: 1),

                // ── 區塊3：資料管理 ──
                _sectionTitle('資料管理', Icons.folder_outlined),

                // 清除習慣紀錄（保留其他設定）
                _dangerButton(
                  label: '清除習慣紀錄',
                  icon: Icons.delete_outline,
                  color: Colors.orange,
                  onTap: _clearHabits,
                ),

                const SizedBox(height: 12),

                // 清除所有資料並重新引導
                _dangerButton(
                  label: '清除所有資料',
                  icon: Icons.warning_amber_rounded,
                  color: Colors.red,
                  onTap: _clearAll,
                ),

                const SizedBox(height: 24),
              ],
            )
          : const Center(child: CircularProgressIndicator()),
    );
  }
}

// ── PIN 設定底部彈出面板 ──
// 負責：PIN 位數切換、第一次設定 PIN、修改 PIN（需先輸入舊 PIN）
class _PinSettingsSheet extends StatefulWidget {
  final String? currentPin;
  final int currentDigits;
  // 儲存新 PIN 及位數的回呼
  final Future<void> Function(String pin, int digits) onSaved;
  // 僅變更位數時的回呼
  final Future<void> Function(int digits) onDigitsChanged;

  const _PinSettingsSheet({
    required this.currentPin,
    required this.currentDigits,
    required this.onSaved,
    required this.onDigitsChanged,
  });

  @override
  State<_PinSettingsSheet> createState() => _PinSettingsSheetState();
}

class _PinSettingsSheetState extends State<_PinSettingsSheet> {
  late int _digits;

  @override
  void initState() {
    super.initState();
    _digits = widget.currentDigits;
  }

  bool get _hasPin => widget.currentPin?.isNotEmpty ?? false;

  // 通用 PIN 輸入對話框
  Future<String?> _promptPin(String title) async {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          obscureText: true,
          maxLength: _digits,
          autofocus: true,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(
            hintText: '請輸入 $_digits 位數字',
            counterText: '',
          ),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('取消', style: TextStyle(color: Colors.grey.shade600)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text),
            child: const Text('確認'),
          ),
        ],
      ),
    );
  }

  // 第一次設定 PIN（輸入兩次確認）
  Future<void> _setupPin() async {
    final newPin = await _promptPin('請設定新 PIN（$_digits 位數字）');
    if (newPin == null || newPin.length != _digits) return;

    final confirm = await _promptPin('請再次輸入 PIN 確認');
    if (!mounted || confirm == null) return;

    if (newPin != confirm) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('兩次輸入的 PIN 不一致')));
      return;
    }
    await widget.onSaved(newPin, _digits);
    if (!mounted) return;
    Navigator.pop(context);
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('PIN 已設定')));
  }

  // 修改 PIN（需先輸入舊 PIN）
  Future<void> _changePin() async {
    final old = await _promptPin('請輸入目前的 PIN');
    if (!mounted || old == null) return;

    if (old != widget.currentPin) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('舊 PIN 錯誤，請再試一次')));
      return;
    }

    final newPin = await _promptPin('請設定新 PIN（$_digits 位數字）');
    if (newPin == null || newPin.length != _digits) return;

    final confirm = await _promptPin('請再次輸入新 PIN 確認');
    if (!mounted || confirm == null) return;

    if (newPin != confirm) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('兩次輸入的 PIN 不一致')));
      return;
    }
    await widget.onSaved(newPin, _digits);
    if (!mounted) return;
    Navigator.pop(context);
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('PIN 已更新')));
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Padding(
      // 讓鍵盤彈出時不遮住內容
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 32,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 標題列
          Row(
            children: [
              Icon(Icons.lock_outline, color: primary),
              const SizedBox(width: 8),
              const Text(
                'PIN 設定',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // PIN 位數選擇（4位 / 6位）
          const Text(
            'PIN 位數',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _DigitChip(
                digits: 4,
                selected: _digits == 4,
                color: primary,
                onTap: () async {
                  setState(() => _digits = 4);
                  await widget.onDigitsChanged(4);
                },
              ),
              const SizedBox(width: 10),
              _DigitChip(
                digits: 6,
                selected: _digits == 6,
                color: primary,
                onTap: () async {
                  setState(() => _digits = 6);
                  await widget.onDigitsChanged(6);
                },
              ),
            ],
          ),
          const SizedBox(height: 24),

          // 設定 / 修改 PIN 按鈕
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _hasPin ? _changePin : _setupPin,
              icon: Icon(_hasPin ? Icons.lock_reset : Icons.lock_open),
              label: Text(_hasPin ? '修改 PIN' : '設定 PIN'),
            ),
          ),

          if (_hasPin)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Center(
                child: Text(
                  '目前已設定 ${widget.currentDigits} 位 PIN',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// 位數選擇 Chip
class _DigitChip extends StatelessWidget {
  final int digits;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  const _DigitChip({
    required this.digits,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? color : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? color : Colors.grey.shade300),
        ),
        child: Text(
          '$digits 位',
          style: TextStyle(
            color: selected ? Colors.white : Colors.grey.shade700,
            fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}
