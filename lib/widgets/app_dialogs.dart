// 對話框按鈕慣例的單一出口。
//
// 全 app 的 AlertDialog 動作鈕照這裡的語彙走：
// - 取消／略過：次要暖棕（AppInk.soft），不搶主行動。
// - 確認：theme primary（預設 TextButton 色）。
// - 危險（刪除／清空）：AppInk.danger 暖磚紅。
// 個別頁面不要再手寫 Colors.grey / Colors.red。
import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../utils/app_feedback.dart';
import '../utils/app_style.dart';
import '../utils/sfx_service.dart';

/// 對話框「取消」類動作鈕（次要視覺）。
/// [label] 不傳時用通用「取消」；[onPressed] 預設 pop(null)；
/// 需要 pop(false) 等自己傳。
Widget dialogCancelAction(
  BuildContext context, {
  String? label,
  VoidCallback? onPressed,
}) {
  return TextButton(
    onPressed: onPressed ?? () => Navigator.pop(context),
    child: Text(
      label ?? AppLocalizations.of(context).commonCancel,
      style: const TextStyle(color: AppInk.soft),
    ),
  );
}

/// 標準確認框：標題 + 訊息 + 取消/確認。回傳 true = 使用者按下確認。
/// [confirmLabel]／[cancelLabel] 不傳時用通用「確定」／「取消」。
/// [danger] = true 時確認鈕用暖磚紅（刪除、清空類）。
/// 回饋語言：**打斷使用者的東西要出聲，使用者自己按的不要重複出聲。**
/// 確認框是 app 主動擋在前面，所以開啟時給一次 selection 觸覺當「這裡停一下」；
/// 取消走 [SfxCue.cancel]（收回、退場的統一語彙），確認則刻意不發——
/// 按下確認之後真正發生的那件事會自己出聲（刪除、清空、儲存各有各的回饋），
/// 在這裡先響一次會變成同一個動作連響兩聲。
Future<bool> showAppConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String? confirmLabel,
  String? cancelLabel,
  bool danger = false,
}) async {
  playHaptic(HapticLevel.selection);
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        dialogCancelAction(
          ctx,
          label: cancelLabel,
          onPressed: () {
            playFeedback(SfxCue.cancel);
            Navigator.pop(ctx, false);
          },
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(
            confirmLabel ?? AppLocalizations.of(ctx).commonOk,
            style: danger ? const TextStyle(color: AppInk.danger) : null,
          ),
        ),
      ],
    ),
  );
  return result == true;
}
