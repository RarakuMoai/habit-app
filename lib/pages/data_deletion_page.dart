import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/app_feedback.dart';
import '../utils/app_restart.dart';
import '../utils/app_style.dart';
import '../utils/parent_pin.dart';
import '../utils/prefs_keys.dart';
import '../widgets/app_dialogs.dart';
import 'family/parent_pin_recovery.dart';

class DataDeletionPage extends StatefulWidget {
  const DataDeletionPage({super.key});

  @override
  State<DataDeletionPage> createState() => _DataDeletionPageState();
}

class _DataDeletionPageState extends State<DataDeletionPage> {
  SharedPreferences? _prefs;
  bool _loaded = false;
  bool _authorized = false;
  bool _verifying = false;
  bool _busy = false;

  int _weightCount = 0;
  int _waterDayCount = 0;
  int _familyCount = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final hasPin = await ParentPin.hasPin(prefs);
    if (!mounted) return;
    _prefs = prefs;
    _refreshCounts();
    setState(() {
      _authorized = !hasPin;
      _loaded = true;
    });
    if (hasPin) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_verifyBeforeEntry());
      });
    }
  }

  void _refreshCounts() {
    final prefs = _prefs;
    if (prefs == null) return;
    _weightCount = _jsonListLength(prefs.getString(PrefsKeys.weightRecords));
    _waterDayCount = _waterRecordDates(prefs).length;
    _familyCount =
        _jsonListLength(prefs.getString(PrefsKeys.children)) +
        _jsonListLength(prefs.getString(PrefsKeys.childHabits)) +
        _jsonListLength(prefs.getString(PrefsKeys.deductionItems)) +
        _jsonListLength(prefs.getString(PrefsKeys.rewardItems)) +
        _jsonListLength(prefs.getString(PrefsKeys.pointRecords)) +
        _jsonListLength(prefs.getString(PrefsKeys.voucherLogs)) +
        _jsonListLength(prefs.getString(PrefsKeys.legacyRedemptionLogs));
  }

  int _jsonListLength(String? raw) {
    if (raw == null || raw.isEmpty) return 0;
    try {
      final decoded = jsonDecode(raw);
      return decoded is List ? decoded.length : 0;
    } catch (_) {
      return 0;
    }
  }

  String? _dateSuffix(String key, String prefix) {
    if (!key.startsWith(prefix)) return null;
    final suffix = key.substring(prefix.length);
    final validDate = RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(suffix);
    return validDate ? suffix : null;
  }

  Set<String> _waterRecordDates(SharedPreferences prefs) {
    final dates = <String>{};
    for (final key in prefs.getKeys()) {
      final date =
          _dateSuffix(key, PrefsKeys.waterEntriesSavedPrefix) ??
          _dateSuffix(key, PrefsKeys.waterEntriesPrefix) ??
          _dateSuffix(key, PrefsKeys.waterExtraPrefix) ??
          _dateSuffix(key, PrefsKeys.waterSavedPrefix) ??
          _dateSuffix(key, PrefsKeys.waterDayPrefix);
      if (date != null) dates.add(date);
    }
    return dates;
  }

  bool _isWaterRecordKey(String key) =>
      _dateSuffix(key, PrefsKeys.waterEntriesSavedPrefix) != null ||
      _dateSuffix(key, PrefsKeys.waterEntriesPrefix) != null ||
      _dateSuffix(key, PrefsKeys.waterExtraPrefix) != null ||
      _dateSuffix(key, PrefsKeys.waterSavedPrefix) != null ||
      _dateSuffix(key, PrefsKeys.waterDayPrefix) != null;

  Future<bool> _verifyBeforeEntry() async {
    if (_verifying || _authorized) return _authorized;
    setState(() => _verifying = true);
    final ok = await _verifyPin(title: '請輸入密碼以進入資料刪除');
    if (!mounted) return false;
    if (ok) {
      setState(() {
        _authorized = true;
        _verifying = false;
      });
      return true;
    }
    Navigator.of(context).pop();
    return false;
  }

  // 回傳 true = 驗證通過；false = 使用者按取消。輸錯不會結束對話框，
  // 而是清空欄位、顯示行內錯誤讓使用者重新輸入。
  //
  // 對話框抽成 [_PinVerifyDialog]（StatefulWidget），讓 TextEditingController
  // 的生命週期綁在 widget 上：dispose 會在對話框退場動畫結束、widget 真正離開
  // 樹之後才發生，不會在退場期間被 TextField 拿來 addListener（提早 dispose
  // 會連鎖 RenderFlex / _dependents.isEmpty 崩潰）。
  Future<bool> _verifyPin({required String title}) async {
    final prefs = _prefs;
    if (prefs == null) return false;
    final digits = prefs.getInt(PrefsKeys.pinDigits) ?? 4;
    final result = await showDialog<_PinResult>(
      context: context,
      barrierDismissible: false,
      builder: (_) =>
          _PinVerifyDialog(prefs: prefs, digits: digits, title: title),
    );
    if (!mounted) return false;
    // 忘記密碼：救援成功（答對問題重設 / 清空重啟）即視為通過。
    if (result == _PinResult.forgot) return showForgotParentPin(context);
    return result == _PinResult.ok;
  }

  Future<bool> _confirmLongPress({
    required String title,
    required String message,
    required Color color,
  }) async {
    return await showDialog<bool>(
          context: context,
          builder: (dialogCtx) => AlertDialog(
            title: Text(title),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(message),
                const SizedBox(height: 18),
                _HoldToConfirmButton(
                  color: color,
                  label: '長按確認刪除',
                  onConfirmed: () => Navigator.pop(dialogCtx, true),
                ),
                const SizedBox(height: 8),
                const Center(
                  child: Text(
                    '按住直到填滿才會刪除，中途放開即取消',
                    style: TextStyle(
                      color: AppInk.soft,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                style: TextButton.styleFrom(
                  minimumSize: const Size(72, 46),
                ),
                onPressed: () => Navigator.pop(dialogCtx, false),
                child: const Text('取消', style: TextStyle(color: AppInk.soft)),
              ),
            ],
          ),
        ) ??
        false;
  }

  // 對話框抽成 [_DeleteWordDialog]（StatefulWidget），理由同 [_verifyPin]：
  // controller 的 dispose 綁在 widget 生命週期，發生在退場動畫之後，避免提早
  // dispose 害退場那一幀的 TextField crash。
  Future<bool> _confirmDeleteWord() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => const _DeleteWordDialog(),
    );
    return ok ?? false;
  }

  Future<void> _runDelete(
    Future<void> Function(SharedPreferences prefs) job,
  ) async {
    final prefs = _prefs;
    if (prefs == null || _busy) return;
    setState(() => _busy = true);
    try {
      await job(prefs);
      _refreshCounts();
      if (mounted) setState(() {});
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _clearWeightRecords() async {
    final confirm = await _confirmLongPress(
      title: '清除體重紀錄',
      message: '會刪除體重歷史紀錄，但保留體重功能開關、連續天數與已得金幣。',
      color: Colors.orange,
    );
    if (!confirm) return;
    await _runDelete((prefs) => prefs.remove(PrefsKeys.weightRecords));
    _showDone('已清除體重紀錄');
  }

  Future<void> _clearWaterRecords() async {
    final confirm = await _confirmLongPress(
      title: '清除喝水紀錄',
      message: '會刪除每日喝水明細，保留每杯容量、每日目標、功能開關與已得金幣。',
      color: Colors.orange,
    );
    if (!confirm) return;
    await _runDelete((prefs) async {
      final keys = prefs.getKeys().where(_isWaterRecordKey).toList();
      for (final key in keys) {
        await prefs.remove(key);
      }
    });
    _showDone('已清除喝水紀錄');
  }

  Future<void> _clearFamilyData() async {
    final confirm = await _confirmLongPress(
      title: '清除家庭資料',
      message: '會刪除小孩、家庭習慣、扣分項目、獎勵、積分紀錄與票券紀錄。家庭模式開關會保留。',
      color: Colors.deepOrange,
    );
    if (!confirm) return;
    await _runDelete((prefs) async {
      await prefs.remove(PrefsKeys.children);
      await prefs.remove(PrefsKeys.childHabits);
      await prefs.remove(PrefsKeys.deductionItems);
      await prefs.remove(PrefsKeys.rewardItems);
      await prefs.remove(PrefsKeys.pointRecords);
      await prefs.remove(PrefsKeys.voucherLogs);
      await prefs.remove(PrefsKeys.legacyRedemptionLogs);
    });
    _showDone('已清除家庭資料');
  }

  Future<void> _resetAll() async {
    final confirm = await _confirmDeleteWord();
    if (!confirm || !mounted) return;
    await _doReset();
  }

  // 清空資料並乾淨重啟整棵 app。不用 pushNamedAndRemoveUntil 逐一強拆
  // route stack（會把含 AnimatedSwitcher(GlobalKey) 的 home route 拆到
  // InheritedElement 還有 dependent，觸發 _dependents.isEmpty 斷言、
  // wrong build scope、RenderFlex overflow 等連鎖崩潰）。
  //
  // 改成 RootRestart：把整棵 MyApp 當一個單位丟棄重建，MyApp 會以全新
  // state 重跑 startup，從清空後的 prefs 重載金幣/衣櫃/音訊並落在
  // onboarding，所以這裡只要 clear prefs + restart，不必手動 reset 各服務。
  Future<void> _doReset() async {
    final prefs = _prefs;
    if (prefs == null || !mounted) return;
    setState(() => _busy = true);
    // 收鍵盤：釋放確認對話框 autofocus TextField 的 Focus 依賴，並等它的
    // 退場動畫結束、route 完全移除，再動整棵樹。
    FocusManager.instance.primaryFocus?.unfocus();
    await Future<void>.delayed(const Duration(milliseconds: 250));
    if (!mounted) return;
    await prefs.clear();
    if (!mounted) return;
    RootRestart.restart(context);
  }

  void _showDone(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded || !_authorized) {
      return Scaffold(
        appBar: AppBar(title: const Text('資料刪除'), centerTitle: true),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('資料刪除'), centerTitle: true),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
        children: [
          _warningHeader(),
          const SizedBox(height: 16),
          _DeleteItemCard(
            icon: Icons.monitor_weight_outlined,
            color: Colors.orange,
            title: '清除體重紀錄',
            subtitle: _weightCount == 0 ? '目前沒有體重紀錄' : '$_weightCount 筆體重紀錄',
            detail: '保留功能開關、連續天數與金幣紀錄',
            enabled: !_busy && _weightCount > 0,
            onTap: _clearWeightRecords,
          ),
          const SizedBox(height: 12),
          _DeleteItemCard(
            icon: Icons.water_drop_outlined,
            color: Colors.orange,
            title: '清除喝水紀錄',
            subtitle: _waterDayCount == 0
                ? '目前沒有喝水紀錄'
                : '$_waterDayCount 天喝水紀錄',
            detail: '保留每杯容量、每日目標與金幣紀錄',
            enabled: !_busy && _waterDayCount > 0,
            onTap: _clearWaterRecords,
          ),
          const SizedBox(height: 12),
          _DeleteItemCard(
            icon: Icons.family_restroom_rounded,
            color: Colors.deepOrange,
            title: '清除家庭資料',
            subtitle: _familyCount == 0 ? '目前沒有家庭資料' : '$_familyCount 筆家庭資料',
            detail: '會刪除小孩、積分、獎勵與票券資料',
            enabled: !_busy && _familyCount > 0,
            onTap: _clearFamilyData,
          ),
          const SizedBox(height: 22),
          _ResetAllCard(enabled: !_busy, onTap: _resetAll),
        ],
      ),
    );
  }

  Widget _warningHeader() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF3F0),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.red.withValues(alpha: 0.16)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: Colors.red.withValues(alpha: 0.11),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.warning_amber_rounded,
              color: Colors.red,
              size: 21,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '刪除前請再確認',
                  style: TextStyle(
                    color: Color(0xFF6F2E24),
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '單項刪除需要長按確認；重置全部資料需要輸入 DELETE。',
                  style: TextStyle(
                    color: Colors.red.shade700,
                    fontSize: 12.5,
                    height: 1.4,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DeleteItemCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final String detail;
  final bool enabled;
  final VoidCallback onTap;

  const _DeleteItemCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.detail,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final fg = enabled ? color : AppInk.iconFaint;
    return Material(
      color: AppSurfaces.card,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppSurfaces.divider),
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: fg.withValues(alpha: enabled ? 0.12 : 0.08),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: fg, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: enabled ? AppInk.strong : AppInk.faint,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: AppInk.soft,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      detail,
                      style: const TextStyle(
                        color: AppInk.soft,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: AppInk.iconFaint),
            ],
          ),
        ),
      ),
    );
  }
}

