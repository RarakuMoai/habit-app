import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/app_localizations.dart';
import '../utils/app_feedback.dart';
import '../utils/app_style.dart';
import '../utils/logical_date.dart';
import '../utils/logical_day_coordinator.dart';
import '../utils/mascot.dart';
import '../utils/preference_write_guard.dart';
import '../utils/prefs_keys.dart';
import '../utils/sfx_service.dart';
import '../utils/units.dart';
import '../utils/usage_stats.dart';
import '../utils/water_entries.dart';
import '../widgets/app_pressable.dart';
import '../widgets/mascot_app_bar.dart';
import '../widgets/mascot_page_shell.dart';
import '../widgets/mascot_scene.dart';
import '../widgets/scene_rooms.dart';
import '../widgets/sheet_drag_handle.dart';
import '../widgets/water_bottle.dart';
import 'home/room_metrics.dart';

const Color _kInk = Color(0xFF245D65);
const Color _kInkSoft = Color(0xFF557B80);
const Color _kBgTop = Color(0xFFE8FAFF);
const Color _kBgMid = Color(0xFFDFF5FF);
const Color _kBgBottom = Color(0xFFFFFFFF);
const Color _kChipBg = Color(0xFFEAF8FF);
const Color _kWaterDeep = AppPalette.water;
const Color _kGoalGold = Color(0xFFFFC857);

/// 一般加水用短泡泡；只有從未達標跨到達標的那一杯改播完整慶祝音。
SfxCue waterAddFeedbackCue({
  required bool wasReached,
  required bool isReached,
}) => !wasReached && isReached ? SfxCue.waterGoal : SfxCue.waterAdd;

class WaterPage extends StatefulWidget {
  final Future<void> Function(bool)? onGoalStatusChanged;
  final ValueChanged<int>? onReloaded;
  final void Function(int, Object, StackTrace)? onReloadFailed;
  final int reloadTrigger;
  const WaterPage({
    super.key,
    this.onGoalStatusChanged,
    this.onReloaded,
    this.onReloadFailed,
    this.reloadTrigger = 0,
  });

  @override
  State<WaterPage> createState() => _WaterPageState();
}

class _WaterSheetResult {
  final int? addMl;

  const _WaterSheetResult.add(this.addMl);
}

typedef _WaterGoalSuggestion = ({int ml, String reason, bool needsActivity});

// 跨日與換日設定變更一律靠 MainPage 傳下來的 [WaterPage.reloadTrigger]
// （來源是 LogicalDayCoordinator 的 revision）。本頁刻意不掛 lifecycle
// observer、也不監聽 LogicalDate.notifier：兩條路並存會讓同一次變更載入兩次。
class _WaterPageState extends State<WaterPage> {
  AppLocalizations get _l10n => AppLocalizations.of(context);

  static const int _defaultCupMl = 250;
  static const int _defaultGoalMl = 2000;
  // 每日總攝取上限（公制 ml）— 不再用「杯數」做門檻。
  // 6000ml 是「補水」合理天花板：成人推薦 ~2-3.7L，6L 已遠超推薦量；
  // 文獻紀錄的水中毒個案多在「短時間內 >6L」，這條線擋的是手滑連按 / 誤觸
  // 累積到不合理的量，不是限制重度運動者的真實補水
  static const int _maxTotalMl = 6000;
  // 「過量但還沒到危險」警告線。4L 超過男性 RDA 3.7L 上限、進入醫學上的
  // 灰色地帶。跨過去 → 兔咪變 sad + 提示語，但不擋使用者繼續紀錄
  static const int _warnTotalMl = 4000;
  static const int _minCupMl = 50;
  static const int _maxCupMl = 1000;
  static const int _minGoalMl = 500;
  static const int _maxGoalMl = 6000;
  // 建議卡被「套用 / 不使用」收起後，要等資料明顯變動才重新提示：新建議與
  // 收起當下的建議值差距 ≥ 這條線（≈ 5–6kg 體重或一級運動量變化）才解除收起，
  // 避免每天體重小波動就一直冒提示。
  static const int _goalResuggestThresholdMl = 200;
  static const int _historyRetainDays = 30;
  static const String _entryKeyPrefix = PrefsKeys.waterEntriesPrefix;
  static const String _keyPrefix = PrefsKeys.waterDayPrefix;
  // Legacy: 自訂量累計（標準杯之外的補水）
  static const String _extraKeyPrefix = PrefsKeys.waterExtraPrefix;
  // home_page 那邊勾「喝足夠的水」習慣時暫存原本杯數用的 key prefix
  static const String _savedKeyPrefix = PrefsKeys.waterSavedPrefix;
  static const String _savedEntryKeyPrefix = PrefsKeys.waterEntriesSavedPrefix;
  // 單次自訂量上限（2L 已經很多，超過就擋）
  static const int _maxSingleAddMl = 2000;

  List<WaterEntry> _entries = [];
  int _cupMl = _defaultCupMl;
  int _goalMl = _defaultGoalMl;
  String _todayKey = '';
  bool _lastReportedReached = false;
  Future<void> _goalStatusTail = Future<void>.value();
  DateTime? _lastMaxCupHint;
  // 本次 session 是否已跳過「跨越過量警告線」提示。
  // 跨界只提醒一次，避免每加一杯就跳，惹人厭
  bool _shownOverhydrationToast = false;
  UnitSystem _unit = UnitSystem.metric;
  _WaterGoalSuggestion? _goalSuggestion;
  bool _goalSuggestionDismissed = false;
  static const Duration _visualIdleDelay = Duration(seconds: 20);
  Timer? _visualIdleTimer;
  bool _visualIdle = false;
  Future<void>? _loadInFlight;
  bool _pendingLoad = false;
  Future<_WaterMutationResult>? _mutationInFlight;
  Future<bool>? _settingsMutationInFlight;
  int? _appliedReloadTrigger;
  int _debugReloadCount = 0;

  @visibleForTesting
  int get debugReloadCount => _debugReloadCount;

  @visibleForTesting
  int get debugTotalMl => _totalMl;

  @visibleForTesting
  Future<bool> debugAddCup() => _addCup();

  @visibleForTesting
  Future<bool> debugRemoveCup() => _removeCup();

  // 顯示用：把公制 ml 轉成目前單位（imperial 顯示 fl oz）
  String _volStr(int ml) => UnitFormat.volume(ml, _unit);
  String get _volLabel => UnitFormat.volumeLabel(_unit);

  int get _cups => _entries.where((entry) => entry.kind == 'cup').length;
  int get _totalMl => _entries.fold(0, (sum, entry) => sum + entry.ml);
  bool get _goalReached => _totalMl >= _goalMl;
  double get _progress => (_totalMl / _goalMl).clamp(0.0, 1.0);

  // 兔咪情境：依目前喝水進度切換（互動時呼叫，用於 MascotPersona.interact）。
  // 注意：overhydration 優先於 allDone — 喝過量比達標重要，要先警告
  MascotContext get _mascotCtx {
    if (_totalMl >= _warnTotalMl) return MascotContext.overhydration;
    if (_goalReached) return MascotContext.allDone;
    if (_cups == 0) return MascotContext.notStarted;
    if (_progress >= 0.5) return MascotContext.halfDone;
    return MascotContext.completedOne;
  }

  @override
  void initState() {
    super.initState();
    UnitSystem.notifier.addListener(_onUnitChanged);
    _loadWater();
    _markVisualActive();
  }

  @override
  void dispose() {
    _visualIdleTimer?.cancel();
    UnitSystem.notifier.removeListener(_onUnitChanged);
    super.dispose();
  }

  // 設定頁切換公制/英制 → 立即反映，不用重開頁
  void _onUnitChanged() {
    if (!mounted) return;
    setState(() => _unit = UnitSystem.notifier.value);
    unawaited(_refreshGoalSuggestion());
  }

  void _markVisualActive() {
    MascotVisualActivity.markActive();
    _visualIdleTimer?.cancel();
    if (_visualIdle && mounted) {
      setState(() => _visualIdle = false);
    }
    _visualIdleTimer = Timer(_visualIdleDelay, _goVisualIdle);
  }

  void _goVisualIdle() {
    if (!mounted || _visualIdle) return;
    setState(() => _visualIdle = true);
  }

  @override
  void didUpdateWidget(WaterPage old) {
    super.didUpdateWidget(old);
    // 跨日、換日設定變更、體重更新都走這一條（MainPage 統一 bump）。
    if (old.reloadTrigger != widget.reloadTrigger) {
      _loadWater();
    }
  }

