// 對話框按鈕慣例的單一出口。
//
// 全 app 的 AlertDialog 動作鈕照這裡的語彙走：
// - 取消／略過：次要暖棕（AppInk.soft），不搶主行動。
// - 確認：theme primary（預設 TextButton 色）。
// - 危險（刪除／清空）：AppInk.danger 暖磚紅。
// 個別頁面不要再手寫 Colors.grey / Colors.red。
import 'package:flutter/material.dart';

import '../utils/app_style.dart';

/// 對話框「取消」類動作鈕（次要視覺）。
/// [onPressed] 預設 pop(null)；需要 pop(false) 等自己傳。
Widget dialogCancelAction(
  BuildContext context, {
  String label = '取消',
  VoidCallback? onPressed,
}) {
  return TextButton(
    onPressed: onPressed ?? () => Navigator.pop(context),
    child: Text(label, style: const TextStyle(color: AppInk.soft)),
  );
}

/// 標準確認框：標題 + 訊息 + 取消/確認。回傳 true = 使用者按下確認。
/// [danger] = true 時確認鈕用暖磚紅（刪除、清空類）。
Future<bool> showAppConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = '確定',
  String cancelLabel = '取消',
  bool danger = false,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        dialogCancelAction(
          ctx,
          label: cancelLabel,
          onPressed: () => Navigator.pop(ctx, false),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(
            confirmLabel,
            style: danger ? const TextStyle(color: AppInk.danger) : null,
          ),
        ),
      ],
    ),
  );
  return result == true;
}
