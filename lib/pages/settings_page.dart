import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/app_feedback.dart';
import '../utils/app_style.dart';
import '../utils/feature_flags.dart';
import '../utils/logical_date.dart';
import '../utils/parent_pin.dart';
import '../utils/prefs_keys.dart';
import '../utils/units.dart';
import '../widgets/app_dialogs.dart';
import '../widgets/settings_ui.dart';
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

  // 換日線：一天從幾點開始（0~6 小時）
  int _dayStartHour = LogicalDate.defaultHour;

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
      _dayStartHour = LogicalDate.load(_prefs!);
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

  Future<void> _setDayStartHour(int h) async {
    final v = h.clamp(LogicalDate.minHour, LogicalDate.maxHour);
    if (v == _dayStartHour) return;
    playHaptic(HapticLevel.selection);
    setState(() => _dayStartHour = v);
    if (_prefs != null) await LogicalDate.save(_prefs!, v);
  }

  // 換日時間顯示文字（0 點 = 午夜；建議值 4 點另在時間軸上標「建議」）。
  String _dayStartLabel(int h) => h == 0 ? '午夜 0:00' : '凌晨 $h:00';

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

                SettingsTileCard(
                  icon: Icons.edit_outlined,
                  iconColor: Colors.orange,
                  title: '基本資料',
                  subtitle: '暱稱、吉祥物名字、身高體重…',
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const ProfileEditPage(),
                      ),
                    );
                  },
                ),

                const Divider(height: 32, thickness: 1),

                // ── 區塊：單位（公制／英制）──
                _sectionTitle('單位', Icons.straighten_outlined),
                SettingsGroupCard(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '身高、體重、容量的顯示方式',
                        style: TextStyle(fontSize: 12, color: AppInk.soft),
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
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppInk.soft,
                        ),
                      ),
                    ],
                  ),
                ),

                const Divider(height: 32, thickness: 1),

                // ── 區塊：換日時間（夜貓族把午夜往後挪）──
                _sectionTitle('換日時間', Icons.bedtime_outlined),
                SettingsGroupCard(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '幾點之後才算新的一天。睡前（這個時間以前）紀錄的喝水、'
                        '體重、習慣都還算「昨天」，晚睡也不會被換日。',
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.5,
                          color: AppInk.soft,
                        ),
                      ),
                      const SizedBox(height: 16),
                      _DayStartTimeline(
                        value: _dayStartHour,
                        minHour: LogicalDate.minHour,
                        maxHour: LogicalDate.maxHour,
                        onChanged: _setDayStartHour,
                      ),
                      const SizedBox(height: 14),
                      Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: _DayStartTimeline.night.withValues(
                              alpha: 0.08,
                            ),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.nightlight_round,
                                size: 14,
                                color: _DayStartTimeline.night,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                _dayStartLabel(_dayStartHour),
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: AppInk.strong,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        '金幣每日獎勵不受影響，仍以午夜計算。',
                        style: TextStyle(fontSize: 11, color: AppInk.faint),
                      ),
                    ],
                  ),
                ),

                const Divider(height: 32, thickness: 1),

                // ── 區塊2：功能開關（進入獨立子頁面）──
                _sectionTitle('功能開關', Icons.tune_outlined),

                SettingsTileCard(
                  icon: Icons.tune_outlined,
                  iconColor: Colors.teal,
                  title: '功能開關',
                  subtitle: '計時、喝水、體重、家庭模式…',
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const FeatureSettingsPage(),
                      ),
                    );
                  },
                ),

                const Divider(height: 32, thickness: 1),

                // ── 安全性區塊：PIN 設定 ──
                _sectionTitle('安全性', Icons.security_outlined),

                SettingsTileCard(
                  icon: Icons.lock_outline,
                  iconColor: Colors.indigo,
                  title: '數字密碼設定',
                  // 依是否設定數字密碼顯示不同狀態文字
                  subtitle: _hasPin ? '已設定（$_pinDigits 位）' : '目前未設定',
                  onTap: _showPinSettings,
                ),

                const Divider(height: 32, thickness: 1),

                // ── 區塊3：進階 ──
                _sectionTitle('進階', Icons.admin_panel_settings_outlined),

                SettingsTileCard(
                  icon: Icons.admin_panel_settings_outlined,
                  iconColor: Colors.deepOrange,
                  title: '進階設定',
                  subtitle: '資料刪除等較高風險操作',
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const AdvancedSettingsPage(),
                      ),
                    );
                  },
                ),

                // ── 區塊4：開發者測試（kDevToolsEnabled 控制；目前 release 也暫時開）──
                if (kDevToolsEnabled) ...[
                  const SizedBox(height: 24),
                  _sectionTitle('開發者測試', Icons.science_outlined),
                  SettingsTileCard(
                    icon: Icons.science_outlined,
                    iconColor: Colors.blueGrey,
                    title: '開發者測試',
                    subtitle: '模擬分頁、場景時段…（測試用，正式版會移除）',
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const DevTestPage(),
                        ),
                      );
                    },
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
          actions: [dialogCancelAction(dialogCtx)],
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
            dialogCancelAction(dialogCtx),
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
                  style: const TextStyle(fontSize: 12, color: AppInk.soft),
                ),
              ),
            ),
            const SizedBox(height: 18),
            const Divider(height: 1),
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(
                  Icons.help_outline_rounded,
                  size: 20,
                  color: AppInk.soft,
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
                          color: _hasQA ? AppInk.soft : Colors.orange.shade700,
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
                  foregroundColor: AppInk.soft,
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
    final hasQuestion = _isCustom
        ? _qCtrl.text.trim().isNotEmpty
        : _selected != null;
    final ready = hasQuestion && _aCtrl.text.trim().isNotEmpty;
    return AlertDialog(
      title: const Text('設定救援問題'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '忘記密碼時，答對這題就能重設密碼，資料不會被清除。挑一題只有你知道答案的問題。',
              style: TextStyle(fontSize: 12.5, color: AppInk.soft),
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
        dialogCancelAction(context, label: widget.initial ? '略過' : '取消'),
        TextButton(
          onPressed: ready
              ? () => Navigator.pop(context, (
                  question: _isCustom ? _qCtrl.text.trim() : _selected!,
                  answer: _aCtrl.text,
                ))
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
        color: selected ? color : AppSurfaces.fill,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: selected ? color : AppSurfaces.divider),
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
                color: selected ? Colors.white : AppInk.soft,
                fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 換日時間視覺化軸：一條「夜→晨」的橫軸，左側染成夜色代表「還算昨天」，
/// 右側淺底代表「新的一天」，把手停在換日點。整條軸切成 (時數+1) 個等寬
/// 槽位，把手中心永遠對齊下方刻度；點任一刻度或直接拖把手都能調整。
/// 點刻度時把手會滑過去（easeOutCubic）；拖曳時即時跟手不延遲。
class _DayStartTimeline extends StatefulWidget {
  const _DayStartTimeline({
    required this.value,
    required this.minHour,
    required this.maxHour,
    required this.onChanged,
  });

  final int value;
  final int minHour;
  final int maxHour;
  final ValueChanged<int> onChanged;

  /// 夜色（還算昨天）— 沉穩夜靛，與暖色世界觀不打架。
  static const Color night = Color(0xFF514B86);
  static const Color _nightSoft = Color(0xFF6F66A6);

  /// 白天（新的一天）— 暖金，呼應清晨日出 accent。
  static const Color _dawn = Color(0xFFD89A5B);

  static const double _trackH = 56;
  static const double _knobR = 15;

  @override
  State<_DayStartTimeline> createState() => _DayStartTimelineState();
}

class _DayStartTimelineState extends State<_DayStartTimeline> {
  // 拖曳中把手即時跟手（不動畫）；點選/外部變更才滑動過去。
  bool _dragging = false;

  int get _slotCount => widget.maxHour - widget.minHour + 1;

  void _emit(double dx, double width) {
    final slotW = width / _slotCount;
    if (slotW <= 0) return;
    final h = (dx / slotW).floor() + widget.minHour;
    widget.onChanged(h.clamp(widget.minHour, widget.maxHour));
  }

  @override
  Widget build(BuildContext context) {
    const night = _DayStartTimeline.night;
    const dawn = _DayStartTimeline._dawn;
    const trackH = _DayStartTimeline._trackH;
    const knobR = _DayStartTimeline._knobR;
    final duration = _dragging
        ? Duration.zero
        : const Duration(milliseconds: 300);
    const curve = Curves.easeOutCubic;

    return LayoutBuilder(
      builder: (context, c) {
        final width = c.maxWidth;
        final slotW = width / _slotCount;
        // 把手中心對齊「value 槽」的正中央。
        final knobX = slotW * (widget.value - widget.minHour + 0.5);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 上排區段標籤：左夜右晨
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 2),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _ZoneLabel(Icons.bedtime_rounded, '還算昨天', night),
                  _ZoneLabel(Icons.wb_twilight_rounded, '新的一天', dawn),
                ],
              ),
            ),
            const SizedBox(height: 9),
            // 軌道 + 夜色填充 + 把手
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (d) => _emit(d.localPosition.dx, width),
              onPanStart: (d) {
                setState(() => _dragging = true);
                _emit(d.localPosition.dx, width);
              },
              onPanUpdate: (d) => _emit(d.localPosition.dx, width),
              onPanEnd: (_) => setState(() => _dragging = false),
              onPanCancel: () => setState(() => _dragging = false),
              child: SizedBox(
                height: trackH,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    // 底軌（新的一天）：淺夜靛
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: const Color(0xFFEFEDF7),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: const Color(0x14514B86)),
                        ),
                      ),
                    ),
                    // 夜色填充（還算昨天）：左端到把手，寬度隨值滑動
                    AnimatedPositioned(
                      duration: duration,
                      curve: curve,
                      left: 0,
                      top: 0,
                      bottom: 0,
                      width: knobX.clamp(0.0, width),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: const Stack(
                          children: [
                            Positioned.fill(
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [
                                      night,
                                      _DayStartTimeline._nightSoft,
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            // 夜色裡的小星點，隨夜色變寬陸續露出。
                            ..._stars,
                          ],
                        ),
                      ),
                    ),
                    // 把手：白圓 + 夜靛描邊 + 月亮，滑動過去
                    AnimatedPositioned(
                      duration: duration,
                      curve: curve,
                      left: knobX - knobR,
                      top: trackH / 2 - knobR,
                      child: _knob(),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            // 下排刻度：每槽一個，點擊可直接選；建議值（4）標「建議」
            Row(
              children: List.generate(_slotCount, (i) {
                final h = widget.minHour + i;
                final selected = h == widget.value;
                final recommended = h == LogicalDate.defaultHour;
                return Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => widget.onChanged(h),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          h == 0 ? '午夜' : '$h',
                          textAlign: TextAlign.center,
                          style: AppType.digits(
                            fontSize: h == 0 ? 11 : 13,
                            fontWeight: selected
                                ? FontWeight.w800
                                : FontWeight.w600,
                            color: selected ? night : AppInk.faint,
                          ),
                        ),
                        const SizedBox(height: 1),
                        // 固定高度的「建議」列，讓每個刻度等高、不跳行
                        SizedBox(
                          height: 14,
                          child: recommended
                              ? Text(
                                  '建議',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: night.withValues(alpha: 0.8),
                                  ),
                                )
                              : null,
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ),
          ],
        );
      },
    );
  }

  static const List<Widget> _stars = [
    Positioned(left: 16, top: 14, child: _Star(2.5)),
    Positioned(left: 38, top: 32, child: _Star(2)),
    Positioned(left: 64, top: 18, child: _Star(3)),
    Positioned(left: 92, top: 36, child: _Star(2)),
    Positioned(left: 120, top: 16, child: _Star(2.5)),
  ];

  Widget _knob() => Container(
    width: _DayStartTimeline._knobR * 2,
    height: _DayStartTimeline._knobR * 2,
    decoration: BoxDecoration(
      color: Colors.white,
      shape: BoxShape.circle,
      border: Border.all(color: _DayStartTimeline.night, width: 2.5),
      boxShadow: AppShadows.flat,
    ),
    child: const Icon(
      Icons.nightlight_round,
      size: 13,
      color: _DayStartTimeline.night,
    ),
  );
}

/// 時間軸上方的區段標籤（左夜右晨）。
class _ZoneLabel extends StatelessWidget {
  const _ZoneLabel(this.icon, this.text, this.color);
  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 14, color: color),
      const SizedBox(width: 4),
      Text(
        text,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    ],
  );
}

/// 夜色填充裡的小星點。
class _Star extends StatelessWidget {
  const _Star(this.size);
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: const BoxDecoration(
      color: Color(0x80FFFFFF),
      shape: BoxShape.circle,
    ),
  );
}
