// 手動輸入日期的對話框：取代 Material 日期選擇器自帶的輸入模式
// （那個模式的解析吃 intl 死格式，使用者少打一個 - 就報錯）。
// 解析走 parseLenientDate，2000-1-1 / 20000101 / 2000年1月1日 都吃。
import 'package:flutter/material.dart';

import '../utils/lenient_date.dart';

/// 回傳解析成功的日期；取消回傳 null。
/// [firstDate]/[lastDate] 之外的日期會擋下並顯示錯誤。
Future<DateTime?> showManualDateDialog(
  BuildContext context, {
  DateTime? initial,
  required DateTime firstDate,
  required DateTime lastDate,
  String title = '輸入日期',
}) {
  final ctrl = TextEditingController(
    text: initial == null
        ? ''
        : '${initial.year}-${initial.month}-${initial.day}',
  );
  String? error;
  return showDialog<DateTime>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) {
        void submit() {
          final parsed = parseLenientDate(ctrl.text);
          if (parsed == null) {
            setS(() => error = '看不懂這個日期，試試 2000-1-1 或 20000101');
            return;
          }
          if (parsed.isBefore(firstDate) || parsed.isAfter(lastDate)) {
            setS(() => error = '日期超出可選範圍');
            return;
          }
          Navigator.pop(ctx, parsed);
        }

        return AlertDialog(
          title: Text(title),
          content: TextField(
            controller: ctrl,
            autofocus: true,
            keyboardType: TextInputType.datetime,
            decoration: InputDecoration(
              hintText: '例：2000-1-1 或 20000101',
              errorText: error,
              errorMaxLines: 2,
            ),
            onChanged: (_) {
              if (error != null) setS(() => error = null);
            },
            onSubmitted: (_) => submit(),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            FilledButton(onPressed: submit, child: const Text('確認')),
          ],
        );
      },
    ),
  );
}
