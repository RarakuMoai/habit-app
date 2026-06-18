import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/app_feedback.dart';
import '../utils/feature_flags.dart';
import '../utils/parent_pin.dart';
import '../utils/prefs_keys.dart';
import '../utils/units.dart';
import 'advanced_settings_page.dart';
import 'dev_test_page.dart';
import 'family/parent_pin_recovery.dart';
import 'feature_settings_page.dart';
import 'profile_edit_page.dart';

class SettingsPage extends StatefulWidget {
  final bool openPinSettingsOnLoad;

  const SettingsPage({super.key, this.openPinSettingsOnLoad = false});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _loaded = false;

  // PIN 相關狀態（明文不進記憶體，只記有沒有設定）
  bool _hasPin = false;
  int _pinDigits = 4; // 4 或 6 位

  // 公制 / 英制
  UnitSystem _unitSystem = UnitSystem.metric;

  SharedPreferences? _prefs;
  bool _openedInitialPinSettings = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    _prefs = await SharedPreferences.getInstance();
    final hasPin = await ParentPin.hasPin(_prefs!);
    if (!mounted) return;
    setState(() {
      _hasPin = hasPin;
      _pinDigits = _prefs!.getInt(PrefsKeys.pinDigits) ?? 4;
      _unitSystem = UnitSystem.load(_prefs!);
      _loaded = true;
    });
    if (widget.openPinSettingsOnLoad && !_openedInitialPinSettings) {
      _openedInitialPinSettings = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_showPinSettings());
      });
    }
  }

  Future<void> _setUnitSystem(UnitSystem v) async {
    if (v == _unitSystem) return;
    playHaptic(HapticLevel.selection);
    setState(() => _unitSystem = v);
    if (_prefs != null) await UnitSystem.save(_prefs!, v);
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

  Future<void> _showPinSettings() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _PinSettingsSheet(
        hasPin: _hasPin,
        currentDigits: _pinDigits,
        onSaved: (newPin, newDigits) async {
          if (_prefs != null) await ParentPin.save(_prefs!, newPin);
          await _prefs?.setInt(PrefsKeys.pinDigits, newDigits);
          setState(() {
            _hasPin = true;
            _pinDigits = newDigits;
          });
        },
        onDigitsChanged: (digits) async {
          await _prefs?.setInt(PrefsKeys.pinDigits, digits);
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
                      '計時、喝水、體重、家庭模式…',
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
                      _hasPin ? '已設定（$_pinDigits 位）' : '目前未設定',
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

                // ── 區塊3：進階 ──
                _sectionTitle('進階', Icons.admin_panel_settings_outlined),

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
                        color: Colors.deepOrange.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.admin_panel_settings_outlined,
                        color: Colors.deepOrange,
                        size: 20,
                      ),
                    ),
                    title: const Text(
                      '進階設定',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: Text(
                      '資料刪除等較高風險操作',
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
                          builder: (_) => const AdvancedSettingsPage(),
                        ),
                      );
                    },
                  ),
                ),

                // ── 區塊4：開發者測試（kDevToolsEnabled 控制；目前 release 也暫時開）──
                if (kDevToolsEnabled) ...[
                  const SizedBox(height: 24),
                  _sectionTitle('開發者測試', Icons.science_outlined),
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
                          color: Colors.blueGrey.withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.science_outlined,
                          color: Colors.blueGrey,
                          size: 20,
                        ),
                      ),
                      title: const Text(
                        '開發者測試',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      subtitle: Text(
                        '模擬分頁、場景時段…（測試用，正式版會移除）',
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
                            builder: (_) => const DevTestPage(),
                          ),
                        );
                      },
                    ),
                  ),
                ],

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
  final bool hasPin;
  final int currentDigits;
  // 儲存新 PIN 及位數的回呼
  final Future<void> Function(String pin, int digits) onSaved;
  // 僅變更位數時的回呼
  final Future<void> Function(int digits) onDigitsChanged;

  const _PinSettingsSheet({
    required this.hasPin,
    required this.currentDigits,
    required this.onSaved,
    required this.onDigitsChanged,
  });

  @override
  State<_PinSettingsSheet> createState() => _PinSettingsSheetState();
}

class _PinSettingsSheetState extends State<_PinSettingsSheet> {
  late int _digits;
  late bool _hasPin;
  bool _hasQA = false; // 是否已設定忘記密碼救援問題

  @override
  void initState() {
    super.initState();
    _digits = widget.currentDigits;
    _hasPin = widget.hasPin;
    _loadQA();
  }

