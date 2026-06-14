import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../utils/app_feedback.dart';
import '../utils/app_style.dart';

/// 生日選擇器：單一畫面同時提供「月曆點選」與「年/月/日手動輸入」，兩者即時互相同步。
/// 美觀友好，回傳所選日期（取消回 null）。
Future<DateTime?> showBirthdayPicker(
  BuildContext context, {
  DateTime? initial,
  required DateTime firstDate,
  required DateTime lastDate,
  required Color accent,
}) {
  return showDialog<DateTime>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.35),
    builder: (_) => _BirthdayPickerDialog(
      initial: initial,
      firstDate: firstDate,
      lastDate: lastDate,
      accent: accent,
    ),
  );
}

class _BirthdayPickerDialog extends StatefulWidget {
  final DateTime? initial;
  final DateTime firstDate;
  final DateTime lastDate;
  final Color accent;
  const _BirthdayPickerDialog({
    required this.initial,
    required this.firstDate,
    required this.lastDate,
    required this.accent,
  });

  @override
  State<_BirthdayPickerDialog> createState() => _BirthdayPickerDialogState();
}

class _BirthdayPickerDialogState extends State<_BirthdayPickerDialog> {
  late DateTime _sel;
  final _yCtrl = TextEditingController();
  final _mCtrl = TextEditingController();
  final _dCtrl = TextEditingController();
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    final d = widget.initial ?? DateTime(widget.lastDate.year - 20);
    _sel = _clamp(d);
    _writeFields(_sel);
    for (final c in [_yCtrl, _mCtrl, _dCtrl]) {
      c.addListener(_onFieldChanged);
    }
  }

  @override
  void dispose() {
    _yCtrl.dispose();
    _mCtrl.dispose();
    _dCtrl.dispose();
    super.dispose();
  }

  DateTime _clamp(DateTime d) {
    if (d.isBefore(widget.firstDate)) return widget.firstDate;
    if (d.isAfter(widget.lastDate)) return widget.lastDate;
    return d;
  }

  void _writeFields(DateTime d) {
    _syncing = true;
    _yCtrl.text = d.year.toString();
    _mCtrl.text = d.month.toString();
    _dCtrl.text = d.day.toString();
    _syncing = false;
  }

  // 手動輸入：三格都湊成合法且在範圍內的日期才套用，不打斷打字。
  void _onFieldChanged() {
    if (_syncing) return;
    final y = int.tryParse(_yCtrl.text);
    final m = int.tryParse(_mCtrl.text);
    final d = int.tryParse(_dCtrl.text);
    if (y == null || m == null || d == null) return;
    if (m < 1 || m > 12 || d < 1 || d > 31) return;
    if (y < widget.firstDate.year || y > widget.lastDate.year) return;
    // 用 DateTime 正規化驗證（例如 2/30 會被擋）
    final candidate = DateTime(y, m, d);
    if (candidate.month != m || candidate.day != d) return;
    if (candidate.isBefore(widget.firstDate) ||
        candidate.isAfter(widget.lastDate)) {
      return;
    }
    setState(() => _sel = candidate);
  }

  void _onCalendarChanged(DateTime d) {
    playHaptic(HapticLevel.selection);
    setState(() => _sel = d);
    _writeFields(d);
  }

  static const List<String> _weekText = ['一', '二', '三', '四', '五', '六', '日'];

  Widget _field(TextEditingController c, String suffix, int maxLen, double w) {
    return SizedBox(
      width: w,
      child: TextField(
        controller: c,
        keyboardType: TextInputType.number,
        textAlign: TextAlign.center,
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
          LengthLimitingTextInputFormatter(maxLen),
        ],
        style: AppType.digits(
          fontSize: 18,
          fontWeight: FontWeight.w800,
          color: AppInk.strong,
        ),
        decoration: InputDecoration(
          isDense: true,
          suffixText: suffix,
          suffixStyle: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: AppInk.soft,
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
          filled: true,
          fillColor: const Color(0xFFFAF7F2),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFFE8DDD4)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFFE8DDD4)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: widget.accent, width: 1.6),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final accent = widget.accent;
    return Dialog(
      backgroundColor: Colors.white,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 標題
              Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: Icon(Icons.cake_rounded, color: accent, size: 20),
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      '選擇生日',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: AppInk.strong,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(
                      Icons.close_rounded,
                      color: AppInk.iconFaint,
                    ),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // 手動輸入：年 / 月 / 日
              Row(
                children: [
                  _field(_yCtrl, '年', 4, 86),
                  const SizedBox(width: 8),
                  _field(_mCtrl, '月', 2, 64),
                  const SizedBox(width: 8),
                  _field(_dCtrl, '日', 2, 64),
                  const Spacer(),
                  Text(
                    _weekText[_sel.weekday - 1],
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: accent,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              const Divider(height: 24, color: Color(0xFFF0E9E1)),
              // 月曆（與手動輸入即時同步：_sel 變更時換 key 重建）
              Theme(
                data: Theme.of(context).copyWith(
                  colorScheme: Theme.of(context).colorScheme.copyWith(
                    primary: accent,
                    onPrimary: Colors.white,
                    onSurface: AppInk.strong,
                  ),
                ),
                child: SizedBox(
                  height: 300,
                  child: CalendarDatePicker(
                    key: ValueKey(_sel),
                    initialDate: _sel,
                    firstDate: widget.firstDate,
                    lastDate: widget.lastDate,
                    onDateChanged: _onCalendarChanged,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              // 動作鈕
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.pop(context),
                      style: TextButton.styleFrom(
                        foregroundColor: AppInk.soft,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                      ),
                      child: const Text(
                        '取消',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: accent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      onPressed: () {
                        playHaptic(HapticLevel.light);
                        Navigator.pop(context, _sel);
                      },
                      icon: const Icon(Icons.check_rounded, size: 19),
                      label: const Text(
                        '完成',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