class _ResetAllCard extends StatelessWidget {
  final bool enabled;
  final VoidCallback onTap;

  const _ResetAllCard({required this.enabled, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFFFF5F5),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.red.withValues(alpha: 0.22)),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.delete_forever_rounded,
                  color: Colors.red,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '重置全部資料',
                      style: TextStyle(
                        color: Color(0xFF8D211D),
                        fontSize: 15.5,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '回到初始狀態，需要輸入 DELETE',
                      style: TextStyle(
                        color: Colors.red.shade700,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: Colors.red.shade200),
            ],
          ),
        ),
      ),
    );
  }
}

// 按住確認鈕：手指按住才會推進進度，填滿才觸發 onConfirmed；
// 中途放開會倒退回 0。進度條 + 漸進觸覺讓「持續按」的回饋很明顯。
class _HoldToConfirmButton extends StatefulWidget {
  final Color color;
  final String label;
  final VoidCallback onConfirmed;

  const _HoldToConfirmButton({
    required this.color,
    required this.label,
    required this.onConfirmed,
  });

  @override
  State<_HoldToConfirmButton> createState() => _HoldToConfirmButtonState();
}

class _HoldToConfirmButtonState extends State<_HoldToConfirmButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1000),
  )..addStatusListener(_onStatus);
  bool _holding = false;
  bool _fired = false;
  int _lastTick = 0;

  @override
  void initState() {
    super.initState();
    _ctrl.addListener(_onTick);
  }

  void _onTick() {
    if (!mounted) return;
    setState(() {});
    // 每推進 1/4 給一次選取觸覺，按越久回饋越密
    final step = (_ctrl.value * 4).floor();
    if (step > _lastTick && step < 4) {
      _lastTick = step;
      playHaptic(HapticLevel.selection);
    }
  }

  void _onStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed && !_fired) {
      _fired = true;
      playHaptic(HapticLevel.medium);
      widget.onConfirmed();
    }
  }

  void _press() {
    if (_fired) return;
    setState(() => _holding = true);
    playHaptic(HapticLevel.light);
    _ctrl.forward();
  }

  void _release() {
    if (_fired) return;
    _lastTick = 0;
    setState(() => _holding = false);
    _ctrl.reverse();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final v = _ctrl.value.clamp(0.0, 1.0);
    final base = widget.color;
    final onFill = v > 0.45 ? Colors.white : base;
    return Listener(
      onPointerDown: (_) => _press(),
      onPointerUp: (_) => _release(),
      onPointerCancel: (_) => _release(),
      child: Container(
        height: 56,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: base.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: base.withValues(alpha: 0.55), width: 1.4),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // 用 Positioned.fill 把進度條移出 Stack 的 intrinsic 寬度計算：
            // AlertDialog 會用 IntrinsicWidth 量 content，而 FractionallySizedBox
            // 在 widthFactor=0（剛開啟時）的 intrinsic 寬會算出 0/0=NaN，
            // 連帶讓整個對話框 layout 崩掉（child!.hasSize 斷言失敗）。
            // 改成 positioned 後它只在實際 layout 階段被定尺寸，不參與量測。
            Positioned.fill(
              child: FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: v,
                child: DecoratedBox(
                  decoration: BoxDecoration(color: base.withValues(alpha: 0.9)),
                ),
              ),
            ),
            Center(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.touch_app_rounded, size: 22, color: onFill),
                  const SizedBox(width: 8),
                  Text(
                    _holding ? '持續按住…' : widget.label,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      color: onFill,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// 家長密碼驗證對話框的結果：ok = 驗證通過；forgot = 使用者點了「忘記密碼」；
// 取消則回傳 null。
enum _PinResult { ok, forgot }

// 家長密碼驗證對話框。controller 由 State 持有，dispose 在 widget 離開樹之後
// 才發生（含退場動畫），避免提早釋放害 TextField 在退場那一幀 crash。
class _PinVerifyDialog extends StatefulWidget {
  final SharedPreferences prefs;
  final int digits;
  final String title;

  const _PinVerifyDialog({
    required this.prefs,
    required this.digits,
    required this.title,
  });

  @override
  State<_PinVerifyDialog> createState() => _PinVerifyDialogState();
}

class _PinVerifyDialogState extends State<_PinVerifyDialog> {
  final _ctrl = TextEditingController();
  bool _obscure = true;
  String? _errorText;
  bool _checking = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _submit(String v) async {
    if (_checking || v.length != widget.digits) return;
    _checking = true;
    final pass = await ParentPin.verify(widget.prefs, v);
    _checking = false;
    if (!mounted) return;
    if (pass) {
      Navigator.pop(context, _PinResult.ok);
    } else {
      playHaptic(HapticLevel.medium);
      setState(() {
        _errorText = '密碼錯誤，請再試一次';
        _ctrl.clear();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _ctrl,
        keyboardType: TextInputType.number,
        obscureText: _obscure,
        maxLength: widget.digits,
        autofocus: true,
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
          LengthLimitingTextInputFormatter(widget.digits),
        ],
        decoration: InputDecoration(
          hintText: '請輸入 ${widget.digits} 位數字密碼',
          counterText: '',
          errorText: _errorText,
          suffixIcon: IconButton(
            icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility),
            onPressed: () => setState(() => _obscure = !_obscure),
          ),
        ),
        onChanged: (v) {
          if (_errorText != null) setState(() => _errorText = null);
          if (v.length == widget.digits) _submit(v);
        },
        onSubmitted: _submit,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, _PinResult.forgot),
          child: const Text('忘記密碼？', style: TextStyle(color: AppInk.soft)),
        ),
        dialogCancelAction(context),
      ],
    );
  }
}

