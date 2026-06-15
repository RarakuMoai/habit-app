import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../utils/app_feedback.dart';
import '../utils/app_style.dart';

/// 生日選擇器：一格快速輸入（打 8 碼自動成日期）＋ 可直接點選年/月的月曆。
/// 設計核心：點一次就能編輯完，月/年用大格子直選，小孩老人都能秒上手。
/// 回傳所選日期（取消回 null）。
Future<DateTime?> showBirthdayPicker(
  BuildContext context, {
  DateTime? initial,
  required DateTime firstDate,
  required DateTime lastDate,
  required Color accent,
}) {
  return showAppDatePicker(
    context,
    initial: initial,
    firstDate: firstDate,
    lastDate: lastDate,
    accent: accent,
    title: '選擇生日',
    icon: Icons.cake_rounded,
    helperText: '直接輸入西元年月日，例如 20190403',
  );
}

/// 單日日期選擇器：沿用生日選擇器的快速輸入、年/月直選與月曆系統。
Future<DateTime?> showAppDatePicker(
  BuildContext context, {
  DateTime? initial,
  required DateTime firstDate,
  required DateTime lastDate,
  required Color accent,
  String title = '選擇日期',
  IconData icon = Icons.event_rounded,
  String helperText = '直接輸入西元年月日，例如 20260615',
}) {
  return showDialog<DateTime>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.35),
    builder: (_) => _BirthdayPickerDialog(
      initial: initial,
      firstDate: firstDate,
      lastDate: lastDate,
      accent: accent,
      title: title,
      icon: icon,
      helperText: helperText,
    ),
  );
}

enum _Mode { day, month, year }

class _BirthdayPickerDialog extends StatefulWidget {
  final DateTime? initial;
  final DateTime firstDate;
  final DateTime lastDate;
  final Color accent;
  final String title;
  final IconData icon;
  final String helperText;
  const _BirthdayPickerDialog({
    required this.initial,
    required this.firstDate,
    required this.lastDate,
    required this.accent,
    required this.title,
    required this.icon,
    required this.helperText,
  });

  @override
  State<_BirthdayPickerDialog> createState() => _BirthdayPickerDialogState();
}

class _BirthdayPickerDialogState extends State<_BirthdayPickerDialog> {
  late DateTime _sel;
  final _ctrl = TextEditingController();
  bool _syncing = false;
  _Mode _mode = _Mode.day;
  ScrollController? _yearScroll;

  static const _fieldFill = Color(0xFFFAF7F2);
  static const _border = Color(0xFFE8DDD4);
  static const _warn = Color(0xFFE0823C); // 無效輸入的柔性提示色（暖琥珀，非刺眼紅）

  // 手動輸入滿 8 碼但日期無效時為 true：欄位轉警示色、星期顯示「—」，
  // 但不阻止輸入、也不動月曆（仍可改成合法值或改用點選）。
  bool _inputInvalid = false;

  @override
  void initState() {
    super.initState();
    final d = widget.initial ?? DateTime(widget.lastDate.year - 20);
    _sel = _clamp(d);
    _writeField(_sel);
    _ctrl.addListener(_onFieldChanged);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _yearScroll?.dispose();
    super.dispose();
  }

  DateTime _clamp(DateTime d) {
    if (d.isBefore(widget.firstDate)) return widget.firstDate;
    if (d.isAfter(widget.lastDate)) return widget.lastDate;
    return d;
  }

  // 用年/月/日組出安全日期：日超過該月天數自動收斂，再夾進允許範圍。
  DateTime _safe(int y, int m, int day) {
    final maxDay = DateTime(y, m + 1, 0).day;
    return _clamp(DateTime(y, m, day.clamp(1, maxDay)));
  }

  void _writeField(DateTime d) {
    _syncing = true;
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    _ctrl.text = '${d.year} / $m / $day';
    _syncing = false;
  }

