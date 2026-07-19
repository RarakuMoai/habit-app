import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/app_restart.dart';
import '../utils/coin_config.dart';
import '../utils/coin_service.dart';
import '../utils/feature_flags.dart';
import '../utils/prefs_keys.dart';
import '../utils/scene_time.dart';
import '../utils/story_catalog.dart';
import '../utils/story_store.dart';
import 'login_streak_page.dart';
import 'story_reveal_page.dart';

/// 開發者測試頁。
///
/// 由 `kDevToolsEnabled` 控制是否從設定頁進得來（目前 release 也暫時開，
/// 正式版改回 `kDebugMode` 就會只在 debug build 顯示、release 不讀這些 key）。
/// 目前提供：
///  - 場景時段：覆寫 `sceneHourNow()`，預覽四個正式時段與交界。
///  - 恢復正常：清掉場景時段覆寫（不動真實進度資料）。
class DevTestPage extends StatefulWidget {
  const DevTestPage({super.key});

  @override
  State<DevTestPage> createState() => _DevTestPageState();
}

class _DevTestPageState extends State<DevTestPage> {
  SharedPreferences? _prefs;
  double? _sceneHour; // null = 真實時間
  int _dayShift = 0; // 已快轉天數

  // 核心時段使用 SceneTimeController 的正式錨點，避免兩邊時間再次脫節。
  static const _periodPresets = <({String label, ScenePeriod period})>[
    (label: '清晨 06:30', period: ScenePeriod.morning),
    (label: '白天 13:00', period: ScenePeriod.day),
    (label: '黃昏 17:30', period: ScenePeriod.dusk),
    (label: '夜晚 23:00', period: ScenePeriod.night),
  ];

  // 各交界的正中點；smoothstep 此時恰好兩張圖各 50%。
  static const _transitionPresets = <({String label, double hour})>[
    (label: '夜→晨 04:37:30', hour: 4.625),
    (label: '晨→晝 08:37:30', hour: 8.625),
    (label: '晝→暮 16:30:00', hour: 16.5),
    (label: '暮→夜 18:37:30', hour: 18.625),
  ];

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
    // 同步還原場景時段覆寫與 UI 狀態
    SceneTimeController.instance.setPreviewHour(
      prefs.getDouble(PrefsKeys.debugSceneHour),
    );
    bumpFeatureFlags();
    await _load();
    if (!mounted) return;
    RootRestart.restart(context);
  }

  Future<void> _setSceneHour(double? hour) async {
    final prefs = _prefs;
    if (prefs == null) return;
    if (hour == null) {
      await prefs.remove(PrefsKeys.debugSceneHour);
    } else {
      await prefs.setDouble(PrefsKeys.debugSceneHour, hour);
    }
    SceneTimeController.instance.setPreviewHour(hour);
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
                  title: '足跡幣（測試）',
                  icon: Icons.monetization_on_outlined,
                  description: '直接加足跡幣方便測試衣櫃購買解鎖；負向「歸零」清空餘額。',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ValueListenableBuilder<int>(
                        valueListenable: CoinService.notifier,
                        builder: (_, coins, _) => Text(
                          '目前足跡幣：$coins',
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
                          for (final n in [1, 5, 10, 100])
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
                  title: '每日登入慶祝（預覽）',
                  icon: Icons.celebration_outlined,
                  description: '免跨日直接看慶祝頁的排版與演出；不動任何登入/金幣狀態。',
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final (label, streak, reward) in [
                        (
                          '第一天',
                          1,
                          const LoginReward(
                            level: 1,
                            amount: CoinConfig.loginBase,
                            graceUsed: false,
                          ),
                        ),
                        (
                          '一般日（第 3 天）',
                          3,
                          const LoginReward(
                            level: 3,
                            amount: CoinConfig.loginBase + 2,
                            graceUsed: false,
                          ),
                        ),
                        (
                          '寬限日（第 5 天）',
                          5,
                          const LoginReward(
                            level: 4,
                            amount: CoinConfig.loginBase + 3,
                            graceUsed: true,
                          ),
                        ),
                        (
                          '里程碑日（第 7 天）',
                          7,
                          const LoginReward(
                            level: 6,
                            amount: CoinConfig.loginBase + 5,
                            graceUsed: false,
                            milestoneAmount: CoinConfig.weeklyStreak,
                          ),
                        ),
                        (
                          '滿級（第 45 天）',
                          45,
                          const LoginReward(
                            level: 6,
                            amount: CoinConfig.loginBase + 5,
                            graceUsed: false,
                          ),
                        ),
                      ])
                        OutlinedButton.icon(
                          icon: const Icon(Icons.play_arrow_rounded, size: 18),
                          onPressed: () => Navigator.of(context).push(
                            LoginStreakPage.route(
                              streak: streak,
                              reward: reward,
                            ),
                          ),
                          label: Text(label),
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
                  title: '場景時段',
                  icon: Icons.wb_twilight_outlined,
                  description:
                      '完整時段：清晨 05:00、白天 09:00、黃昏 17:00、'
                      '夜晚 19:00；16:00 開始轉黃昏，其餘交界為 45 分鐘。'
                      '覆寫會同步套用首頁場景與底部裝飾條。',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _testSubheading('核心時段'),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _choice(
                            '真實時間',
                            _sceneHour == null,
                            () => _setSceneHour(null),
                          ),
                          for (final preset in _periodPresets)
                            _choice(
                              preset.label,
                              _sceneHour ==
                                  SceneTimeController.periodAnchorHour(
                                    preset.period,
                                  ),
                              () => _setSceneHour(
                                SceneTimeController.periodAnchorHour(
                                  preset.period,
                                ),
                              ),
                            ),
                        ],
                      ),
                      _testSubheading('交界中點（前後時段各 50%）'),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final preset in _transitionPresets)
                            _choice(
                              preset.label,
                              _sceneHour == preset.hour,
                              () => _setSceneHour(preset.hour),
                            ),
                        ],
                      ),
                      const SizedBox(height: 10),
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
                      '喝水／專注計時累計按真實日期存、不歸零。目前已快轉 $_dayShift 天。',
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
          _formatClock(effective),
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
            divisions: 96,
            label: _formatClock(effective),
            onChanged: _setSceneHour,
          ),
        ),
      ],
    );
  }

  static String _formatClock(double hour) {
    final totalSeconds = ((hour % 24) * 3600).round() % (24 * 3600);
    final h = totalSeconds ~/ 3600;
    final m = (totalSeconds % 3600) ~/ 60;
    final s = totalSeconds % 60;
    final base =
        '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
    return s == 0 ? base : '$base:${s.toString().padLeft(2, '0')}';
  }

  Widget _testSubheading(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 12.5,
        fontWeight: FontWeight.w800,
        color: Colors.brown.shade400,
      ),
    ),
  );

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
