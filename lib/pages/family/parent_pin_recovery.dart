// 家長密碼救援：忘記密碼時的兩條出路。
//   1) 答對救援安全問題 → 直接重設新密碼（資料完全保留）。
//   2) 清除所有資料重新開始（保底，一定能解開「忘記密碼 = 死鎖」）。
//
// 之所以保底要付出「清空資料」的代價：家長密碼是本機「防小孩」的鎖，
// 若無條件就能清掉，鎖等於虛設；要破解就得連自己的資料一起清，形成自然嚇阻。
//
// 對話框內的 TextEditingController 一律由 StatefulWidget 持有，dispose 綁在
// widget 生命週期，避免在退場動畫期間被存取而崩潰。
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../utils/app_feedback.dart';
import '../../utils/app_restart.dart';
import '../../utils/app_style.dart';
import '../../utils/parent_pin.dart';
import '../../utils/prefs_keys.dart';

/// 顯示「忘記家長密碼」流程。
/// 回傳 true = 已重設密碼或已清空重啟（呼叫端可據此關閉當前的驗證流程）。
Future<bool> showForgotParentPin(BuildContext context) async {
  final prefs = await SharedPreferences.getInstance();
  if (!context.mounted) return false;
  final action = await showDialog<_ForgotAction>(
    context: context,
    builder: (_) => _ForgotPinDialog(prefs: prefs),
  );
  if (action == null || !context.mounted) return false;
  switch (action) {
    case _ForgotAction.answered:
      return _resetPinFlow(context, prefs);
    case _ForgotAction.wipe:
      await _wipeAndRestart(context, prefs);
      return true;
  }
}

enum _ForgotAction { answered, wipe }

// 答對安全問題後：設定新密碼（兩次確認）。
Future<bool> _resetPinFlow(
  BuildContext context,
  SharedPreferences prefs,
) async {
  final digits = prefs.getInt(PrefsKeys.pinDigits) ?? 4;
  final first = await _promptNewPin(context, '設定新密碼（$digits 位數字）', digits);
  if (first == null || !context.mounted) return false;
  final second = await _promptNewPin(context, '再次輸入新密碼確認', digits);
  if (!context.mounted || second == null) return false;
  if (first != second) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('兩次輸入的密碼不一致')));
    return false;
  }
  await ParentPin.save(prefs, first);
  parentSession.value = true; // 重設成功直接視為已通過驗證
  if (context.mounted) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('密碼已重設')));
  }
  return true;
}

// 清空所有資料並乾淨重啟整棵 app（與資料刪除頁的「重置全部資料」同一條路徑）。
Future<void> _wipeAndRestart(
  BuildContext context,
  SharedPreferences prefs,
) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await Future<void>.delayed(const Duration(milliseconds: 250));
  await prefs.clear();
  if (context.mounted) RootRestart.restart(context);
}

Future<String?> _promptNewPin(BuildContext context, String title, int digits) {
  return showDialog<String>(
    context: context,
    builder: (_) => _SetPinDialog(title: title, digits: digits),
  );
}

// 忘記密碼主對話框：有安全問題就讓使用者作答，並一律提供「清空重來」保底。
class _ForgotPinDialog extends StatefulWidget {
  final SharedPreferences prefs;
  const _ForgotPinDialog({required this.prefs});

  @override
  State<_ForgotPinDialog> createState() => _ForgotPinDialogState();
}

class _ForgotPinDialogState extends State<_ForgotPinDialog> {
  final _answerCtrl = TextEditingController();
  String? _error;

  bool get _hasQA => ParentPin.hasSecurityQuestion(widget.prefs);

  @override
  void dispose() {
    _answerCtrl.dispose();
    super.dispose();
  }

  void _checkAnswer() {
    if (ParentPin.verifySecurityAnswer(widget.prefs, _answerCtrl.text)) {
      Navigator.pop(context, _ForgotAction.answered);
    } else {
      playHaptic(HapticLevel.medium);
      setState(() => _error = '答案不對，再試一次');
    }
  }

  Future<void> _confirmWipe() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清除所有資料？'),
        content: const Text('將清空全部資料（習慣、體重、喝水、家庭、金幣、衣櫃與密碼）並回到初始狀態，此動作無法復原。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('取消', style: TextStyle(color: AppInk.soft)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('清除並重啟'),
          ),
        ],
      ),
    );
    if (ok == true && mounted) Navigator.pop(context, _ForgotAction.wipe);
  }

  @override
  Widget build(BuildContext context) {
    final hasQA = _hasQA;
    return AlertDialog(
      title: const Text('忘記家長密碼'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (hasQA) ...[
            const Text('回答你設定的安全問題即可重設密碼，資料不會被清除：'),
            const SizedBox(height: 10),
            Text(
              ParentPin.securityQuestion(widget.prefs) ?? '',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _answerCtrl,
              autofocus: true,
              decoration: InputDecoration(
                labelText: '你的答案',
                border: const OutlineInputBorder(),
                errorText: _error,
              ),
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
              onSubmitted: (_) => _checkAnswer(),
            ),
          ] else
            const Text('你沒有設定安全問題，因此無法直接重設密碼，只能清除所有資料重新開始。'),
          const SizedBox(height: 14),
          const Divider(height: 1),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _confirmWipe,
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              icon: const Icon(Icons.delete_forever_rounded, size: 20),
              label: const Text('清除所有資料並重新開始'),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('取消', style: TextStyle(color: AppInk.soft)),
        ),
        if (hasQA)
          FilledButton(onPressed: _checkAnswer, child: const Text('驗證並重設')),
      ],
    );
  }
}

// 設定新密碼用：滿位數才可按「確認」，不自動送出避免誤觸。
class _SetPinDialog extends StatefulWidget {
  final String title;
  final int digits;
  const _SetPinDialog({required this.title, required this.digits});

  @override
  State<_SetPinDialog> createState() => _SetPinDialogState();
}

class _SetPinDialogState extends State<_SetPinDialog> {
  final _ctrl = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ready = _ctrl.text.length == widget.digits;
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
          hintText: '請輸入 ${widget.digits} 位數字',
          counterText: '',
          suffixIcon: IconButton(
            icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility),
            onPressed: () => setState(() => _obscure = !_obscure),
          ),
        ),
        onChanged: (_) => setState(() {}),
        onSubmitted: (v) {
          if (v.length == widget.digits) Navigator.pop(context, v);
        },
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('取消', style: TextStyle(color: AppInk.soft)),
        ),
        TextButton(
          onPressed: ready ? () => Navigator.pop(context, _ctrl.text) : null,
          child: const Text('確認'),
        ),
      ],
    );
  }
}
