// 首頁（每日／每週習慣打卡 + 兔咪場景）。
// 其餘部分拆在 home/：習慣卡片、新增／編輯 bottom sheet、preset 定義、
// 問候橫幅、共用小元件與場景 painter。
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/app_localizations.dart';
import '../utils/app_feedback.dart';
import '../utils/app_style.dart';
import '../utils/coin_config.dart';
import '../utils/coin_service.dart';
import '../utils/habit_history.dart';
import '../utils/input_formatters.dart';
import '../utils/logical_date.dart';
import '../utils/logical_day_coordinator.dart';
import '../utils/mascot.dart';
import '../utils/preference_write_guard.dart';
import '../utils/prefs_keys.dart';
import '../utils/scene_time.dart';
import '../utils/sfx_service.dart';
import '../utils/story_store.dart';
import '../utils/usage_stats.dart';
import '../utils/weight_records.dart';
import '../widgets/app_dialogs.dart';
import '../widgets/four_period_background.dart';
import '../widgets/habit_ui.dart';
import '../widgets/mascot_app_bar.dart';
import '../widgets/mascot_page_shell.dart';
import '../widgets/mascot_scene.dart';
import '../widgets/scene_air_layer.dart';
import '../widgets/scene_clock.dart';
import '../widgets/scene_rooms.dart';
import 'home/completion_presentation_controller.dart';
import 'home/greeting_banner.dart';
import 'home/habit_card.dart';
import 'home/habit_sheets.dart';
import 'home/home_presets.dart';
import 'home/room_metrics.dart';
import 'home/room_scene_painters.dart';

/// 首頁兔咪環境融合的驗收開關；預設開啟。
/// A/B 截圖可傳 `--dart-define=SCENE_MASCOT_FUSION=false` 取得中性對照。
const bool _kHomeMascotFusionEnabled = bool.fromEnvironment(
  'SCENE_MASCOT_FUSION',
  defaultValue: true,
);

class HomePage extends StatefulWidget {
  final VoidCallback? onSettingsChanged;
  final bool waterHabitAutoComplete;
  final bool weightHabitAutoComplete;
  final Future<void> Function(bool)? onWaterHabitToggled;
  final ValueChanged<int>? onDayReloaded;
  final void Function(int, Object, StackTrace)? onDayReloadFailed;
  final int reloadTrigger;

  /// 目前邏輯日（由 [LogicalDayCoordinator] 擁有，經 MainPage 傳下來）。
  /// revision 一變就重新載入；首頁不再自己判斷跨日或推進 lastOpenDate。
  /// null 只出現在「單獨掛載首頁」的測試路徑，此時退回自行計算今天。
  final LogicalDayStamp? dayStamp;

  const HomePage({
    super.key,
    this.onSettingsChanged,
    this.waterHabitAutoComplete = false,
    this.weightHabitAutoComplete = false,
    this.onWaterHabitToggled,
    this.onDayReloaded,
    this.onDayReloadFailed,
    this.reloadTrigger = 0,
    this.dayStamp,
  });

  @override
  State<HomePage> createState() => _HomePageState();
}

// 喝水 preset 的名稱同時是「已存習慣的識別鍵」：喝水頁連動靠比對它，
// 所以不能翻譯（見 docs/i18n_migration.md 的跳過清單）。
const String _kWaterHabitPresetName = '喝足夠的水';

class _HomePageState extends State<HomePage> with TickerProviderStateMixin {
  AppLocalizations get _l10n => AppLocalizations.of(context);

  final List<Map<String, dynamic>> habits = [];
  bool isLoading = true;
  int streak = 0;
  String _nickname = '';
  String mascotName0 = MascotName.fallback;
  bool yesterdayAllDone = false;
  // 換日線（一天從幾點開始）；loadHabits 每次顯示首頁時從 prefs 重讀。
  int _dayStartHour = LogicalDate.defaultHour;
  DateTime? onboardingDate;
  DateTime? userBirthday;

  // 兔咪近期採 CG/PNG 差分 + Flutter 輕量演出，不以 Rive 作為近期主線。

  late AnimationController _celebCtrl;
  late Animation<double> _celebScale;
  // 進度列尾端亮點的呼吸光暈（達標時 repeat，未達標停在 0）
  late AnimationController _glowCtrl;
  // 場景微動與完成星光共用下方 20fps SceneAnimationClock；本頁不再為每層
  // 各建 AnimationController，避免重複排幀。
  // 編輯模式所有卡片共用的抖動驅動（一條 ticker，各卡片用不同相位）。
  // 不放在每張卡上，避免被拖曳 reparent 時帶著正在跑的 ticker 撞 element 生命週期。
  late AnimationController _jiggleCtrl;

  final Set<String> _animatedIn = {};
  // 抖動排序模式（像 iOS 主畫面長按 App）：全卡片抖動＋可拖，底部換成完成鈕。
  // 進入＝長按任一卡片或「⋯」選單的「移動」；退出＝點「完成」。
  bool _editMode = false;
  int? _reorderGeneration;

  // ── 首頁裝飾動畫的閒置凍結（省電 / 降溫）─────────────────────
  // 背景 crossfade 不需逐幀動畫；塵埃／星光與兔咪呼吸仍會排幀。停在首頁
  // 不互動 20 秒後全部凍結，一有觸碰立即恢復。
  static const Duration _sceneIdleDelay = Duration(seconds: 20);
  Timer? _sceneIdleTimer;
  bool _sceneIdle = false;
  // 追蹤本頁是否為當前可見分頁（外層 TickerMode），切回來時喚醒場景。
  bool _wasVisible = true;
  // 單一場景動畫時鐘：空氣層與完成特效共享（20fps；§5.2）。
  // 切分頁/退背景由外層 TickerMode 靜音；閒置凍結由下面兩個 hook 停啟。
  late final SceneAnimationClock _sceneClock;

  // 有互動：取消計時、若正凍結則喚醒，並重排下一次閒置。
  void _markSceneActive() {
    _sceneIdleTimer?.cancel();
    _sceneClock.start();
    if (_sceneIdle) {
      setState(() => _sceneIdle = false);
    }
    _sceneIdleTimer = Timer(_sceneIdleDelay, _goSceneIdle);
  }

  // 閒置到時：場景時鐘完全停止（0fps；時段配色改由 SceneTimeController
  // 的分鐘級單次 repaint 維持正確），兔咪演出由 TickerMode/paused 一起凍結。
  void _goSceneIdle() {
    if (!mounted || _sceneIdle) return;
    _sceneClock.stop();
    setState(() => _sceneIdle = true);
  }

