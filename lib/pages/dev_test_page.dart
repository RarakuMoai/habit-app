import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/feature_flags.dart';
import '../utils/prefs_keys.dart';
import 'home/room_ambient_overlay.dart';

/// 開發者測試頁。
///
/// 僅 debug build 從設定頁進得來（release 不顯示入口、也不讀這些 key）。
/// 目前提供：
///  - 假選單數量：強制湊到 6~10 個選單，預覽底部列兩排版面。
///  - 場景時段：覆寫 `sceneHourNow()`，讓首頁場景 / 底部裝飾條切到早中晚。
///  - 恢復正常：清掉上面兩個覆寫（不動真實進度資料）。
class DevTestPage extends StatefulWidget {
  const DevTestPage({super.key});

  @override
  State<DevTestPage> createState() => _DevTestPageState();
}

class _DevTestPageState extends State<DevTestPage> {
  SharedPreferences? _prefs;
  int _fakeTabs = 0; // 0 = 關閉
  double? _sceneHour; // null = 真實時間
  int _dayShift = 0; // 已快轉天數

  // 場景時段預設點
  static const _presets = <String, double>{
    '早晨': 8,
    '中午': 13,
    '傍晚': 18,
    '夜晚': 23,
  };

  // 換日：往前推一天就能觸發真換日的「每日狀態日期標記」
  static const _dayMarkers = <String>[
    PrefsKeys.lastOpenDate, // streak / 習慣勾選重置
    PrefsKeys.coinLastLoginDate, // 每日登入獎勵
    PrefsKeys.waterGoalDate, // 喝水目標達成旗標
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _prefs = prefs;
      _fakeTabs = prefs.getInt(PrefsKeys.debugFakeTabCount) ?? 0;
      _sceneHour = prefs.getDouble(PrefsKeys.debugSceneHour);
      _dayShift = prefs.getInt(PrefsKeys.debugDayShift) ?? 0;
    });
  }

  static String _fmtDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  // 快轉一天：把每日狀態日期標記往前推一天。重開 App 後真實時鐘一比對，
  // 就會跑真正的換日流程（習慣勾選清空、streak 計算、登入獎勵重開）。
  // 第一次快轉前先整包快照 prefs，供「還原換日」回復。
  Future<void> _fastForwardOneDay() async {
    final prefs = _prefs;
    if (prefs == null) return;
    if (!prefs.containsKey(PrefsKeys.debugDaySnapshot)) {
      await _snapshot(prefs);
    }
    final yesterday = _fmtDate(
      DateTime.now().subtract(const Duration(days: 1)),
    );
    for (final k in _dayMarkers) {
      final cur = prefs.getString(k);
      // 有值就往前推一天；沒值就設成昨天，確保換日一定觸發
      final shifted = cur == null
          ? yesterday
          : _fmtDate(
              (DateTime.tryParse(cur) ?? DateTime.now())
                  .subtract(const Duration(days: 1)),
            );
      await prefs.setString(k, shifted);
    }
    final n = _dayShift + 1;
    await prefs.setInt(PrefsKeys.debugDayShift, n);
    if (!mounted) return;
    setState(() => _dayShift = n);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已快轉一天，重開 App 看換日效果')),
    );
  }

  // 整包快照（restore 用）。值型別 bool/int/double/String/List<String> 都帶 tag。
  Future<void> _snapshot(SharedPreferences prefs) async {
    final map = <String, Map<String, dynamic>>{};
    for (final k in prefs.getKeys()) {
      final v = prefs.get(k);
      if (v is List) {
        map[k] = {'t': 'list', 'v': v.cast<String>()};
      } else if (v is bool) {
        map[k] = {'t': 'bool', 'v': v};
      } else if (v is int) {
        map[k] = {'t': 'int', 'v': v};
      } else if (v is double) {
        map[k] = {'t': 'double', 'v': v};
      } else if (v is String) {
        map[k] = {'t': 'string', 'v': v};
      }
    }
    await prefs.setString(PrefsKeys.debugDaySnapshot, jsonEncode(map));
  }

  // 還原換日：清空 prefs 後從快照重寫，回到第一次快轉前的狀態。
  Future<void> _restoreDays() async {
    final prefs = _prefs;
    if (prefs == null) return;
    final raw = prefs.getString(PrefsKeys.debugDaySnapshot);
    if (raw == null) return;
    final map = (jsonDecode(raw) as Map<String, dynamic>).cast<String, dynamic>();
    await prefs.clear(); // 快照/天數 key 都在快照後寫入，clear 後不會復活
    for (final e in map.entries) {
      final entry = (e.value as Map).cast<String, dynamic>();
      final v = entry['v'];
      switch (entry['t']) {
        case 'bool':
          await prefs.setBool(e.key, v as bool);
        case 'int':
          await prefs.setInt(e.key, (v as num).toInt());
        case 'double':
          await prefs.setDouble(e.key, (v as num).toDouble());
        case 'list':
          await prefs.setStringList(e.key, (v as List).cast<String>());
        default:
          await prefs.setString(e.key, v as String);
      }
    }
    // 同步還原場景時段覆寫（靜態值）與 UI 狀態
    HomeSceneDebug.hourOverride = prefs.getDouble(PrefsKeys.debugSceneHour);
    bumpFeatureFlags();
    await _load();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已還原換日，重開 App 生效')),
    );
  }

  Future<void> _setFakeTabs(int n) async {
    final prefs = _prefs;
    if (prefs == null) return;
    if (n <= 0) {
      await prefs.remove(PrefsKeys.debugFakeTabCount);
    } else {
      await prefs.setInt(PrefsKeys.debugFakeTabCount, n);
    }
    bumpFeatureFlags(); // 讓常駐的 MainPage 立刻重組底部列
    setState(() => _fakeTabs = n <= 0 ? 0 : n);
  }

  Future<void> _setSceneHour(double? hour) async {
    final prefs = _prefs;
    if (prefs == null) return;
    if (hour == null) {
      await prefs.remove(PrefsKeys.debugSceneHour);
      HomeSceneDebug.hourOverride = null;
    } else {
      await prefs.setDouble(PrefsKeys.debugSceneHour, hour);
      HomeSceneDebug.hourOverride = hour;
    }
    setState(() => _sceneHour = hour);
  }

  Future<void> _reset() async {
    await _setFakeTabs(0);
    await _setSceneHour(null);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已恢復正常（測試覆寫已清除）')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('開發者測試'), centerTitle: true),
      body: _prefs == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
              children: [
                _card(
                  title: '假選單數量',
                  icon: Icons.dashboard_customize_outlined,
                  description: '像功能開關一樣，開到第幾個分頁底部列就有幾個分頁，'
                      '用來預覽 6~10 個時的兩排版面。會補「測試N」假頁，關掉即消失。',
                  child: Column(
                    children: [
                      for (final t in const [6, 7, 8, 9, 10]) _fakeTabSwitch(t),
                    ],
                  ),
                ),
                _card(
                  title: '場景時段',
                  icon: Icons.wb_twilight_outlined,
                  description: '覆寫場景時間，首頁場景與底部裝飾條會切到對應時段。',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _choice(
                            '真實時間',
                            _sceneHour == null,
                            () => _setSceneHour(null),
                          ),
                          for (final e in _presets.entries)
                            _choice(
                              e.key,
                              _sceneHour == e.value,
                              () => _setSceneHour(e.value),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      _hourSlider(),
                    ],
                  ),
                ),
                _card(
                  title: '換日（快轉一天）',
                  icon: Icons.fast_forward_outlined,
                  description:
                      '把每日狀態日期推前一天，重開 App 後會跑真正的換日：'
                      '習慣勾選清空、streak 重算、登入獎勵重開。'
                      '喝水/番茄鐘累計按真實日期存、不歸零。目前已快轉 $_dayShift 天。',
                  child: Row(
                    children: [
                      Expanded(
                        child: FilledButton.tonalIcon(
                          onPressed: _fastForwardOneDay,
                          icon: const Icon(Icons.fast_forward, size: 18),
                          label: const Text('快轉一天'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _dayShift > 0 ? _restoreDays : null,
                          icon: const Icon(Icons.undo, size: 18),
                          label: const Text('還原換日'),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _reset,
                    icon: const Icon(Icons.restore, size: 18),
                    label: const Text('恢復場景/選單覆寫'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                      side: BorderSide(
                        color: Colors.red.withValues(alpha: 0.5),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _hourSlider() {
    final effective = _sceneHour ?? sceneHourNow();
    return Row(
      children: [
        Text(
          effective.toStringAsFixed(1),
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        ),
        Expanded(
          child: Slider(
            value: effective.clamp(0, 24),
            max: 24,
            divisions: 48,
            label: effective.toStringAsFixed(1),
            onChanged: _setSceneHour,
          ),
        ),
      ],
    );
  }

  // 區塊卡：圓角白卡 + 標題列 + 說明 + 內容，整頁統一語彙。
  Widget _card({
    required String title,
    required IconData icon,
    String? description,
    required Widget child,
  }) {
    final color = Theme.of(context).colorScheme.primary;
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ],
          ),
          if (description != null) ...[
            const SizedBox(height: 8),
            Text(
              description,
              style: TextStyle(
                fontSize: 12,
                height: 1.45,
                color: Colors.grey.shade600,
              ),
            ),
          ],
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  // 假選單開關（填充式）：開「第 N 個分頁」＝目標總數 N，N 以下自動跟著開。
  Widget _fakeTabSwitch(int total) {
    final on = _fakeTabs >= total;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '第 $total 個分頁',
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
          ),
          Switch(
            value: on,
            onChanged: (v) =>
                _setFakeTabs(v ? total : (total - 1 >= 6 ? total - 1 : 0)),
          ),
        ],
      ),
    );
  }

  Widget _choice(String label, bool selected, VoidCallback onTap) {
    final color = Theme.of(context).colorScheme.primary;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      // 不顯示打勾：避免選中時多出勾號撐寬、造成 Wrap 重排位移
      showCheckmark: false,
      onSelected: (_) => onTap(),
      selectedColor: color.withValues(alpha: 0.18),
      labelStyle: TextStyle(
        fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
        color: selected ? color : Colors.grey.shade700,
      ),
    );
  }
}
