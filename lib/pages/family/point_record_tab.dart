import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../l10n/app_localizations.dart';
import '../../utils/app_style.dart';
import '../../widgets/app_waiting.dart';
import 'family_models.dart';
import 'family_store.dart';

// ── 積分紀錄 Tab ──

class PointRecordTab extends StatefulWidget {
  final ChildData child;

  const PointRecordTab({super.key, required this.child});

  @override
  State<PointRecordTab> createState() => _PointRecordTabState();
}

/// 列表的一列。「每日可多次」的習慣一天會寫進好幾筆完成紀錄（做家事記 5 次
/// 就是 5 筆），全部攤平會把這一頁洗掉，所以同一天同一個習慣的完成紀錄摺成
/// 一列，點開才展開。撤銷與家長手動加減分**不摺**——那些是要一眼看到的事件。
class _LogRow {
  /// 新到舊；長度為 1 代表這列就是單筆，外觀與摺疊前完全一樣。
  final List<PointRecord> group;
  const _LogRow(this.group);

  PointRecord get latest => group.first;
  bool get folded => group.length > 1;
  int get sumDelta => group.fold(0, (sum, r) => sum + r.delta);
}

class _PointRecordTabState extends State<PointRecordTab> {
  AppLocalizations get _l10n => AppLocalizations.of(context);

  List<PointRecord> _records = [];
  bool _loaded = false;
  // 'week' | 'month' | 'custom' | 'all'；預設本週
  String _filter = 'week';
  DateTimeRange? _customRange;
  // 已展開的摺疊列（key 同 _rowsOf 的分組鍵）
  final Set<String> _expanded = <String>{};

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

  /// 分組鍵：同一天＋同一個習慣的完成紀錄共用一個 key，其餘每筆自成一列。
  String _groupKey(PointRecord r) {
    final sourceId = r.sourceId;
    if (r.kind != PointRecordKind.habitCompletion || sourceId == null) {
      return 'single|${r.id}';
    }
    return 'habit|${r.time.split(' ').first}|$sourceId';
  }

  /// 依 [_groupKey] 把紀錄摺成列。_records 是新到舊，群組位置由該群組最新的
  /// 那一筆決定，所以摺疊後的排序跟摺疊前一致。
  List<_LogRow> _rowsOf(List<PointRecord> records) {
    final groups = <String, List<PointRecord>>{};
    final order = <String>[];
    for (final r in records) {
      final key = _groupKey(r);
      final existing = groups[key];
      if (existing == null) {
        groups[key] = [r];
        order.add(key);
      } else {
        existing.add(r);
      }
    }
    return [for (final key in order) _LogRow(groups[key]!)];
  }

  /// 一列：單筆維持原本外觀；摺疊列多一個展開箭頭，展開後在下面列出每一次。
  Widget _rowTile(_LogRow row) {
    final r = row.latest;
    final key = _groupKey(r);
    final expanded = _expanded.contains(key);
    final delta = row.folded ? row.sumDelta : r.delta;
    final isPlus = delta >= 0;

    final tile = ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      onTap: row.folded
          ? () => setState(
              () => expanded ? _expanded.remove(key) : _expanded.add(key),
            )
          : null,
      title: Text(
        row.folded
            ? _l10n.prtFoldedTitle(r.reason, row.group.length)
            : r.reason,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
      ),
      subtitle: Text(
        // 摺疊列的每一筆時間各自不同，只標日期；展開後才逐筆看時間
        row.folded ? r.time.split(' ').first : r.time,
        style: TextStyle(fontSize: 12, color: AppInk.soft),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                _l10n.prtDelta(isPlus ? '+' : '', delta),
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: isPlus ? Colors.green : Colors.red,
                ),
              ),
              Text(
                // 摺疊時取最新那筆的累計，那才是這一天結束時的分數
                _l10n.prtTotal(r.total),
                style: TextStyle(fontSize: 11, color: AppInk.faint),
              ),
            ],
          ),
          if (row.folded)
            Icon(
              expanded ? Icons.expand_less_rounded : Icons.expand_more_rounded,
              size: 20,
              color: AppInk.iconFaint,
            ),
        ],
      ),
    );

    if (!row.folded || !expanded) return tile;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        tile,
        for (final item in row.group)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 4, 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _recordTime(item),
                  style: TextStyle(fontSize: 12, color: AppInk.soft),
                ),
                Text(
                  _l10n.prtDelta(item.delta >= 0 ? '+' : '', item.delta),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: item.delta >= 0 ? Colors.green : Colors.red,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  /// 從 `yyyy-MM-dd HH:mm` 取 `HH:mm`
  String _recordTime(PointRecord r) {
    final parts = r.time.split(' ');
    return parts.length > 1 ? parts.last : r.time;
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
    if (r == null) return _l10n.prtCustom;
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
      return const AppPageWaiting();
    }

    final filtered = _filtered;
    final rows = _rowsOf(filtered);

    return Column(
      children: [
        // ── 篩選列 ──
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _filterChip(_l10n.weightRangeWeek, 'week'),
                const SizedBox(width: 8),
                _filterChip(_l10n.weightRangeMonth, 'month'),
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
                _filterChip(_l10n.prtAll, 'all'),
              ],
            ),
          ),
        ),
        if (filtered.isEmpty)
          Expanded(
            child: Center(
              child: Text(
                _filter == 'all' ? _l10n.prtEmptyAll : _l10n.prtEmptyRange,
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
                itemCount: rows.length,
                separatorBuilder: (_, _) =>
                    const Divider(height: 1, thickness: 0.5),
                itemBuilder: (_, i) => _rowTile(rows[i]),
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
