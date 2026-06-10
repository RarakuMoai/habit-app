import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/prefs_keys.dart';

// 功能開關頁：集中管理各頁籤的顯示開關
class FeatureSettingsPage extends StatefulWidget {
  const FeatureSettingsPage({super.key});

  @override
  State<FeatureSettingsPage> createState() => _FeatureSettingsPageState();
}

class _FeatureSettingsPageState extends State<FeatureSettingsPage> {
  bool _timerEnabled = true;
  bool _waterEnabled = false;
  bool _weightTrackingEnabled = false;
  bool _familyEnabled = false;
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
      _timerEnabled = _prefs!.getBool(PrefsKeys.timerEnabled) ?? true;
      _waterEnabled = _prefs!.getBool(PrefsKeys.waterEnabled) ?? false;
      _weightTrackingEnabled =
          _prefs!.getBool(PrefsKeys.weightTrackingEnabled) ?? false;
      _familyEnabled = _prefs!.getBool(PrefsKeys.familyEnabled) ?? false;
      _loaded = true;
    });
  }

  Future<void> _saveBool(String key, bool value) async {
    await _prefs?.setBool(key, value);
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('功能開關'),
        centerTitle: true,
      ),
      body: _loaded
          ? ListView(
              padding: const EdgeInsets.all(24),
              children: [
                // 番茄鐘開關
                _toggleTile(
                  icon: Icons.timer_outlined,
                  iconColor: Colors.red.shade400,
                  title: '番茄鐘',
                  subtitle: '顯示底部番茄鐘頁籤',
                  value: _timerEnabled,
                  onChanged: (v) async {
                    setState(() => _timerEnabled = v);
                    await _saveBool(PrefsKeys.timerEnabled, v);
                  },
                ),

                // 喝水頁開關
                _toggleTile(
                  icon: Icons.water_drop_outlined,
                  iconColor: Colors.blue,
                  title: '喝水紀錄',
                  subtitle: '顯示底部喝水頁籤',
                  value: _waterEnabled,
                  onChanged: (v) async {
                    setState(() => _waterEnabled = v);
                    await _saveBool(PrefsKeys.waterEnabled, v);
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
                    await _saveBool(PrefsKeys.weightTrackingEnabled, v);
                  },
                ),

                // 家庭模式開關
                _toggleTile(
                  icon: Icons.family_restroom,
                  iconColor: Colors.purple,
                  title: '家庭模式',
                  subtitle: '顯示底部家庭頁籤',
                  value: _familyEnabled,
                  onChanged: (v) async {
                    setState(() => _familyEnabled = v);
                    await _saveBool(PrefsKeys.familyEnabled, v);
                  },
                ),
              ],
            )
          : const Center(child: CircularProgressIndicator()),
    );
  }
}
