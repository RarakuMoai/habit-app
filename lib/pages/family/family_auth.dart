// 家長密碼：輸入對話框與驗證（Session 有效或未設密碼時直接通過）
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../utils/app_style.dart';
import '../../utils/parent_pin.dart';
import '../../utils/prefs_keys.dart';

// ── 密碼輸入對話框（供本檔案內部使用）──
// 回傳使用者輸入的字串；取消回傳 null
Future<String?> showPinDialog(
  BuildContext context, {
  required int digits,
  required String title,
  Future<void> Function()? onForgotPassword,
}) async {
  final controller = TextEditingController();
  var obscure = true;
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
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(digits),
          ],
          decoration: InputDecoration(
            hintText: '請輸入 $digits 位數字密碼',
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
          if (onForgotPassword != null)
            TextButton(
              onPressed: () {
                Navigator.pop(dialogCtx);
                onForgotPassword();
              },
              child: Text('忘記密碼？', style: TextStyle(color: AppInk.soft)),
            ),
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: Text('取消', style: TextStyle(color: AppInk.soft)),
          ),
        ],
      ),
    ),
  );
}

// 驗證家長密碼（Session 有效或未設密碼時直接通過）
Future<bool> verifyParentPinIfNeeded(
  BuildContext context, {
  String title = '請輸入家長密碼',
}) async {
  if (parentSession.value) return true;
  final prefs = await SharedPreferences.getInstance();
  if (!await ParentPin.hasPin(prefs)) return true;
  if (!context.mounted) return false;
  final digits = prefs.getInt(PrefsKeys.pinDigits) ?? 4;
  final entered = await showPinDialog(context, digits: digits, title: title);
  if (entered == null) return false;
  if (await ParentPin.verify(prefs, entered)) {
    parentSession.value = true;
    return true;
  }
  if (!context.mounted) return false;
  ScaffoldMessenger.of(
    context,
  ).showSnackBar(const SnackBar(content: Text('密碼錯誤')));
  return false;
}
