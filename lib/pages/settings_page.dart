import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/app_localizations.dart';
import '../utils/app_feedback.dart';
import '../utils/app_style.dart';
import '../utils/coin_service.dart';
import '../utils/feature_flags.dart';
import '../utils/logical_date.dart';
import '../utils/mascot.dart';
import '../utils/parent_pin.dart';
import '../utils/prefs_keys.dart';
import '../utils/units.dart';
import '../widgets/app_dialogs.dart';
import '../widgets/settings_ui.dart';
import 'advanced_settings_page.dart';
import 'dev_test_page.dart';
import 'family/parent_pin_recovery.dart';
import 'feature_settings_page.dart';
import 'mascot_profile_page.dart';
import 'profile_edit_page.dart';
import 'review_page.dart';

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

  // 兔咪名片資料（名字可在編輯基本資料改，回到本頁要刷新）
  String _mascotName = MascotName.fallback;
  int _companionDays = 1;
  int _coinBalance = 0;

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
    final balance = await CoinService.balance();
    if (!mounted) return;
    setState(() {
      _hasPin = hasPin;
      _pinDigits = _prefs!.getInt(PrefsKeys.pinDigits) ?? 4;
      _unitSystem = UnitSystem.load(_prefs!);
      _dayStartHour = LogicalDate.load(_prefs!);
      _applyCardData(balance);
      _loaded = true;
    });
    if (widget.openPinSettingsOnLoad && !_openedInitialPinSettings) {
      _openedInitialPinSettings = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_showPinSettings());
      });
    }
  }

  // setState 內套用名片資料（名字空白視同預設名）。
  void _applyCardData(int balance) {
    final prefs = _prefs;
    if (prefs == null) return;
    final name = prefs.getString(PrefsKeys.mascotName)?.trim();
    _mascotName = (name == null || name.isEmpty) ? MascotName.fallback : name;
    _companionDays = companionDays(prefs, DateTime.now());
    _coinBalance = balance;
  }

  // 從檔案頁 / 編輯基本資料回來時刷新名片（名字可能剛改過）。
  Future<void> _refreshCard() async {
    final balance = await CoinService.balance();
    if (!mounted) return;
    setState(() => _applyCardData(balance));
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
  String _dayStartLabel(int h) {
    final l10n = AppLocalizations.of(context);
    return h == 0 ? l10n.dayStartMidnightLabel : l10n.dayStartHourLabel(h);
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
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsTitle), centerTitle: true),
      body: _loaded
          ? ListView(
              padding: const EdgeInsets.all(24),
              children: [
                // ── 兔咪名片：點進檔案頁（足跡總覽）──
                MascotCallingCard(
                  name: _mascotName,
                  companionDays: _companionDays,
                  coinBalance: _coinBalance,
                  onCoinTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const ReviewPage(),
                      ),
                    );
                  },
                  onTap: () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const MascotProfilePage(),
                      ),
                    );
                    await _refreshCard();
                  },
                ),

                const Divider(height: 32, thickness: 1),

                // ── 區塊1：基本資料（進入子頁面編輯）──
                _sectionTitle(l10n.basicInfoTitle, Icons.person_outline),

                SettingsTileCard(
                  icon: Icons.edit_outlined,
                  iconColor: Colors.orange,
                  // 卡片標題與區塊標題錯開，避免同字重複兩次
                  title: l10n.settingsEditProfileTitle,
                  subtitle: l10n.settingsEditProfileSubtitle,
                  onTap: () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const ProfileEditPage(),
                      ),
                    );
                    await _refreshCard();
                  },
                ),

                const Divider(height: 32, thickness: 1),

                // ── 區塊：單位（公制／英制）──
                _sectionTitle(
                  l10n.settingsSectionUnits,
                  Icons.straighten_outlined,
                ),
                SettingsGroupCard(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.settingsUnitsDescription,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppInk.soft,
                        ),
                      ),
                      const SizedBox(height: 10),
                      SegmentedButton<UnitSystem>(
                        segments: [
                          ButtonSegment(
                            value: UnitSystem.metric,
                            label: Text(l10n.unitMetric),
                            icon: const Icon(Icons.straighten),
                          ),
                          ButtonSegment(
                            value: UnitSystem.imperial,
                            label: Text(l10n.unitImperial),
                            icon: const Icon(Icons.square_foot),
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
                _sectionTitle(
                  l10n.settingsSectionDayStart,
                  Icons.bedtime_outlined,
                ),
                SettingsGroupCard(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.settingsDayStartDescription,
                        style: const TextStyle(
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
                      Text(
                        l10n.settingsDayStartCoinNote,
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppInk.faint,
                        ),
                      ),
                    ],
                  ),
                ),

                const Divider(height: 32, thickness: 1),

                // ── 區塊2：功能開關（進入獨立子頁面）──
                _sectionTitle(l10n.featureSettingsTitle, Icons.tune_outlined),

                SettingsTileCard(
                  icon: Icons.tune_outlined,
                  iconColor: Colors.teal,
                  title: l10n.settingsManageFeaturesTitle,
                  subtitle: l10n.settingsManageFeaturesSubtitle,
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
                _sectionTitle(
                  l10n.settingsSectionSecurity,
                  Icons.security_outlined,
                ),

                SettingsTileCard(
                  icon: Icons.lock_outline,
                  iconColor: Colors.indigo,
                  title: l10n.pinSettingsTitle,
                  // 依是否設定數字密碼顯示不同狀態文字
                  subtitle: _hasPin
                      ? l10n.pinStatusSet(_pinDigits)
                      : l10n.pinStatusUnset,
                  onTap: _showPinSettings,
                ),

                const Divider(height: 32, thickness: 1),

                // ── 區塊3：進階 ──
                _sectionTitle(
                  l10n.settingsSectionAdvanced,
                  Icons.admin_panel_settings_outlined,
                ),

                SettingsTileCard(
                  icon: Icons.admin_panel_settings_outlined,
                  iconColor: Colors.deepOrange,
                  title: l10n.settingsAdvancedTitle,
                  subtitle: l10n.settingsAdvancedSubtitle,
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
                  _sectionTitle(l10n.devToolsTitle, Icons.science_outlined),
                  SettingsTileCard(
                    icon: Icons.science_outlined,
                    iconColor: Colors.blueGrey,
                    title: l10n.devToolsTitle,
                    subtitle: l10n.devToolsSubtitle,
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
              hintText: AppLocalizations.of(
                context,
              ).pinEnterDigitsHint(_digits),
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
              hintText: AppLocalizations.of(
                context,
              ).pinEnterDigitsHint(_digits),
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
              child: Text(AppLocalizations.of(context).commonConfirm),
            ),
          ],
        ),
      ),
    );
  }

  // 第一次設定 PIN（輸入兩次確認）
  Future<void> _setupPin() async {
    final l10n = AppLocalizations.of(context);
    final newPin = await _promptNewPin(l10n.pinPromptNew(_digits));
    if (newPin == null || newPin.length != _digits) return;

    final confirm = await _promptNewPin(l10n.pinPromptConfirmFirst);
    if (!mounted || confirm == null) return;

    if (newPin != confirm) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.pinMismatch)));
      return;
    }
    await widget.onSaved(newPin, _digits);
    if (!mounted) return;
    setState(() => _hasPin = true);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(l10n.pinSaved)));
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
      ..showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).qaSaved)),
      );
  }

  // 忘記密碼：答對救援問題重設，或清空重來。成功就關閉本面板。
  Future<void> _forgotPassword() async {
    final ok = await showForgotParentPin(context);
    if (ok && mounted) Navigator.pop(context);
  }

  // 修改 PIN（需先輸入舊 PIN）
  Future<void> _changePin() async {
    final l10n = AppLocalizations.of(context);
    final old = await _promptOldPin(l10n.pinPromptCurrent);
    if (!mounted || old == null) return;

    if (!await _verifyOldPin(old)) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.pinOldWrong)));
      return;
    }
    if (!mounted) return;

    final newPin = await _promptNewPin(l10n.pinPromptNew(_digits));
    if (newPin == null || newPin.length != _digits) return;

    final confirm = await _promptNewPin(l10n.pinPromptConfirmNew);
    if (!mounted || confirm == null) return;

    if (newPin != confirm) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.pinMismatch)));
      return;
    }
    await widget.onSaved(newPin, _digits);
    if (!mounted) return;
    Navigator.pop(context);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(l10n.pinUpdated)));
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

    final l10n = AppLocalizations.of(context);
    // 已設定數字密碼：先用目前位數驗證舊密碼
    final old = await _promptOldPin(l10n.pinPromptCurrentWithDigits(_digits));
    if (!mounted || old == null) return;

    if (!await _verifyOldPin(old)) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.pinOldWrong)));
      return;
    }
    if (!mounted) return;

    // 驗證通過，切換至新位數並要求重設密碼（兩次確認）
    setState(() => _digits = newDigits);

    final newPin = await _promptNewPin(l10n.pinPromptNewShort(newDigits));
    if (!mounted || newPin == null || newPin.length != newDigits) {
      setState(() => _digits = widget.currentDigits);
      return;
    }

    final confirm = await _promptNewPin(l10n.pinPromptConfirmNew);
    if (!mounted || confirm == null) {
      setState(() => _digits = widget.currentDigits);
      return;
    }

    if (newPin != confirm) {
      setState(() => _digits = widget.currentDigits);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.pinMismatch)));
      return;
    }

    await widget.onSaved(newPin, newDigits);
    if (!mounted) return;
    Navigator.pop(context);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(l10n.pinDigitsUpdated)));
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final l10n = AppLocalizations.of(context);
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
              Text(
                l10n.pinSettingsTitle,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // 密碼位數選擇（4位 / 6位）
          Text(
            l10n.pinDigitsLabel,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
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
              label: Text(_hasPin ? l10n.pinChangeButton : l10n.pinSetupButton),
            ),
          ),

          if (_hasPin) ...[
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Center(
                child: Text(
                  l10n.pinCurrentStatus(_digits),
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
                      Text(
                        l10n.qaRowTitle,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _hasQA ? l10n.qaStatusSet : l10n.qaStatusUnset,
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
                  child: Text(_hasQA ? l10n.commonModify : l10n.commonSetUp),
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
                label: Text(l10n.forgotPasscode),
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
  static const _customValue = '__custom__'; // 下拉「自訂問題…」的哨兵值

  final _qCtrl = TextEditingController(); // 僅自訂時使用
  final _aCtrl = TextEditingController();
  String? _selected; // 選中的預設問題，或 _customValue
  bool _initializedSelection = false;

  // 預設救援問題。問句設計成答案短、唯一、不易隨時間改變。
  // 儲存的是「當時顯示的字串」，所以換語言後舊問題會被視為自訂問題，可正常作答。
  List<String> _presetQuestions(AppLocalizations l10n) => [
    l10n.qaPresetFirstPet,
    l10n.qaPresetMotherName,
    l10n.qaPresetBirthCity,
    l10n.qaPresetFirstSchool,
    l10n.qaPresetChildhoodFriend,
    l10n.qaPresetFavoriteDish,
  ];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 初始選擇要比對 l10n 的預設問題清單，initState 拿不到 InheritedWidget，
    // 所以放這裡做一次。
    if (_initializedSelection) return;
    _initializedSelection = true;
    final q = widget.initialQuestion;
    if (q != null && q.isNotEmpty) {
      if (_presetQuestions(AppLocalizations.of(context)).contains(q)) {
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
    final l10n = AppLocalizations.of(context);
    final hasQuestion = _isCustom
        ? _qCtrl.text.trim().isNotEmpty
        : _selected != null;
    final ready = hasQuestion && _aCtrl.text.trim().isNotEmpty;
    return AlertDialog(
      title: Text(l10n.qaDialogTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.qaDialogDescription,
              style: const TextStyle(fontSize: 12.5, color: AppInk.soft),
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              initialValue: _selected,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: l10n.qaQuestionLabel,
                border: const OutlineInputBorder(),
              ),
              hint: Text(l10n.qaQuestionHint),
              items: [
                for (final q in _presetQuestions(l10n))
                  DropdownMenuItem(
                    value: q,
                    child: Text(q, overflow: TextOverflow.ellipsis),
                  ),
                DropdownMenuItem(
                  value: _customValue,
                  child: Text(l10n.qaCustomOption),
                ),
              ],
              onChanged: (v) => setState(() => _selected = v),
            ),
            if (_isCustom) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _qCtrl,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: l10n.qaCustomLabel,
                  hintText: l10n.qaCustomHint,
                  border: const OutlineInputBorder(),
                ),
                onChanged: (_) => setState(() {}),
              ),
            ],
            const SizedBox(height: 12),
            TextField(
              controller: _aCtrl,
              decoration: InputDecoration(
                labelText: l10n.qaAnswerLabel,
                border: const OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ],
        ),
      ),
      actions: [
        dialogCancelAction(
          context,
          label: widget.initial ? l10n.commonSkip : null,
        ),
        TextButton(
          onPressed: ready
              ? () => Navigator.pop(context, (
                  question: _isCustom ? _qCtrl.text.trim() : _selected!,
                  answer: _aCtrl.text,
                ))
              : null,
          child: Text(l10n.commonSave),
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
              AppLocalizations.of(context).pinDigitsChip(digits),
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
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _ZoneLabel(
                    Icons.bedtime_rounded,
                    AppLocalizations.of(context).dayStartZoneYesterday,
                    night,
                  ),
                  _ZoneLabel(
                    Icons.wb_twilight_rounded,
                    AppLocalizations.of(context).dayStartZoneNewDay,
                    dawn,
                  ),
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
                          h == 0
                              ? AppLocalizations.of(
                                  context,
                                ).dayStartTickMidnight
                              : '$h',
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
                                  AppLocalizations.of(
                                    context,
                                  ).dayStartRecommended,
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