// 「重置全部資料」確認對話框：要輸入 DELETE 才能按永久刪除。controller 生命
// 週期同 [_PinVerifyDialog]，綁在 State 上避免提早 dispose。
class _DeleteWordDialog extends StatefulWidget {
  const _DeleteWordDialog();

  @override
  State<_DeleteWordDialog> createState() => _DeleteWordDialogState();
}

class _DeleteWordDialogState extends State<_DeleteWordDialog> {
  final _ctrl = TextEditingController();
  bool _enabled = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('重置全部資料'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('這會清除所有資料並回到初始狀態，包含習慣、喝水、體重、家庭、金幣、衣櫃與密碼設定。'),
          const SizedBox(height: 14),
          TextField(
            controller: _ctrl,
            autofocus: true,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(
              labelText: '輸入 DELETE 以確認',
              border: OutlineInputBorder(),
            ),
            onChanged: (v) => setState(() => _enabled = v.trim() == 'DELETE'),
          ),
        ],
      ),
      actions: [
        TextButton(
          style: TextButton.styleFrom(minimumSize: const Size(72, 46)),
          onPressed: () => Navigator.pop(context, false),
          child: const Text('取消', style: TextStyle(color: AppInk.soft)),
        ),
        FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: AppInk.danger,
            minimumSize: const Size(0, 48),
            padding: const EdgeInsets.symmetric(horizontal: 18),
            textStyle: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
          onPressed: _enabled ? () => Navigator.pop(context, true) : null,
          icon: const Icon(Icons.delete_forever_rounded, size: 20),
          label: const Text('永久刪除'),
        ),
      ],
    );
  }
}