  Future<void> _loadQA() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() => _hasQA = ParentPin.hasSecurityQuestion(prefs));
  }

  // 對照儲存的雜湊驗證舊 PIN
  Future<bool> _verifyOldPin(String entered) async {
    final prefs = await SharedPreferences.getInstance();
    return ParentPin.verify(prefs, entered);
  }

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
    setState(() => _hasPin = true);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('密碼已設定')));
    // 首次設定後引導設救援問題（可略過），讓忘記密碼時能不丟資料重設。
    // 不自動關閉面板，讓使用者能看到救援問題狀態與「忘記密碼」入口。
    await _setupSecurityQuestion(initial: true);
  }

  // 設定／修改救援安全問題。initial=true 是「首次設密碼後的引導」，可略過。
  Future<void> _setupSecurityQuestion({bool initial = false}) async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    final current = ParentPin.securityQuestion(prefs);
    final result = await showDialog<({String question, String answer})>(
      context: context,
      builder: (_) =>
          _SecurityQuestionDialog(initial: initial, initialQuestion: current),
    );
    if (result == null || !mounted) return;
    await ParentPin.saveSecurityQuestion(prefs, result.question, result.answer);
    if (!mounted) return;
    setState(() => _hasQA = true);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('救援問題已設定')));
  }

  // 忘記密碼：答對救援問題重設，或清空重來。成功就關閉本面板。
  Future<void> _forgotPassword() async {
    final ok = await showForgotParentPin(context);
    if (ok && mounted) Navigator.pop(context);
  }

  // 修改 PIN（需先輸入舊 PIN）
  Future<void> _changePin() async {
    final old = await _promptOldPin('請輸入目前的密碼');
    if (!mounted || old == null) return;

    if (!await _verifyOldPin(old)) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('舊密碼錯誤，請再試一次')));
      return;
    }
    if (!mounted) return;

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

    if (!await _verifyOldPin(old)) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('舊密碼錯誤，請再試一次')));
      return;
    }
    if (!mounted) return;

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

          if (_hasPin) ...[
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Center(
                child: Text(
                  '目前已設定 $_digits 位數字密碼',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                ),
              ),
            ),
            const SizedBox(height: 18),
            const Divider(height: 1),
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(
                  Icons.help_outline_rounded,
                  size: 20,
                  color: Colors.grey.shade600,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '忘記密碼救援問題',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _hasQA ? '已設定，忘記密碼可用它重設' : '尚未設定（建議設定，免得忘記只能清空）',
                        style: TextStyle(
                          fontSize: 12,
                          color: _hasQA
                              ? Colors.grey.shade500
                              : Colors.orange.shade700,
                        ),
                      ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: _setupSecurityQuestion,
                  child: Text(_hasQA ? '修改' : '設定'),
                ),
              ],
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _forgotPassword,
                style: TextButton.styleFrom(
                  foregroundColor: Colors.grey.shade700,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
                icon: const Icon(Icons.lock_reset_rounded, size: 18),
                label: const Text('忘記密碼？'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// 救援問題設定對話框：從預設問題挑一題（或自訂），填答案才可儲存。
// 預設清單避免使用者每次都要自己想問題；最後一項「自訂問題…」保留彈性。
// controller 由 State 持有，dispose 綁 widget 生命週期（避免退場期間被存取）。
class _SecurityQuestionDialog extends StatefulWidget {
  final bool initial;
  final String? initialQuestion; // 修改時帶入現有問題，預選對應項
  const _SecurityQuestionDialog({required this.initial, this.initialQuestion});

  @override
  State<_SecurityQuestionDialog> createState() =>
      _SecurityQuestionDialogState();
}

class _SecurityQuestionDialogState extends State<_SecurityQuestionDialog> {
  // 預設救援問題。問句設計成答案短、唯一、不易隨時間改變。
  static const _presetQuestions = <String>[
    '我的第一隻寵物叫什麼名字？',
    '我母親（媽媽）的名字是？',
    '我出生的城市是哪裡？',
    '我就讀的第一所學校叫什麼？',
    '我童年最好的朋友叫什麼名字？',
    '我最喜歡的一道菜是什麼？',
  ];
  static const _customValue = '__custom__'; // 下拉「自訂問題…」的哨兵值

  final _qCtrl = TextEditingController(); // 僅自訂時使用
  final _aCtrl = TextEditingController();
  String? _selected; // 選中的預設問題，或 _customValue

  @override
  void initState() {
    super.initState();
    final q = widget.initialQuestion;
    if (q != null && q.isNotEmpty) {
      if (_presetQuestions.contains(q)) {
        _selected = q;
      } else {
        _selected = _customValue;
        _qCtrl.text = q;
      }
    }
  }

  @override
  void dispose() {
    _qCtrl.dispose();
    _aCtrl.dispose();
    super.dispose();
  }

  bool get _isCustom => _selected == _customValue;

  @override
  Widget build(BuildContext context) {
    final hasQuestion = _isCustom ? _qCtrl.text.trim().isNotEmpty : _selected != null;
    final ready = hasQuestion && _aCtrl.text.trim().isNotEmpty;
    return AlertDialog(
      title: const Text('設定救援問題'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '忘記密碼時，答對這題就能重設密碼，資料不會被清除。挑一題只有你知道答案的問題。',
              style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              initialValue: _selected,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: '問題',
                border: OutlineInputBorder(),
              ),
              hint: const Text('選擇一個問題'),
              items: [
                for (final q in _presetQuestions)
                  DropdownMenuItem(
                    value: q,
                    child: Text(q, overflow: TextOverflow.ellipsis),
                  ),
                const DropdownMenuItem(
                  value: _customValue,
                  child: Text('自訂問題…'),
                ),
              ],
              onChanged: (v) => setState(() => _selected = v),
            ),
            if (_isCustom) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _qCtrl,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: '自訂問題',
                  hintText: '例如：我的機車車牌末三碼？',
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => setState(() {}),
              ),
            ],
            const SizedBox(height: 12),
            TextField(
              controller: _aCtrl,
              decoration: const InputDecoration(
                labelText: '答案',
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(
            widget.initial ? '略過' : '取消',
            style: TextStyle(color: Colors.grey.shade600),
          ),
        ),
        TextButton(
          onPressed: ready
              ? () => Navigator.pop(
                  context,
                  (
                    question: _isCustom ? _qCtrl.text.trim() : _selected!,
                    answer: _aCtrl.text,
                  ),
                )
              : null,
          child: const Text('儲存'),
        ),
      ],
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
    return DecoratedBox(
      decoration: BoxDecoration(
        color: selected ? color : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: selected ? color : Colors.grey.shade300),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          splashColor: color.withValues(alpha: 0.18),
          highlightColor: color.withValues(alpha: 0.08),
          onTap: () {
            playHaptic(HapticLevel.selection);
            onTap();
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
            child: Text(
              '$digits 位',
              style: TextStyle(
                color: selected ? Colors.white : Colors.grey.shade700,
                fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
