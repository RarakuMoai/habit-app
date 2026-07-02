import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../utils/app_style.dart';
import 'family_models.dart';
import 'family_store.dart';

// ── 積分紀錄 Tab ──

class PointRecordTab extends StatefulWidget {
  final ChildData child;

  const PointRecordTab({super.key, required this.child});

  @override
  State<PointRecordTab> createState() => _PointRecordTabState();
}

class _PointRecordTabState extends State<PointRecordTab> {
  List<PointRecord> _records = [];
  bool _loaded = false;
  // 'week' | 'month' | 'custom' | 'all'；預設本週
  String _filter = 'week';
  DateTimeRange? _customRange;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final all = await loadRecords(prefs);
    setState(() {
      _records = all.where((r) => r.childId == widget.child.id).toList();
      _loaded = true;
    });
  }

  List<PointRecord> get _filtered {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    return _records.where((r) {
      final dateStr = r.time.split(' ').first;
      final dt = DateTime.tryParse(dateStr);
      if (dt == null) return false;
      final day = DateTime(dt.year, dt.month, dt.day);

      switch (_filter) {
        case 'week':
          return !day.isBefore(today.subtract(const Duration(days: 6)));
        case 'month':
          return dt.year == now.year && dt.month == now.month;
        case 'custom':
          final r = _customRange;
          if (r == null) return false;
          return !day.isBefore(r.start) && !day.isAfter(r.end);
        default: // 'all'
          return true;
      }
    }).toList();
  }

  // 打開日期範圍選擇器
  Future<void> _pickCustomRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 2),
      lastDate: now,
      initialEntryMode: DatePickerEntryMode.input,
      initialDateRange:
          _customRange ??
          DateTimeRange(start: now.subtract(const Duration(days: 6)), end: now),
      locale: const Locale('zh', 'TW'),
    );
    if (picked != null) {
      setState(() {
        _customRange = picked;
        _filter = 'custom';
      });
    }
  }

  String _customLabel() {
    final r = _customRange;
    if (r == null) return '自訂';
    String fmt(DateTime d) => '${d.month}/${d.day}';
    return '${fmt(r.start)}–${fmt(r.end)}';
  }

  Widget _filterChip(String label, String value) {
    final selected = _filter == value;
    final primary = Theme.of(context).colorScheme.primary;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => setState(() => _filter = value),
      selectedColor: primary.withValues(alpha: 0.15),
      labelStyle: TextStyle(
        color: selected ? primary : AppInk.soft,
        fontWeight: selected ? FontWeight.bold : FontWeight.normal,
        fontSize: 13,
      ),
      side: BorderSide(color: selected ? primary : AppSurfaces.divider),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return const Center(child: CircularProgressIndicator());
    }

    final filtered = _filtered;

    return Column(
      children: [
        // ── 篩選列 ──
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _filterChip('本週', 'week'),
                const SizedBox(width: 8),
                _filterChip('本月', 'month'),
                const SizedBox(width: 8),
                // 自訂：點擊開啟日期選擇器
                GestureDetector(
                  onTap: _pickCustomRange,
                  child: _CustomRangeChip(
                    label: _customLabel(),
                    selected: _filter == 'custom',
                    primary: Theme.of(context).colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 8),
                _filterChip('全部', 'all'),
              ],
            ),
          ),
        ),
        if (filtered.isEmpty)
          Expanded(
            child: Center(
              child: Text(
                _filter == 'all' ? '尚無積分紀錄' : '此期間無積分紀錄',
                style: TextStyle(color: AppInk.faint, fontSize: 15),
              ),
            ),
          )
        else
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
              child: ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: filtered.length,
                separatorBuilder: (_, _) =>
                    const Divider(height: 1, thickness: 0.5),
                itemBuilder: (_, i) {
                  final r = filtered[i];
                  final isPlus = r.delta >= 0;
                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 4,
                    ),
                    title: Text(
                      r.reason,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    subtitle: Text(
                      r.time,
                      style: TextStyle(fontSize: 12, color: AppInk.soft),
                    ),
                    trailing: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '${isPlus ? '+' : ''}${r.delta} 分',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: isPlus ? Colors.green : Colors.red,
                          ),
                        ),
                        Text(
                          '共 ${r.total} 分',
                          style: TextStyle(fontSize: 11, color: AppInk.faint),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
      ],
    );
  }
}

// 自訂日期範圍篩選 Chip（顯示日期標籤，含日曆圖示）
class _CustomRangeChip extends StatelessWidget {
  final String label;
  final bool selected;
  final Color primary;

  const _CustomRangeChip({
    required this.label,
    required this.selected,
    required this.primary,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: selected ? primary.withValues(alpha: 0.15) : Colors.transparent,
        border: Border.all(color: selected ? primary : AppSurfaces.divider),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.date_range,
            size: 14,
            color: selected ? primary : AppInk.soft,
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: selected ? primary : AppInk.soft,
              fontWeight: selected ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }
}
