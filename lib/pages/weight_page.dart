import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fl_chart/fl_chart.dart';
import 'dart:convert';
import 'settings_page.dart';

class WeightPage extends StatefulWidget {
  const WeightPage({super.key});

  @override
  State<WeightPage> createState() => _WeightPageState();
}

class _WeightPageState extends State<WeightPage> {
  // 所有體重紀錄（按日期降序）
  List<Map<String, dynamic>> _records = [];
  double? _userHeight; // 身高（公分）
  String _gender = '';
  DateTime? _birthday;
  // 控制 BottomSheet 是否顯示體脂欄位
  bool _weightTrackingEnabled = false;
  // 目標體重（從設定讀取）
  double? _targetWeight;
  // 圖表顯示範圍：0=本週, 1=本月, 2=三個月
  int _chartRangeIndex = 0;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    final String? json = prefs.getString('weight_records');
    final String? bday = prefs.getString('user_birthday');

    List<Map<String, dynamic>> records = [];
    if (json != null) {
      final List<dynamic> decoded = jsonDecode(json);
      records = decoded.map((e) => Map<String, dynamic>.from(e)).toList();
    }
    // 按日期降序排列（最新在上）
    records.sort((a, b) => b['date'].compareTo(a['date']));

    setState(() {
      _records = records;
      _userHeight = prefs.getDouble('user_height');
      _gender = prefs.getString('user_gender') ?? '';
      if (bday != null) _birthday = DateTime.tryParse(bday);
      _weightTrackingEnabled = prefs.getBool('weight_tracking_enabled') ?? false;
      _targetWeight = prefs.getDouble('target_weight');
      _loaded = true;
    });
  }

  Future<void> _saveRecords() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('weight_records', jsonEncode(_records));
  }

  // 今天日期字串（yyyy-MM-dd）
  String _todayString() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  // DateTime 轉 yyyy-MM-dd 字串
  String _dateStr(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  // BMI = 體重 ÷ 身高(m)²
  double? _calcBMI(double weight) {
    if (_userHeight == null || _userHeight! <= 0) return null;
    final hM = _userHeight! / 100;
    return weight / (hM * hM);
  }

  // 從生日計算年齡
  int? _calcAge() {
    if (_birthday == null) return null;
    final now = DateTime.now();
    int age = now.year - _birthday!.year;
    if (now.month < _birthday!.month ||
        (now.month == _birthday!.month && now.day < _birthday!.day)) {
      age--;
    }
    return age;
  }

  // BMR（Mifflin-St Jeor）：男 10w+6.25h-5a+5，女 10w+6.25h-5a-161
  double? _calcBMR(double weight) {
    if (_userHeight == null) return null;
    final age = _calcAge();
    if (age == null) return null;
    if (_gender == '男') return 10 * weight + 6.25 * _userHeight! - 5 * age + 5;
    if (_gender == '女') return 10 * weight + 6.25 * _userHeight! - 5 * age - 161;
    return null;
  }

  // 本週週一到週日的 DateTime 列表（x=0~6 對應週一~週日）
  List<DateTime> _currentWeekDays() {
    final now = DateTime.now();
    final monday = now.subtract(Duration(days: now.weekday - 1));
    return List.generate(
      7,
      (i) => DateTime(monday.year, monday.month, monday.day + i),
    );
  }

  // 本週折線圖資料點（x = 0~6）
  // 歷史不足7天時只顯示有資料的點，不強制補滿
  List<FlSpot> _weekSpots() {
    final weekDays = _currentWeekDays();
    final List<FlSpot> spots = [];
    for (int i = 0; i < weekDays.length; i++) {
      final dayStr = _dateStr(weekDays[i]);
      final idx = _records.indexWhere((r) => r['date'] == dayStr);
      if (idx >= 0) {
        spots.add(FlSpot(i.toDouble(), (_records[idx]['weight'] as num).toDouble()));
      }
    }
    return spots;
  }

  // 本月折線圖資料點（x = 當月日期數字）
  List<FlSpot> _monthSpots() {
    final now = DateTime.now();
    final prefix = '${now.year}-${now.month.toString().padLeft(2, '0')}';
    final List<FlSpot> spots = [];
    // reversed 讓資料從舊到新（ascending order for chart）
    for (final rec in _records.reversed) {
      final date = rec['date'] as String;
      if (date.startsWith(prefix)) {
        final day = int.tryParse(date.split('-')[2]);
        if (day != null) {
          spots.add(FlSpot(day.toDouble(), (rec['weight'] as num).toDouble()));
        }
      }
    }
    return spots;
  }

  // 三個月折線圖資料點（x = 距90天前的偏移天數, 0~89）
  List<FlSpot> _threeMonthSpots() {
    final now = DateTime.now();
    // 起始日期：89 天前（含今天共 90 天）
    final startDate = DateTime(now.year, now.month, now.day)
        .subtract(const Duration(days: 89));
    final List<FlSpot> spots = [];
    for (final rec in _records.reversed) {
      final date = DateTime.tryParse(rec['date'] as String);
      if (date == null) continue;
      final offset = date.difference(startDate).inDays;
      if (offset >= 0 && offset <= 89) {
        spots.add(FlSpot(offset.toDouble(), (rec['weight'] as num).toDouble()));
      }
    }
    return spots;
  }

  // 新增或覆蓋同日紀錄（同一天只保留一筆）
  void _upsertRecord(Map<String, dynamic> record) {
    setState(() {
      _records.removeWhere((r) => r['date'] == record['date']);
      _records.add(record);
      _records.sort((a, b) => b['date'].compareTo(a['date']));
    });
    _saveRecords();
  }

  // 刪除指定日期的紀錄
  void _deleteRecord(Map<String, dynamic> rec) {
    setState(() {
      _records.removeWhere((r) => r['date'] == rec['date']);
    });
    _saveRecords();
  }

  // 格式化數字（整數不顯示小數點，否則保留指定位數）
  String _fmt(double v, {int decimal = 1}) {
    if (decimal == 0) return v.round().toString();
    if (v == v.truncateToDouble()) return v.toInt().toString();
    return v.toStringAsFixed(decimal);
  }

  // 取得目前圖表範圍的資料點與 X 軸設定（封裝為 _ChartData）
  _ChartData _getChartData() {
    switch (_chartRangeIndex) {
      case 1: // 本月：x = 當月日期數字
        final spots = _monthSpots();
        final now = DateTime.now();
        final daysInMonth = DateTime(now.year, now.month + 1, 0).day;
        return _ChartData(
          spots: spots,
          minX: 1,
          maxX: daysInMonth.toDouble(),
          getBottomTitle: (value, meta) {
            final day = value.toInt();
            // 只顯示 1、8、15、22 及月底
            if (day == 1 || day == 8 || day == 15 || day == 22 || day == daysInMonth) {
              return Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '$day',
                  style: TextStyle(
                    fontSize: 10,
                    color: day == now.day ? Colors.orange : Colors.grey,
                    fontWeight: day == now.day ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              );
            }
            return const SizedBox.shrink();
          },
        );

      case 2: // 三個月：x = 距90天前的偏移天數
        final spots = _threeMonthSpots();
        final now = DateTime.now();
        final startDate = DateTime(now.year, now.month, now.day)
            .subtract(const Duration(days: 89));
        return _ChartData(
          spots: spots,
          minX: 0,
          maxX: 89,
          getBottomTitle: (value, meta) {
            final offset = value.toInt();
            final d = startDate.add(Duration(days: offset));
            // 每月 1 日或起始日才顯示標籤
            if (d.day == 1 || offset == 0) {
              return Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '${d.month}/${d.day}',
                  style: TextStyle(
                    fontSize: 9,
                    color: (d.year == now.year &&
                            d.month == now.month &&
                            d.day == now.day)
                        ? Colors.orange
                        : Colors.grey,
                  ),
                ),
              );
            }
            return const SizedBox.shrink();
          },
        );

      case 0: // 本週（預設）：x = 0~6 對應週一~週日
      default:
        final spots = _weekSpots();
        final weekDays = _currentWeekDays();
        const labels = ['一', '二', '三', '四', '五', '六', '日'];
        final now = DateTime.now();
        return _ChartData(
          spots: spots,
          minX: 0,
          maxX: 6,
          getBottomTitle: (value, meta) {
            final idx = value.toInt();
            if (idx < 0 || idx > 6) return const SizedBox.shrink();
            final d = weekDays[idx];
            final isToday = d.year == now.year &&
                d.month == now.month &&
                d.day == now.day;
            return Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                labels[idx],
                style: TextStyle(
                  fontSize: 11,
                  color: isToday ? Colors.orange : Colors.grey,
                  fontWeight: isToday ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            );
          },
        );
    }
  }

  // 開啟新增／編輯 BottomSheet
  // existing 不為 null 時為編輯模式，預填現有資料
  void _openAddSheet({Map<String, dynamic>? existing}) {
    DateTime selectedDate = existing != null
        ? (DateTime.tryParse(existing['date'] as String) ?? DateTime.now())
        : DateTime.now();
    final weightCtrl = TextEditingController(
      text: existing != null
          ? _fmt((existing['weight'] as num).toDouble())
          : '',
    );
    final fatCtrl = TextEditingController(
      text: existing != null && existing['body_fat'] != null
          ? _fmt((existing['body_fat'] as num).toDouble())
          : '',
    );

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(ctx).viewInsets.bottom,
              ),
              child: Container(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
                decoration: const BoxDecoration(
                  color: Color(0xFFFFF8F0),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 標題列（新增 vs 編輯）
                    Row(
                      children: [
                        const Icon(
                          Icons.monitor_weight_outlined,
                          color: Colors.orange,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          existing != null ? '編輯體重紀錄' : '新增體重紀錄',
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                            color: Colors.orange,
                          ),
                        ),
                        const Spacer(),
                        IconButton(
                          icon: Icon(Icons.close, color: Colors.grey.shade500),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // 日期選擇（點擊開啟日期選擇器）
                    InkWell(
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: ctx,
                          initialDate: selectedDate,
                          firstDate: DateTime(2000),
                          lastDate: DateTime.now(),
                        );
                        if (picked != null) {
                          setSheetState(() => selectedDate = picked);
                        }
                      },
                      borderRadius: BorderRadius.circular(12),
                      child: InputDecorator(
                        decoration: InputDecoration(
                          labelText: '日期',
                          suffixIcon: const Icon(
                            Icons.calendar_today_outlined,
                            size: 18,
                            color: Colors.orange,
                          ),
                          filled: true,
                          fillColor: Colors.white,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: Colors.grey.shade300),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 14,
                          ),
                        ),
                        child: Text(
                          '${selectedDate.year} 年 '
                          '${selectedDate.month.toString().padLeft(2, '0')} 月 '
                          '${selectedDate.day.toString().padLeft(2, '0')} 日',
                          style: const TextStyle(fontSize: 15),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // 體重（必填）
                    TextField(
                      controller: weightCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText: '體重 *',
                        suffixText: 'kg',
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: Colors.orange),
                        ),
                      ),
                    ),

                    // 體脂（選填，依 weight_tracking_enabled 控制顯示）
                    if (_weightTrackingEnabled) ...[
                      const SizedBox(height: 12),
                      TextField(
                        controller: fatCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: InputDecoration(
                          labelText: '體脂率（選填）',
                          suffixText: '%',
                          filled: true,
                          fillColor: Colors.white,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: Colors.orange),
                          ),
                        ),
                      ),
                    ],

                    const SizedBox(height: 20),

                    // 儲存按鈕
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () {
                          final weight =
                              double.tryParse(weightCtrl.text.trim());
                          if (weight == null) return;
                          final fat = double.tryParse(fatCtrl.text.trim());
                          final now = DateTime.now();
                          final time =
                              '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
                          final record = <String, dynamic>{
                            'date': _dateStr(selectedDate),
                            // 編輯模式保留原始時間；新增模式使用當前時間
                            'time': existing?['time'] ?? time,
                            'weight': weight,
                          };
                          if (fat != null) record['body_fat'] = fat;
                          _upsertRecord(record);
                          Navigator.pop(ctx);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orange,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: const Text(
                          '儲存',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    ).whenComplete(() {
      // BottomSheet 關閉後釋放控制器
      weightCtrl.dispose();
      fatCtrl.dispose();
    });
  }

  // 顯示紀錄操作選單（長按或左滑呼叫）
  void _showRecordActions(Map<String, dynamic> rec) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            // 把手指示條
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.edit_outlined, color: Colors.orange),
              title: const Text('編輯'),
              onTap: () {
                Navigator.pop(ctx);
                _openAddSheet(existing: rec);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: const Text('刪除', style: TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.pop(ctx);
                _confirmDelete(rec);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  // 刪除二次確認 Dialog
  void _confirmDelete(Map<String, dynamic> rec) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('確認刪除'),
        content: Text('確定要刪除 ${rec['date']} 的體重紀錄嗎？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _deleteRecord(rec);
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('刪除'),
          ),
        ],
      ),
    );
  }

  // 目標體重進度條（若未設定目標或無紀錄則回傳 null）
  Widget? _buildTargetProgress() {
    if (_targetWeight == null || _records.isEmpty) return null;

    final target = _targetWeight!;
    // _records 降序排列，last 為最早一筆（作為起始體重）
    final initialWeight = (_records.last['weight'] as num).toDouble();
    final latestWeight = (_records.first['weight'] as num).toDouble();

    // 起始與目標相同則不顯示
    if ((target - initialWeight).abs() < 0.001) return null;

    // 進度 = (目前改變量) / (總目標改變量)，0~1
    final rawProgress =
        (latestWeight - initialWeight) / (target - initialWeight);
    final progress = rawProgress.clamp(0.0, 1.0);
    final isGoalReached = rawProgress >= 1.0;
    final diff = (latestWeight - target).abs();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.orange.shade100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.flag_outlined, color: Colors.orange, size: 18),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  isGoalReached
                      ? '目標：${_fmt(target)} kg　已達成！'
                      : '目標：${_fmt(target)} kg，還差 ${_fmt(diff)} kg',
                  style: const TextStyle(fontSize: 14, color: Colors.black87),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // 線性進度條
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              backgroundColor: Colors.orange.shade100,
              valueColor: const AlwaysStoppedAnimation<Color>(Colors.orange),
              minHeight: 8,
            ),
          ),
          const SizedBox(height: 4),
          // 起始與目標標籤
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '起始 ${_fmt(initialWeight)} kg',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
              ),
              Text(
                '目標 ${_fmt(target)} kg',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final today = _todayString();
    // 今天的紀錄（若有）
    final todayIdx = _records.indexWhere((r) => r['date'] == today);
    final Map<String, dynamic>? todayRec =
        todayIdx >= 0 ? _records[todayIdx] : null;

    // 提前計算，避免 build() 中重複呼叫
    final chartData = _getChartData();
    final targetProgressWidget = _buildTargetProgress();

    return Scaffold(
      backgroundColor: const Color(0xFFFFF8F0),
      appBar: AppBar(
        backgroundColor: Colors.orange,
        title: const Text('體重紀錄', style: TextStyle(color: Colors.white)),
        centerTitle: true,
        actions: [
          // 齒輪按鈕：進入設定頁，返回後重新載入體重相關設定
          IconButton(
            icon: const Icon(Icons.settings_outlined, color: Colors.white),
            tooltip: '設定',
            onPressed: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SettingsPage()),
              );
              _loadData();
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openAddSheet(),
        backgroundColor: Colors.orange,
        child: const Icon(Icons.add, color: Colors.white),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
        children: [
          // ── 折線圖卡片（含範圍切換按鈕） ──
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.orange.shade100),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 範圍切換按鈕列（本週 / 本月 / 三個月）
                Row(
                  children: [
                    _chartRangeButton('本週', 0),
                    const SizedBox(width: 8),
                    _chartRangeButton('本月', 1),
                    const SizedBox(width: 8),
                    _chartRangeButton('三個月', 2),
                  ],
                ),
                const SizedBox(height: 12),
                // 無資料時顯示友善提示，否則顯示折線圖
                chartData.spots.isEmpty
                    ? const SizedBox(
                        height: 100,
                        child: Center(
                          child: Text(
                            '此區間沒有紀錄',
                            style: TextStyle(color: Colors.grey, fontSize: 14),
                          ),
                        ),
                      )
                    : SizedBox(
                        height: 160,
                        child: LineChart(
                          LineChartData(
                            minX: chartData.minX,
                            maxX: chartData.maxX,
                            // Y 軸範圍：最小值 -2，最大值 +2（讓線不貼邊）
                            minY: chartData.spots
                                    .map((s) => s.y)
                                    .reduce((a, b) => a < b ? a : b) -
                                2,
                            maxY: chartData.spots
                                    .map((s) => s.y)
                                    .reduce((a, b) => a > b ? a : b) +
                                2,
                            lineBarsData: [
                              LineChartBarData(
                                spots: chartData.spots,
                                isCurved: true,
                                color: Colors.orange,
                                barWidth: 2.5,
                                dotData: const FlDotData(show: true),
                                belowBarData: BarAreaData(
                                  show: true,
                                  color: Colors.orange.withValues(alpha: 0.08),
                                ),
                              ),
                            ],
                            gridData: const FlGridData(show: false),
                            borderData: FlBorderData(show: false),
                            titlesData: FlTitlesData(
                              leftTitles: const AxisTitles(
                                sideTitles: SideTitles(showTitles: false),
                              ),
                              topTitles: const AxisTitles(
                                sideTitles: SideTitles(showTitles: false),
                              ),
                              // 右側顯示體重數值
                              rightTitles: AxisTitles(
                                sideTitles: SideTitles(
                                  showTitles: true,
                                  reservedSize: 44,
                                  getTitlesWidget: (value, meta) => Padding(
                                    padding: const EdgeInsets.only(left: 4),
                                    child: Text(
                                      value.toStringAsFixed(1),
                                      style: const TextStyle(
                                        fontSize: 10,
                                        color: Colors.grey,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              // 底部標籤由各範圍自行提供
                              bottomTitles: AxisTitles(
                                sideTitles: SideTitles(
                                  showTitles: true,
                                  reservedSize: 28,
                                  getTitlesWidget: chartData.getBottomTitle,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // ── 今日數據卡片 ──
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.orange.shade100),
            ),
            child: todayRec != null
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '今日數據',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: Colors.orange,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _buildStatGrid(todayRec),
                    ],
                  )
                : const Center(
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Text(
                        '今天還沒量體重喔',
                        style: TextStyle(color: Colors.grey, fontSize: 15),
                      ),
                    ),
                  ),
          ),

          // ── 目標體重進度條（有設定目標才顯示） ──
          if (targetProgressWidget != null) ...[
            const SizedBox(height: 12),
            targetProgressWidget,
          ],

          const SizedBox(height: 12),

          // ── 歷史紀錄列表 ──
          const Text(
            '歷史紀錄',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: Colors.orange,
            ),
          ),
          const SizedBox(height: 8),
          if (_records.isEmpty)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  '還沒有體重紀錄',
                  style: TextStyle(color: Colors.grey),
                ),
              ),
            )
          else
            ..._records.map((rec) => _buildHistoryTile(rec)),
        ],
      ),
    );
  }

  // 圖表範圍切換按鈕（選中時橘底白字）
  Widget _chartRangeButton(String label, int index) {
    final selected = _chartRangeIndex == index;
    return GestureDetector(
      onTap: () => setState(() => _chartRangeIndex = index),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? Colors.orange : Colors.orange.shade50,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            color: selected ? Colors.white : Colors.orange.shade700,
            fontWeight: selected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  // 今日數據格子（BMI/BMR 缺資料時顯示友善提示）
  Widget _buildStatGrid(Map<String, dynamic> rec) {
    final weight = (rec['weight'] as num).toDouble();
    final fat =
        rec['body_fat'] != null ? (rec['body_fat'] as num).toDouble() : null;
    final bmi = _calcBMI(weight);
    final bmr = _calcBMR(weight);
    // 任一計算值缺失時顯示補充資料提示
    final needsHint = bmi == null || bmr == null;

    final items = <_StatItem>[
      _StatItem(label: '體重', value: '${_fmt(weight)} kg'),
      if (fat != null) _StatItem(label: '體脂率', value: '${_fmt(fat)} %'),
      if (bmi != null) _StatItem(label: 'BMI', value: _fmt(bmi)),
      if (bmr != null)
        _StatItem(label: 'BMR', value: '${_fmt(bmr, decimal: 0)} kcal'),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GridView.count(
          crossAxisCount: 2,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          childAspectRatio: 2.4,
          children: items
              .map(
                (item) => Container(
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        item.label,
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.orange.shade600,
                        ),
                      ),
                      Text(
                        item.value,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              )
              .toList(),
        ),
        // 缺少身高、生日或性別時顯示提示
        if (needsHint) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.info_outline, size: 13, color: Colors.grey.shade400),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  '請至設定補充個人資料以計算 BMI / BMR',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade400),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  // 歷史紀錄單筆 tile
  // 長按或向左滑動（endToStart）皆呼叫操作選單（編輯／刪除）
  Widget _buildHistoryTile(Map<String, dynamic> rec) {
    final weight = (rec['weight'] as num).toDouble();
    final fat =
        rec['body_fat'] != null ? (rec['body_fat'] as num).toDouble() : null;
    final bmi = _calcBMI(weight);
    final date = rec['date'] as String;
    final time = rec['time'] as String;

    return Dismissible(
      key: Key(date),
      direction: DismissDirection.endToStart,
      // confirmDismiss 回傳 false：不自動刪除，改由選單確認
      confirmDismiss: (_) async {
        _showRecordActions(rec);
        return false;
      },
      // 左滑時顯示的背景提示（橘底 + 更多圖示）
      background: Container(
        margin: const EdgeInsets.only(bottom: 10),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: Colors.orange.shade50,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Icon(Icons.more_horiz, color: Colors.orange.shade400, size: 26),
      ),
      child: GestureDetector(
        onLongPress: () => _showRecordActions(rec),
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Row(
            children: [
              // 日期與時間
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    date,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    time,
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                  ),
                ],
              ),
              const Spacer(),
              // 體重、體脂、BMI
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${_fmt(weight)} kg',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Row(
                    children: [
                      if (fat != null) ...[
                        Text(
                          '體脂 ${_fmt(fat)}%',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey.shade500,
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      if (bmi != null)
                        Text(
                          'BMI ${_fmt(bmi)}',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey.shade500,
                          ),
                        ),
                    ],
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

// 圖表資料封裝（各範圍的資料點與 X 軸標籤邏輯）
class _ChartData {
  final List<FlSpot> spots;
  final double minX;
  final double maxX;
  final Widget Function(double, TitleMeta) getBottomTitle;

  const _ChartData({
    required this.spots,
    required this.minX,
    required this.maxX,
    required this.getBottomTitle,
  });
}

// 今日數據卡片的格子資料模型
class _StatItem {
  final String label;
  final String value;
  const _StatItem({required this.label, required this.value});
}