  // 由月曆/格子選擇而來：更新 _sel 並同步回輸入框。
  // 改用「點」的就順手收鍵盤，讓月曆完整露出。
  void _apply(DateTime d, {bool toField = true}) {
    FocusScope.of(context).unfocus();
    setState(() {
      _sel = _clamp(d);
      _inputInvalid = false;
    });
    if (toField) _writeField(_sel);
  }

  // 手動輸入：滿 8 碼才判斷。合法→套用到月曆；不合法→不動月曆、亮柔性警示。
  void _onFieldChanged() {
    if (_syncing) return;
    final digits = _ctrl.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length < 8) {
      if (_inputInvalid) setState(() => _inputInvalid = false);
      return;
    }
    final y = int.parse(digits.substring(0, 4));
    final m = int.parse(digits.substring(4, 6));
    final d = int.parse(digits.substring(6, 8));
    final candidate = (m >= 1 && m <= 12 && d >= 1 && d <= 31)
        ? DateTime(y, m, d)
        : null;
    final valid =
        candidate != null &&
        candidate.month == m && // 例如 2/30 會被正規化掉
        candidate.day == d &&
        !candidate.isBefore(widget.firstDate) &&
        !candidate.isAfter(widget.lastDate);
    setState(() {
      if (valid) {
        _sel = candidate; // valid 為真時 candidate 必非 null（flow 已推斷）
        _inputInvalid = false;
      } else {
        _inputInvalid = true;
      }
    });
  }

  void _setMode(_Mode m) {
    FocusScope.of(context).unfocus();
    playHaptic(HapticLevel.selection);
    if (m == _Mode.year) {
      final idx = _sel.year - widget.firstDate.year;
      final row = idx ~/ 4;
      _yearScroll?.dispose();
      _yearScroll = ScrollController(
        initialScrollOffset: (row * 52.0 - 80).clamp(0.0, double.infinity),
      );
    }
    setState(() => _mode = _mode == m ? _Mode.day : m);
  }

  void _shiftMonth(int delta) {
    playHaptic(HapticLevel.selection);
    _apply(_safe(_sel.year, _sel.month + delta, _sel.day));
  }

  static const List<String> _weekText = ['一', '二', '三', '四', '五', '六', '日'];

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
        // 動作鈕釘在底部、不進捲動區：鍵盤彈出時 Dialog 會被推到鍵盤上方，
        // 釘住的「取消/完成」永遠貼在對話框底＝永遠看得到；中間月曆改成可
        // 壓縮的捲動區（Flexible loose），沒鍵盤時仍維持原本的精簡高度。
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 4),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _titleRow(accent),
                    const SizedBox(height: 12),
                    _inputField(accent),
                    const SizedBox(height: 8),
                    Text(
                      widget.helperText,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: AppInk.faint,
                      ),
                    ),
                    const Divider(height: 26, color: Color(0xFFF0E9E1)),
                    _navHeader(accent),
                    const SizedBox(height: 10),
                    SizedBox(height: 268, child: _body(accent)),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: _actions(accent),
            ),
          ],
        ),
      ),
    );
  }

  Widget _titleRow(Color accent) {
    return Row(
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(13),
          ),
          child: Icon(widget.icon, color: accent, size: 20),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            widget.title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              color: AppInk.strong,
            ),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.close_rounded, color: AppInk.iconFaint),
          onPressed: () => Navigator.pop(context),
        ),
      ],
    );
  }

  // 單一輸入框：打 8 碼自動排成「YYYY / MM / DD」。右側顯示星期。
  Widget _inputField(Color accent) {
    return TextField(
      controller: _ctrl,
      keyboardType: TextInputType.number,
      textInputAction: TextInputAction.done,
      onSubmitted: (_) => FocusScope.of(context).unfocus(),
      style: AppType.digits(
        fontSize: 20,
        fontWeight: FontWeight.w800,
        color: _inputInvalid ? _warn : AppInk.strong,
        letterSpacing: 1.5,
      ),
      inputFormatters: [_DateDigitsFormatter()],
      decoration: InputDecoration(
        isDense: true,
        hintText: 'YYYY / MM / DD',
        hintStyle: AppType.digits(
          fontSize: 20,
          color: AppInk.faint,
          letterSpacing: 1.5,
        ),
        prefixIcon: Icon(Icons.edit_calendar_rounded, color: accent, size: 22),
        suffixIcon: Padding(
          padding: const EdgeInsets.only(right: 14),
          child: Text(
            _inputInvalid ? '—' : '週${_weekText[_sel.weekday - 1]}',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: _inputInvalid ? _warn : accent,
            ),
          ),
        ),
        suffixIconConstraints: const BoxConstraints(),
        contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 16),
        filled: true,
        fillColor: _fieldFill,
        border: _fieldBorder(_border, 1),
        enabledBorder: _fieldBorder(
          _inputInvalid ? _warn : _border,
          _inputInvalid ? 1.6 : 1,
        ),
        focusedBorder: _fieldBorder(_inputInvalid ? _warn : accent, 1.8),
      ),
    );
  }

  OutlineInputBorder _fieldBorder(Color c, double w) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(16),
    borderSide: BorderSide(color: c, width: w),
  );

  // 年/月 直選列：左右箭頭微調月份，中間兩顆大 chip 點開年/月格子。
  Widget _navHeader(Color accent) {
    final atFirst = !_sel.isAfter(
      DateTime(widget.firstDate.year, widget.firstDate.month),
    );
    final atLast =
        DateTime(_sel.year, _sel.month).isAtSameMomentAs(
          DateTime(widget.lastDate.year, widget.lastDate.month),
        ) ||
        DateTime(
          _sel.year,
          _sel.month,
        ).isAfter(DateTime(widget.lastDate.year, widget.lastDate.month));
    return Row(
      children: [
        _arrow(
          Icons.chevron_left_rounded,
          atFirst ? null : () => _shiftMonth(-1),
        ),
        Expanded(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _headerChip(
                '${_sel.year} 年',
                _mode == _Mode.year,
                accent,
                () => _setMode(_Mode.year),
              ),
              const SizedBox(width: 8),
              _headerChip(
                '${_sel.month} 月',
                _mode == _Mode.month,
                accent,
                () => _setMode(_Mode.month),
              ),
            ],
          ),
        ),
        _arrow(
          Icons.chevron_right_rounded,
          atLast ? null : () => _shiftMonth(1),
        ),
      ],
    );
  }

  Widget _arrow(IconData icon, VoidCallback? onTap) {
    return IconButton(
      onPressed: onTap,
      icon: Icon(icon, size: 26),
      color: AppInk.soft,
      disabledColor: const Color(0xFFE0D6CC),
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
    );
  }

  Widget _headerChip(
    String text,
    bool active,
    Color accent,
    VoidCallback onTap,
  ) {
    return Material(
      color: active ? accent.withValues(alpha: 0.14) : _fieldFill,
      borderRadius: BorderRadius.circular(13),
      child: InkWell(
        borderRadius: BorderRadius.circular(13),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 9, 8, 9),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                text,
                style: AppType.digits(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: active ? accent : AppInk.strong,
                ),
              ),
              Icon(
                Icons.arrow_drop_down_rounded,
                size: 22,
                color: active ? accent : AppInk.faint,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _body(Color accent) {
    switch (_mode) {
      case _Mode.year:
        return _yearGrid(accent);
      case _Mode.month:
        return _monthGrid(accent);
      case _Mode.day:
        return _dayGrid(accent);
    }
  }

  // ── 日：月曆格子 ──
  Widget _dayGrid(Color accent) {
    final y = _sel.year, m = _sel.month;
    final lead = DateTime(y, m).weekday - 1; // 週一為首
    final days = DateTime(y, m + 1, 0).day;
    final today = DateTime.now();

    final cells = <Widget?>[];
    for (var i = 0; i < lead; i++) {
      cells.add(null);
    }
    for (var d = 1; d <= days; d++) {
      cells.add(_dayCell(d, accent, today));
    }
    while (cells.length % 7 != 0) {
      cells.add(null);
    }

    final rows = <Widget>[
      Row(
        children: _weekText
            .map(
              (t) => Expanded(
                child: Center(
                  child: Text(
                    t,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: AppInk.faint,
                    ),
                  ),
                ),
              ),
            )
            .toList(),
      ),
      const SizedBox(height: 4),
    ];
    for (var i = 0; i < cells.length; i += 7) {
      rows.add(
        Expanded(
          child: Row(
            children: [
              for (var j = 0; j < 7; j++)
                Expanded(child: cells[i + j] ?? const SizedBox.shrink()),
            ],
          ),
        ),
      );
    }
    return Column(children: rows);
  }

  Widget _dayCell(int day, Color accent, DateTime today) {
    final date = DateTime(_sel.year, _sel.month, day);
    final selected = day == _sel.day;
    final disabled =
        date.isBefore(widget.firstDate) || date.isAfter(widget.lastDate);
    final isToday =
        date.year == today.year &&
        date.month == today.month &&
        date.day == today.day;
    return Padding(
      padding: const EdgeInsets.all(2),
      child: Material(
        color: selected ? accent : Colors.transparent,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: disabled
              ? null
              : () {
                  playHaptic(HapticLevel.selection);
                  _apply(date);
                },
          child: Container(
            alignment: Alignment.center,
            decoration: isToday && !selected
                ? BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: accent.withValues(alpha: 0.5)),
                  )
                : null,
            child: Text(
              '$day',
              style: AppType.digits(
                fontSize: 16,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                color: selected
                    ? Colors.white
                    : disabled
                    ? AppInk.faint
                    : AppInk.strong,
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── 月：12 顆大按鈕 ──
  Widget _monthGrid(Color accent) {
    return GridView.count(
      crossAxisCount: 4,
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      childAspectRatio: 1.5,
      physics: const NeverScrollableScrollPhysics(),
      children: List.generate(12, (i) {
        final m = i + 1;
        final selected = m == _sel.month;
        final probe = _safe(_sel.year, m, _sel.day);
        final disabled = probe.year != _sel.year || probe.month != m;
        return _gridButton('$m 月', selected, disabled, accent, () {
          playHaptic(HapticLevel.selection);
          _apply(_safe(_sel.year, m, _sel.day));
          setState(() => _mode = _Mode.day);
        });
      }),
    );
  }

  // ── 年：可捲動年份格，開啟時自動捲到目前年 ──
  Widget _yearGrid(Color accent) {
    final first = widget.firstDate.year;
    final last = widget.lastDate.year;
    final count = last - first + 1;
    return GridView.builder(
      controller: _yearScroll,
      itemCount: count,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        mainAxisExtent: 44,
      ),
      itemBuilder: (_, i) {
        final y = first + i;
        final selected = y == _sel.year;
        return _gridButton('$y', selected, false, accent, () {
          playHaptic(HapticLevel.selection);
          _apply(_safe(y, _sel.month, _sel.day));
          setState(() => _mode = _Mode.day);
        });
      },
    );
  }

  Widget _gridButton(
    String text,
    bool selected,
    bool disabled,
    Color accent,
    VoidCallback onTap,
  ) {
    return Material(
      color: selected
          ? accent
          : (disabled ? const Color(0xFFF4EFE9) : _fieldFill),
      borderRadius: BorderRadius.circular(13),
      child: InkWell(
        borderRadius: BorderRadius.circular(13),
        onTap: disabled ? null : onTap,
        child: Center(
          child: Text(
            text,
            style: AppType.digits(
              fontSize: 16,
              fontWeight: selected ? FontWeight.w800 : FontWeight.w700,
              color: selected
                  ? Colors.white
                  : disabled
                  ? AppInk.faint
                  : AppInk.strong,
            ),
          ),
        ),
      ),
    );
  }

  Widget _actions(Color accent) {
    return Row(
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
    );
  }
}

/// 把純數字排成「YYYY / MM / DD」：只留數字、最多 8 碼，邊打邊補分隔線。
class _DateDigitsFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    var digits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length > 8) digits = digits.substring(0, 8);
    final b = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i == 4 || i == 6) b.write(' / ');
      b.write(digits[i]);
    }
    final text = b.toString();
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}
