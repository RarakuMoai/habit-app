import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/app_restart.dart';
import '../utils/coin_service.dart';
import '../utils/debug_fake_tabs.dart';
import '../utils/feature_flags.dart';
import '../utils/prefs_keys.dart';
import '../utils/story_catalog.dart';
import '../utils/story_store.dart';
import 'home/room_ambient_overlay.dart';
import 'story_reveal_page.dart';

/// 開發者測試頁。
///
/// 由 `kDevToolsEnabled` 控制是否從設定頁進得來（目前 release 也暫時開，
/// 正式版改回 `kDebugMode` 就會只在 debug build 顯示、release 不讀這些 key）。
/// 目前提供：
///  - 模擬分頁開關：像正式功能開關一樣加減 debug 分頁，預覽底部列版面。
///  - 場景時段：覆寫 `sceneHourNow()`，讓首頁場景 / 底部裝飾條切到早中晚。
///  - 恢復正常：清掉上面兩個覆寫（不動真實進度資料）。
class DevTestPage extends StatefulWidget {
  const DevTestPage({super.key});

  @override
  State<DevTestPage> createState() => _DevTestPageState();
}

class _DevTestPageState extends State<DevTestPage> {
  SharedPreferences? _prefs;
  Set<String> _fakeTabIds = {};
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
      _fakeTabIds =
          (prefs.getStringList(PrefsKeys.debugFakeTabs) ?? const <String>[])
              .toSet();
      _sceneHour = prefs.getDouble(PrefsKeys.debugSceneHour);
      _dayShift = prefs.getInt(PrefsKeys.debugDayShift) ?? 0;
    });
  }

  static String _fmtDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  // 快轉一天：把每日狀態日期標記往前推一天，接著程式內重建整棵 app。
  // 重建後真實時鐘一比對，就會跑真正的換日流程
  // （習慣勾選清空、streak 計算、登入獎勵重開）。
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
              (DateTime.tryParse(cur) ?? DateTime.now()).subtract(
                const Duration(days: 1),
              ),
            );
      await prefs.setString(k, shifted);
    }
    final n = _dayShift + 1;
    await prefs.setInt(PrefsKeys.debugDayShift, n);
    if (!mounted) return;
    setState(() => _dayShift = n);
    RootRestart.restart(context);
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
    final map = (jsonDecode(raw) as Map<String, dynamic>)
        .cast<String, dynamic>();
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
    RootRestart.restart(context);
  }

  Future<void> _setFakeTab(String id, bool enabled) async {
    final prefs = _prefs;
    if (prefs == null) return;
    final next = {..._fakeTabIds};
    if (enabled) {
      next.add(id);
    } else {
      next.remove(id);
    }
    final ordered = [
      for (final spec in debugFakeTabSpecs)
        if (next.contains(spec.id)) spec.id,
    ];
    if (ordered.isEmpty) {
      await prefs.remove(PrefsKeys.debugFakeTabs);
    } else {
      await prefs.setStringList(PrefsKeys.debugFakeTabs, ordered);
    }
    await prefs.remove(PrefsKeys.debugFakeTabCount);
    bumpFeatureFlags(); // 讓常駐的 MainPage 立刻重組底部列
    setState(() => _fakeTabIds = ordered.toSet());
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

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _unlockMemory(String id) async {
    final ok = await StoryStore.unlock(id);
    if (!mounted) return;
    final title = storyEventById(id).title;
    _toast(ok ? '已解鎖：$title（揭曉即將自動播放）' : '已經解鎖過了：$title');
  }

  /// 免解鎖直接看揭曉動畫與繪本排版（不動任何狀態，怎麼看都不會誤解鎖）。
  void _previewReveal(StoryEventSpec event) {
    Navigator.of(context).push(StoryRevealPage.route(event: event));
  }

  /// 走「真實觸發判定」：跟正式接線呼叫同一個 API，驗證門檻、冪等、
  /// 佇列與揭曉播放整條路。
  Future<void> _simulateTrigger(
    String label,
    Future<String?> Function() run,
  ) async {
    final id = await run();
    if (!mounted) return;
    _toast(
      id != null
          ? '$label → 解鎖「${storyEventById(id).title}」，揭曉即將播放'
          : '$label → 沒有新事件（未達門檻或已解鎖過）',
    );
  }

  Future<void> _simulateSeason(String label, DateTime date) async {
    final ids = await StoryEvents.onSeasonDay(date);
    if (!mounted) return;
    _toast(
      ids.isNotEmpty
          ? '$label → 解鎖 ${ids.map((i) => '「${storyEventById(i).title}」').join('、')}'
          : '$label → 沒有命中的節日事件（或已解鎖過）',
    );
  }

  Widget _memorySection(String label) => Padding(
    padding: const EdgeInsets.only(top: 12, bottom: 8),
    child: Text(
      label,
      style: TextStyle(
        fontSize: 12.5,
        fontWeight: FontWeight.w800,
        color: Colors.brown.shade400,
      ),
    ),
  );

  Future<void> _reset() async {
    final prefs = _prefs;
    if (prefs != null) {
      await prefs.remove(PrefsKeys.debugFakeTabs);
      await prefs.remove(PrefsKeys.debugFakeTabCount);
      bumpFeatureFlags();
      setState(() => _fakeTabIds = {});
    }
    await _setSceneHour(null);
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('已恢復正常（測試覆寫已清除）')));
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
                  title: '金幣（測試）',
                  icon: Icons.monetization_on_outlined,
                  description: '直接加金幣方便測試衣櫃購買解鎖；負向「歸零」清空餘額。',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ValueListenableBuilder<int>(
                        valueListenable: CoinService.notifier,
                        builder: (_, coins, _) => Text(
                          '目前金幣：$coins',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final n in [50, 200, 1000])
                            FilledButton.tonal(
                              onPressed: () => CoinService.debugAdd(n),
                              child: Text('+$n'),
                            ),
                          OutlinedButton(
                            onPressed: () => CoinService.debugAdd(
                              -CoinService.notifier.value,
                            ),
                            child: const Text('歸零'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                _card(
                  title: '回憶本 / 特殊事件（測試）',
                  icon: Icons.auto_stories_outlined,
                  description:
                      '預覽＝免解鎖直接看揭曉動畫與排版；模擬觸發＝走真實判定，'
                      '驗證門檻/冪等/揭曉整條路。解鎖後到衣櫃 → 回憶 翻閱。',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AnimatedBuilder(
                        animation: Listenable.merge([
                          StoryStore.unlocked,
                          StoryStore.unread,
                          StoryStore.pendingReveal,
                        ]),
                        builder: (_, _) => Text(
                          '已解鎖：${StoryStore.unlocked.value.length} 則'
                          '　未讀：${StoryStore.unread.value.length} 則'
                          '　待揭曉：${StoryStore.pendingReveal.value.length} 則',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      _memorySection('預覽揭曉（不動資料，看圖與動畫排版）'),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final event in storyCatalog)
                            OutlinedButton.icon(
                              icon: const Icon(
                                Icons.play_arrow_rounded,
                                size: 18,
                              ),
                              onPressed: () => _previewReveal(event),
                              label: Text(event.title),
                            ),
                        ],
                      ),
                      _memorySection('模擬觸發（走真實判定與揭曉佇列）'),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          FilledButton.tonal(
                            onPressed: () => _simulateTrigger(
                              '第一次建立習慣',
                              StoryEvents.onFirstHabitCreated,
                            ),
                            child: const Text('第一次建立習慣'),
                          ),
                          FilledButton.tonal(
                            onPressed: () => _simulateTrigger(
                              '第一次全完成',
                              StoryEvents.onFirstAllDone,
                            ),
                            child: const Text('第一次全完成'),
                          ),
                          FilledButton.tonal(
                            onPressed: () => _simulateTrigger(
                              '連勝 7 天',
                              () => StoryEvents.onHabitStreak(7),
                            ),
                            child: const Text('連勝 7 天'),
                          ),
                          FilledButton.tonal(
                            onPressed: () => _simulateTrigger(
                              '久違 7 天回來',
                              () => StoryEvents.onComeback(7),
                            ),
                            child: const Text('久違 7 天回來'),
                          ),
                          FilledButton.tonal(
                            onPressed: () =>
                                _simulateSeason('節日檢查（今天）', DateTime.now()),
                            child: const Text('節日檢查（今天）'),
                          ),
                          // 目錄裡每個節日事件都給一顆「假裝今天是那天」的按鈕
                          for (final event in storyCatalog)
                            if (event.trigger == StoryTrigger.season &&
                                event.season != null)
                              FilledButton.tonal(
                                onPressed: () => _simulateSeason(
                                  '模擬 ${event.title} 當天',
                                  DateTime(
                                    DateTime.now().year,
                                    event.season!.month,
                                    event.season!.day,
                                  ),
                                ),
                                child: Text('模擬 ${event.title} 當天'),
                              ),
                        ],
                      ),
                      _memorySection('直接解鎖（跳過判定；也會排進揭曉佇列）'),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final event in storyCatalog)
                            FilledButton.tonal(
                              onPressed: () => _unlockMemory(event.id),
                              child: Text('解鎖 ${event.title}'),
                            ),
                          OutlinedButton(
                            onPressed: () async {
                              await StoryStore.clear();
                              if (!mounted) return;
                              _toast('已清空回憶（含待揭曉佇列）');
                            },
                            child: const Text('清空回憶'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                _card(
                  title: '模擬分頁開關',
                  icon: Icons.dashboard_customize_outlined,
                  description:
                      '像設定裡的正式功能開關一樣，打開哪個就真的多哪個分頁。'
                      '可搭配關閉喝水、體重、家庭等正式頁來測底部列排版。',
                  child: Column(
                    children: [
                      for (final spec in debugFakeTabSpecs)
                        _fakeTabSwitch(spec),
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
                      '把每日狀態日期推前一天，按下後會自動刷新並跑真正的換日：'
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

  Widget _fakeTabSwitch(DebugFakeTabSpec spec) {
    final on = _fakeTabIds.contains(spec.id);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: spec.color.withValues(alpha: on ? 0.16 : 0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              spec.icon,
              size: 19,
              color: on ? spec.color : Colors.grey.shade500,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  spec.label,
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  spec.subtitle,
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
          Switch(
            value: on,
            activeThumbColor: spec.color,
            onChanged: (v) => _setFakeTab(spec.id, v),
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
