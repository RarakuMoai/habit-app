import 'package:flutter/material.dart';
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
