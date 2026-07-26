import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/app_localizations.dart';
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
  AppLocalizations get _l10n => AppLocalizations.of(context);

  SharedPreferences? _prefs;
  double? _sceneHour; // null = 真實時間
  int _dayShift = 0; // 已快轉天數

  // 核心時段使用 SceneTimeController 的正式錨點，避免兩邊時間再次脫節。
  List<({String label, ScenePeriod period})> get _periodPresets => [
    (label: _l10n.dvPeriodMorning, period: ScenePeriod.morning),
    (label: _l10n.dvPeriodDay, period: ScenePeriod.day),
    (label: _l10n.dvPeriodDusk, period: ScenePeriod.dusk),
    (label: _l10n.dvPeriodNight, period: ScenePeriod.night),
  ];

  // 各交界的正中點；smoothstep 此時恰好兩張圖各 50%。
  List<({String label, double hour})> get _transitionPresets => [
    (label: _l10n.dvEdgeNightMorning, hour: 4.625),
    (label: _l10n.dvEdgeMorningDay, hour: 8.625),
    (label: _l10n.dvEdgeDayDusk, hour: 16.5),
    (label: _l10n.dvEdgeDuskNight, hour: 18.625),
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

  // 快轉 N 天：把每日狀態日期標記往前推 N 天，接著程式內重建整棵 app。
  // 重建後真實時鐘一比對，就會跑真正的換日流程
  // （習慣勾選清空、streak 計算、登入獎勵重開）。
  // N >= 2 等於中間有 N-1 天完全沒開 app：快轉 2 天觸發登入寬限、
  // 3 天觸發中斷歸零（重建當下首頁會自動領獎把日期蓋回今天，
  // 所以連按兩次快轉一天只會是連續簽到，湊不出缺席）。
  // 第一次快轉前先整包快照 prefs，供「還原換日」回復。
  Future<void> _fastForwardDays(int days) async {
    final prefs = _prefs;
    if (prefs == null) return;
    if (!prefs.containsKey(PrefsKeys.debugDaySnapshot)) {
      await _snapshot(prefs);
    }
    final fallback = _fmtDate(DateTime.now().subtract(Duration(days: days)));
    for (final k in _dayMarkers) {
      final cur = prefs.getString(k);
      // 有值就往前推 N 天；沒值就設成 N 天前，確保換日一定觸發
      final shifted = cur == null
          ? fallback
          : _fmtDate(
              (DateTime.tryParse(cur) ?? DateTime.now()).subtract(
                Duration(days: days),
              ),
            );
      await prefs.setString(k, shifted);
    }
    // claimDailyLogin 還會用「今天的 per-day claim」防重複入帳。
    // 開發者快轉是要模擬新的登入日，因此只重開登入與連續里程碑；
    // 其他每日來源仍保留，避免快轉意外重領其他獎勵。
    final today = _fmtDate(DateTime.now());
    for (final source in [CoinSource.dailyLogin, CoinSource.weeklyStreak]) {
      await prefs.remove(PrefsKeys.coinClaim(source.name, today));
    }
    final n = _dayShift + days;
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
    _toast(ok ? _l10n.dvUnlocked(title) : _l10n.dvAlreadyUnlocked(title));
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
          ? _l10n.dvTriggerHit(label, storyEventById(id).title)
          : _l10n.dvTriggerMiss(label),
    );
  }

  Future<void> _simulateSeason(String label, DateTime date) async {
    final ids = await StoryEvents.onSeasonDay(date);
    if (!mounted) return;
    _toast(
      ids.isNotEmpty
          ? _l10n.dvSeasonHit(
              label,
              ids.map((i) => '「${storyEventById(i).title}」').join('、'),
            )
          : _l10n.dvSeasonMiss(label),
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
    ).showSnackBar(SnackBar(content: Text(_l10n.dvOverrideCleared)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_l10n.dvTitle), centerTitle: true),
      body: _prefs == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
              children: [
                _card(
                  title: _l10n.dvCoinsTitle,
                  icon: Icons.monetization_on_outlined,
                  description: _l10n.dvCoinsDesc,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ValueListenableBuilder<int>(
                        valueListenable: CoinService.notifier,
                        builder: (_, coins, _) => Text(
                          _l10n.dvCurrentCoins(coins),
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
                            child: Text(_l10n.dvResetZero),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                _card(
                  title: _l10n.dvLoginPreviewTitle,
                  icon: Icons.celebration_outlined,
                  description: _l10n.dvLoginPreviewDesc,
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final (label, streak, reward) in [
                        (
                          _l10n.dvLoginDay1,
                          1,
                          const LoginReward(
                            level: 1,
                            amount: CoinConfig.loginBase,
                            graceUsed: false,
                          ),
                        ),
                        (
                          _l10n.dvLoginDay3,
                          3,
                          const LoginReward(
                            level: 3,
                            amount: CoinConfig.loginBase + 2,
                            graceUsed: false,
                          ),
                        ),
                        (
                          _l10n.dvLoginDay5,
                          5,
                          const LoginReward(
                            level: 4,
                            amount: CoinConfig.loginBase + 3,
                            graceUsed: true,
                          ),
                        ),
                        (
                          _l10n.dvLoginDay7,
                          7,
                          const LoginReward(
                            level: 6,
                            amount: CoinConfig.loginBase + 5,
                            graceUsed: false,
                            milestoneAmount: CoinConfig.weeklyStreak,
                          ),
                        ),
                        (
                          _l10n.dvLoginDay45,
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
                  title: _l10n.dvMemoryTitle,
                  icon: Icons.auto_stories_outlined,
                  description: _l10n.dvMemoryDesc,
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
                          _l10n.dvMemoryCounts(
                            StoryStore.unlocked.value.length,
                            StoryStore.unread.value.length,
                            StoryStore.pendingReveal.value.length,
                          ),
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      _memorySection(_l10n.dvMemoryPreviewSection),
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
                      _memorySection(_l10n.dvMemorySimulateSection),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          FilledButton.tonal(
                            onPressed: () => _simulateTrigger(
                              _l10n.dvSimFirstHabit,
                              StoryEvents.onFirstHabitCreated,
                            ),
                            child: Text(_l10n.dvSimFirstHabit),
                          ),
                          FilledButton.tonal(
                            onPressed: () => _simulateTrigger(
                              _l10n.dvSimFirstAllDone,
                              StoryEvents.onFirstAllDone,
                            ),
                            child: Text(_l10n.dvSimFirstAllDone),
                          ),
                          FilledButton.tonal(
                            onPressed: () => _simulateTrigger(
                              _l10n.dvSimStreak7,
                              () => StoryEvents.onHabitStreak(7),
                            ),
                            child: Text(_l10n.dvSimStreak7),
                          ),
                          FilledButton.tonal(
                            onPressed: () => _simulateTrigger(
                              _l10n.dvSimReturn7,
                              () => StoryEvents.onComeback(7),
                            ),
                            child: Text(_l10n.dvSimReturn7),
                          ),
                          FilledButton.tonal(
                            onPressed: () => _simulateSeason(
                              _l10n.dvSimSeasonToday,
                              DateTime.now(),
                            ),
                            child: Text(_l10n.dvSimSeasonToday),
                          ),
                          // 目錄裡每個節日事件都給一顆「假裝今天是那天」的按鈕
                          for (final event in storyCatalog)
                            if (event.trigger == StoryTrigger.season &&
                                event.season != null)
                              FilledButton.tonal(
                                onPressed: () => _simulateSeason(
                                  _l10n.dvSimEventDay(event.title),
                                  DateTime(
                                    DateTime.now().year,
                                    event.season!.month,
                                    event.season!.day,
                                  ),
                                ),
                                child: Text(_l10n.dvSimEventDay(event.title)),
                              ),
                        ],
                      ),
                      _memorySection(_l10n.dvMemoryUnlockSection),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final event in storyCatalog)
                            FilledButton.tonal(
                              onPressed: () => _unlockMemory(event.id),
                              child: Text(_l10n.dvUnlockEvent(event.title)),
                            ),
                          OutlinedButton(
                            onPressed: () async {
                              await StoryStore.clear();
                              if (!mounted) return;
                              _toast(_l10n.dvMemoriesCleared);
                            },
                            child: Text(_l10n.dvClearMemories),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                _card(
                  title: _l10n.dvSceneTitle,
                  icon: Icons.wb_twilight_outlined,
                  description: _l10n.dvSceneDesc,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _testSubheading(_l10n.dvSceneCoreSection),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _choice(
                            _l10n.dvSceneRealTime,
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
                      _testSubheading(_l10n.dvSceneEdgeSection),
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
                  title: _l10n.dvDayShiftTitle,
                  icon: Icons.fast_forward_outlined,
                  description: _l10n.dvDayShiftDesc(_dayShift),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: FilledButton.tonalIcon(
                              onPressed: () => _fastForwardDays(1),
                              icon: const Icon(Icons.fast_forward, size: 18),
                              label: Text(_l10n.dvShiftOneDay),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _dayShift > 0 ? _restoreDays : null,
                              icon: const Icon(Icons.undo, size: 18),
                              label: Text(_l10n.dvUndoShift),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => _fastForwardDays(2),
                              child: Text(_l10n.dvShift2Grace),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => _fastForwardDays(3),
                              child: Text(_l10n.dvShift3Break),
                            ),
                          ),
                        ],
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
                    label: Text(_l10n.dvRestoreOverrides),
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
