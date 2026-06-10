import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/audio_settings_service.dart';
import '../utils/bgm_service.dart';
import '../utils/units.dart';
import 'feature_settings_page.dart';
import 'profile_edit_page.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _loaded = false;

  // PIN 相關狀態
  String? _parentPin; // null 表示尚未設定
  int _pinDigits = 4; // 4 或 6 位

  // 公制 / 英制
  UnitSystem _unitSystem = UnitSystem.metric;

  SharedPreferences? _prefs;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    _prefs = await SharedPreferences.getInstance();
    setState(() {
      _parentPin = _prefs!.getString('parent_pin');
      _pinDigits = _prefs!.getInt('pin_digits') ?? 4;
      _unitSystem = UnitSystem.load(_prefs!);
      _loaded = true;
    });
  }

  Future<void> _setUnitSystem(UnitSystem v) async {
    if (v == _unitSystem) return;
    setState(() => _unitSystem = v);
    if (_prefs != null) await UnitSystem.save(_prefs!, v);
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

  // 驗證數字密碼（危險操作前的把關），通過回傳 true
  Future<bool> _verifyPin() async {
    final ctrl = TextEditingController();
    var obscure = true;
    final entered = await showDialog<String>(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (_, setS) => AlertDialog(
          title: const Text('請輸入數字密碼'),
          content: TextField(
            controller: ctrl,
            keyboardType: TextInputType.number,
            obscureText: obscure,
            maxLength: _pinDigits,
            autofocus: true,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(
              hintText: '請輸入 $_pinDigits 位數字',
              counterText: '',
              suffixIcon: IconButton(
                icon: Icon(obscure ? Icons.visibility_off : Icons.visibility),
                onPressed: () => setS(() => obscure = !obscure),
              ),
            ),
            onChanged: (v) {
              if (v.length == _pinDigits) Navigator.pop(dialogCtx, v);
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
    if (entered == null) return false;
    if (entered == _parentPin) return true;
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('密碼錯誤')));
    }
    return false;
  }

  // 刪除所有體重紀錄（其他資料保留）
  Future<void> _clearWeightRecords() async {
    // 計算目前筆數
    final json = _prefs?.getString('weight_records');
    var count = 0;
    if (json != null) {
      final decoded = jsonDecode(json);
      if (decoded is List) count = decoded.length;
    }
    if (count == 0) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('目前沒有體重紀錄')));
      return;
    }

    // 有設定數字密碼時先驗證
    if (_parentPin?.isNotEmpty ?? false) {
      final ok = await _verifyPin();
      if (!ok || !mounted) return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('刪除所有體重紀錄'),
        content: Text('確定要刪除全部 $count 筆體重紀錄嗎？此操作無法復原。'),
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
    if (confirm == true) {
      await _prefs?.remove('weight_records');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('已刪除所有體重紀錄')));
      }
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
      // 切回引導 BGM（cross-fade），音樂與音效也恢復為開啟。
      await AudioSettingsService.instance.setAllMuted(false);
      unawaited(BgmService.instance.play('sounds/bgm_onboarding.m4a'));
      unawaited(nav.pushNamedAndRemoveUntil('/onboarding', (_) => false));
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
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
    );
  }

  Future<void> _showPinSettings() async {
    await showModalBottomSheet<void>(
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
      appBar: AppBar(title: const Text('設定'), centerTitle: true),
      body: _loaded
          ? ListView(
              padding: const EdgeInsets.all(24),
              children: [
                // ── 區塊1：基本資料（進入子頁面編輯）──
                _sectionTitle('基本資料', Icons.person_outline),

                DecoratedBox(
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
                      child: const Icon(
                        Icons.edit_outlined,
                        color: Colors.orange,
                        size: 20,
                      ),
                    ),
                    title: const Text(
                      '基本資料',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: Text(
                      '暱稱、吉祥物名字、身高體重…',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade500,
                      ),
                    ),
                    trailing: Icon(
                      Icons.chevron_right,
                      color: Colors.grey.shade400,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const ProfileEditPage(),
                        ),
                      );
                    },
                  ),
                ),

                const Divider(height: 32, thickness: 1),

                // ── 區塊：單位（公制／英制）──
                _sectionTitle('單位', Icons.straighten_outlined),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '身高、體重、容量的顯示方式',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                      const SizedBox(height: 10),
                      SegmentedButton<UnitSystem>(
                        segments: const [
                          ButtonSegment(
                            value: UnitSystem.metric,
                            label: Text('公制'),
                            icon: Icon(Icons.straighten),
                          ),
                          ButtonSegment(
                            value: UnitSystem.imperial,
                            label: Text('英制'),
                            icon: Icon(Icons.square_foot),
                          ),
                        ],
                        selected: {_unitSystem},
                        onSelectionChanged: (sel) => _setUnitSystem(sel.first),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _unitSystem == UnitSystem.metric
                            ? 'cm · kg · ml' // units-ok
                            : 'ft / in · lb · fl oz', // units-ok
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade500,
                        ),
                      ),
                    ],
                  ),
                ),

                const Divider(height: 32, thickness: 1),

                // ── 區塊2：功能開關（進入獨立子頁面）──
                _sectionTitle('功能開關', Icons.tune_outlined),

                DecoratedBox(
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
                        color: Colors.teal.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.tune_outlined,
                        color: Colors.teal,
                        size: 20,
                      ),
                    ),
                    title: const Text(
                      '功能開關',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: Text(
                      '番茄鐘、喝水、體重、家庭模式…',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade500,
                      ),
                    ),
                    trailing: Icon(
                      Icons.chevron_right,
                      color: Colors.grey.shade400,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const FeatureSettingsPage(),
                        ),
                      );
                    },
                  ),
                ),

                const Divider(height: 32, thickness: 1),

                // ── 安全性區塊：PIN 設定 ──
                _sectionTitle('安全性', Icons.security_outlined),

                DecoratedBox(
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
                      child: const Icon(
                        Icons.lock_outline,
                        color: Colors.indigo,
                        size: 20,
                      ),
                    ),
                    title: const Text(
                      '數字密碼設定',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    // 依是否設定數字密碼顯示不同狀態文字
                    subtitle: Text(
                      (_parentPin?.isNotEmpty ?? false)
                          ? '已設定（$_pinDigits 位）'
                          : '目前未設定',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade500,
                      ),
                    ),
                    trailing: Icon(
                      Icons.chevron_right,
                      color: Colors.grey.shade400,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
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

                // 刪除所有體重紀錄（保留其他設定，有密碼時需驗證）
                _dangerButton(
                  label: '刪除所有體重紀錄',
                  icon: Icons.monitor_weight_outlined,
                  color: Colors.orange,
                  onTap: _clearWeightRecords,
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

  // 驗證舊 PIN：滿位數自動確認，僅顯示取消，含顯示/隱藏切換
  Future<String?> _promptOldPin(String title) async {
    final ctrl = TextEditingController();
    var obscure = true;
    return showDialog<String>(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (_, setS) => AlertDialog(
          title: Text(title),
          content: TextField(
            controller: ctrl,
            keyboardType: TextInputType.number,
            obscureText: obscure,
            maxLength: _digits,
            autofocus: true,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(
              hintText: '請輸入 $_digits 位數字',
              counterText: '',
              suffixIcon: IconButton(
                icon: Icon(obscure ? Icons.visibility_off : Icons.visibility),
                onPressed: () => setS(() => obscure = !obscure),
              ),
            ),
            onChanged: (v) {
              if (v.length == _digits) Navigator.pop(dialogCtx, v);
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

  // 設定／確認新 PIN：需按確認按鈕，不自動送出，含顯示/隱藏切換
  Future<String?> _promptNewPin(String title) async {
    final ctrl = TextEditingController();
    var obscure = true;
    return showDialog<String>(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (_, setS) => AlertDialog(
          title: Text(title),
          content: TextField(
            controller: ctrl,
            keyboardType: TextInputType.number,
            obscureText: obscure,
            maxLength: _digits,
            autofocus: true,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(
              hintText: '請輸入 $_digits 位數字',
              counterText: '',
              suffixIcon: IconButton(
                icon: Icon(obscure ? Icons.visibility_off : Icons.visibility),
                onPressed: () => setS(() => obscure = !obscure),
              ),
            ),
            onChanged: (v) => setS(() {}), // 觸發重繪，更新確認按鈕狀態
            onSubmitted: (v) {
              if (ctrl.text.length == _digits) {
                Navigator.pop(dialogCtx, ctrl.text);
              }
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: Text('取消', style: TextStyle(color: Colors.grey.shade600)),
            ),
            TextButton(
              // 位數未達要求時禁用確認按鈕
              onPressed: ctrl.text.length == _digits
                  ? () => Navigator.pop(dialogCtx, ctrl.text)
                  : null,
              child: const Text('確認'),
            ),
          ],
        ),
      ),
    );
  }

  // 第一次設定 PIN（輸入兩次確認）
  Future<void> _setupPin() async {
    final newPin = await _promptNewPin('請設定新密碼（$_digits 位數字）');
    if (newPin == null || newPin.length != _digits) return;

    final confirm = await _promptNewPin('請再次輸入密碼確認');
    if (!mounted || confirm == null) return;

    if (newPin != confirm) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('兩次輸入的密碼不一致')));
      return;
    }
    await widget.onSaved(newPin, _digits);
    if (!mounted) return;
    Navigator.pop(context);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('密碼已設定')));
  }

  // 修改 PIN（需先輸入舊 PIN）
  Future<void> _changePin() async {
    final old = await _promptOldPin('請輸入目前的密碼');
    if (!mounted || old == null) return;

    if (old != widget.currentPin) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('舊密碼錯誤，請再試一次')));
      return;
    }

    final newPin = await _promptNewPin('請設定新密碼（$_digits 位數字）');
    if (newPin == null || newPin.length != _digits) return;

    final confirm = await _promptNewPin('請再次輸入新密碼確認');
    if (!mounted || confirm == null) return;

    if (newPin != confirm) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('兩次輸入的密碼不一致')));
      return;
    }
    await widget.onSaved(newPin, _digits);
    if (!mounted) return;
    Navigator.pop(context);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('密碼已更新')));
  }

  // 切換 PIN 位數（有 PIN 時需先驗證舊 PIN 再重設新 PIN）
  Future<void> _changeDigits(int newDigits) async {
    if (newDigits == _digits) return;

    if (!_hasPin) {
      // 尚未設定 PIN，直接套用新位數
      setState(() => _digits = newDigits);
      await widget.onDigitsChanged(newDigits);
      return;
    }

    // 已設定數字密碼：先用目前位數驗證舊密碼
    final old = await _promptOldPin('請輸入目前的密碼（$_digits 位）');
    if (!mounted || old == null) return;

    if (old != widget.currentPin) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('舊密碼錯誤，請再試一次')));
      return;
    }

    // 驗證通過，切換至新位數並要求重設密碼（兩次確認）
    setState(() => _digits = newDigits);

    final newPin = await _promptNewPin('請設定新密碼（$newDigits 位）');
    if (!mounted || newPin == null || newPin.length != newDigits) {
      setState(() => _digits = widget.currentDigits);
      return;
    }

    final confirm = await _promptNewPin('請再次輸入新密碼確認');
    if (!mounted || confirm == null) {
      setState(() => _digits = widget.currentDigits);
      return;
    }

    if (newPin != confirm) {
      setState(() => _digits = widget.currentDigits);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('兩次輸入的密碼不一致')));
      return;
    }

    await widget.onSaved(newPin, newDigits);
    if (!mounted) return;
    Navigator.pop(context);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('位數已更新，密碼已重設')));
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
                '數字密碼設定',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // 密碼位數選擇（4位 / 6位）
          const Text(
            '密碼位數',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _DigitChip(
                digits: 4,
                selected: _digits == 4,
                color: primary,
                onTap: () => _changeDigits(4),
              ),
              const SizedBox(width: 10),
              _DigitChip(
                digits: 6,
                selected: _digits == 6,
                color: primary,
                onTap: () => _changeDigits(6),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // 設定 / 修改密碼按鈕
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _hasPin ? _changePin : _setupPin,
              icon: Icon(_hasPin ? Icons.lock_reset : Icons.lock_open),
              label: Text(_hasPin ? '修改密碼' : '設定密碼'),
            ),
          ),

          if (_hasPin)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Center(
                child: Text(
                  '目前已設定 ${widget.currentDigits} 位數字密碼',
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