  Future<void> _notifyGoalStatus({bool force = false}) async {
    final reached = _goalReached;
    final operation = _goalStatusTail.then((_) async {
      if (!force && _lastReportedReached == reached) return;
      await widget.onGoalStatusChanged?.call(reached);
      // callback 真正成功後才 commit；失敗時下一次同狀態仍會重試。
      _lastReportedReached = reached;
    });
    // caller 仍會收到 operation 的錯誤；tail 自己恢復，後續狀態不被永久毒死。
    _goalStatusTail = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace stackTrace) {},
    );
    await operation;
  }

  Future<void> _cleanupOldKeys(SharedPreferences prefs) async {
    final cutoff = DateTime.now().subtract(
      const Duration(days: _historyRetainDays),
    );
    // 長 prefix 先檢查，避免 'water_extra_2025-..' 被當作 'water_' 的 key 漏掉
    for (final key in prefs.getKeys()) {
      String? datePart;
      if (key.startsWith(_savedEntryKeyPrefix)) {
        datePart = key.substring(_savedEntryKeyPrefix.length);
      } else if (key.startsWith(_entryKeyPrefix)) {
        datePart = key.substring(_entryKeyPrefix.length);
      } else if (key.startsWith(_extraKeyPrefix)) {
        datePart = key.substring(_extraKeyPrefix.length);
      } else if (key.startsWith(_savedKeyPrefix)) {
        datePart = key.substring(_savedKeyPrefix.length);
      } else if (key.startsWith(_keyPrefix)) {
        datePart = key.substring(_keyPrefix.length);
      }
      if (datePart == null) continue;
      final parsed = DateTime.tryParse(datePart);
      if (parsed != null && parsed.isBefore(cutoff)) {
        await PreferenceWriteGuard.write(prefs, () => prefs.remove(key), key);
      }
    }
  }

  int _sanitizeCupMl(int? raw) =>
      (raw == null || raw < _minCupMl || raw > _maxCupMl) ? _defaultCupMl : raw;
  int _sanitizeGoalMl(int? raw) =>
      (raw == null || raw < _minGoalMl || raw > _maxGoalMl)
      ? _defaultGoalMl
      : raw;

  Future<void> _loadWater() {
    final inFlight = _loadInFlight;
    if (inFlight != null) {
      _pendingLoad = true;
      return inFlight;
    }
    final future = _drainWaterLoads();
    _loadInFlight = future;
    return future;
  }

  Future<void> _drainWaterLoads() async {
    late _WaterLoadResult result;
    do {
      _pendingLoad = false;
      result = await _runWaterLoad();
    } while (_pendingLoad && mounted);
    _loadInFlight = null;
    if (!mounted) return;
    final error = result.error;
    final stackTrace = result.stackTrace;
    if (error != null && stackTrace != null) {
      widget.onReloadFailed?.call(result.trigger, error, stackTrace);
    } else if (result.applied) {
      widget.onReloaded?.call(result.trigger);
    }
  }

  Future<_WaterLoadResult> _runWaterLoad() async {
    final trigger = widget.reloadTrigger;
    try {
      final applied = await LogicalDayCoordinator.instance.synchronizeStorage(
        () async {
          final prefs = await SharedPreferences.getInstance();
          await PreferenceWriteGuard.ensureHealthy(prefs);
          await _cleanupOldKeys(prefs);
          final dayStartHour = LogicalDate.load(prefs);
          final today = LogicalDate.stringFor(DateTime.now(), dayStartHour);
          final todayKey = '$_keyPrefix$today';
          final entriesKey = '$_entryKeyPrefix$today';
          final cupMl = _sanitizeCupMl(prefs.getInt(PrefsKeys.waterCupMl));
          final goalMl = _sanitizeGoalMl(prefs.getInt(PrefsKeys.waterGoalMl));
          final suggestionDismissed =
              prefs.getBool(PrefsKeys.waterGoalSuggestionDismissed) ?? false;
          // legacy cup 數舊鍵：只用來把舊資料 migrate 進 entries，clamp 寬鬆即可
          final cups = (prefs.getInt(todayKey) ?? 0).clamp(0, 100);
          final extra = (prefs.getInt('$_extraKeyPrefix$today') ?? 0).clamp(
            0,
            _maxGoalMl * 2,
          );
          var entries = parseWaterEntries(
            prefs.getString(entriesKey),
            maxEntryMl: _maxGoalMl * 2,
          );
          if (!prefs.containsKey(entriesKey)) {
            entries = legacyWaterEntries(
              cups: cups,
              extraMl: extra,
              cupMl: cupMl,
            );
            // Key presence is the authority boundary. Persist an empty baseline
            // too, otherwise a later mirror-only partial write can be mistaken
            // for valid legacy data and resurrect a mutation that reported failure.
            await PreferenceWriteGuard.write(
              prefs,
              () => prefs.setString(entriesKey, encodeWaterEntries(entries)),
              entriesKey,
            );
          }
          final unit = UnitSystem.load(prefs);
          if (!mounted || widget.reloadTrigger != trigger) return false;
          setState(() {
            _todayKey = entriesKey;
            _cupMl = cupMl;
            _goalMl = goalMl;
            _entries = entries;
            _unit = unit;
            _goalSuggestionDismissed = suggestionDismissed;
            _appliedReloadTrigger = trigger;
            _debugReloadCount++;
          });
          return true;
        },
      );
      if (!applied) {
        return _WaterLoadResult.cancelled(trigger);
      }
      // Main 的達標同步未必永遠使用同一種 storage 實作；留在 gate 外可避免
      // 未來改成 synchronizeStorage 後形成不可重入的巢狀鎖。
      await _notifyGoalStatus(force: true);
      await _refreshGoalSuggestion();
      return _WaterLoadResult.success(trigger);
    } catch (e, st) {
      debugPrint('Water reload failed: $e\n$st');
      return _WaterLoadResult.failed(trigger, e, st);
    }
  }

  bool get _waterMutationBlocked {
    final coordinator = LogicalDayCoordinator.instance;
    return _loadInFlight != null ||
        _mutationInFlight != null ||
        _settingsMutationInFlight != null ||
        coordinator.transitionInProgress ||
        _appliedReloadTrigger != widget.reloadTrigger ||
        _todayKey.isEmpty;
  }

  Future<_WaterMutationResult> _mutateEntries(
    _WaterMutationDecision Function(List<WaterEntry> entries) decide,
  ) {
    final coordinator = LogicalDayCoordinator.instance;
    if (_waterMutationBlocked) {
      return Future<_WaterMutationResult>.value(
        const _WaterMutationResult.blocked(),
      );
    }

    // 這些值在任何 await 前固定；後續不再從可被 reload 改寫的 State 取快照。
    final expectedTrigger = widget.reloadTrigger;
    final expectedKey = _todayKey;
    final goalMl = _goalMl;
    late final Future<_WaterMutationResult> tracked;
    final storageMutation = coordinator.synchronizeStorage(() async {
      final prefs = await SharedPreferences.getInstance();
      await PreferenceWriteGuard.ensureHealthy(prefs);
      final dayStartHour = LogicalDate.load(prefs);
      final today = LogicalDate.stringFor(DateTime.now(), dayStartHour);
      final currentKey = '$_entryKeyPrefix$today';
      if (currentKey != expectedKey ||
          widget.reloadTrigger != expectedTrigger ||
          _appliedReloadTrigger != expectedTrigger) {
        return const _WaterMutationResult.stale();
      }

      // 以 gate 內的 durable 最新值為基礎，避免另一個已排隊操作加入的紀錄
      // 被這次舊 UI snapshot 整包覆蓋。
      late final List<WaterEntry> current;
      if (prefs.containsKey(currentKey)) {
        current = parseWaterEntries(
          prefs.getString(currentKey),
          maxEntryMl: _maxGoalMl * 2,
        );
      } else {
        final cups = (prefs.getInt('$_keyPrefix$today') ?? 0).clamp(0, 100);
        final extra = (prefs.getInt('$_extraKeyPrefix$today') ?? 0).clamp(
          0,
          _maxGoalMl * 2,
        );
        current = legacyWaterEntries(
          cups: cups,
          extraMl: extra,
          cupMl: _sanitizeCupMl(prefs.getInt(PrefsKeys.waterCupMl)),
        );
        // Establish the authoritative old value before touching either mirror.
        await PreferenceWriteGuard.write(
          prefs,
          () => prefs.setString(currentKey, encodeWaterEntries(current)),
          currentKey,
        );
      }
      final beforeTotal = current.fold<int>(0, (sum, entry) => sum + entry.ml);
      final decision = decide(List<WaterEntry>.from(current));
      final next = decision.entries;
      if (next == null) {
        return _WaterMutationResult.notApplied(
          decision.status,
          beforeTotal: beforeTotal,
          goalMl: goalMl,
        );
      }

      // legacy mirrors 先寫，canonical entries 最後寫並充當 commit marker。
      // mirror 中途失敗時 retry 仍從舊 canonical 重算，不會把同一杯加兩次。
      await _syncLegacyWaterKeys(prefs, today: today, entries: next);
      await PreferenceWriteGuard.write(
        prefs,
        () => prefs.setString(currentKey, encodeWaterEntries(next)),
        currentKey,
      );
      final afterTotal = next.fold<int>(0, (sum, entry) => sum + entry.ml);
      if (!mounted ||
          widget.reloadTrigger != expectedTrigger ||
          _todayKey != expectedKey) {
        return _WaterMutationResult.superseded(
          beforeTotal: beforeTotal,
          afterTotal: afterTotal,
          goalMl: goalMl,
        );
      }
      setState(() {
        _entries = List<WaterEntry>.from(next);
      });
      return _WaterMutationResult.applied(
        beforeTotal: beforeTotal,
        afterTotal: afterTotal,
        goalMl: goalMl,
      );
    });
    final guarded = storageMutation.then<_WaterMutationResult>(
      (result) => result,
      onError: (Object error, StackTrace stackTrace) {
        debugPrint('Water mutation failed: $error\n$stackTrace');
        if (mounted) playHaptic(HapticLevel.light);
        return const _WaterMutationResult.failed();
      },
    );
    tracked = guarded.whenComplete(() {
      if (identical(_mutationInFlight, tracked)) _mutationInFlight = null;
    });
    _mutationInFlight = tracked;
    return tracked;
  }

  Future<bool> _finishWaterMutation(_WaterMutationResult result) async {
    if (result.status == _WaterMutationStatus.stale ||
        result.status == _WaterMutationStatus.superseded) {
      // 日期已移動但 Main 的 revision 尚未落到本頁時，主動補一次 freshness；
      // 真正的 reload 仍會由 Main trigger 合併，不會寫入舊畫面的 snapshot。
      try {
        await LogicalDayCoordinator.instance.ensureCurrent(
          trigger: LogicalDayTrigger.manual,
        );
      } catch (_) {
        return false;
      }
      if (mounted) await _loadWater();
      return false;
    }
    if (result.status != _WaterMutationStatus.applied) return false;
    if (LogicalDayCoordinator.instance.transitionInProgress || !mounted) {
      return true;
    }
    try {
      await _notifyGoalStatus();
      return true;
    } catch (error, stackTrace) {
      debugPrint('Water goal sync failed: $error\n$stackTrace');
      if (mounted) playHaptic(HapticLevel.light);
      // The canonical mutation and UI state are already committed. Force one
      // reload so the derived goal callback is retried against durable state;
      // persistent failures are surfaced through the reload failure callback.
      if (mounted) await _loadWater();
      return true;
    }
  }

  Future<void> _refreshGoalSuggestion() async {
    if (!mounted) return;
    // 建議說明是要顯示的文字，l10n 在第一個 await 之前先取，
    // 避免非同步回來時 context 已經失效。
    final suggestion = await _suggestGoal(_l10n);
    if (!mounted) return;
    if (_goalSuggestionDismissed) {
      // 收起狀態下仍重算建議：若新建議與「收起當下的建議值」差距夠大
      // （資料明顯變動），就解除收起讓提示回來；否則維持收起。
      final prefs = await SharedPreferences.getInstance();
      final baseline = prefs.getInt(PrefsKeys.waterGoalSuggestionBaseline);
      final changedEnough =
          baseline == null ||
          (suggestion.ml - baseline).abs() >= _goalResuggestThresholdMl;
      if (!mounted) return;
      if (changedEnough) {
        await prefs.setBool(PrefsKeys.waterGoalSuggestionDismissed, false);
        await prefs.remove(PrefsKeys.waterGoalSuggestionBaseline);
        if (!mounted) return;
        setState(() {
          _goalSuggestionDismissed = false;
          _goalSuggestion = suggestion;
        });
      } else {
        setState(() => _goalSuggestion = null);
      }
      return;
    }
    setState(() => _goalSuggestion = suggestion);
  }

  Future<void> _syncLegacyWaterKeys(
    SharedPreferences prefs, {
    required String today,
    required List<WaterEntry> entries,
  }) async {
    final cupCount = entries.where((entry) => entry.kind == 'cup').length;
    final cupMlTotal = entries
        .where((entry) => entry.kind == 'cup')
        .fold(0, (sum, entry) => sum + entry.ml);
    final totalMl = entries.fold<int>(0, (sum, entry) => sum + entry.ml);
    final customMl = math.max(0, totalMl - cupMlTotal);
    final cupsKey = '$_keyPrefix$today';
    final extraKey = '$_extraKeyPrefix$today';
    await PreferenceWriteGuard.write(
      prefs,
      () => prefs.setInt(cupsKey, cupCount),
      cupsKey,
    );
    await PreferenceWriteGuard.write(
      prefs,
      () => prefs.setInt(extraKey, customMl),
      extraKey,
    );
  }

  Future<bool> _addCup() async {
    final cupMl = _cupMl;
    final result = await _mutateEntries((entries) {
      final total = entries.fold<int>(0, (sum, entry) => sum + entry.ml);
      if (total + cupMl > _maxTotalMl) {
        return const _WaterMutationDecision.overLimit();
      }
      return _WaterMutationDecision.apply([...entries, WaterEntry.cup(cupMl)]);
    });
    if (result.status == _WaterMutationStatus.overLimit) {
      if (mounted) _showOverLimitHint();
      return false;
    }
    if (!await _finishWaterMutation(result)) return false;
    unawaited(UsageStats.bump(UsageEvents.waterAdd));
    playFeedback(
      waterAddFeedbackCue(
        wasReached: result.wasReached,
        isReached: result.isReached,
      ),
    );
    MascotPersona.interact(_mascotCtx);
    _maybeShowOverhydrationToast(
      wasUnderWarn: result.beforeTotal < _warnTotalMl,
    );
    return true;
  }

  Future<bool> _removeCup() async {
    final result = await _mutateEntries((entries) {
      if (entries.isEmpty) return const _WaterMutationDecision.unchanged();
      return _WaterMutationDecision.apply(
        entries.sublist(0, entries.length - 1),
      );
    });
    if (!await _finishWaterMutation(result)) return false;
    unawaited(SfxService.instance.stop(SfxCue.waterGoal));
    playFeedback(SfxCue.cancel);
    MascotPersona.interact(_mascotCtx);
    return true;
  }

  Future<bool> _deleteEntry(WaterEntry target) async {
    final result = await _mutateEntries((entries) {
      final index = entries.indexWhere(
        (entry) =>
            entry.ml == target.ml &&
            entry.kind == target.kind &&
            entry.at == target.at,
      );
      if (index < 0) return const _WaterMutationDecision.unchanged();
      final next = List<WaterEntry>.from(entries)..removeAt(index);
      return _WaterMutationDecision.apply(next);
    });
    if (!await _finishWaterMutation(result)) return false;
    unawaited(SfxService.instance.stop(SfxCue.waterGoal));
    playFeedback(SfxCue.cancel);
    MascotPersona.interact(_mascotCtx);
    return true;
  }

  // 加入一個自訂量，作為一筆可被「減少」撤銷的喝水紀錄。
  Future<bool> _addCustomMl(int ml) async {
    if (ml <= 0) return false;
    final clamped = ml.clamp(1, _maxSingleAddMl);
    final result = await _mutateEntries((entries) {
      final total = entries.fold<int>(0, (sum, entry) => sum + entry.ml);
      if (total + clamped > _maxTotalMl) {
        return const _WaterMutationDecision.overLimit();
      }
      return _WaterMutationDecision.apply([
        ...entries,
        WaterEntry.custom(clamped),
      ]);
    });
    if (result.status == _WaterMutationStatus.overLimit) {
      if (mounted) _showOverLimitHint();
      return false;
    }
    if (!await _finishWaterMutation(result)) return false;
    unawaited(UsageStats.bump(UsageEvents.waterAdd));
    playFeedback(
      waterAddFeedbackCue(
        wasReached: result.wasReached,
        isReached: result.isReached,
      ),
    );
    MascotPersona.interact(_mascotCtx);
    _maybeShowOverhydrationToast(
      wasUnderWarn: result.beforeTotal < _warnTotalMl,
    );
    return true;
  }

  // 跨越過量警告線時跳 snackbar 一次（同 session 內不重複）。
  // 兔咪變 sad 已經是視覺主場，這個 toast 只是再強化提示
  void _maybeShowOverhydrationToast({required bool wasUnderWarn}) {
    if (!mounted) return;
    if (!wasUnderWarn || _totalMl < _warnTotalMl) return;
    if (_shownOverhydrationToast) return;
    _shownOverhydrationToast = true;
    final warnStr = _volStr(_warnTotalMl);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(_l10n.waterOverhydrationToast(warnStr))),
      );
  }

  // 超出每日上限的提示（4s 內 debounce 不重複跳）
  void _showOverLimitHint() {
    final now = DateTime.now();
    if (_lastMaxCupHint != null &&
        now.difference(_lastMaxCupHint!) < const Duration(seconds: 4)) {
      return;
    }
    _lastMaxCupHint = now;
    final limitStr = _volStr(_maxTotalMl);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(_l10n.waterOverLimitHint(limitStr)),
          duration: const Duration(seconds: 3),
        ),
      );
  }

  Future<void> _openCustomCupSheet() async {
    // 刪除走 callback，sheet 自己留著、自己 setState 更新內部紀錄列表，
    // 不會像之前那樣 pop 整個視窗
    final result = await showModalBottomSheet<_WaterSheetResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CustomCupSheet(
        unit: _unit,
        maxMl: _maxSingleAddMl,
        entries: _entries,
        onDeleteEntry: _deleteEntry,
      ),
    );
    if (result == null) return;
    final addMl = result.addMl;
    if (addMl != null && addMl > 0) {
      await _addCustomMl(addMl);
    }
  }

  Future<void> _saveWaterSettings({
    required int cupMl,
    required int goalMl,
  }) async {
    if (_waterMutationBlocked) return;
    final coordinator = LogicalDayCoordinator.instance;
    final expectedTrigger = widget.reloadTrigger;
    final expectedKey = _todayKey;
    late final Future<bool> tracked;
    final storageMutation = coordinator.synchronizeStorage(() async {
      final prefs = await SharedPreferences.getInstance();
      await PreferenceWriteGuard.ensureHealthy(prefs);
      final dayStartHour = LogicalDate.load(prefs);
      final currentKey =
          '$_entryKeyPrefix${LogicalDate.stringFor(DateTime.now(), dayStartHour)}';
      if (currentKey != expectedKey ||
          widget.reloadTrigger != expectedTrigger ||
          _appliedReloadTrigger != expectedTrigger) {
        return false;
      }
      await PreferenceWriteGuard.write(
        prefs,
        () => prefs.setInt(PrefsKeys.waterCupMl, cupMl),
        PrefsKeys.waterCupMl,
      );
      await PreferenceWriteGuard.write(
        prefs,
        () => prefs.setInt(PrefsKeys.waterGoalMl, goalMl),
        PrefsKeys.waterGoalMl,
      );
      if (!mounted || widget.reloadTrigger != expectedTrigger) return true;
      setState(() {
        _cupMl = cupMl;
        _goalMl = goalMl;
      });
      return true;
    });
    tracked = storageMutation.whenComplete(() {
      if (identical(_settingsMutationInFlight, tracked)) {
        _settingsMutationInFlight = null;
      }
    });
    _settingsMutationInFlight = tracked;
    bool saved;
    try {
      saved = await tracked;
    } catch (error, stackTrace) {
      debugPrint('Water settings save failed: $error\n$stackTrace');
      if (mounted) playHaptic(HapticLevel.light);
      return;
    }
    if (!saved || !mounted || coordinator.transitionInProgress) return;
    try {
      await _notifyGoalStatus();
    } catch (error, stackTrace) {
      debugPrint('Water settings goal sync failed: $error\n$stackTrace');
      if (mounted) playHaptic(HapticLevel.light);
      if (mounted) await _loadWater();
      return;
    }
    unawaited(_refreshGoalSuggestion());
  }

  int _roundToNearest50(num value, {int min = 1200, int max = 4200}) =>
      ((value / 50).round() * 50).clamp(min, max).toInt();

  // Latest tracked weight (from weight tracking page) takes priority over
  // the static profile weight, since the profile copy may be stale.
  double? _latestTrackedWeight(SharedPreferences prefs) {
    final raw = prefs.getString(PrefsKeys.weightRecords);
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List || decoded.isEmpty) return null;
      // Records may be saved in any order; pick the entry with the
      // lexicographically largest yyyy-MM-dd.
      String? bestDate;
      num? bestWeight;
      for (final item in decoded) {
        if (item is! Map) continue;
        final date = item['date'];
        final weight = item['weight'];
        if (date is! String || weight is! num) continue;
        if (bestDate == null || date.compareTo(bestDate) > 0) {
          bestDate = date;
          bestWeight = weight;
        }
      }
      if (bestWeight == null) return null;
      final w = bestWeight.toDouble();
      if (w < 20 || w > 250) return null;
      return w;
    } catch (_) {
      return null;
    }
  }

  // Conservative beverage-water targets for children (rough USDA/EFSA
  // blended guidance), used as the baseline before activity bonus.
  int _childWaterBaseMl(int age) {
    if (age <= 3) return 900;
    if (age <= 8) return 1200;
    return 1600; // 9–13
  }

  int _ageFromBirthday(String? value) {
    if (value == null) return 0;
    final birthday = DateTime.tryParse(value);
    if (birthday == null) return 0;
    final now = DateTime.now();
    var age = now.year - birthday.year;
    if (now.month < birthday.month ||
        (now.month == birthday.month && now.day < birthday.day)) {
      age--;
    }
    return age;
  }

  // Map both legacy Chinese display strings and forward-looking enum keys
  // to a stable code so swapping the persisted value (for i18n) won't
  // break suggestion logic here.
  static const Map<String, String> _genderCode = {
    '男': 'male',
    'male': 'male',
    'M': 'male',
    '女': 'female',
    'female': 'female',
    'F': 'female',
  };
  // 每公斤飲水量（ml/kg）。臨床慣用的 30–35 ml/kg 估的是「總水分需求」
  // （口服＋食物＋維持量、且被註明偏寬鬆）；食物約供 20%、飲料約 80%。
  // 本 App 目標是「飲水（補水）」而非總水分，故取貼近 EFSA 飲水基準的
  // 30 ml/kg：70kg≈2100ml（EFSA 男飲水 ~2.0L＋小幅 buffer），不用總水分的 35。
  static const int _mlPerKg = 30;
  static const Map<String, int> _activityBonusMl = {
    '輕度': 250,
    'light': 250,
    'low': 250,
    '中度': 500,
    'moderate': 500,
    'mid': 500,
    '高度': 750,
    'high': 750,
  };

  Future<_WaterGoalSuggestion> _suggestGoal(AppLocalizations l10n) async {
    final prefs = await SharedPreferences.getInstance();

    // Prefer the most recent tracked weight; only fall back to the
    // static profile weight when no records exist.
    final tracked = _latestTrackedWeight(prefs);
    final profileWeight = prefs.getDouble(PrefsKeys.userWeight);
    final weight = tracked ?? profileWeight;
    final usingTracked = tracked != null;

    final height = prefs.getDouble(PrefsKeys.userHeight);
    final gender = _genderCode[prefs.getString(PrefsKeys.userGender) ?? ''];
    final activity = prefs.getString(PrefsKeys.userActivityLevel) ?? '';
    final needsActivity = activity.isEmpty;
    final age = _ageFromBirthday(prefs.getString(PrefsKeys.userBirthday));

    // Children: age-tiered base. Activity bonus is halved (kids hydrate
    // less per workout than adults), and the lower bound of the rounder
    // is relaxed so we don't artificially push small kids up.
    if (age > 0 && age < 14) {
      num childBase = _childWaterBaseMl(age);
      childBase += (_activityBonusMl[activity] ?? 0) ~/ 2;
      return (
        ml: _roundToNearest50(childBase, min: 600, max: 2200),
        reason: l10n.waterReasonAge(age),
        needsActivity: needsActivity,
      );
    }

    num base;
    String reason;
    if (weight != null && weight >= 20 && weight <= 250) {
      base = weight * _mlPerKg;
      final wDisp = UnitFormat.weight(weight, _unit);
      reason = usingTracked
          ? l10n.waterReasonLatestWeight(wDisp)
          : l10n.waterReasonWeight(wDisp);
    } else if (height != null && height >= 100 && height <= 230) {
      // 無體重時用 BMI 22 估健康體重，再套同一個 ml/kg。
      final h = height / 100;
      base = 22 * h * h * _mlPerKg;
      reason = l10n.waterReasonHeight;
    } else if (gender == 'male') {
      // EFSA 飲水基準：男 ~2.0L、女 ~1.6L（總水分 2.5/2.0L 的 ~80%）。
      base = 2000;
      reason = l10n.waterReasonMale;
    } else if (gender == 'female') {
      base = 1600;
      reason = l10n.waterReasonFemale;
    } else {
      base = _defaultGoalMl;
      reason = l10n.waterReasonGeneric;
    }

    base += _activityBonusMl[activity] ?? 0;

    // Older adults: thirst sensation declines with age, so nudge up a
    // little to compensate.
    if (age >= 65) {
      base += 300;
      reason = l10n.waterReasonSenior(reason);
    }

    return (
      ml: _roundToNearest50(base),
      reason: reason,
      needsActivity: needsActivity,
    );
  }

  Future<void> _openWaterSettings() async {
    final suggestion = await _suggestGoal(_l10n);
    if (!mounted) return;

    final result = await showModalBottomSheet<_WaterSettingsResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _WaterSettingsSheet(
        initialCupMl: _cupMl,
        initialGoalMl: _goalMl,
        suggestion: suggestion,
        minCupMl: _minCupMl,
        maxCupMl: _maxCupMl,
        minGoalMl: _minGoalMl,
        maxGoalMl: _maxGoalMl,
        unit: _unit,
      ),
    );

    if (result != null && mounted) {
      await _saveWaterSettings(cupMl: result.cupMl, goalMl: result.goalMl);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: const Color(0xFFEFF9FF),
      appBar: MascotAppBar(accent: _kInk, onSettingsReturn: _loadWater),
      body: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) => _markVisualActive(),
        onPointerSignal: (_) => _markVisualActive(),
        child: Stack(
          children: [
            const Positioned.fill(child: _BackdropDecor()),
            // 場景背景：延伸到 AppBar 後面。高度跟首頁同一套「寬度錨點」
            // （14PM 時 == 舊的 螢幕高×0.56，零位移；見 home/room_metrics.dart）
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: roomSceneHeight(MediaQuery.of(context).size.width),
              child: const FourPeriodRoomScene(room: FourPeriodRoom.water),
            ),
            SafeArea(
              child: MascotPageShell(
                accent: _kInk,
                sceneHeight: sceneRegionHeightAnchored(
                  MediaQuery.of(context).size.width,
                  MediaQuery.of(context).padding.top,
                ),
                scene: PersonaScene(
                  accent: _kInk,
                  lightGeometry: FourPeriodRoom.water.light,
                ),
                child: LayoutBuilder(
                  builder: (context, box) {
                    // The shell may leave less than 300 pt when the room is
                    // open on a small phone. Keep controls anchored and let
                    // the journal scroll; never replace today's data with a
                    // suggestion or shrink a label to make the layout fit.
                    final compact = box.maxHeight < 460;
                    final suggestion = _goalSuggestion;
                    final hasSuggestion =
                        !_goalSuggestionDismissed &&
                        suggestion != null &&
                        (suggestion.ml - _goalMl).abs() >= 50;
                    return Column(
                      children: [
                        Expanded(
                          child: ListView(
                            key: const PageStorageKey('water-journal'),
                            padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                            children: [
                              _summaryCard(compact: compact),
                              const SizedBox(height: 12),
                              _waterMoodLine(),
                              if (hasSuggestion) ...[
                                const SizedBox(height: 14),
                                _goalSuggestionCard(suggestion),
                              ],
                              const SizedBox(height: 14),
                              _recentWaterEntries(),
                            ],
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                          child: _controls(),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _summaryCard({required bool compact}) {
    final left = math.max(0, _goalMl - _totalMl);
    final goalDisp = _volStr(_goalMl);
    final subtitle = _goalReached
        ? _l10n.waterGoalReached(goalDisp)
        : _l10n.waterGoalRemaining(goalDisp, _volStr(left));
    final totalDisp = _unit == UnitSystem.imperial
        ? UnitConvert.mlToFlOz(_totalMl.toDouble()).round().toString()
        : _totalMl.toString();
    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    return Container(
      key: const ValueKey('water-today-card'),
      padding: const EdgeInsets.fromLTRB(20, 12, 16, 18),
      decoration: BoxDecoration(
        color: const Color(0xFFEDF7F7),
        borderRadius: BorderRadius.circular(AppCardStyle.radius),
        border: Border.all(color: _kWaterDeep.withValues(alpha: 0.10)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _l10n.waterTodayTitle,
                  style: const TextStyle(
                    color: _kInk,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              _summarySettingsButton(),
            ],
          ),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.end,
                      spacing: 6,
                      children: [
                        AnimatedSwitcher(
                          duration: reduceMotion
                              ? Duration.zero
                              : const Duration(milliseconds: 180),
                          child: Text(
                            totalDisp,
                            key: ValueKey(totalDisp),
                            style: AppType.digits(
                              color: _kInk,
                              fontSize: compact ? 44 : 52,
                              letterSpacing: -1.2,
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 7),
                          child: Text(
                            _volLabel,
                            style: const TextStyle(
                              color: _kInkSoft,
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    _summaryStatusPill(),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              ExcludeSemantics(
                child: SizedBox(
                  width: compact ? 74 : 92,
                  height: compact ? 111 : 138,
                  child: RepaintBoundary(
                    child: WaterBottle(
                      progress: _progress,
                      reached: _goalReached,
                      bumpKey: _entries.length,
                      panelOpenValue: 0,
                      paused: _visualIdle || reduceMotion,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 9),
          Semantics(
            label: _l10n.waterProgressSemantics(_volStr(_totalMl), goalDisp),
            child: TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: _progress, end: _progress),
              duration: reduceMotion
                  ? Duration.zero
                  : const Duration(milliseconds: 420),
              curve: Curves.easeOutCubic,
              builder: (_, value, _) => LinearProgressIndicator(
                value: value,
                minHeight: 6,
                borderRadius: BorderRadius.circular(3),
                color: _goalReached ? const Color(0xFF55987C) : _kWaterDeep,
                backgroundColor: _kWaterDeep.withValues(alpha: 0.11),
              ),
            ),
          ),
          const SizedBox(height: 11),
          Text(
            subtitle,
            style: const TextStyle(
              color: _kInkSoft,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _recentWaterEntries() {
    final recent = _entries.reversed.take(3).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                _l10n.waterTodayRecords,
                style: const TextStyle(
                  color: _kInk,
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            TextButton(
              onPressed: _openCustomCupSheet,
              style: TextButton.styleFrom(foregroundColor: _kInkSoft),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_l10n.waterRecordCount(_entries.length)),
                  const Icon(Icons.chevron_right_rounded, size: 18),
                ],
              ),
            ),
          ],
        ),
        if (recent.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              _l10n.waterNoRecords,
              style: const TextStyle(color: _kInkSoft, fontSize: 13),
            ),
          )
        else
          ...recent.map(
            (entry) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 9),
              child: Row(
                children: [
                  const Icon(
                    Icons.water_drop_outlined,
                    size: 18,
                    color: _kWaterDeep,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    MaterialLocalizations.of(context).formatTimeOfDay(
                      TimeOfDay.fromDateTime(entry.at),
                      alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(
                        context,
                      ),
                    ),
                    style: const TextStyle(color: _kInkSoft, fontSize: 13),
                  ),
                  const Spacer(),
                  Text(
                    _volStr(entry.ml),
                    style: AppType.digits(color: _kInk, fontSize: 16),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _summaryStatusPill() {
    final reached = _goalReached;
    final color = reached ? const Color(0xFFA87400) : _kInk;
    final bg = reached
        ? _kGoalGold.withValues(alpha: 0.24)
        : _kChipBg.withValues(alpha: 0.86);
    final label = reached
        ? _l10n.waterPillReached
        : '${(_progress * 100).round()}%';
    final icon = reached ? Icons.check_rounded : Icons.water_drop_rounded;
    return Container(
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: Colors.white.withValues(alpha: 0.72)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  Widget _waterMoodLine() {
    final text = _totalMl >= _warnTotalMl
        ? _l10n.waterMoodTooMuch
        : _goalReached
        ? _l10n.waterMoodReached
        : _progress >= 0.75
        ? _l10n.waterMoodNearly
        : _progress >= 0.5
        ? _l10n.waterMoodHalf
        : _totalMl > 0
        ? _l10n.waterMoodStarted
        : _l10n.waterMoodEmpty;
    final reached = _goalReached && _totalMl < _warnTotalMl;
    final icon = reached
        ? Icons.auto_awesome_rounded
        : Icons.local_drink_rounded;
    final color = reached ? const Color(0xFF7E6100) : _kInk;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: reached
            ? _kGoalGold.withValues(alpha: 0.16)
            : Colors.white.withValues(alpha: 0.64),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: reached
              ? _kGoalGold.withValues(alpha: 0.22)
              : Colors.white.withValues(alpha: 0.72),
        ),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color.withValues(alpha: 0.86)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color.withValues(alpha: 0.86),
                fontSize: 12.5,
                height: 1.25,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _summarySettingsButton() {
    return IconButton(
      tooltip: _l10n.waterAdjustGoal,
      onPressed: _openWaterSettings,
      icon: const Icon(Icons.tune_rounded, size: 20, color: _kInkSoft),
      style: IconButton.styleFrom(
        minimumSize: const Size(44, 44),
        backgroundColor: Colors.white.withValues(alpha: 0.72),
      ),
    );
  }

  Widget _goalSuggestionCard(_WaterGoalSuggestion suggestion) {
    return Material(
      color: const Color(0xFFEAF8FF),
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
        child: Column(
          children: [
            Row(
              children: [
                Icon(Icons.auto_awesome_rounded, color: _kInk, size: 18),
                const SizedBox(width: 9),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _l10n.waterSuggestAmount(_volStr(suggestion.ml)),
                        style: const TextStyle(
                          color: _kInk,
                          fontSize: 13,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        suggestion.reason,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: _kInkSoft,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _SuggestionActionButton(
                    label: _l10n.waterSuggestDismiss,
                    icon: Icons.close_rounded,
                    color: _kInkSoft,
                    filled: false,
                    onTap: _dismissGoalSuggestion,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _SuggestionActionButton(
                    label: _l10n.commonApply,
                    icon: Icons.check_rounded,
                    color: _kInk,
                    filled: true,
                    onTap: () => _applySuggestedGoal(suggestion),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // baselineMl：收起當下的建議值，之後用來判斷資料是否「明顯變動」需重新提示。
  Future<void> _setGoalSuggestionDismissed(int baselineMl) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(PrefsKeys.waterGoalSuggestionDismissed, true);
    await prefs.setInt(PrefsKeys.waterGoalSuggestionBaseline, baselineMl);
    if (!mounted) return;
    setState(() {
      _goalSuggestionDismissed = true;
      _goalSuggestion = null;
    });
  }

  Future<void> _dismissGoalSuggestion() async {
    final baseline = _goalSuggestion?.ml ?? _goalMl;
    playFeedback(SfxCue.cancel);
    await _setGoalSuggestionDismissed(baseline);
  }

  Future<void> _applySuggestedGoal(_WaterGoalSuggestion suggestion) async {
    playFeedback(SfxCue.tap);
    await _setGoalSuggestionDismissed(suggestion.ml);
    await _saveWaterSettings(cupMl: _cupMl, goalMl: suggestion.ml);
  }

  void _onAddCupPressed() {
    if (_totalMl + _cupMl > _maxTotalMl) {
      _showOverLimitHint();
      return;
    }
    _addCup();
  }

  Widget _controls() {
    final atMax = _totalMl + _cupMl > _maxTotalMl;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _mainCupButton(atMax: atMax),
        const SizedBox(height: 3),
        Row(
          children: [
            Expanded(
              child: TextButton(
                onPressed: _entries.isNotEmpty ? _removeCup : null,
                style: TextButton.styleFrom(
                  foregroundColor: _kInkSoft,
                  minimumSize: const Size(44, 44),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 8,
                  ),
                  textStyle: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                child: Text(_l10n.waterMinusCup),
              ),
            ),
            Container(width: 1, height: 16, color: AppSurfaces.divider),
            Expanded(
              child: TextButton(
                onPressed: _openCustomCupSheet,
                style: TextButton.styleFrom(
                  foregroundColor: _kInk,
                  minimumSize: const Size(44, 44),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 8,
                  ),
                  textStyle: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                child: Text(_l10n.waterCustomAmount),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _mainCupButton({required bool atMax}) {
    final reached = _goalReached && !atMax;
    final colors = atMax
        ? const [Color(0xFF8BB7C4), Color(0xFF6E9DAB)]
        : reached
        ? const [Color(0xFF27A58E), Color(0xFF56C9AC)]
        : const [_kInk, _kWaterDeep];
    final title = atMax
        ? _l10n.waterCupSlowDown
        : reached
        ? _l10n.waterCupMore
        : _l10n.waterCupDrank;
    final icon = reached ? Icons.check_rounded : Icons.local_drink_rounded;
    return Semantics(
      button: true,
      label: _l10n.waterCupSemantics(_volStr(_cupMl)),
      child: AppPressable(
        onPressed: atMax ? _onAddCupPressed : _addCup,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: colors,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(AppCardStyle.radius),
          ),
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(AppCardStyle.radius),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.20),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.14),
                      ),
                    ),
                    child: Icon(icon, color: Colors.white, size: 20),
                  ),
                  const SizedBox(width: 14),
                  Flexible(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            height: 1.1,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          atMax ? _l10n.waterCupSlowDownSub : _volStr(_cupMl),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.86),
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SuggestionActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final bool filled;
  final VoidCallback onTap;

  const _SuggestionActionButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.filled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final background = filled ? color : Colors.white.withValues(alpha: 0.78);
    final foreground = filled ? Colors.white : color;
    return Material(
      color: background,
      borderRadius: BorderRadius.circular(99),
      child: InkWell(
        borderRadius: BorderRadius.circular(99),
        onTap: onTap,
        child: SizedBox(
          height: 44,
          child: Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, color: foreground, size: 16),
                  const SizedBox(width: 4),
                  Text(
                    label,
                    style: TextStyle(
                      color: foreground,
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _WaterSettingsResult {
  final int cupMl;
  final int goalMl;
  const _WaterSettingsResult(this.cupMl, this.goalMl);
}

class _WaterSettingsSheet extends StatefulWidget {
  final int initialCupMl;
  final int initialGoalMl;
  final _WaterGoalSuggestion suggestion;
  final int minCupMl;
  final int maxCupMl;
  final int minGoalMl;
  final int maxGoalMl;
  final UnitSystem unit;

  const _WaterSettingsSheet({
    required this.initialCupMl,
    required this.initialGoalMl,
    required this.suggestion,
    required this.minCupMl,
    required this.maxCupMl,
    required this.minGoalMl,
    required this.maxGoalMl,
    required this.unit,
  });

  @override
  State<_WaterSettingsSheet> createState() => _WaterSettingsSheetState();
}

class _WaterSettingsSheetState extends State<_WaterSettingsSheet> {
  AppLocalizations get _l10n => AppLocalizations.of(context);

  // 顯示值依 unit；imperial 模式以 fl oz 進出，存的時候轉回 ml。
  late final TextEditingController _cupCtrl = TextEditingController(
    text: _initial(widget.initialCupMl),
  );
  late final TextEditingController _goalCtrl = TextEditingController(
    text: _initial(widget.initialGoalMl),
  );
  String? _cupErr;
  String? _goalErr;

  bool get _imperial => widget.unit == UnitSystem.imperial;
  String get _label => UnitFormat.volumeLabel(widget.unit);

  String _initial(int ml) => _imperial
      ? UnitConvert.mlToFlOz(ml.toDouble()).round().toString()
      : ml.toString();

  int? _parseMl(String raw) {
    final v = double.tryParse(raw.trim());
    if (v == null) return null;
    return _imperial ? UnitConvert.flOzToMl(v).round() : v.round();
  }

  String _displayRange(int minMl, int maxMl) {
    if (!_imperial) return '$minMl–$maxMl $_label';
    final lo = UnitConvert.mlToFlOz(minMl.toDouble()).round();
    final hi = UnitConvert.mlToFlOz(maxMl.toDouble()).round();
    return '$lo–$hi $_label';
  }

  @override
  void dispose() {
    _cupCtrl.dispose();
    _goalCtrl.dispose();
    super.dispose();
  }

  // 「套用」＝立即生效：把建議值帶入欄位後直接走儲存流程關閉面板，
  // 與摘要卡的「套用」語意一致，不再是「只填欄位、要再按儲存」的兩段式。
  void _applySuggestion() {
    _goalCtrl.text = _initial(widget.suggestion.ml);
    _goalErr = null;
    _submit();
  }

  void _submit() {
    final cupMl = _parseMl(_cupCtrl.text);
    final goalMl = _parseMl(_goalCtrl.text);
    final cupErr =
        (cupMl == null || cupMl < widget.minCupMl || cupMl > widget.maxCupMl)
        ? _l10n.waterEnterRange(_displayRange(widget.minCupMl, widget.maxCupMl))
        : null;
    final goalErr =
        (goalMl == null ||
            goalMl < widget.minGoalMl ||
            goalMl > widget.maxGoalMl)
        ? _l10n.waterEnterRange(
            _displayRange(widget.minGoalMl, widget.maxGoalMl),
          )
        : null;
    if (cupErr != null || goalErr != null) {
      setState(() {
        _cupErr = cupErr;
        _goalErr = goalErr;
      });
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    Navigator.of(context).pop(_WaterSettingsResult(cupMl!, goalMl!));
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, bottom + 16),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              // 規範：陰影不用純黑；用頁面墨色帶藍調
              color: _kInk.withValues(alpha: 0.16),
              blurRadius: 22,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _l10n.waterSettingsTitle,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 16),
            _NumField(
              controller: _cupCtrl,
              label: _l10n.waterCupSizeLabel,
              suffix: _label,
              errorText: _cupErr,
              onChanged: () {
                if (_cupErr != null) setState(() => _cupErr = null);
              },
            ),
            const SizedBox(height: 12),
            _NumField(
              controller: _goalCtrl,
              label: _l10n.waterDailyGoalLabel,
              suffix: _label,
              errorText: _goalErr,
              onChanged: () {
                if (_goalErr != null) setState(() => _goalErr = null);
              },
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFEAF8FF),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.auto_awesome,
                    color: Colors.cyan.shade700,
                    size: 18,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '${_l10n.waterSuggestAmount(UnitFormat.volume(widget.suggestion.ml, widget.unit))}\n'
                      '${widget.suggestion.reason}'
                      '${widget.suggestion.needsActivity ? '\n${_l10n.waterSuggestNeedsActivity}' : ''}',
                      style: TextStyle(
                        color: Colors.cyan.shade900,
                        fontSize: 13,
                        height: 1.35,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 78,
                    child: _SuggestionActionButton(
                      label: _l10n.commonApply,
                      icon: Icons.check_rounded,
                      color: Colors.cyan.shade700,
                      filled: true,
                      onTap: _applySuggestion,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _l10n.waterSuggestDisclaimer,
              style: TextStyle(
                color: _kInkSoft.withValues(alpha: 0.85),
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.cyan.shade600,
                  foregroundColor: Colors.white,
                ),
                onPressed: _submit,
                child: Text(_l10n.waterSaveSettings),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NumField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String suffix;
  final String? errorText;
  final VoidCallback? onChanged;

  const _NumField({
    required this.controller,
    required this.label,
    required this.suffix,
    this.errorText,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      onChanged: onChanged == null ? null : (_) => onChanged!(),
      onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
      decoration: InputDecoration(
        labelText: label,
        suffixText: suffix,
        errorText: errorText,
        filled: true,
        fillColor: const Color(0xFFF7FBFD),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}

class _BackdropDecor extends StatelessWidget {
  const _BackdropDecor();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [_kBgTop, _kBgMid, _kBgBottom],
          stops: [0.0, 0.55, 1.0],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: CustomPaint(painter: _BackdropPainter()),
    );
  }
}

class _BackdropPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    // upper-left soft light spot
    final spot1 = Paint()
      ..shader =
          RadialGradient(
            colors: [
              Colors.white.withValues(alpha: 0.55),
              Colors.white.withValues(alpha: 0.0),
            ],
          ).createShader(
            Rect.fromCircle(
              center: Offset(size.width * 0.18, size.height * 0.18),
              radius: size.width * 0.55,
            ),
          );
    canvas.drawCircle(
      Offset(size.width * 0.18, size.height * 0.18),
      size.width * 0.55,
      spot1,
    );

    // lower-right faint cyan glow
    final spot2 = Paint()
      ..shader =
          RadialGradient(
            colors: [
              Colors.cyan.withValues(alpha: 0.10),
              Colors.cyan.withValues(alpha: 0.0),
            ],
          ).createShader(
            Rect.fromCircle(
              center: Offset(size.width * 0.85, size.height * 0.72),
              radius: size.width * 0.6,
            ),
          );
    canvas.drawCircle(
      Offset(size.width * 0.85, size.height * 0.72),
      size.width * 0.6,
      spot2,
    );

    // a few tiny bubble dots
    final bubble = Paint()..color = Colors.white.withValues(alpha: 0.55);
    final bubbles = <Offset>[
      Offset(size.width * 0.08, size.height * 0.62),
      Offset(size.width * 0.92, size.height * 0.34),
      Offset(size.width * 0.78, size.height * 0.84),
      Offset(size.width * 0.20, size.height * 0.86),
    ];
    final radii = [3.0, 4.5, 2.5, 3.5];
    for (var i = 0; i < bubbles.length; i++) {
      canvas.drawCircle(bubbles[i], radii[i], bubble);
    }
  }

  @override
  bool shouldRepaint(covariant _BackdropPainter old) => false;
}

// ── 自訂喝水量 sheet ──
//
// 快捷選擇（100/200/300/500）一點就直接記錄並關閉；
// 自訂輸入框輸入完按「加入」會回傳該量（已轉成 ml）。
class _CustomCupSheet extends StatefulWidget {
  final UnitSystem unit;
  final int maxMl;
  final List<WaterEntry> entries;
  // 刪除一筆紀錄。sheet 不會 pop，自己 setState 更新內部列表；
  // 這個 callback 負責 parent 那邊持久化（_deleteEntryAt）
  final Future<bool> Function(WaterEntry entry) onDeleteEntry;

  const _CustomCupSheet({
    required this.unit,
    required this.maxMl,
    required this.entries,
    required this.onDeleteEntry,
  });

  @override
  State<_CustomCupSheet> createState() => _CustomCupSheetState();
}

class _CustomCupSheetState extends State<_CustomCupSheet> {
  AppLocalizations get _l10n => AppLocalizations.of(context);

  static const List<int> _presetMl = [100, 200, 300, 500];
  // 自訂量內建小鍵盤可輸入位數上限（4 位 = 最多 9999，公制 ml/英制 fl oz 都夠用）
  static const int _maxDigits = 4;

  // sheet 內部維護紀錄列表，刪除時 setState 更新自己 + 通知 parent 持久化
  late List<WaterEntry> _localEntries;
  // 內建小鍵盤輸入緩衝（取代 TextField，系統鍵盤不會出來）
  String _input = '';
  String? _err;
  // 正在播刪除動畫的那一筆（reference 比對）。同時間只允許一筆，
  // 避免使用者連點時動畫互相打架、_localEntries 索引漂移
  WaterEntry? _entryBeingRemoved;
  // 刪除動畫 + 列表塌陷的長度
  Duration get _deleteAnimDuration =>
      AppMotion.duration(context, const Duration(milliseconds: 280));

  @override
  void initState() {
    super.initState();
    _localEntries = List.of(widget.entries);
  }

  void _pressDigit(String d) {
    if (_input.length >= _maxDigits) return;
    // 前置 0 沒意義：第一個就按 0 直接跳過
    if (_input.isEmpty && d == '0') return;
    setState(() {
      _input += d;
      _err = null;
    });
  }

  void _pressBackspace() {
    if (_input.isEmpty) return;
    setState(() {
      _input = _input.substring(0, _input.length - 1);
      _err = null;
    });
  }

  void _pressClear() {
    if (_input.isEmpty) return;
    setState(() {
      _input = '';
      _err = null;
    });
  }

  void _submitCustom() {
    if (_input.isEmpty) {
      setState(() => _err = _l10n.valEnterNumber);
      return;
    }
    final n = int.tryParse(_input);
    if (n == null || n <= 0) {
      setState(() => _err = _l10n.waterEnterPositive);
      return;
    }
    // 公制直接用，英制把 fl oz 轉成 ml
    final ml = widget.unit == UnitSystem.imperial
        ? UnitConvert.flOzToMl(n.toDouble()).round()
        : n;
    if (ml > widget.maxMl) {
      setState(() => _err = _l10n.waterAmountTooLarge); // units-ok
      return;
    }
    Navigator.of(context).pop(_WaterSheetResult.add(ml));
  }

  Future<void> _handleDelete(int index) async {
    // 序列化：同時間只允許一筆在做刪除動畫，避免索引漂移
    if (_entryBeingRemoved != null) return;
    if (index < 0 || index >= _localEntries.length) return;
    final entry = _localEntries[index];

    // 第 1 階段：標記為「正在移除」→ tile fade + 高度塌陷動畫
    setState(() => _entryBeingRemoved = entry);
    await Future<void>.delayed(_deleteAnimDuration);
    if (!mounted) return;

    // 第 2 階段：先讓 parent 以 entry 身分在 durable 最新列表中刪除。若此刻
    // 正在跨日／reload，parent 會拒絕，sheet 也保留原列，不製造假刪除。
    final removed = await widget.onDeleteEntry(entry);
    if (!mounted) return;
    if (!removed) {
      setState(() => _entryBeingRemoved = null);
      return;
    }
    // 用 indexOf 重抓位置，避免動畫期間若有外部變動造成索引錯位。
    final currentIndex = _localEntries.indexOf(entry);
    if (currentIndex < 0) {
      setState(() => _entryBeingRemoved = null);
      return;
    }
    setState(() {
      _localEntries.removeAt(currentIndex);
      _entryBeingRemoved = null;
    });
  }

  String _formatEntryTime(DateTime at) {
    final h = at.hour.toString().padLeft(2, '0');
    final m = at.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  String _entryTypeLabel(WaterEntry entry) {
    return entry.kind == 'cup' ? _l10n.waterEntryCup : _l10n.waterEntryCustom;
  }

  @override
  Widget build(BuildContext context) {
    final label = UnitFormat.volumeLabel(widget.unit);
    final history = _localEntries.indexed.toList().reversed.toList();
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.86,
          ),
          child: Container(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
            decoration: BoxDecoration(
              color: AppSurfaces.card,
              borderRadius: BorderRadius.circular(AppCardStyle.sheetRadius),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SheetDragHandle(),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _l10n.waterSheetTitle,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              color: _kInk,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _l10n.waterSheetSub,
                            style: const TextStyle(
                              fontSize: 12,
                              color: _kInkSoft,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: _l10n.commonCancel,
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded, color: _kInkSoft),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: _presetMl
                              .map(
                                (ml) => _PresetChip(
                                  label: UnitFormat.volume(ml, widget.unit),
                                  onTap: () => Navigator.of(
                                    context,
                                  ).pop(_WaterSheetResult.add(ml)),
                                ),
                              )
                              .toList(),
                        ),
                        const SizedBox(height: 20),
                        _CustomCupInputDisplay(
                          input: _input,
                          unitLabel: label,
                          error: _err,
                        ),
                        const SizedBox(height: 12),
                        _CustomCupKeypad(
                          onDigit: _pressDigit,
                          onBackspace: _pressBackspace,
                          onClear: _pressClear,
                          onSubmit: _submitCustom,
                          submitEnabled: _input.isNotEmpty,
                        ),
                        const SizedBox(height: 24),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                _l10n.waterTodayRecords,
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800,
                                  color: _kInk,
                                ),
                              ),
                            ),
                            Text(
                              _l10n.waterRecordCount(_localEntries.length),
                              style: const TextStyle(
                                color: _kInkSoft,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        if (history.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            child: Text(
                              _l10n.waterNoRecords,
                              style: const TextStyle(
                                color: _kInkSoft,
                                fontSize: 13,
                              ),
                            ),
                          )
                        else
                          ...history.map((indexed) {
                            final (index, entry) = indexed;
                            final removing = identical(
                              entry,
                              _entryBeingRemoved,
                            );
                            return KeyedSubtree(
                              key: ValueKey(entry.at),
                              child: ClipRect(
                                child: AnimatedAlign(
                                  duration: _deleteAnimDuration,
                                  curve: Curves.easeInCubic,
                                  alignment: Alignment.topCenter,
                                  heightFactor: removing ? 0 : 1,
                                  child: AnimatedOpacity(
                                    duration: _deleteAnimDuration,
                                    opacity: removing ? 0 : 1,
                                    child: IgnorePointer(
                                      ignoring: removing,
                                      child: Padding(
                                        padding: const EdgeInsets.only(
                                          bottom: 8,
                                        ),
                                        child: _WaterHistoryTile(
                                          time: _formatEntryTime(entry.at),
                                          amount: UnitFormat.volume(
                                            entry.ml,
                                            widget.unit,
                                          ),
                                          type: _entryTypeLabel(entry),
                                          onDelete: () => _handleDelete(index),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            );
                          }),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// 自訂量輸入顯示框（取代 TextField，純展示用，沒有系統鍵盤）
class _CustomCupInputDisplay extends StatelessWidget {
  final String input;
  final String unitLabel;
  final String? error;

  const _CustomCupInputDisplay({
    required this.input,
    required this.unitLabel,
    this.error,
  });

  @override
  Widget build(BuildContext context) {
    final hasInput = input.isNotEmpty;
    final hasError = error != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(
              color: hasError ? AppInk.danger : _kInk.withValues(alpha: 0.32),
              width: 1.4,
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  hasInput
                      ? input
                      : AppLocalizations.of(context).waterKeypadHint,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: hasInput ? _kInk : _kInkSoft.withValues(alpha: 0.55),
                  ),
                ),
              ),
              Text(
                unitLabel,
                style: const TextStyle(
                  fontSize: 14,
                  color: _kInkSoft,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        if (hasError)
          Padding(
            padding: const EdgeInsets.only(top: 4, left: 4),
            child: Text(
              error!,
              style: TextStyle(color: AppInk.danger, fontSize: 12),
            ),
          ),
      ],
    );
  }
}

// 自訂量內建小鍵盤：3×4 數字格 + 加入按鈕，全部在 sheet 內、不召喚系統鍵盤
class _CustomCupKeypad extends StatelessWidget {
  final void Function(String digit) onDigit;
  final VoidCallback onBackspace;
  final VoidCallback onClear;
  final VoidCallback onSubmit;
  final bool submitEnabled;

  const _CustomCupKeypad({
    required this.onDigit,
    required this.onBackspace,
    required this.onClear,
    required this.onSubmit,
    required this.submitEnabled,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final row in const [
          ['1', '2', '3'],
          ['4', '5', '6'],
          ['7', '8', '9'],
        ])
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: [
                for (final d in row) ...[
                  Expanded(
                    child: _KeyButton(label: d, onTap: () => onDigit(d)),
                  ),
                  if (d != row.last) const SizedBox(width: 6),
                ],
              ],
            ),
          ),
        Row(
          children: [
            Expanded(
              child: _KeyButton(label: 'C', onTap: onClear, muted: true),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: _KeyButton(label: '0', onTap: () => onDigit('0')),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: _KeyButton(
                icon: Icons.backspace_outlined,
                onTap: onBackspace,
                muted: true,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: submitEnabled ? onSubmit : null,
            style: FilledButton.styleFrom(
              backgroundColor: _kInk,
              disabledBackgroundColor: _kInkSoft.withValues(alpha: 0.35),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Text(
              AppLocalizations.of(context).waterKeypadAdd,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
          ),
        ),
      ],
    );
  }
}

class _KeyButton extends StatelessWidget {
  final String? label;
  final IconData? icon;
  final VoidCallback onTap;
  final bool muted;

  const _KeyButton({
    this.label,
    this.icon,
    required this.onTap,
    this.muted = false,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: muted ? _kChipBg.withValues(alpha: 0.45) : _kChipBg,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          height: 38,
          child: Center(
            child: icon != null
                ? Icon(icon, size: 20, color: _kInk)
                : Text(
                    label!,
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: _kInk,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

class _WaterHistoryTile extends StatelessWidget {
  final String time;
  final String amount;
  final String type;
  final VoidCallback onDelete;

  const _WaterHistoryTile({
    required this.time,
    required this.amount,
    required this.type,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: BoxDecoration(
        color: _kChipBg.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.cyan.withValues(alpha: 0.10)),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.74),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              time,
              style: const TextStyle(
                color: _kInk,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  amount,
                  style: const TextStyle(
                    color: _kInk,
                    fontSize: 14.5,
                    fontWeight: FontWeight.w900,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  type,
                  style: const TextStyle(
                    color: _kInkSoft,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    height: 1.1,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: AppLocalizations.of(context).commonDelete,
            onPressed: onDelete,
            icon: const Icon(Icons.delete_outline_rounded),
            color: AppInk.danger,
            iconSize: 21,
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}

class _PresetChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _PresetChip({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _kChipBg,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          child: Text(
            label,
            style: const TextStyle(
              color: _kInk,
              fontWeight: FontWeight.w700,
              fontSize: 14,
            ),
          ),
        ),
      ),
    );
  }
}

enum _WaterMutationStatus {
  applied,
  blocked,
  failed,
  stale,
  superseded,
  unchanged,
  overLimit,
}

class _WaterMutationDecision {
  final _WaterMutationStatus status;
  final List<WaterEntry>? entries;

  const _WaterMutationDecision._(this.status, this.entries);

  const _WaterMutationDecision.apply(List<WaterEntry> entries)
    : this._(_WaterMutationStatus.applied, entries);

  const _WaterMutationDecision.unchanged()
    : this._(_WaterMutationStatus.unchanged, null);

  const _WaterMutationDecision.overLimit()
    : this._(_WaterMutationStatus.overLimit, null);
}

class _WaterMutationResult {
  final _WaterMutationStatus status;
  final int beforeTotal;
  final int afterTotal;
  final int goalMl;

  const _WaterMutationResult._({
    required this.status,
    required this.beforeTotal,
    required this.afterTotal,
    required this.goalMl,
  });

  const _WaterMutationResult.applied({
    required int beforeTotal,
    required int afterTotal,
    required int goalMl,
  }) : this._(
         status: _WaterMutationStatus.applied,
         beforeTotal: beforeTotal,
         afterTotal: afterTotal,
         goalMl: goalMl,
       );

  const _WaterMutationResult.notApplied(
    _WaterMutationStatus status, {
    required int beforeTotal,
    required int goalMl,
  }) : this._(
         status: status,
         beforeTotal: beforeTotal,
         afterTotal: beforeTotal,
         goalMl: goalMl,
       );

  const _WaterMutationResult.blocked()
    : this._(
        status: _WaterMutationStatus.blocked,
        beforeTotal: 0,
        afterTotal: 0,
        goalMl: 1,
      );

  const _WaterMutationResult.failed()
    : this._(
        status: _WaterMutationStatus.failed,
        beforeTotal: 0,
        afterTotal: 0,
        goalMl: 1,
      );

  const _WaterMutationResult.stale()
    : this._(
        status: _WaterMutationStatus.stale,
        beforeTotal: 0,
        afterTotal: 0,
        goalMl: 1,
      );

  const _WaterMutationResult.superseded({
    required int beforeTotal,
    required int afterTotal,
    required int goalMl,
  }) : this._(
         status: _WaterMutationStatus.superseded,
         beforeTotal: beforeTotal,
         afterTotal: afterTotal,
         goalMl: goalMl,
       );

  bool get wasReached => beforeTotal >= goalMl;
  bool get isReached => afterTotal >= goalMl;
}

class _WaterLoadResult {
  final int trigger;
  final bool applied;
  final Object? error;
  final StackTrace? stackTrace;

  const _WaterLoadResult._({
    required this.trigger,
    required this.applied,
    this.error,
    this.stackTrace,
  });

  const _WaterLoadResult.success(int trigger)
    : this._(trigger: trigger, applied: true);

  const _WaterLoadResult.cancelled(int trigger)
    : this._(trigger: trigger, applied: false);

  const _WaterLoadResult.failed(
    int trigger,
    Object error,
    StackTrace stackTrace,
  ) : this._(
        trigger: trigger,
        applied: false,
        error: error,
        stackTrace: stackTrace,
      );
}