  @override
  void initState() {
    super.initState();
    // 分鐘級時段更新：讓背景漸層/色罩/accent 跟著時間走
    //（閒置凍結時也會更新，不會停格在舊時段）。
    SceneTimeController.instance.addListener(_handleSceneTimeChanged);
    MascotPersona.current.addListener(_handleMascotActivity);
    _celebCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _celebScale = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.05), weight: 50),
      TweenSequenceItem(tween: Tween(begin: 1.05, end: 1.0), weight: 50),
    ]).animate(_celebCtrl);
    _glowCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _jiggleCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 620),
    );
    _sceneClock = SceneAnimationClock(vsync: this);
    _markSceneActive(); // 啟動場景時鐘並武裝閒置凍結計時

    // 互動演出過期後，兔咪要停在符合今天進度的表情，而不是開 app 的中性臉。
    MascotPersona.idleBaseline = _idleMascotState;

    loadHabits();
  }

  /// 給 [MascotPersona] 的待機 baseline：純由今天進度推導、不帶台詞。
  MascotState? _idleMascotState() {
    if (!mounted || isLoading) return null;
    return MascotState(_baselineMascotAsset, null);
  }

  @override
  void dispose() {
    SceneTimeController.instance.removeListener(_handleSceneTimeChanged);
    MascotPersona.current.removeListener(_handleMascotActivity);
    if (MascotPersona.idleBaseline == _idleMascotState) {
      MascotPersona.idleBaseline = null;
    }
    _sceneIdleTimer?.cancel();
    _transientMascotTimer?.cancel();
    _transientSpeechTimer?.cancel();
    _completion.dispose();
    _sceneClock.dispose();
    _celebCtrl.dispose();
    _glowCtrl.dispose();
    _jiggleCtrl.dispose();
    super.dispose();
  }

  void _handleMascotActivity() {
    if (_suppressSceneWake) return;
    _markSceneActive();
  }

  void _handleSceneTimeChanged() {
    if (mounted) setState(() {});
  }

  // ── 習慣載入（可安全重入的 reload）─────────────────────────
  //
  // 拆成兩段：[_readSnapshot] 只碰 storage（讀取、遷移、跨日結算、連動同步），
  // 產出一份全新的 [_HomeSnapshot]；[_applySnapshot] 再用單一 setState 原子
  // 替換畫面資料。舊版直接 `habits.addAll(...)` 進既有清單，呼叫第二次就會
  // 讓每個習慣變兩份，所以那時的 loadHabits 只能在 initState 跑一次。
  //
  // 重入策略：同時只跑一輪；期間再被要求就記下來，跑完補跑最後一次。補跑會
  // 重新讀 storage，拿到的一定是最新資料，不會重播舊參數。

  /// 目前正在跑的那一輪；null 代表閒置。用 Future 而不是單純 boolean，
  /// 呼叫端可以 await 同一輪，且 `whenComplete` 保證例外時也會釋放。
  Future<void>? _loadInFlight;
  bool _pendingReload = false;
  int _reloadGeneration = 0;
  int _debugReloadCount = 0;
  Completer<void>? _mutationGate;
  Future<void> _storageTail = Future<void>.value();

  /// reload 進行中：畫面上還是上一份清單，這時落地的打勾會被接著替換的新
  /// 快照蓋掉（等於使用者的操作被吃掉），所以一律擋下且不給成功回饋。
  bool _reloading = false;

  /// 已經播過問候的 transition id；同一次跨日重複 reload 不重播。
  String? _greetedTransitionId;

  /// 上一次套用的邏輯日；用來判斷這次 reload 是不是真的換了一天。
  String? _appliedDate;
  String? _handledTransitionId;

  /// 跨日重置兔咪時暫時忽略「兔咪有動作」→ 喚醒場景的連動。
  bool _suppressSceneWake = false;

  /// 載入 / 重新載入習慣。重複呼叫安全：進行中會合併；同一個 Future 直到
  /// 期間累積的最後一次補跑也完成才返回。
  Future<void> loadHabits() {
    _reloadGeneration++;
    _cancelMovingForReload();
    final inFlight = _loadInFlight;
    if (inFlight != null) {
      _pendingReload = true;
      return inFlight;
    }
    final future = _drainLoads();
    _loadInFlight = future;
    return future;
  }

  Future<void> _drainLoads() async {
    late _HomeLoadResult result;
    _reloading = true;
    try {
      do {
        _pendingReload = false;
        result = await _runLoad();
      } while (_pendingReload && mounted);
    } finally {
      // 整個 drain（含 catch-up）共用同一個 guard，中間不落下；同步清 pointer
      // 也關掉最後一次 while 檢查後的 lost-wakeup window。
      _reloading = false;
      _loadInFlight = null;
    }
    if (!mounted) return;
    final error = result.error;
    final stackTrace = result.stackTrace;
    if (error != null && stackTrace != null) {
      widget.onDayReloadFailed?.call(result.trigger, error, stackTrace);
    } else if (result.applied) {
      widget.onDayReloaded?.call(result.trigger);
    }
  }

  Future<_HomeLoadResult> _runLoad() async {
    _debugReloadCount++;
    final trigger = widget.reloadTrigger;
    try {
      final mutationGate = _mutationGate;
      if (mutationGate != null) await mutationGate.future;
      final expectedStamp = widget.dayStamp;
      if (expectedStamp != null) {
        // Coordinator 可能已開始寫 journal/reset，但尚未 publish 新 stamp。先等
        // 同一個 drain 完整結束，再確認這個 widget 仍拿著最新 revision；否則
        // 舊日 snapshot 會把已 reset 的 habits 寫回昨天的歷史。
        await LogicalDayCoordinator.instance.ensureCurrent(
          trigger: LogicalDayTrigger.manual,
        );
      }
      return await LogicalDayCoordinator.instance.synchronizeStorage(() async {
        final prefs = await SharedPreferences.getInstance();
        await PreferenceWriteGuard.ensureHealthy(prefs);
        if (expectedStamp != null) {
          final currentStamp = LogicalDayCoordinator.instance.stamp.value;
          if (currentStamp?.revision != expectedStamp.revision) {
            throw const _StaleHomeLoad();
          }
        }
        final generation = _reloadGeneration;
        if (!mounted) return _HomeLoadResult.cancelled(trigger);
        _throwIfStale(generation);
        final snapshot = await _readSnapshot(prefs, generation);
        if (!mounted) return _HomeLoadResult.cancelled(trigger);
        final firstApply = _appliedDate == null;
        _applySnapshot(snapshot);
        _afterApply(prefs, snapshot, firstApply);
        return _HomeLoadResult.success(trigger);
      });
    } catch (e, st) {
      if (e is _StaleHomeLoad) return _HomeLoadResult.cancelled(trigger);
      // 讀寫失敗不清空畫面：維持上一份清單，等下一次觸發重試。
      debugPrint('loadHabits failed: $e\n$st');
      return _HomeLoadResult.failed(trigger, e, st);
    }
  }

  @visibleForTesting
  bool get debugReloading => _reloading;

  @visibleForTesting
  int get debugReloadCount => _debugReloadCount;

  bool get _mutationsBlocked =>
      _reloading ||
      _mutationGate != null ||
      LogicalDayCoordinator.instance.transitionInProgress ||
      !_dayStampIsCurrent;

  bool get _dayStampIsCurrent {
    final current = LogicalDayCoordinator.instance.stamp.value;
    final local = widget.dayStamp;
    if (current == null || local == null) {
      return current == null && local == null;
    }
    return current.revision == local.revision;
  }

  void _throwIfStale(int generation) {
    if (generation != _reloadGeneration) throw const _StaleHomeLoad();
  }

  /// 只讀 storage 並把該落地的寫入做完，不碰任何 widget 狀態。
  Future<_HomeSnapshot> _readSnapshot(
    SharedPreferences prefs,
    int generation,
  ) async {
    final l10n = _l10n;
    SceneTimeController.instance.loadFromPrefs(prefs); // 固定時段/預覽覆寫
    // 「今天」的單一真相來自 coordinator 的 stamp；首頁不再自己保留一份換日
    // 設定。stamp 為 null 只出現在單獨掛載首頁的測試路徑，才退回自行計算。
    final stamp = widget.dayStamp;
    final waterHabitAutoComplete = widget.waterHabitAutoComplete;
    final weightHabitAutoComplete = widget.weightHabitAutoComplete;
    final dayStartHour = stamp?.dayStartHour ?? LogicalDate.load(prefs);
    // 同一輪固定一個時間基準，避免 today 與 todayDay 落在不同天。
    final now = DateTime.now();
    final today =
        stamp?.logicalDate ?? LogicalDate.stringFor(now, dayStartHour);
    final streakValue = prefs.getInt(PrefsKeys.streak) ?? 0;
    // 結算結果（含被結算掉那天的完成狀態與結算前的 lastOpenDate）從 journal
    // 讀，因為 coordinator 已經把 lastOpenDate 推進到今天了。
    final journal = LogicalDayJournal.read(prefs);
    final settledToday = journal != null && journal.settledOn(today);
    final previousOpen = settledToday
        ? journal.previousOpenDate
        : prefs.getString(PrefsKeys.lastOpenDate);
    final nickname =
        prefs.getString(PrefsKeys.userNickname) ?? l10n.hpNicknameFallback;
    final mascotName =
        prefs.getString(PrefsKeys.mascotName) ?? MascotName.fallback;
    final birthday = DateTime.tryParse(
      prefs.getString(PrefsKeys.userBirthday) ?? '',
    );

    DateTime? onboarding;
    final obDateStr = prefs.getString(PrefsKeys.onboardingDate);
    if (obDateStr != null) {
      onboarding = DateTime.tryParse(obDateStr);
    } else {
      onboarding = now;
      _throwIfStale(generation);
      await _checkedPreferenceWrite(
        prefs,
        () => prefs.setString(
          PrefsKeys.onboardingDate,
          onboarding!.toIso8601String(),
        ),
        PrefsKeys.onboardingDate,
      );
      _throwIfStale(generation);
    }

    // 每輪都建全新的 list，不再往既有的 habits 追加。
    final next = <Map<String, dynamic>>[];
    final habitsJson = prefs.getString(PrefsKeys.habits);
    if (habitsJson != null) {
      final decoded = jsonDecode(habitsJson) as List<dynamic>;
      next.addAll(decoded.map((e) => Map<String, dynamic>.from(e as Map)));
    }

    // 遷移：補上穩定 id 與建立日（補打勾 / 統計用）。舊習慣不知道真正的
    // 建立日，退而用 onboarding 日期（至少不會晚於實際），再不行才用今天。
    // 之後新增的習慣會在建立當下就帶 id/createdAt，不靠這裡。
    var habitsMigrated = false;
    final fallbackCreated = onboarding != null ? _fmtDate(onboarding) : today;
    for (final habit in next) {
      if (habit['id'] is! String || (habit['id'] as String).isEmpty) {
        habit['id'] = HabitHistory.newId();
        habitsMigrated = true;
      }
      if (habit['createdAt'] is! String ||
          (habit['createdAt'] as String).isEmpty) {
        habit['createdAt'] = fallbackCreated;
        habitsMigrated = true;
      }
    }
    if (habitsMigrated) {
      _throwIfStale(generation);
      await _checkedPreferenceWrite(
        prefs,
        () => prefs.setString(PrefsKeys.habits, jsonEncode(next)),
        PrefsKeys.habits,
      );
      _throwIfStale(generation);
    }

    // 跨日結算（連勝、當日勾選重置、lastOpenDate 推進）已交給
    // [LogicalDayCoordinator]：它是唯一擁有邏輯日生命週期的元件，冷啟動、
    // resume、前景邊界計時器與換日設定變更都由它偵測，並保證同一個邏輯日只
    // 結算一次。首頁到這裡只是把結果讀出來顯示。
    final yesterdayDone = settledToday && journal.yesterdayAllDone;

    // 連勝里程碑 → 解鎖回憶事件（冪等：已解鎖會 no-op；既有高連勝用戶下次開啟補發）
    unawaited(StoryEvents.onHabitStreak(streakValue));
    // 第一個習慣：新增當下也會觸發（_showAddHabitSheet），這裡是補發——
    // 涵蓋 onboarding 建的習慣與既有資料，冪等所以重複呼叫沒關係。
    if (next.isNotEmpty) unawaited(StoryEvents.onFirstHabitCreated());
    // 久違回來：用 journal 記下的「結算前 lastOpenDate」算天數（與問候語同一
    // 把尺）；marker 已被 coordinator 推進，不能再直接讀它。
    final daysAwayForStory = _daysSinceDateString(
      previousOpen,
      LogicalDate.dayOf(now, dayStartHour),
    );
    if (daysAwayForStory != null) {
      unawaited(StoryEvents.onComeback(daysAwayForStory));
    }

    // Always recompute done for weekly habits from weeklyDates
    final weekSet = _weekStringsFor(now, dayStartHour).toSet();
    for (final habit in next) {
      if ((habit['frequency'] ?? 'daily') == 'weekly') {
        final target = (habit['weeklyTarget'] as int?) ?? 3;
        final dates = List<String>.from((habit['weeklyDates'] as List?) ?? []);
        habit['done'] = dates.where(weekSet.contains).length >= target;
      }
    }

    // 跨頁籤切換時首頁會整頁重建，didUpdateWidget 不會觸發，
    // 因此在這裡依喝水頁達標狀態同步「喝足夠的水」習慣的勾選狀態
    final waterIdx = next.indexWhere(
      (h) => h['name'] == _kWaterHabitPresetName,
    );
    if (waterIdx != -1 && next[waterIdx]['done'] != waterHabitAutoComplete) {
      next[waterIdx]['done'] = waterHabitAutoComplete;
      _throwIfStale(generation);
      await _checkedPreferenceWrite(
        prefs,
        () => prefs.setString(PrefsKeys.habits, jsonEncode(next)),
        PrefsKeys.habits,
      );
      _throwIfStale(generation);
    }
    final weightIdx = next.indexWhere(
      (h) =>
          (h['frequency'] ?? 'daily') != 'weekly' &&
          isWeightHabitName(h['name'] as String?),
    );
    if (weightIdx != -1 && next[weightIdx]['done'] != weightHabitAutoComplete) {
      next[weightIdx]['done'] = weightHabitAutoComplete;
      _throwIfStale(generation);
      await _checkedPreferenceWrite(
        prefs,
        () => prefs.setString(PrefsKeys.habits, jsonEncode(next)),
        PrefsKeys.habits,
      );
      _throwIfStale(generation);
    }

    // 換日時間往後調時，logical date 可能暫時倒退，而 lastOpen marker 仍在較晚
    // 的日期。這時只顯示回退後的日期，不得用目前 habits 覆寫那個歷史日。
    // 正常同日／向前跨日則 marker 與 today 相同，可以安全同步。
    if (prefs.getString(PrefsKeys.lastOpenDate) == today) {
      _throwIfStale(generation);
      await _writeTodayHistory(prefs, next, today);
      _throwIfStale(generation);
    }

    return _HomeSnapshot(
      dayStartHour: dayStartHour,
      logicalDate: today,
      habits: next,
      streak: streakValue,
      nickname: nickname,
      mascotName: mascotName,
      userBirthday: birthday,
      onboardingDate: onboarding,
      yesterdayAllDone: yesterdayDone,
      transitionId: stamp?.transitionId,
      previousOpenDate: previousOpen,
    );
  }

  /// 單一 setState 原子替換：替換前不動 [habits]，所以 reload 期間畫面
  /// 一直是上一份完整清單，不會閃出空列表或錯誤進度。
  void _applySnapshot(_HomeSnapshot s) {
    final firstApply = _appliedDate == null;
    // 除了日期真的向前，還必須是尚未處理過的新 settlement。換日設定先回退再
    // 復原會讓日期 08-01→07-31→08-01，但 journal/transition 身分沒變；那不
    // 是第二個新日，不能再次清掉 MI 或重播卡片。
    final newTransition =
        s.transitionId != null && s.transitionId != _handledTransitionId;
    final dayChanged =
        !firstApply &&
        newTransition &&
        s.logicalDate.compareTo(_appliedDate!) > 0;
    if (dayChanged) {
      _transientMascotTimer?.cancel();
      _transientMascotTimer = null;
      _transientSpeechTimer?.cancel();
      _transientSpeechTimer = null;
    }
    setState(() {
      _dayStartHour = s.dayStartHour;
      habits
        ..clear()
        ..addAll(s.habits);
      streak = s.streak;
      _nickname = s.nickname;
      mascotName0 = s.mascotName;
      userBirthday = s.userBirthday;
      onboardingDate = s.onboardingDate;
      yesterdayAllDone = s.yesterdayAllDone;
      if (dayChanged) {
        _transientMascot = null;
        _transientSpeech = null;
      }
      // 新的一天讓卡片重播一次進場；同一天的 reload 保持原樣，否則每次
      // resume 整列卡片都會重新淡入。
      if (dayChanged) _animatedIn.clear();
      isLoading = false;
    });
    _appliedDate = s.logicalDate;
    if (s.transitionId != null) _handledTransitionId = s.transitionId;
    if (dayChanged) {
      // 新的一天：兔咪要從昨天的情緒（例如全完成的開心臉）回到中性待機，
      // 否則 MI 的基準會和歸零後的進度對不上。同日 reload 不動，免得打斷
      // 使用者剛剛的互動演出。
      //
      // resetToIdle 會改全域 notifier，而首頁監聽它會順手喚醒場景時鐘；
      // 自動跨日沒有使用者互動（可能是凌晨四點），不該把畫面叫醒。
      _suppressSceneWake = true;
      try {
        MascotPersona.resetToIdle();
      } finally {
        _suppressSceneWake = false;
      }
    }
  }

  void _afterApply(SharedPreferences prefs, _HomeSnapshot s, bool firstApply) {
    // 只有第一次把內容放上畫面才開始計閒置。之後的 reload 都是 coordinator
    // 驅動的（跨日 / resume），沒有使用者互動，不該喚醒已凍結的場景。
    if (firstApply) _markSceneActive();
    // 問候綁在 transition identity 上：同一次跨日只播一次，RootRestart 或
    // 重新訂閱都不會重播（待消費的 token 存在 coordinator 單例）。
    final id = s.transitionId;
    if (id == null || _greetedTransitionId == id) return;
    if (!LogicalDayCoordinator.instance.consumeGreeting(id)) return;
    _greetedTransitionId = id;
    Future.delayed(const Duration(milliseconds: 400), () {
      if (mounted) showGreeting(prefs, s.previousOpenDate);
    });
  }

  void showGreeting(SharedPreferences prefs, String? lastOpen) {
    // 每日登入獎勵演出（慶祝頁＋金幣飛行）進行中就不疊問候橫幅：
    // 橫幅走全域 Overlay 會蓋在慶祝頁上；慶祝頁本身就是當天的迎接，
    // pop 後的兔咪開心演出會接手當日迎接。
    if (CoinService.dailyRewardShowing.value) return;
    // 當日個人化橫幅就是開場問候；先收掉冷啟動的一般氣泡，
    // 避免首頁同時出現兩句兔咪台詞。
    MascotPersona.resetToIdle();
    showGreetingBanner(buildGreetingMessage(lastOpen));
  }

  int? _daysSinceDateString(String? raw, DateTime now) {
    if (raw == null) return null;
    final parts = raw.split('-');
    if (parts.length != 3) return null;
    final lastDate = DateTime.tryParse(
      '${parts[0]}-${parts[1].padLeft(2, '0')}-${parts[2].padLeft(2, '0')}',
    );
    if (lastDate == null) return null;
    final today = DateTime(now.year, now.month, now.day);
    final lastDay = DateTime(lastDate.year, lastDate.month, lastDate.day);
    return today.difference(lastDay).inDays;
  }

  String buildGreetingMessage(String? lastOpen) {
    final now = DateTime.now();
    final birthday = userBirthday;
    if (birthday != null &&
        birthday.month == now.month &&
        birthday.day == now.day) {
      return '生日快樂，$_nickname。\n今天也讓我陪你。';
    }

    // lastOpen 是用邏輯日存的，比對也要用邏輯日的今天。
    final daysAway = _daysSinceDateString(
      lastOpen,
      LogicalDate.dayOf(now, _dayStartHour),
    );
    if (daysAway != null && daysAway >= 14) {
      return '好久不見。\n今天慢慢來就好。';
    }
    if (daysAway != null && daysAway >= 2) {
      return '又見到你了。\n今天慢慢來就好。';
    }

    if (streak >= 30 && streak % 10 == 0) {
      return '連續 $streak 天了。\n你真的一天一天走過來。';
    }
    if (streak == 14) return '連續兩週了。\n我們一天一天走到這裡了。';
    if (streak == 7) return '連續一週了。\n你一直有回來。';
    if (yesterdayAllDone) return '昨天也完成了。\n我記得。';

    if (onboardingDate != null) {
      final start = onboardingDate!;
      final daysSince =
          DateTime(
            now.year,
            now.month,
            now.day,
          ).difference(DateTime(start.year, start.month, start.day)).inDays +
          1;
      if (daysSince == 1) return '第一天。\n我們慢慢熟起來。';
      if (daysSince == 3) return '第 3 天。\n你又回來了。';
      if (daysSince == 7) return '第 7 天。\n我開始記得你的節奏了。';
    }
    if (now.weekday == DateTime.monday) return '新的一週。\n先從小小的一件事開始。';
    // 問候在「當天第一次打開」觸發，不一定是早上（夜貓換日線更晚）：
    // 依實際時鐘挑時段問候，晚上開 app 不該被說早安。
    if (now.hour >= 5 && now.hour < 11) {
      return '早安，$_nickname。\n今天也從一點點開始？';
    }
    if (now.hour >= 11 && now.hour < 18) {
      return '午安，$_nickname。\n想從哪件小事開始？';
    }
    return '辛苦了，$_nickname。\n今天回來了就好。';
  }

  void showGreetingBanner(String message) {
    final overlay = Overlay.of(context);
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => GreetingBanner(
        mascotName: mascotName0,
        message: message,
        onDismiss: () => entry.remove(),
      ),
    );
    overlay.insert(entry);
    // 兩行情感文案 + 350ms 進場，2 秒讀不完；停留 4.5 秒，點擊仍可立即關。
    Future.delayed(const Duration(milliseconds: 4500), () {
      if (entry.mounted) entry.remove();
    });
  }

  String _fmtDate(DateTime d) {
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '${d.year}-$m-$day';
  }

  // 換日線往後挪時，睡前完成的習慣仍算前一天（與喝水/體重一致）。
  // 互動日期要和畫面已套用的 stamp 綁在一起。邊界到了但 coordinator 尚未
  // settlement 的短窗口內，畫面仍是舊日；此時接受的操作也必須完整排在舊日，
  // 不能讓 habits 寫舊日、history 卻用 wall clock 提前寫進新日。
  String todayString() =>
      widget.dayStamp?.logicalDate ??
      _appliedDate ??
      LogicalDate.stringFor(DateTime.now(), _dayStartHour);

  /// 純函式版：載入流程用它，才不必依賴還沒套用的 [_dayStartHour] 欄位。
  List<String> _weekStringsFor(DateTime at, int dayStartHour) {
    // 用邏輯日的今天決定本週，weeklyDates 也是用 todayString() 存的。
    final today = LogicalDate.dayOf(at, dayStartHour);
    final monday = today.subtract(Duration(days: today.weekday - 1));
    return List.generate(7, (i) => _fmtDate(monday.add(Duration(days: i))));
  }

  List<String> _currentWeekStrings() =>
      _weekStringsFor(DateTime.now(), _dayStartHour);

  int _weeklyCount(Map<String, dynamic> habit) {
    final dates = List<String>.from((habit['weeklyDates'] as List?) ?? []);
    final weekSet = _currentWeekStrings().toSet();
    return dates.where(weekSet.contains).length;
  }

  Future<void> _checkedPreferenceWrite(
    SharedPreferences prefs,
    Future<bool> Function() operation,
    String key,
  ) => PreferenceWriteGuard.write(prefs, operation, key);

  Future<void> _queueStorageWrite(Future<void> Function() write) {
    // 立刻向全域 FIFO 保留位置，再在自己的 slot 裡等前一筆 Home 寫入。
    // 若先用 `_storageTail.then` 延後登記，緊接著開始的跨日結算會超車，讓舊日
    // snapshot 在 reset 之後才覆寫回 storage。
    final previous = _storageTail;
    final operation = LogicalDayCoordinator.instance.synchronizeStorage(
      () async {
        await previous;
        await write();
      },
    );
    final guarded = operation.catchError((Object error, StackTrace stackTrace) {
      debugPrint('Home storage write failed: $error\n$stackTrace');
    });
    _storageTail = guarded;
    return guarded;
  }

  Future<void> saveHabits() {
    // 呼叫當下就序列化，後續 UI mutation 不會改到排隊中的寫入內容。
    final encoded = jsonEncode(habits);
    return _queueStorageWrite(() async {
      final prefs = await SharedPreferences.getInstance();
      await _checkedPreferenceWrite(
        prefs,
        () => prefs.setString(PrefsKeys.habits, encoded),
        PrefsKeys.habits,
      );
    });
  }

  /// 明確帶入來源清單與日期的版本：載入流程用它，避免依賴還沒替換上去的
  /// [habits] 欄位與還沒套用的 [_dayStartHour]。
  Future<void> _writeTodayHistory(
    SharedPreferences prefs,
    List<Map<String, dynamic>> source,
    String date,
  ) async {
    final ids = source
        .where((h) => (h['frequency'] ?? 'daily') != 'weekly')
        .where((h) => h['done'] == true)
        .map((h) => h['id'])
        .whereType<String>()
        .toList();
    final key = PrefsKeys.habitDoneDay(date);
    final values = ids.toSet().toList();
    await _checkedPreferenceWrite(
      prefs,
      () => values.isEmpty
          ? prefs.remove(key)
          : prefs.setString(key, jsonEncode(values)),
      key,
    );
  }

  // 互動後 fire-and-forget 更新今天的歷史；日期與完成集合都在呼叫當下固定，
  // 並與 habits 寫入共用一條 tail，避免快速操作時舊 Future 最後才覆蓋新狀態。
  Future<void> _recordTodayHistory() {
    final date = todayString();
    final snapshot = habits.map(Map<String, dynamic>.from).toList();
    return _queueStorageWrite(() async {
      final prefs = await SharedPreferences.getInstance();
      await _writeTodayHistory(prefs, snapshot, date);
    });
  }

  void _startMovingHabits({int? expectedGeneration}) {
    final generation = expectedGeneration ?? _reloadGeneration;
    if (_mutationsBlocked || _editMode || generation != _reloadGeneration) {
      return;
    }
    _reorderGeneration = generation;
    setState(() => _editMode = true);
    _jiggleCtrl.repeat();
    playFeedback(SfxCue.tap);
  }

  void _finishMovingHabits() {
    if (!_editMode) return;
    setState(() => _editMode = false);
    _reorderGeneration = null;
    _jiggleCtrl
      ..stop()
      ..value = 0;
    playFeedback(SfxCue.tap);
  }

  void _cancelMovingForReload() {
    if (!_editMode) return;
    setState(() {
      _editMode = false;
      _reorderGeneration = null;
    });
    _jiggleCtrl
      ..stop()
      ..value = 0;
  }

  void _reorderHabitSection({
    required bool weekly,
    required int oldIndex,
    required int newIndex,
  }) {
    if (_mutationsBlocked || _reorderGeneration != _reloadGeneration) return;
    if (newIndex > oldIndex) newIndex -= 1;
    final sectionHabits = habits
        .where((h) => ((h['frequency'] ?? 'daily') == 'weekly') == weekly)
        .toList();
    if (oldIndex < 0 ||
        oldIndex >= sectionHabits.length ||
        newIndex < 0 ||
        newIndex >= sectionHabits.length) {
      return;
    }

    final moved = sectionHabits.removeAt(oldIndex);
    sectionHabits.insert(newIndex, moved);

    var sectionIndex = 0;
    setState(() {
      for (var i = 0; i < habits.length; i++) {
        final isSameSection =
            ((habits[i]['frequency'] ?? 'daily') == 'weekly') == weekly;
        if (isSameSection) {
          habits[i] = sectionHabits[sectionIndex++];
        }
      }
    });
    unawaited(saveHabits());
  }

  @override
  void didUpdateWidget(HomePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 邏輯日換了就整份重載。MainPage 保證這一幀裡的 auto-complete 旗標已經
    // 是新一天的值，所以重載讀到的連動狀態不會是昨天的殘留；也因此這時不必
    // 再單獨跑下面兩個 sync（重載的快照已經把它們算進去了）。
    if (oldWidget.dayStamp?.revision != widget.dayStamp?.revision ||
        oldWidget.reloadTrigger != widget.reloadTrigger) {
      unawaited(loadHabits());
      return;
    }
    if (oldWidget.waterHabitAutoComplete != widget.waterHabitAutoComplete) {
      _syncWaterHabit(widget.waterHabitAutoComplete);
    }
    if (oldWidget.weightHabitAutoComplete != widget.weightHabitAutoComplete) {
      _syncWeightHabit(widget.weightHabitAutoComplete);
    }
  }

  void _syncWaterHabit(bool done) {
    if (_mutationsBlocked) {
      unawaited(loadHabits());
      return;
    }
    final idx = habits.indexWhere((h) => h['name'] == _kWaterHabitPresetName);
    if (idx == -1 || habits[idx]['done'] == done) return;
    setState(() => habits[idx]['done'] = done);
    saveHabits();
    unawaited(_recordTodayHistory());
  }

  void _syncWeightHabit(bool done) {
    if (_mutationsBlocked) {
      unawaited(loadHabits());
      return;
    }
    final idx = habits.indexWhere(
      (h) =>
          (h['frequency'] ?? 'daily') != 'weekly' &&
          isWeightHabitName(h['name'] as String?),
    );
    if (idx == -1 || habits[idx]['done'] == done) return;
    setState(() => habits[idx]['done'] = done);
    saveHabits();
    unawaited(_recordTodayHistory());
  }

  List<Map<String, dynamic>> get _dailyHabits =>
      habits.where((h) => (h['frequency'] ?? 'daily') != 'weekly').toList();

  List<Map<String, dynamic>> get _weeklyHabits =>
      habits.where((h) => (h['frequency'] ?? 'daily') == 'weekly').toList();

  int get dailyDoneCount => _dailyHabits.where((h) => h['done'] == true).length;
  int get weeklyMetCount =>
      _weeklyHabits.where((h) => h['done'] == true).length;

  int get doneCount {
    final weekSet = _currentWeekStrings().toSet();
    return habits.where((h) {
      if ((h['frequency'] ?? 'daily') == 'weekly') {
        final target = (h['weeklyTarget'] as int?) ?? 3;
        final dates = List<String>.from((h['weeklyDates'] as List?) ?? []);
        return dates.where(weekSet.contains).length >= target;
      }
      return h['done'] == true;
    }).length;
  }

  // 只有每日習慣全完成才算「全部完成」，每週習慣不影響
  bool get allDone0 => _dailyHabits.isNotEmpty
      ? dailyDoneCount == _dailyHabits.length
      : habits.isNotEmpty && weeklyMetCount == _weeklyHabits.length;

  // 兔咪短暫情緒：撤銷打卡後 2 秒顯示 sad
  String? _transientMascot;
  // 對話泡泡內的文字（點兔咪時暫時覆蓋）
  String? _transientSpeech;
  Timer? _transientMascotTimer;
  Timer? _transientSpeechTimer;
  int _mascotReactionTick = 0;

  void _showTransientMascot(
    String name, {
    Duration duration = const Duration(seconds: 2),
  }) {
    // 注意：這裡不加 _mascotReactionTick——彈跳是「正向」動作語彙，
    // 這條路目前只給撤銷打卡的 sad 用，難過還跳起來會很突兀；
    // 換圖動畫＋汗滴泡泡＋語音已足夠承載這個時刻。
    _transientMascotTimer?.cancel();
    setState(() {
      _transientMascot = name;
    });
    _applyPersona(_baselineMascotContext);
    _transientMascotTimer = Timer(duration, () {
      if (mounted) {
        setState(() => _transientMascot = null);
        // 回 baseline 是「收拾」不是新事件：不能再冒一次泡泡或再叫一聲。
        _applyPersona(_baselineMascotContext, silent: true, force: true);
      }
      _transientMascotTimer = null;
    });
  }

  void _onMascotTap() {
    _transientSpeechTimer?.cancel();
    _celebCtrl.forward(from: 0);
    final ctx = _baselineMascotContext;
    // 進度中的情境改用帶件數的具體回應：使用者主動點兔咪等於在問
    // 「你怎麼看今天？」，這時給得出數字才有被看見的實感。
    final done = _dailyHabits.isNotEmpty ? dailyDoneCount : weeklyMetCount;
    final speech =
        (ctx == MascotContext.completedOne || ctx == MascotContext.halfDone)
        ? MascotLines.doneCountLine(done)
        : MascotLines.randomHomeTapLineFor(ctx);
    setState(() {
      _transientSpeech = speech;
      _mascotReactionTick++;
    });
    // 點兔咪本身才是 tapReaction（問號泡泡＋疑問聲）；打卡不走這條。
    final accepted = _applyPersona(MascotContext.tapReaction);
    if (accepted) {
      _transientSpeechTimer = Timer(const Duration(seconds: 3), () {
        if (mounted) {
          setState(() => _transientSpeech = null);
          _applyPersona(_baselineMascotContext, silent: true, force: true);
        }
        _transientSpeechTimer = null;
      });
    } else {
      setState(() => _transientSpeech = null);
      _transientSpeechTimer = null;
    }
  }

  void _onMascotHeadPet() {
    MascotPersona.interact(MascotContext.headPet);
  }

  // 兔咪圖選擇器（按進度、時間、streak 決定）。
  // 透過 [MascotEmotion.assetPath] 取對應的 CG 立繪。
  String get _mascotAsset {
    if (_transientMascot != null) {
      final emo = MascotEmotion.values.firstWhere(
        (e) => e.assetKey == _transientMascot,
        orElse: () => MascotEmotion.neutralFront,
      );
      return emo.assetPath;
    }
    return _baselineMascotAsset;
  }

  /// 純由今天進度推導的立繪，不含任何 transient 演出。
  /// 演出結束後要回到的就是這張——不是開 app 的中性臉。
  String get _baselineMascotAsset {
    if (habits.isEmpty) return MascotEmotion.neutralFront.assetPath;

    final ref = _dailyHabits.isNotEmpty ? _dailyHabits : _weeklyHabits;
    final done = _dailyHabits.isNotEmpty ? dailyDoneCount : weeklyMetCount;
    final ratio = done / ref.length;

    if (ratio == 1.0) {
      return streak >= 7
          ? MascotEmotion.streak.assetPath
          : MascotEmotion.happy.assetPath;
    }
    if (ratio >= 0.5) return MascotEmotion.smile.assetPath;
    if (ratio > 0) return MascotEmotion.expect.assetPath;

    final hour = sceneHourNow().floor();
    return hour >= 22 || hour < 6
        ? MascotEmotion.night.assetPath
        : MascotEmotion.sleep.assetPath;
  }

  /// 純由今天進度推導的情境。
  ///
  /// 刻意**不看** `_transientSpeech`：台詞是演出結果，不是語意來源。舊版用它
  /// 反推 [MascotContext.tapReaction]，害得「今天第一件完成」被當成使用者
  /// 點了兔咪，冒問號、播疑問聲。要 tapReaction 的呼叫端自己指定就好。
  MascotContext get _baselineMascotContext {
    if (_transientMascot == 'sad') return MascotContext.undone;
    if (habits.isEmpty) return MascotContext.emptyHabits;

    final ref = _dailyHabits.isNotEmpty ? _dailyHabits : _weeklyHabits;
    final done = _dailyHabits.isNotEmpty ? dailyDoneCount : weeklyMetCount;
    final ratio = done / ref.length;
    if (ratio == 1.0) {
      return streak >= 7 ? MascotContext.streak : MascotContext.allDone;
    }
    if (ratio >= 0.5) return MascotContext.halfDone;
    if (ratio > 0) return MascotContext.completedOne;

    final hour = sceneHourNow().floor();
    if (hour >= 22 || hour < 6) return MascotContext.night;
    return MascotContext.notStarted;
  }

  @visibleForTesting
  MascotContext get debugBaselineMascotContext => _baselineMascotContext;

  void toggleHabit(int index) {
    // reload 進行中：畫面上還是上一份清單，index 可能已經對不上，落地也會被
    // 接著替換的新快照蓋掉。一律擋下且不給成功回饋（給了會讓使用者以為打成功）。
    if (_mutationsBlocked || index >= habits.length) return;
    final wasAllDone = allDone0;
    // 進度條要晚一拍才收束（讓它讀起來是「結果」而不是同拍的裝飾），
    // 所以要先記下按下去之前的值。
    final progressBefore = _displayProgress;
    final habit = habits[index];
    final wasHabitDone = habit['done'] == true;
    final isWeekly = (habit['frequency'] ?? 'daily') == 'weekly';
    final isWeightLinked = isWeightHabitName(habit['name'] as String?);
    if (!isWeekly &&
        isWeightLinked &&
        widget.weightHabitAutoComplete &&
        wasHabitDone) {
      playFeedback(SfxCue.tap);
      return;
    }
    if (isWeekly) {
      final today = todayString();
      final dates = List<String>.from((habit['weeklyDates'] as List?) ?? []);
      final target = (habit['weeklyTarget'] as int?) ?? 3;
      final weekSet = _currentWeekStrings().toSet();
      if (dates.where(weekSet.contains).length >= 20) return; // 上限 20 次/週
      dates.add(today);
      setState(() {
        habit['weeklyDates'] = dates;
        habit['done'] = dates.where(weekSet.contains).length >= target;
      });
      // 每週習慣每次累加都是一次打卡（減少時對稱扣回，刷不了幣）
      CoinService.award(CoinSource.habitDone, note: habit['name'] as String?);
      unawaited(UsageStats.bump(UsageEvents.habitCheck));
    } else {
      final wasDone = habit['done'] as bool;
      setState(() {
        habit['done'] = !wasDone;
      });
      if (wasDone) {
        // 撤銷要能中斷還沒播完的正向尾韻：過時的跳躍／星星／泡泡／語音
        // 一律不再發生（已經提交的資料照既有規則撤銷，不受影響）。
        _cancelCompletionPresentation();
        _showTransientMascot('sad');
      }
      // 打卡 +金幣／取消打卡對稱扣回
      if (wasDone) {
        CoinService.revoke(
          CoinSource.habitDone,
          note: habit['name'] as String?,
        );
      } else {
        CoinService.award(CoinSource.habitDone, note: habit['name'] as String?);
        unawaited(UsageStats.bump(UsageEvents.habitCheck));
      }
    }
    saveHabits();
    // 每日習慣的完成集合進歷史；每週走 weeklyDates，不在此記。
    if (!isWeekly) unawaited(_recordTodayHistory());
    if (!wasAllDone && allDone0) {
      // 跨進全完成：普通完成的演出立刻讓位，不能兩套 MI 反應疊著播。
      _cancelCompletionPresentation();
      // 當日全完成加碼（每日一次，service 內建防重複）
      CoinService.award(
        CoinSource.allHabitsDone,
        note: _l10n.hpCoinNoteAllDone,
      );
      playFeedback(SfxCue.complete);
      _celebCtrl.forward(from: 0);
      setState(() {
        _completionReactionStrength = 1.0;
        _mascotReactionTick++;
      });
      // 第一次全完成 → 回憶事件（冪等；揭曉由 MainPage 佇列稍後接手播）
      unawaited(StoryEvents.onFirstAllDone());
      _applyPersona(_baselineMascotContext);
    } else if (!isWeekly && !wasHabitDone && habits[index]['done'] == true) {
      // ★ 本次里程碑的主角：一件普通每日習慣完成，今天還沒做完。
      // 資料已經在上面提交，這裡只排「演出」的時間線。
      _startCompletionPresentation(progressBefore: progressBefore);
    } else if (habits[index]['done'] == true) {
      // 每週習慣剛好達標：交給既有的即時回饋，不走打卡編排。
      playFeedback(wasHabitDone ? SfxCue.tap : SfxCue.success);
      setState(() {
        _completionReactionStrength = 1.0;
        _mascotReactionTick++;
      });
      _applyPersona(_baselineMascotContext);
    } else if (isWeekly) {
      // 每週習慣累加但還沒達標：是正向操作，給 tap 不給 cancel
      playFeedback(SfxCue.tap);
      setState(() {
        _completionReactionStrength = 1.0;
        _mascotReactionTick++;
      });
      _applyPersona(_baselineMascotContext);
    } else {
      playFeedback(SfxCue.cancel);
      // 撤銷的 sad 已由上面的 _showTransientMascot 套用，不再重送一次。
    }
    if (habits[index]['name'] == _kWaterHabitPresetName) {
      widget.onWaterHabitToggled?.call(habits[index]['done'] as bool);
    }
  }

  // ── 一件普通每日習慣完成的演出 ─────────────────────────────
  // 資料在 toggleHabit 就提交完了；這一段只決定「裝飾在第幾毫秒發生」。
  // 時間線與各拍的職責見 completion_presentation_controller.dart。

  /// 打卡的小跳幅度。直接點兔咪是 1.0；打卡是高頻動作，克制到六成多，
  /// 才不會每完成一件都像在慶祝。
  static const double _kCompletionReactionStrength = 0.62;

  late final CompletionPresentationController _completion =
      CompletionPresentationController(onPhase: _onCompletionPhase);

  int _mascotNoticeTick = 0;
  int _mascotReactionCancelTick = 0;
  double _completionReactionStrength = 1.0;

  /// 進度條在衝擊點之前先按住的值；null = 直接跟著真實進度。
  /// **只影響動畫值**，「3 / 5」那個數字一律即時更新（那是事實不是演出）。
  double? _progressHold;

  /// 目前為止一共建立過幾個完成事件（一次 input 應該只 +1）。
  @visibleForTesting
  int get debugCompletionEventId => _completion.lastEventId;

  /// 目前有沒有一條 MI 動作弧線在跑（連打時應該共用同一條）。
  @visibleForTesting
  bool get debugCompletionArcActive => _completion.arcActive;

  double get _displayProgress {
    final daily = _dailyHabits;
    final total = daily.isNotEmpty ? daily.length : _weeklyHabits.length;
    if (habits.isEmpty || total == 0) return 0.0;
    final done = daily.isNotEmpty ? dailyDoneCount : weeklyMetCount;
    return done / total;
  }

  bool get _reduceMotion {
    final mq = MediaQuery.maybeOf(context);
    return mq?.disableAnimations == true || mq?.accessibleNavigation == true;
  }

  void _startCompletionPresentation({required double progressBefore}) {
    final doneNow = _dailyHabits.isNotEmpty ? dailyDoneCount : weeklyMetCount;
    final reduceMotion = _reduceMotion;
    if (!reduceMotion) setState(() => _progressHold = progressBefore);
    _completion.start(
      isFirstOfDay: doneNow == 1,
      doneCount: doneNow,
      reduceMotion: reduceMotion,
    );
  }

  /// 丟掉還沒播的正向裝飾，並讓已經在跑的動作收束。
  /// 已提交的習慣資料不受影響——撤銷是使用者的事，不是演出的事。
  void _cancelCompletionPresentation() {
    _completion.cancel();
    if (!mounted) return;
    setState(() {
      _progressHold = null;
      _mascotReactionCancelTick++;
    });
  }

  void _onCompletionPhase(CompletionPhase phase, HomeCompletionEvent event) {
    if (!mounted) return;
    switch (phase) {
      case CompletionPhase.confirm:
        // 資料已提交、卡片自己會開始描勾。這一拍刻意什麼都不做：
        // 使用者按下去的第一個回饋只該是 ink + 勾，不是音效或震動。
        break;
      case CompletionPhase.notice:
        setState(() => _mascotNoticeTick++);
      case CompletionPhase.anticipate:
        setState(() {
          _completionReactionStrength = _kCompletionReactionStrength;
          _mascotReactionTick++;
        });
      case CompletionPhase.impact:
        // 勾勾筆尖落點：全場唯一的觸覺與音效，換 pose，放開進度條。
        playFeedback(SfxCue.success, haptic: HapticLevel.light);
        if (_progressHold != null) setState(() => _progressHold = null);
        _applyPersona(
          MascotContext.completedOne,
          keepSpeech: true,
          silent: true,
          force: true,
        );
      case CompletionPhase.speak:
        // MI 已經動起來了才開口。當天第一件才有台詞與語音。
        if (event.isFirstOfDay) {
          setState(
            () => _transientSpeech = MascotLines.doneCountLine(event.doneCount),
          );
        }
        _applyPersona(
          MascotContext.completedOne,
          withVoice: event.isFirstOfDay,
          force: true,
        );
      case CompletionPhase.recover:
        // 落地：回到「目前進度」推導的 baseline（可能已經是 halfDone），
        // 但不再演一次——里程碑的完整反應要留給既有的高層級事件。
        _applyPersona(
          _baselineMascotContext,
          keepSpeech: true,
          silent: true,
          force: true,
        );
      case CompletionPhase.quiet:
        if (_transientSpeech == null) return;
        setState(() => _transientSpeech = null);
        _applyPersona(_baselineMascotContext, silent: true, force: true);
    }
  }

  void decrementWeeklyHabit(int index) {
    if (_mutationsBlocked || index >= habits.length) return;
    final habit = habits[index];
    final today = todayString();
    final dates = List<String>.from((habit['weeklyDates'] as List?) ?? []);
    final lastIdx = dates.lastIndexOf(today);
    if (lastIdx == -1) return;
    dates.removeAt(lastIdx);
    final target = (habit['weeklyTarget'] as int?) ?? 3;
    final weekSet = _currentWeekStrings().toSet();
    setState(() {
      habit['weeklyDates'] = dates;
      habit['done'] = dates.where(weekSet.contains).length >= target;
    });
    // 對稱扣回（對應 toggleHabit 的每週累加 +金幣）
    CoinService.revoke(CoinSource.habitDone, note: habit['name'] as String?);
    saveHabits();
    playFeedback(SfxCue.cancel);
    _cancelCompletionPresentation();
    _showTransientMascot('sad');
  }

  void deleteHabit(int index) {
    if (_mutationsBlocked || index >= habits.length) return;
    final habit = habits[index];
    final name = habit['name'] as String;
    final id = habit['id'] as String?;
    final createdAt = habit['createdAt'] as String?;
    final frequency = (habit['frequency'] ?? 'daily') as String;
    _animatedIn.remove(name);
    setState(() => habits.removeAt(index));
    final date = todayString();
    final remaining = habits.map(Map<String, dynamic>.from).toList();
    unawaited(saveHabits());
    // 留一筆墓碑：補打勾仍能顯示「當時存在、後來刪掉」的條目。
    // 同時刷新今天的歷史（刪掉的習慣不該再算在今天的完成集合裡）。
    if (id != null) {
      unawaited(
        _queueStorageWrite(() async {
          final prefs = await SharedPreferences.getInstance();
          await HabitHistory.addTombstone(
            prefs,
            id: id,
            name: name,
            frequency: frequency,
            createdAt: createdAt ?? date,
            deletedAt: date,
          );
          await _writeTodayHistory(prefs, remaining, date);
        }),
      );
    }
    if (name == _kWaterHabitPresetName) {
      unawaited(
        _queueStorageWrite(() async {
          final prefs = await SharedPreferences.getInstance();
          await _checkedPreferenceWrite(
            prefs,
            () => prefs.setBool(PrefsKeys.waterEnabled, false),
            PrefsKeys.waterEnabled,
          );
          if (mounted) widget.onSettingsChanged?.call();
        }),
      );
    } else if (isWeightHabitName(name)) {
      unawaited(
        _queueStorageWrite(() async {
          final prefs = await SharedPreferences.getInstance();
          await _checkedPreferenceWrite(
            prefs,
            () => prefs.setBool(PrefsKeys.weightTrackingEnabled, false),
            PrefsKeys.weightTrackingEnabled,
          );
          if (mounted) widget.onSettingsChanged?.call();
        }),
      );
    }
  }

  Future<void> renameHabit(int index) async {
    if (_mutationsBlocked || index >= habits.length) return;
    final generation = _reloadGeneration;
    final ctrl = TextEditingController(text: habits[index]['name'] as String);
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_l10n.hpRenameTitle),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLength: kHabitNameMaxLength,
          decoration: InputDecoration(labelText: _l10n.hsNameHint),
        ),
        actions: [
          dialogCancelAction(ctx, onPressed: () => Navigator.pop(ctx, false)),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(_l10n.commonSave),
          ),
        ],
      ),
    );
    final rawName = ctrl.text;
    ctrl.dispose();
    if (result != true ||
        !mounted ||
        _mutationsBlocked ||
        generation != _reloadGeneration ||
        index >= habits.length) {
      return;
    }
    final name = clampHabitName(rawName);
    if (name.isEmpty) return;
    setState(() => habits[index]['name'] = name);
    unawaited(saveHabits());
  }

  Future<void> _confirmDeleteHabit(int index) async {
    if (_mutationsBlocked || index >= habits.length) return;
    final generation = _reloadGeneration;
    final name = habits[index]['name'] as String;
    final confirm = await showAppConfirmDialog(
      context,
      title: _l10n.pmDeleteHabitTitle,
      message: _l10n.pmDeleteNamedMessage(name),
      confirmLabel: _l10n.commonDelete,
      danger: true,
    );
    if (confirm &&
        mounted &&
        !_mutationsBlocked &&
        generation == _reloadGeneration &&
        index < habits.length) {
      deleteHabit(index);
    }
  }

  Future<void> _editHabitSheet(int index) async {
    if (_mutationsBlocked || index >= habits.length) return;
    final generation = _reloadGeneration;
    await showEditHabitSheet(
      context,
      habit: habits[index],
      onSave: (newName, freq, weeklyTarget) {
        if (!mounted ||
            _mutationsBlocked ||
            generation != _reloadGeneration ||
            index >= habits.length) {
          return;
        }
        setState(() {
          habits[index]['name'] = newName;
          habits[index]['frequency'] = freq;
          if (freq == 'weekly') {
            habits[index]['weeklyTarget'] = weeklyTarget;
            habits[index].putIfAbsent('weeklyDates', () => <String>[]);
          } else {
            habits[index].remove('weeklyTarget');
            habits[index].remove('weeklyDates');
            habits[index]['done'] = false;
          }
        });
        saveHabits();
        unawaited(_recordTodayHistory());
      },
    );
  }

  Future<void> _showAddHabitSheet() async {
    if (_mutationsBlocked) return;
    final generation = _reloadGeneration;
    final existing = habits.map((h) => h['name'] as String).toSet();
    final available = kHomePresets.where((p) {
      if (p.defaultMinutes != null) {
        return !existing.any((n) => n == p.name || n.startsWith('${p.name} '));
      }
      return !existing.contains(p.name);
    }).toList();
    await showAddHabitSheet(
      context,
      available: available,
      onConfirm:
          (customName, customMinutes, freq, weeklyTarget, selected) async {
            if (!mounted ||
                _mutationsBlocked ||
                generation != _reloadGeneration) {
              return;
            }
            if (_mutationGate != null) {
              return;
            }

            // onConfirm 進入同步區段時立刻關上 mutation gate。整輪 reload 都會
            // 維持 _reloading=true，所以上面的 guard 已排除舊 load；新 load 與
            // 其他 mutator 則會被 gate 擋住。先等既有 storage tail 落地，再以
            // durable 狀態為基礎 commit。
            final gate = Completer<void>();
            _mutationGate = gate;
            _reloadGeneration++;
            _cancelMovingForReload();
            final expectedDayRevision = widget.dayStamp?.revision;
            var habitsCommitted = false;
            final shouldReconcileSettings = selected.keys.any((name) {
              final idx = available.indexWhere((p) => p.name == name);
              return idx != -1 && available[idx].linkedSetting != null;
            });
            try {
              await _storageTail;
              if (!mounted) return;
              await LogicalDayCoordinator.instance.synchronizeStorage(() async {
                if (expectedDayRevision != null &&
                    LogicalDayCoordinator.instance.stamp.value?.revision !=
                        expectedDayRevision) {
                  return;
                }
                final prefs = await SharedPreferences.getInstance();
                if (!mounted) return;

                final today = todayString();
                final next = habits.map(Map<String, dynamic>.from).toList();
                if (customName.isNotEmpty) {
                  final fullName = customMinutes > 0
                      ? _l10n.habitNameMinutes(customName, customMinutes)
                      : customName;
                  final map = <String, dynamic>{
                    'id': HabitHistory.newId(),
                    'name': fullName,
                    'createdAt': today,
                    'done':
                        isWeightHabitName(fullName) &&
                        widget.weightHabitAutoComplete,
                    'frequency': freq,
                  };
                  if (freq == 'weekly') {
                    map['weeklyTarget'] = weeklyTarget;
                    map['weeklyDates'] = <String>[];
                  }
                  next.add(map);
                }
                for (final entry in selected.entries) {
                  final p = available.firstWhere((p) => p.name == entry.key);
                  final cfg = entry.value;
                  final habitName =
                      (p.defaultMinutes != null && cfg.minutes > 0)
                      ? _l10n.habitNameMinutes(p.name, cfg.minutes)
                      : p.name;
                  final map = <String, dynamic>{
                    'id': HabitHistory.newId(),
                    'name': habitName,
                    'createdAt': today,
                    'done':
                        isWeightHabitName(habitName) &&
                        widget.weightHabitAutoComplete,
                    'frequency': cfg.frequency,
                  };
                  if (cfg.frequency == 'weekly') {
                    map['weeklyTarget'] = cfg.weeklyTarget;
                    map['weeklyDates'] = <String>[];
                  }
                  next.add(map);
                }

                await _checkedPreferenceWrite(
                  prefs,
                  () => prefs.setString(PrefsKeys.habits, jsonEncode(next)),
                  PrefsKeys.habits,
                );
                habitsCommitted = true;

                for (final name in selected.keys) {
                  final idx = available.indexWhere((p) => p.name == name);
                  if (idx == -1 || available[idx].linkedSetting == null) {
                    continue;
                  }
                  final key = available[idx].linkedSetting!;
                  if (prefs.getBool(key) ?? false) continue;
                  await _checkedPreferenceWrite(
                    prefs,
                    () => prefs.setBool(key, true),
                    key,
                  );
                }
                await _writeTodayHistory(prefs, next, today);
              });
            } catch (e, st) {
              // Sheet 已經關閉，async callback 的錯誤不能變成 unhandled Future。
              // 保留既有畫面；下次 reload 會從 durable storage 收斂。
              debugPrint('Add habit commit failed: $e\n$st');
            } finally {
              if (identical(_mutationGate, gate)) _mutationGate = null;
              if (!gate.isCompleted) gate.complete();
            }

            if (!habitsCommitted || !mounted) return;
            await loadHabits();
            if (!mounted) return;
            if (shouldReconcileSettings) widget.onSettingsChanged?.call();
            // 第一個習慣誕生的當下就觸發回憶事件（冪等，之後再加都是 no-op）
            if (habits.isNotEmpty) {
              unawaited(StoryEvents.onFirstHabitCreated());
            }
          },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final colors = _sceneColors;
    final sceneProgress = habits.isEmpty ? 0.0 : doneCount / habits.length;
    // 背景場景高度改吃「螢幕寬」等比（房間圖 cover-by-width，地板線只跟寬走）。
    // 14PM（寬 430）時 == 舊的 screenH×0.56，對作者實機零位移。
    final bgH = roomSceneHeight(MediaQuery.of(context).size.width);
    // 從別的分頁切回首頁時（外層 TickerMode 由 false→true）喚醒裝飾場景。
    final visible = TickerMode.valuesOf(context).enabled;
    if (visible && !_wasVisible) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _markSceneActive();
      });
    }
    // 切走分頁：還沒播的打卡演出直接作廢。看不到兔咪卻聽到牠出聲、或切回來
    // 才補播一次舊的完成反應，都是錯的。
    if (!visible && _wasVisible && _completion.arcActive) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _cancelCompletionPresentation();
      });
    }
    _wasVisible = visible;
    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: Colors.transparent,
      appBar: MascotAppBar(
        accent: colors.accent,
        onSettingsReturn: () => widget.onSettingsChanged?.call(),
      ),
      // 任何觸碰都視為互動：取消閒置凍結、重排計時。translucent 才不會
      // 攔掉底下卡片/兔咪的點擊。
      body: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) => _markSceneActive(),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 600),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [colors.top, colors.bottom],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
          child: Stack(
            children: [
              // 四時段完整背景：天色/窗光/檯燈/長影全部由圖承擔，交界走
              // SceneTimeController 分鐘級 crossfade（無動畫幀成本）。
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: bgH,
                child: FourPeriodBackground(assets: FourPeriodRoom.home.assets),
              ),
              // 全完成慶祝罩（時段氛圍已由背景圖承擔，這層只剩狀態回饋）。
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: bgH,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 600),
                  color: _sceneTint,
                ),
              ),
              // 空氣層：清晨窗光塵埃＋夜晚星光眨眼（20fps 共享時鐘，
              // 閒置凍結一起停）。
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: bgH,
                child: TickerMode(
                  enabled: !_sceneIdle,
                  child: SceneAirLayer(
                    clock: _sceneClock.time,
                    spec: FourPeriodRoom.home.air,
                  ),
                ),
              ),
              // 全完成的星光慶祝層：只在全完成時掛載。
              if (allDone0 && habits.isNotEmpty)
                Positioned.fill(
                  child: TickerMode(
                    enabled: !_sceneIdle,
                    child: RoomSceneEffects(
                      accent: colors.accent,
                      progress: sceneProgress.clamp(0.0, 1.0),
                      clock: _sceneClock.time,
                    ),
                  ),
                ),
              // 內容
              SafeArea(child: _buildMascotScene()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMascotScene() {
    final colors = _sceneColors;
    final dl = _dailyHabits;
    final displayDone = dl.isNotEmpty ? dailyDoneCount : weeklyMetCount;
    final displayTotal = dl.isNotEmpty ? dl.length : _weeklyHabits.length;
    final progress = habits.isEmpty ? 0.0 : displayDone / displayTotal;

    return MascotPageShell(
      accent: colors.accent,
      sceneHeight: sceneRegionHeightAnchored(
        MediaQuery.of(context).size.width,
        MediaQuery.of(context).padding.top,
      ),
      scene: ScaleTransition(
        scale: _celebScale,
        child: PersonaScene(
          accent: colors.accent,
          reactionTick: _mascotReactionTick,
          noticeTick: _mascotNoticeTick,
          reactionStrength: _completionReactionStrength,
          reactionCancelTick: _mascotReactionCancelTick,
          // 打卡台詞是短尾韻，自己淡出後才被清掉（不是硬切）。
          speechVisibleDuration: const Duration(milliseconds: 2200),
          onTap: _onMascotTap,
          onHeadPet: _onMascotHeadPet,
          paused: _sceneIdle, // 閒置時連兔咪呼吸/眨眼一起凍結 → 畫面全靜止
          // 四時段色溫＋接地影融合；compile-time 開關只供 A/B 對照。
          lightGeometry: _kHomeMascotFusionEnabled
              ? FourPeriodRoom.home.light
              : null,
        ),
      ),
      child: _habitCardContent(
        progress: progress,
        displayDone: displayDone,
        displayTotal: displayTotal,
        accent: colors.accent,
      ),
    );
  }

  /// 把首頁當下的立繪 + 指定語意送進全域 [MascotPersona]。
  ///
  /// **情境由呼叫端負責**：同一個畫面狀態可能是「剛完成一件」也可能是
  /// 「使用者點了兔咪」，語意不該從 transient 欄位反推。
  /// [silent] 用在同一個事件的中間拍與收尾拍（換姿勢但不再演一次）。
  /// [keepSpeech] 讓那些中間拍不要把兔咪**原本正在說的話**砍掉——打卡不該
  /// 讓一句還沒講完的開場問候憑空消失，再空兩百毫秒才冒出新的一句。
  bool _applyPersona(
    MascotContext ctx, {
    String? speech,
    bool keepSpeech = false,
    bool silent = false,
    bool withVoice = true,
    bool force = false,
  }) {
    return MascotPersona.setForContext(
      _mascotAsset,
      ctx,
      speech:
          speech ??
          _transientSpeech ??
          (keepSpeech ? MascotPersona.current.value.speech : null),
      silent: silent,
      withVoice: withVoice,
      force: force,
    );
  }

  Widget _habitCardContent({
    required double progress,
    required int displayDone,
    required int displayTotal,
    required Color accent,
  }) {
    final reached = displayTotal > 0 && displayDone >= displayTotal;
    // 達標時亮點呼吸，未達標時停住歸零（在 build 同步狀態，含載入時）
    if (reached && !_glowCtrl.isAnimating) {
      _glowCtrl.repeat(reverse: true);
    } else if (!reached && _glowCtrl.isAnimating) {
      _glowCtrl
        ..stop()
        ..value = 0;
    }
    return Column(
      children: [
        if (habits.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Row(
              children: [
                Expanded(
                  child: TweenAnimationBuilder<double>(
                    // 打卡瞬間先按住舊值，等勾勾觸底（impact）才放開：
                    // 進度收束是「結果」，跟輸入同拍反而讀不出因果。
                    tween: Tween(begin: 0.0, end: _progressHold ?? progress),
                    duration: const Duration(milliseconds: 460),
                    curve: Curves.easeOutCubic,
                    builder: (_, value, _) => _ProgressBar(
                      value: value,
                      accent: accent,
                      glow: _glowCtrl,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                // 達標時數字升級成綠色膠囊＋勾，給一個小小的完成獎勵
                AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: reached ? Colors.green.shade50 : Colors.transparent,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (reached) ...[
                        Icon(
                          Icons.check_circle_rounded,
                          size: 13,
                          color: Colors.green.shade500,
                        ),
                        const SizedBox(width: 3),
                      ],
                      Text(
                        '$displayDone / $displayTotal',
                        style: AppType.digits(
                          color: reached ? Colors.green.shade700 : accent,
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 8),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: _editMode ? _buildMoveDoneBar() : _buildAddButton(),
        ),
        const SizedBox(height: 12),
        Expanded(child: _buildHabitList()),
      ],
    );
  }

  // 房間背景上的慶祝色罩：時段氛圍已由四時段完整背景承擔（計劃書原則：
  // 圖畫好的不再堆色罩），這層只保留「全完成」的暖光狀態回饋。
  Color get _sceneTint {
    if (allDone0 && habits.isNotEmpty) {
      return const Color(0xFFFFF3C4).withValues(alpha: 0.10);
    }
    return Colors.transparent;
  }

  // 場景配色：四時段權重連續混色（晨粉金 / 晝暖白 / 暮金橘 / 夜暖燈）；
  // 全完成的綠色慶祝主題維持覆蓋（短暫的狀態回饋，優先於時段）。
  ({Color top, Color bottom, Color accent}) get _sceneColors {
    if (allDone0 && habits.isNotEmpty) {
      return (
        top: const Color(0xFFE8F8E5),
        bottom: const Color(0xFFCDEFCD),
        accent: const Color(0xFF66BB6A),
      );
    }
    final s = SceneTimeController.instance.state;
    return (
      top: s.blendOpaque(
        morning: const Color(0xFFFFF6EA),
        day: const Color(0xFFFFF4E0),
        dusk: const Color(0xFFFFEACF),
        night: const Color(0xFFFFF4E8),
      ),
      bottom: s.blendOpaque(
        morning: const Color(0xFFFFE0C5),
        day: const Color(0xFFFFE5C7),
        dusk: const Color(0xFFF1C9A8),
        night: const Color(0xFFEED8C4),
      ),
      accent: s.blendOpaque(
        morning: const Color(0xFFF08A62),
        day: const Color(0xFFFF8A50),
        dusk: const Color(0xFFC47A52),
        night: const Color(0xFFC28A55),
      ),
    );
  }

  Widget _buildAddButton() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _showAddHabitSheet,
          borderRadius: BorderRadius.circular(16),
          splashColor: Colors.orange.withValues(alpha: 0.15),
          highlightColor: Colors.orange.withValues(alpha: 0.08),
          child: Ink(
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFFFF8EC), Color(0xFFFFEFDA)],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.orange.withValues(alpha: 0.35)),
            ),
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: Colors.orange.shade400,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.add, size: 16, color: Colors.white),
                ),
                const SizedBox(width: 10),
                Text(
                  _l10n.hsAddTitle,
                  style: TextStyle(
                    color: Colors.orange.shade800,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // 編輯模式下「新增習慣」鈕原地換成的完成鈕：外框／大小與 _buildAddButton
  // 完全一致（同 gradient／border／radius／padding），只有 icon＋文字內容不同。
  // 整顆可點＝退出排序。
  Widget _buildMoveDoneBar() {
    return Padding(
      key: const ValueKey('move_done_bar'),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _finishMovingHabits,
          borderRadius: BorderRadius.circular(16),
          splashColor: Colors.white.withValues(alpha: 0.18),
          highlightColor: Colors.white.withValues(alpha: 0.10),
          child: Ink(
            // 外框（圓角 16／尺寸／padding）與新增習慣鈕一致；填色換成綠色：
            // 綠＝「完成/確認」且和橘色系首頁對比強，最醒目、和新增鈕徹底區分。
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.green.shade500, Colors.green.shade600],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.green.withValues(alpha: 0.40)),
            ),
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 24,
                  height: 24,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.check_rounded,
                    size: 16,
                    color: Colors.green.shade600,
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  _l10n.wdDoneSort,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHabitList() {
    if (habits.isEmpty) return _buildEmptyState();

    final dailyEntries = habits
        .asMap()
        .entries
        .where((e) => (e.value['frequency'] ?? 'daily') != 'weekly')
        .toList();
    final weeklyEntries = habits
        .asMap()
        .entries
        .where((e) => (e.value['frequency'] ?? 'daily') == 'weekly')
        .toList();

    Widget buildCard(MapEntry<int, Map<String, dynamic>> entry) {
      final index = entry.key;
      final habit = entry.value;
      final name = habit['name'] as String;
      final alreadyShown = _animatedIn.contains(name);
      _animatedIn.add(name);
      return TweenAnimationBuilder<double>(
        key: ValueKey('anim_$name'),
        tween: Tween(begin: alreadyShown ? 1.0 : 0.0, end: 1.0),
        duration: Duration(milliseconds: alreadyShown ? 0 : 220 + index * 55),
        curve: Curves.easeOut,
        builder: (_, v, child) => Opacity(
          opacity: v,
          child: Transform.translate(
            offset: Offset(0, 16 * (1 - v)),
            child: child,
          ),
        ),
        child: HabitCard(
          key: ValueKey(name),
          habit: habit,
          onToggle: () => toggleHabit(index),
          onEdit: () => _editHabitSheet(index),
          onDelete: () => _confirmDeleteHabit(index),
          isWeekly: (habit['frequency'] ?? 'daily') == 'weekly',
          weeklyCount: _weeklyCount(habit),
          weeklyTarget: (habit['weeklyTarget'] as int?) ?? 3,
          todayCount: List<String>.from(
            (habit['weeklyDates'] as List?) ?? [],
          ).where((d) => d == todayString()).length,
          onDecrement: (habit['frequency'] ?? 'daily') == 'weekly'
              ? () => decrementWeeklyHabit(index)
              : null,
          isLinked:
              kHomePresets.any(
                (p) => p.linkedSetting != null && habit['name'] == p.name,
              ) ||
              isWeightHabitName(habit['name'] as String?),
          isMoving: _editMode,
          onMove: _startMovingHabits,
        ),
      );
    }

    // 拖曳代理：被抬起的卡片放大 + 投影
    Widget proxyDecorator(
      Widget child,
      int index,
      Animation<double> animation,
    ) {
      return AnimatedBuilder(
        animation: animation,
        builder: (_, _) => Transform.scale(
          scale: 1 + animation.value * 0.035,
          child: Material(
            color: Colors.transparent,
            elevation: 10 * animation.value,
            shadowColor: const Color(0xFF8D6E63).withValues(alpha: 0.30),
            borderRadius: BorderRadius.circular(AppCardStyle.radius),
            child: child,
          ),
        ),
      );
    }

    // 每段獨立的 sliver reorderable。拖曳辨識器一直存在：未進編輯模式時走
    // 「長按啟動拖曳」（同一手勢長按完直接滑，不必放手重抓），進模式後即時拖。
    // 進入抖動模式由 onReorderStart 觸發。拖到上下緣會帶外層自動捲動；daily/weekly 不互拖。
    Widget sectionSliver({
      required bool weekly,
      required List<MapEntry<int, Map<String, dynamic>>> entries,
    }) {
      return SliverReorderableList(
        itemCount: entries.length,
        proxyDecorator: proxyDecorator,
        onReorderStart: (_) {
          if (_mutationsBlocked) return;
          final dragGeneration = _reloadGeneration;
          if (_editMode) {
            if (_reorderGeneration == _reloadGeneration) {
              playFeedback(SfxCue.tap);
            }
          } else {
            // 首次長按拖曳：本幀後再翻成編輯模式，避免拖曳啟動當下重建清單
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                _startMovingHabits(expectedGeneration: dragGeneration);
              }
            });
          }
        },
        onReorder: (oldIndex, newIndex) => _reorderHabitSection(
          weekly: weekly,
          oldIndex: oldIndex,
          newIndex: newIndex,
        ),
        itemBuilder: (_, i) {
          final entry = entries[i];
          final habit = entry.value;
          return _HabitDragListener(
            key: ValueKey(
              'reorder_${weekly ? 'weekly' : 'daily'}_${habit['name']}',
            ),
            index: i,
            immediate: _editMode,
            child: _Jiggle(
              animation: _jiggleCtrl,
              enabled: _editMode,
              seed: (habit['name'] as String).hashCode,
              child: buildCard(entry),
            ),
          );
        },
      );
    }

    return CustomScrollView(
      slivers: [
        if (dailyEntries.isNotEmpty) ...[
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: SliverToBoxAdapter(
              child: HabitSectionHeader(
                label: _l10n.htDailyHabits,
                icon: Icons.wb_sunny_rounded,
                color: Colors.orange,
                done: dailyDoneCount,
                total: _dailyHabits.length,
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: sectionSliver(weekly: false, entries: dailyEntries),
          ),
        ],
        if (weeklyEntries.isNotEmpty) ...[
          if (dailyEntries.isNotEmpty)
            const SliverToBoxAdapter(child: SizedBox(height: 20)),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: SliverToBoxAdapter(
              child: HabitSectionHeader(
                label: _l10n.htWeeklyHabits,
                icon: Icons.calendar_view_week_rounded,
                color: Colors.indigo,
                done: weeklyMetCount,
                total: _weeklyHabits.length,
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: sectionSliver(weekly: true, entries: weeklyEntries),
          ),
        ],
        const SliverToBoxAdapter(child: SizedBox(height: 24)),
      ],
    );
  }

  // 空狀態：淡入＋上浮，視覺語言對齊喝水頁的「今天還沒有補水紀錄」
  Widget _buildEmptyState() {
    final accent = _sceneColors.accent;
    return Center(
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0.0, end: 1.0),
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeOut,
        builder: (_, v, child) => Opacity(
          opacity: v,
          child: Transform.translate(
            offset: Offset(0, 12 * (1 - v)),
            child: child,
          ),
        ),
        // FittedBox：兔咪面板展開時卡片高度有限，等比縮小避免 overflow
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(32, 0, 32, 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.10),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.spa_rounded, size: 30, color: accent),
                ),
                const SizedBox(height: 14),
                Text(
                  _l10n.hpEmptyTitle,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: AppInk.strong,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  _l10n.hpEmptySub,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 13,
                    height: 1.5,
                    fontWeight: FontWeight.w500,
                    color: AppInk.soft,
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

/// 一輪載入讀出來的完整結果。`_readSnapshot` 產生、`_applySnapshot` 消費，
/// 中間不碰任何 widget 狀態——這是「reload 期間畫面維持上一份清單」的前提。
class _HomeSnapshot {
  final int dayStartHour;

  /// 這份快照對應的邏輯日（yyyy-MM-dd）。
  final String logicalDate;
  final List<Map<String, dynamic>> habits;
  final int streak;
  final String nickname;
  final String mascotName;
  final DateTime? userBirthday;
  final DateTime? onboardingDate;
  final bool yesterdayAllDone;

  /// 這輪對應的跨日 transition id；null = 這次沒有跨日，不問候。
  final String? transitionId;

  /// 覆寫 lastOpenDate 之前的舊值；問候語要靠它算久違天數。
  final String? previousOpenDate;

  const _HomeSnapshot({
    required this.dayStartHour,
    required this.logicalDate,
    required this.habits,
    required this.streak,
    required this.nickname,
    required this.mascotName,
    required this.userBirthday,
    required this.onboardingDate,
    required this.yesterdayAllDone,
    required this.transitionId,
    required this.previousOpenDate,
  });
}

class _HomeLoadResult {
  final int trigger;
  final bool applied;
  final Object? error;
  final StackTrace? stackTrace;

  const _HomeLoadResult._({
    required this.trigger,
    required this.applied,
    this.error,
    this.stackTrace,
  });

  const _HomeLoadResult.success(int trigger)
    : this._(trigger: trigger, applied: true);

  const _HomeLoadResult.cancelled(int trigger)
    : this._(trigger: trigger, applied: false);

  const _HomeLoadResult.failed(int trigger, Object error, StackTrace stackTrace)
    : this._(
        trigger: trigger,
        applied: false,
        error: error,
        stackTrace: stackTrace,
      );
}

class _StaleHomeLoad implements Exception {
  const _StaleHomeLoad();
}

// 編輯模式下每張卡片的「Q 版抖動」：監聽 _HomePageState 共用的 _jiggleCtrl
// （無自己的 ticker），依名字 hash 給不同相位/方向，看起來像 iOS 主畫面長按 App
// 那樣整列在輕輕晃。enabled=false 時零成本直通。共用 ticker 讓被拖曳的卡片
// reparent 時不會帶著正在跑的 ticker，避開 element 生命週期崩潰。
class _Jiggle extends StatelessWidget {
  final Animation<double> animation;
  final bool enabled;
  final int seed;
  final Widget child;

  const _Jiggle({
    required this.animation,
    required this.enabled,
    required this.seed,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final direction = seed.isEven ? 1.0 : -1.0;
    final phaseOffset = (seed.abs() % 100) / 100 * math.pi * 2;
    // AnimatedBuilder 永遠存在（結構穩定）：停用時 builder 直接回傳 child、
    // controller 停在 0 不重繪；啟用時才套抖動 transform。
    return AnimatedBuilder(
      animation: animation,
      child: child,
      builder: (_, child) {
        if (!enabled) return child!;
        final phase = animation.value * math.pi * 2 + phaseOffset;
        final sway = math.sin(phase);
        final bounce = math.sin(phase + math.pi / 2);
        final squash = math.sin(phase + math.pi);
        // 抖動幅度：旋轉是主要訊號（~0.8°），位移/擠壓小幅跟上
        return Transform.translate(
          offset: Offset(direction * sway * 0.5, bounce * 0.9),
          child: Transform.rotate(
            angle: direction * sway * 0.014,
            child: Transform.scale(
              scaleX: 1 + squash * 0.005,
              scaleY: 1 - squash * 0.0035,
              child: child,
            ),
          ),
        );
      },
    );
  }
}

// 拖曳啟動辨識器：未進編輯模式用 Delayed（長按啟動，同一手勢直接拖）；
// 進模式後用 Immediate（觸碰即拖）。同一 widget 型別、只換 recognizer，
// 不會在拖曳途中替換 element 破壞 SliverReorderableList 的 GlobalKey reparent。
class _HabitDragListener extends ReorderableDragStartListener {
  final bool immediate;

  const _HabitDragListener({
    super.key,
    required super.child,
    required super.index,
    required this.immediate,
  });

  @override
  MultiDragGestureRecognizer createRecognizer() {
    return immediate
        ? ImmediateMultiDragGestureRecognizer(debugOwner: this)
        : DelayedMultiDragGestureRecognizer(
            // 預設 kLongPressTimeout(500ms) 太靈敏，滑一下容易誤觸進排序。
            // 拉長到 1 秒；每週卡的「按住綠波紋」也用這個常數，填滿即進排序。
            delay: kHabitDragHoldDelay,
            debugOwner: this,
          );
  }
}

// 進度列：漸層填色 + 尾端亮點；達標時亮點隨 [glow] 呼吸發光
class _ProgressBar extends StatelessWidget {
  final double value;
  final Color accent;
  final Animation<double> glow;

  const _ProgressBar({
    required this.value,
    required this.accent,
    required this.glow,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 14,
      child: LayoutBuilder(
        builder: (_, constraints) {
          final w = constraints.maxWidth;
          final x = (w * value).clamp(0.0, w);
          return Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.centerLeft,
            children: [
              Container(
                height: 6,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              Container(
                height: 6,
                width: x,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [accent.withValues(alpha: 0.72), accent],
                  ),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              if (value > 0.03)
                AnimatedBuilder(
                  animation: glow,
                  builder: (_, _) => Positioned(
                    left: (x - 5).clamp(0.0, w - 10),
                    child: Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        border: Border.all(color: accent, width: 2.5),
                        boxShadow: [
                          BoxShadow(
                            color: accent.withValues(
                              alpha: 0.35 + 0.30 * glow.value,
                            ),
                            blurRadius: 4 + 6 * glow.value,
                            spreadRadius: 0.5 + 1.5 * glow.value,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
