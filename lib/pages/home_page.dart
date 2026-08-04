// 首頁（每日／每週習慣打卡 + 兔咪場景）。
// 其餘部分拆在 home/：習慣卡片、新增／編輯 bottom sheet、preset 定義、
// 問候橫幅、共用小元件與場景 painter。
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
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
import 'home/home_speech_owner.dart';
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

  /// 上一次看到的 Reduce Motion 狀態；用來偵測**執行中**被打開。
  bool _lastReduceMotion = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 系統偏好可以在 app 執行中被切換（設定 App 就在旁邊）。開啟的那一刻，
    // 正在播的全完成慶祝必須當場停住——只保留資料、靜態立繪、台詞與音效。
    // MediaQuery 改變本來就會走到這裡，不需要另外掛 observer。
    final reduce = _reduceMotion;
    if (reduce == _lastReduceMotion) return;
    _lastReduceMotion = reduce;
    if (!reduce) return;
    _celebCtrl.stop();
    _celebCtrl.value = 0; // TweenSequence 的 0 就是原尺寸，不留半路的縮放
    // 進度列尾端的光暈：停住並歸零。`_habitCardContent` 每次 build 也會
    // 同步一次，但那段在載入中不會跑到——這裡先把它關掉，controller 就
    // 不會在背景繼續排幀。
    _glowCtrl
      ..stop()
      ..value = 0;
  }

  @override
  void dispose() {
    SceneTimeController.instance.removeListener(_handleSceneTimeChanged);
    MascotPersona.current.removeListener(_handleMascotActivity);
    if (MascotPersona.idleBaseline == _idleMascotState) {
      MascotPersona.idleBaseline = null;
    }
    _sceneIdleTimer?.cancel();
    // 收掉排程與**仍然由 Home 擁有的**全域兔咪狀態。dispose 不能 setState，
    // 所以走不依賴 rebuild 的那條路；資料一律不動，收據不符則整段 no-op。
    _cancelCompletionSchedules();
    _releaseHomePersona();
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
    // **重載一開始**就作廢舊演出，不等到快照真的換上去。storage 上鎖或
    // 等待期間可能有好幾百毫秒，那段時間不該再冒出舊的 impact／音效／台詞。
    _invalidateCompletionPresentation();
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
    // 作廢已經在 loadHabits 開頭做過了（不等快照換上去）；這裡只處理
    // 跨日才需要的額外清理。
    if (dayChanged) {
      _transientMascotSeq++;
      _transientMascotTimer?.cancel();
      _transientMascotTimer = null;
      _transientSpeechTimer?.cancel();
      _transientSpeechTimer = null;
      _speechOwner = null;
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
    if (dayChanged) _requestNewDayNeutral();
  }

  // ── 換日的 Persona settlement：順序無關的交易 ─────────────────
  //
  // 一次 reload 會產生兩件事，而它們的先後**沒有保證**：
  //
  //   * 收拾舊 Home 狀態（可能同步、也可能被推到 post-frame）；
  //   * 套用新快照（storage 的 async 續體，可能先到也可能後到）。
  //
  // 舊版把中間結果放在一個全域欄位上做「兩階段橋接」，於是：snapshot 先到
  // 時沒有收據可用，那個需求就整個被丟掉（兔咪停在昨天的姿勢）；而遲到的
  // stale 收拾又會把**新一輪**的收據擦掉。
  //
  // 改成一筆交易：兩邊的結果寫在同一個物件上，誰後到誰負責收尾。stale 的
  // callback 只認得自己那一筆，寫不到現行的那一筆。

  /// 目前這一輪的 settlement 交易。
  _PersonaSettlement? _settlement;
  int _settlementSeq = 0;

  /// 開一筆新交易，並讓舊的那一筆明確作廢——但**先把它還欠著的責任接過來**。
  ///
  /// 「明確 supersede」而不是「等收據自然對不上」：新一輪已經接手了，舊那筆
  /// 遲到的 callback 不該再寫任何東西。可是 supersede 不等於「那些事不用做
  /// 了」：舊那筆可能還握著一份**捕捉好、卻還沒執行**的收拾責任（deferred
  /// cleanup 排在 post-frame，本地欄位卻已經清空），也可能已經記下了「這次
  /// 快照是新的一天」。第二次 `loadHabits()` 進來時它自己拿不到 claim，
  /// 若直接把舊那筆丟掉，那份收拾就永遠不會發生。
  ///
  /// 所以交接是**原子的**：claim、lease、cleanup duty、settled receipt 與
  /// needsNeutral 一起搬到新的一筆上，舊那筆從此純粹是 no-op。每份捕捉到的
  /// Home claim/lease 仍然最多只清理一次，而且一律 compare-gated。
  _PersonaSettlement _beginSettlement({
    required MascotClaim? claim,
    required MascotSpeechLease? lease,
  }) {
    final previous = _settlement;
    previous?.superseded = true;
    var handedClaim = claim;
    var handedLease = lease;
    var cleanupDone = false;
    MascotClaim? receipt;
    // 換日的中性收尾是**累積**的需求：它可能在上一筆交易身上就登記過了，
    // 不能因為換了一筆交易就消失。
    final needsNeutral =
        previous != null && previous.needsNeutral && !previous.neutralDone;

    if (claim == null && previous != null) {
      if (!previous.cleanupDone) {
        // 上一筆還欠著一次收拾：把它捕捉到的那份 claim／lease 整組接過來。
        handedClaim = previous.claim;
        handedLease = previous.lease;
      } else {
        // 上一筆已經收完：接手它的收據，換日才有東西可以再往前收一格。
        // compare-gated——中間只要有人寫過就對不上，這一筆就什麼都不帶。
        final inherited = previous.settledReceipt;
        if (inherited != null && MascotPersona.claim == inherited) {
          cleanupDone = true;
          receipt = inherited;
        }
      }
    }

    final settlement =
        _PersonaSettlement(
            id: ++_settlementSeq,
            generation: _presentationGeneration,
            claim: handedClaim,
            lease: handedLease,
          )
          ..cleanupDone = cleanupDone
          ..settledReceipt = receipt
          ..needsNeutral = needsNeutral;
    _settlement = settlement;
    return settlement;
  }

  /// 收拾階段結束（成功或失敗都算），並看看要不要接著做新一天的中性收尾。
  void _completeSettlement(
    _PersonaSettlement settlement, {
    required MascotClaim? receipt,
  }) {
    // stale：更新的一輪已經接手。**只**放棄自己這一筆，絕不改寫別人的。
    if (settlement.superseded) return;
    // 已經有結果了（例如接手了上一筆的收據）：不得被之後的 null 蓋掉。
    if (settlement.cleanupDone) return;
    settlement.cleanupDone = true;
    settlement.settledReceipt = receipt;
    _maybeSettleNeutral(settlement);
  }

  /// Home 同步收拾自己成功（撤銷結束、開新弧線前放掉舊佔用）：
  /// 用一筆已經完成收拾的交易持有那張收據，換日才有東西可以接著收。
  void _recordOwnSettlement(MascotClaim receipt) {
    final settlement = _beginSettlement(claim: null, lease: null)
      ..cleanupDone = true
      ..settledReceipt = receipt;
    _maybeSettleNeutral(settlement);
  }

  /// 這次快照是新的一天：交易要在收拾完成之後把姿勢收成中性。
  ///
  /// 兔咪要從昨天的情緒（例如全完成的開心臉）回到中性，否則 MI 的基準會和
  /// 歸零後的進度對不上。同日 reload 不動，免得打斷使用者剛剛的互動演出。
  ///
  /// **不是** `resetToIdle()`：那是無條件的全域重設，會建立一份新的開場問候
  /// 租約並把還沒講完的問候文字一起清掉。開場問候的狀態擁有權與台詞租約是
  /// 分開的兩條壽命（[MascotStateOrigin] / [MascotSpeechLease]），跨日只有資格
  /// 動自己那一半：
  ///
  /// - **狀態**：走 compare-and-clear。相符才收，不符（其他分頁接手、新一代
  ///   Home 已經寫過）就整段 no-op，絕不覆寫別人。
  /// - **台詞**：一個字都不碰。整份租約（來源、絕對期限、計時器）原封不動；
  ///   Home 自己那句已經由 [_invalidateCompletionPresentation] 依租約收掉了。
  void _requestNewDayNeutral() {
    // Home 此刻就握著活的擁有權（同步收拾那條路）：直接用它開一筆已完成
    // 收拾的交易，不必等任何 callback。
    final live = _personaStillOurs ? _personaClaim : null;
    if (live != null) {
      final settlement = _beginSettlement(claim: live, lease: _speechLease)
        ..needsNeutral = true;
      _completeSettlement(settlement, receipt: live);
      return;
    }
    final settlement = _settlement;
    if (settlement == null ||
        settlement.superseded ||
        settlement.generation != _presentationGeneration) {
      return;
    }
    // 收拾還沒回來也照樣登記：需求不能因為 callback 還沒到就被丟掉，
    // 那正是「snapshot 先到就停在昨天姿勢」的成因。
    settlement.needsNeutral = true;
    _maybeSettleNeutral(settlement);
  }

  /// 交易的收尾：兩個階段都到齊了才做，所以誰先誰後都收斂到同一個結果。
  ///
  /// 在 build 階段（跨日是從 `MainPage` 的重建流下來的）連同收據與立繪一起
  /// 推到這一幀之後——這一步會通知全域 notifier。
  void _maybeSettleNeutral(_PersonaSettlement settlement) {
    if (settlement.superseded) return;
    if (!settlement.needsNeutral || settlement.neutralDone) return;
    if (!settlement.cleanupDone) return;
    final receipt = settlement.settledReceipt;
    // 收拾失敗（external 或新一代 Home 接手）：交易到此為止，不覆寫別人，
    // 也不留下一張可以復活的收據。
    if (receipt == null) {
      settlement.neutralDone = true;
      return;
    }
    // 新的一天回到的是「開 app 的中性臉」，不是由進度推導的 baseline：
    // 進度剛歸零，睡臉／夜晚臉是給「今天還沒開始」的情境用的，跨日這一刻
    // 只需要一個乾淨的起點。
    const asset = MascotEmotion.neutralFront;
    if (_inBuildPhase) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _applyNewDayNeutral(settlement, asset.assetPath);
      });
      return;
    }
    _applyNewDayNeutral(settlement, asset.assetPath);
  }

  /// 純函式式的那一步：只用交易自己捕捉到的收據與立繪，不讀任何會在延後
  /// 期間變動的欄位。首頁監聽全域狀態時會順手喚醒場景時鐘；自動跨日沒有
  /// 使用者互動（可能是凌晨四點），不該把畫面叫醒。
  void _applyNewDayNeutral(_PersonaSettlement settlement, String asset) {
    if (settlement.superseded || settlement.neutralDone) return;
    final receipt = settlement.settledReceipt;
    if (receipt == null) return;
    settlement.neutralDone = true;
    _suppressSceneWake = true;
    try {
      if (MascotPersona.clearStateIfClaim(receipt, assetPath: asset)) {
        settlement.settledReceipt = MascotPersona.claim;
      }
    } finally {
      _suppressSceneWake = false;
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
  // 對話泡泡內的文字（點兔咪／打卡時暫時覆蓋）
  String? _transientSpeech;
  Timer? _transientMascotTimer;
  Timer? _transientSpeechTimer;
  int _mascotReactionTick = 0;

  // ── 擁有權（誰有資格清掉現在這句話／這個 transient）──
  //
  // 兩件事必須分開，否則收拾會漏：
  //
  //   * **台詞擁有權**（[_speechOwner]）：畫面上那句話是誰的。沒有台詞的
  //     普通完成根本不會有 owner。
  //   * **整體 persona 擁有權**（[_personaClaim]）：Home 上一次成功寫進全域
  //     的收據。就算那次寫入沒有台詞，姿勢、泡泡與停留狀態仍然是 Home 的。
  //
  // 舊版只有一個欄位，於是「有沒有台詞」被當成「Home 有沒有擁有 persona」；
  // speech 為 null 的完成在切分頁、換快照、跨日、dispose 時就沒人收，
  // Home 寫的姿勢會一路留到全域十秒回神。
  HomeSpeechToken? _speechOwner;

  /// Home 上一次**成功**寫入全域 [MascotPersona] 的收據（與有沒有台詞無關）。
  /// 相等 = 這中間沒有別人寫過，Home 仍然擁有畫面上那個兔咪狀態。
  MascotClaim? _personaClaim;

  /// Home 上一次**自己寫下那句台詞**時拿到的租約；null = 畫面上那句話不是
  /// 首頁的（沿用的開場問候、其他分頁的話），收拾時完全不能碰它。
  MascotSpeechLease? _speechLease;

  /// 單調遞增的台詞序號：用來比較「這句話比那次完成早還是晚」。
  int _speechSerial = 0;
  int _speechOwnerSerial = 0;

  /// 每條**弧線**建立當下的台詞序號。
  ///
  /// key 刻意是 arcId 不是 eventId：語意屬於整條弧線，撤銷其中一件不該讓
  /// 收尾拍查不到 epoch 而回退成 0（0 會讓所有比較都失準）。
  final Map<int, int> _completionSpeechEpoch = {};

  /// 每條弧線在全域 persona 上的收據。
  ///
  /// 弧線的第一拍靠 [MascotPersona] 的優先度爭取寫入權；成功之後才留下收據，
  /// 後面幾拍拿它做**嚴格 compare-and-apply**——相符才允許 force 接手自己的
  /// 狀態，不符就代表有更新的東西（撤銷、喝水過量、其他分頁）寫過了。
  final Map<int, MascotClaim> _arcPersonaClaim = {};

  /// 已經確定失去 persona 擁有權的弧線：之後每一拍都 no-op，不再搶回來。
  final Set<int> _arcPersonaLost = {};

  int _presentationGeneration = 0;
  int _tapSeq = 0;
  int _undoSeq = 0;
  int _milestoneSeq = 0;

  /// sad transient 的擁有者；被新事件取代後舊 timer 就不再作數。
  int _transientMascotSeq = 0;

  /// 目前那一次撤銷的完整身分。
  ///
  /// 本地 sad、全域佔用與「被它擋下來的那次跨越」是同一件事，收在一起才
  /// 有辦法讓兩個結束來源（自然到期、被新的正向輸入取代）跑同一段 terminal
  /// operation。見 [_finishUndoTransient]。
  _UndoLifecycle? _undo;

  /// 全域狀態現在還是不是 Home 上次寫進去的那一份。
  bool get _personaStillOurs =>
      _personaClaim != null && MascotPersona.claim == _personaClaim;

  /// 目前畫面上那句話是不是「開場問候／待機」這種系統寫入。
  ///
  /// 舊版用「Home 沒有主張擁有權」反推，只要有第三方寫過就會判斷錯；
  /// 改成直接問全域狀態自己的來源。
  /// 目前畫面上**那句話**是不是開場問候／待機這種系統寫入。
  ///
  /// 讀的是台詞的 provenance，不是整體狀態的擁有權：打卡的中間拍會換姿勢並
  /// 取得狀態擁有權，但那句問候仍然是問候。兩者共用一個欄位時，衝擊點換完
  /// 姿勢後就再也認不出它，470ms 的語意拍會把還沒講完的問候提早清掉。
  bool get _personaShowsOpening =>
      MascotPersona.speechOrigin == MascotStateOrigin.opening;

  /// 只清**本地**的台詞與擁有者，條件只有本地 token。
  ///
  /// 刻意不看 [MascotClaim]：本地欄位是首頁自己的東西，沒有別人會替它收。
  /// 綁上全域收據的話，只要有人接手過，這一句就永遠留在首頁的狀態裡，
  /// 之後被沿用回畫面上。能不能改寫**全域** persona
  /// 是另一個問題，由呼叫端另外問 [_personaStillOurs]。
  bool _releaseLocalSpeechIfOwned(HomeSpeechToken token) {
    if (_speechOwner != token) return false;
    setState(() {
      _transientSpeech = null;
      _speechOwner = null;
    });
    return true;
  }

  /// 高優先事件（撤銷、里程碑、全完成）接手時，先把舊台詞的擁有權收掉，
  /// 免得它被當成「兔咪原本正在說的話」帶進新情境。
  ///
  /// 這是「我要蓋過去」不是「我要收拾」，所以不比對收據——真正的寫入
  /// 仍然要通過 [MascotPersona] 的優先度規則。
  void _takeOverSpeech() {
    _transientSpeechTimer?.cancel();
    _transientSpeechTimer = null;
    if (_transientSpeech == null && _speechOwner == null) return;
    setState(() {
      _transientSpeech = null;
      _speechOwner = null;
    });
  }

  /// 只登記真的被接受的寫入：被優先度擋下來時什麼都沒發生，
  /// 不能把別人的狀態登記成 Home 的。
  /// [ownsSpeech] = 畫面上那句話是這次寫入自己的。為 false 時（沿用了別人
  /// 還在講的話）只登記狀態擁有權，不搶台詞的擁有者。
  void _claimPersona(
    HomeSpeechToken? token, {
    required bool accepted,
    bool ownsSpeech = true,
  }) {
    if (!accepted) return;
    _personaClaim = MascotPersona.claim;
    _speechOwner = (!ownsSpeech || MascotPersona.current.value.speech == null)
        ? null
        : token;
    _speechOwnerSerial = ++_speechSerial;
  }

  /// 放掉 Home **自己**上一次留在全域的佔用（停留時間、優先度、台詞）。
  ///
  /// 新的一次使用者輸入不該被自己上一段演出擋住：`_canApply` 是嚴格大於，
  /// 同情境（下一件普通完成）在停留期內會被自己的舊事件擋掉；撤銷留下的
  /// `undone`（優先度 20）更會把接下來的重做整個吃掉。
  ///
  /// 走 compare-and-clear：收據不符——喝水頁的過量提醒、衣櫃、更新的事件
  /// ——就整段 no-op，**絕不**放掉別人的狀態。
  /// 回傳有沒有真的放掉——呼叫端據此決定要不要讓弧線重新爭取擁有權。
  ///
  /// 這條路只從使用者互動（撤銷、開新弧線）進來，永遠不在 build 階段，
  /// 所以可以同步收。
  bool _releaseStalePersonaHold() {
    final claim = _personaClaim;
    if (claim == null) return false;
    final lease = _speechLease;
    // 先收台詞：清狀態時 `current.value` 會換一份新的，租約的比對必須在
    // 那之前完成。台詞不是我們的就整段跳過，它有自己的期限。
    if (lease != null) MascotPersona.clearSpeechIfLease(lease);
    _speechLease = null;
    if (!MascotPersona.clearStateIfClaim(
      claim,
      assetPath: _baselineMascotAsset,
    )) {
      return false;
    }
    _recordOwnSettlement(MascotPersona.claim);
    _personaClaim = null;
    _speechOwner = null;
    return true;
  }

  /// 取代正在顯示的 sad transient（新的正向事件、里程碑、全完成都要呼叫）。
  ///
  /// 回傳「有沒有順手放掉 Home 自己的 hold」。
  ///
  /// 撤銷的顯示期在這裡結束，走的是與自然到期**同一個** terminal operation：
  /// 舊版只在這裡 `cancel()` 掉 expiry timer，而那條 timer 的 callback 同時是
  /// 唯一的 ownership release ＋ 補送入口——於是「使用者又做了一件」反而把
  /// 本來會自動發生的補送一起取消掉了。
  bool _supersedeTransientMascot() {
    if (_undo != null) {
      // 補送刻意不在這裡發生：呼叫端接下來還會放掉自己上一段演出的佔用
      // （`_releaseStalePersonaHold`），補送若排在那之前會被當場清掉。
      final released = _finishUndoTransient(retryNow: false);
      _transientMascotSeq++;
      _transientMascotTimer?.cancel();
      _transientMascotTimer = null;
      return released;
    }
    _transientMascotSeq++;
    _transientMascotTimer?.cancel();
    _transientMascotTimer = null;
    if (_transientMascot == null) return false;
    setState(() => _transientMascot = null);
    // 這個 transient 對應的全域狀態也一起作廢：留著的話，接下來的正向事件
    // 會被自己剛寫下的 `undone` 優先度擋住，兔咪一路停在難過的臉。
    return _releaseStalePersonaHold();
  }

  void _showTransientMascot(
    String name, {
    Duration duration = const Duration(seconds: 2),
  }) {
    // 注意：這裡不加 _mascotReactionTick——彈跳是「正向」動作語彙，
    // 這條路目前只給撤銷打卡的 sad 用，難過還跳起來會很突兀；
    // 換圖動畫＋汗滴泡泡＋語音已足夠承載這個時刻。
    //
    // 上一次撤銷（若還在）直接作廢，不跑 terminal operation：新的撤銷馬上
    // 又會把擁有權拿回去，那時補送一定被擋，跑了也只是白跑一次。欠條留著，
    // 由**最新**這一次的顯示期結束時償還。
    _discardUndoLifecycle();
    final seq = ++_transientMascotSeq;
    setState(() {
      _transientMascot = name;
    });
    final accepted = _applyPersona(
      _baselineMascotContext,
      speechWrite: MascotSpeechWrite.generate,
    );
    final token = HomeSpeechToken(
      HomeSpeechSource.undo,
      _presentationGeneration,
      ++_undoSeq,
    );
    _claimPersona(token, accepted: accepted);
    // 這一次撤銷**自己那一份**收據與租約。結束時比對的是它們，不是之後才讀的
    // 欄位：中間若有更新的事件（含 Home 自己的）接手，這次的結束就不該再
    // 動任何東西。
    final undo = _UndoLifecycle(
      seq: seq,
      generation: _presentationGeneration,
      token: token,
      claim: accepted ? MascotPersona.claim : null,
      lease: accepted ? MascotPersona.speechLease : null,
    );
    _undo = undo;
    _transientMascotTimer = Timer(duration, () {
      _transientMascotTimer = null;
      _finishUndoTransient(retryNow: true);
    });
    undo.timer = _transientMascotTimer;
  }

  /// generation 已經作廢（跨日／重載／切分頁／dispose／全完成接手）：
  /// 這一次撤銷直接丟掉，不做任何 release 或補送。
  void _discardUndoLifecycle() {
    final undo = _undo;
    if (undo == null) return;
    undo.finished = true;
    undo.timer?.cancel();
    undo.timer = null;
    _undo = null;
  }

  /// **撤銷顯示期結束**——唯一、可重入、恰好一次的 terminal operation。
  ///
  /// 兩個來源共用同一段：
  ///   1. 兩秒 expiry 自然到期；
  ///   2. 新的正向輸入主動取代這次撤銷（[_supersedeTransientMascot]）。
  ///
  /// 「取消 timer」不等於「撤銷結束」——那正是上一版把唯一的補送入口一起
  /// 取消掉的原因。這裡把驗證、清本地、compare-release、恢復資格與補送
  /// 綁成同一件事，誰先到誰負責，重複呼叫是安全的 no-op。
  ///
  /// [retryNow] = false：只做到「恢復資格」，補送由呼叫端在放掉自己那一段
  /// 佔用之後再叫（見 [_supersedeTransientMascot]）。補送本身冪等——欠條在
  /// 交付當下就結清了。
  ///
  /// 回傳「有沒有真的放掉這次撤銷在全域的佔用」。
  bool _finishUndoTransient({required bool retryNow}) {
    final undo = _undo;
    if (undo == null || undo.finished) return false;
    undo.finished = true;
    undo.timer?.cancel();
    undo.timer = null;
    _undo = null;
    // 身分不符：更新的 transient 已經接手、跨日／重載換了 generation、
    // 或整棵樹已經拆掉。本地與全域都不動。
    if (!mounted ||
        undo.seq != _transientMascotSeq ||
        undo.generation != _presentationGeneration) {
      return false;
    }
    // 1. 本地 sad 只看自己的身分：它是首頁自己的欄位，沒有人會替它收。
    //    舊版把全域收據也綁進來，於是這次撤銷被更高優先的狀態（喝水過量）
    //    擋下時，本地就永遠卡著一張 sad——切回首頁或下次點兔咪都會突然變
    //    難過，而且 `_baselineMascotContext` 會一路回報 `undone`。
    if (_transientMascot != null) {
      setState(() => _transientMascot = null);
    }
    // 2. 全域只放掉**這一次撤銷**留下的那一份佔用，走 compare-and-clear。
    //    不符（其他分頁、使用者更新的動作）就到此為止，不碰別人的狀態、
    //    也不強行把 half 講出來。
    if (!_releaseUndoHold(undo)) return false;
    // 3. 真的放掉自己的擁有權之後，被它擋下來的跨越才重新有資格。
    _restoreMilestoneAvailability();
    if (retryNow) _retryPendingMilestoneSemantic();
    return true;
  }

  /// 放掉**這一次撤銷自己**在全域留下的佔用。
  ///
  /// 刻意不是 `force + holds:false` 寫一次 baseline——那是「蓋過去」，會在
  /// 收據對不上時覆寫別人，也會留下一張已經失效的 claim。這裡是原子的
  /// 「相符才動手」：不符就整段 no-op，回傳 false 讓呼叫端知道擁有權還在
  /// 別人手上（因此也不該補送任何語意）。
  bool _releaseUndoHold(_UndoLifecycle undo) {
    final claim = undo.claim;
    if (claim == null) return false;
    // 先問一次收據：不符就整段不動手。台詞雖然是我們自己的，但放不掉狀態時
    // 收掉它只會留下半套——擁有權還在別人手上，這時什麼都不該做。
    if (MascotPersona.claim != claim) return false;
    // 先收台詞：清狀態會換一份新的 `current.value`，租約比對必須在那之前。
    final lease = undo.lease;
    if (lease != null) MascotPersona.clearSpeechIfLease(lease);
    if (!MascotPersona.clearStateIfClaim(
      claim,
      assetPath: _baselineMascotAsset,
    )) {
      return false;
    }
    _recordOwnSettlement(MascotPersona.claim);
    if (_personaClaim == claim) _personaClaim = null;
    if (_speechLease == lease) _speechLease = null;
    _releaseLocalSpeechIfOwned(undo.token);
    return true;
  }

  /// 被這次撤銷擋下來的弧線，重新有資格爭取全域擁有權。
  ///
  /// `_arcPersonaLost` 是「這條弧線已經確定失去擁有權」的短路旗標，擋下那一拍
  /// 的正是我們自己剛放掉的撤銷。只放行真的補得出來的那幾條，其餘弧線維持
  /// 原本的短路。跨越是全域的，所以這可能一次放行好幾條弧線。
  void _restoreMilestoneAvailability() {
    for (final arcId in _completion.pendingSemanticArcIds) {
      _arcPersonaLost.remove(arcId);
      // 舊收據跟著撤銷一起失效了：補送的第一拍不 force，讓優先度重新裁決。
      _arcPersonaClaim.remove(arcId);
    }
  }

  /// 補送「門檻仍然成立、卻還沒交付」的那一次跨越。
  ///
  /// 撤銷在自己的顯示期內優先是既有 invariant（`undone` 20 > `halfDone` 12），
  /// 但它只是**延後**那次跨越，不是取消：資料仍在門檻之上，使用者也已經看過
  /// 那一勾落下。所以顯示期結束（自然到期或被新輸入取代）、而且我們確實放掉
  /// 了自己的佔用之後，要把欠的那一次補回來——不需要使用者再輸入第三次，
  /// 新的輸入也不該把它取消掉。
  void _retryPendingMilestoneSemantic() {
    _restoreMilestoneAvailability();
    _completion.retryPendingSemantic();
  }

  void _onMascotTap() {
    // 這裡刻意**不先**取消既有的 expiry：這次點擊可能被優先度擋下來，
    // 先取消就會讓舊台詞失去自己原本剩餘的壽命。
    if (!_reduceMotion) _celebCtrl.forward(from: 0);
    final ctx = _baselineMascotContext;
    // 進度中的情境改用帶件數的具體回應：使用者主動點兔咪等於在問
    // 「你怎麼看今天？」，這時給得出數字才有被看見的實感。
    final done = _dailyHabits.isNotEmpty ? dailyDoneCount : weeklyMetCount;
    final speech =
        (ctx == MascotContext.completedOne || ctx == MascotContext.halfDone)
        ? MascotLines.doneCountLine(done)
        : MascotLines.randomHomeTapLineFor(ctx);
    final token = HomeSpeechToken(
      HomeSpeechSource.tap,
      _presentationGeneration,
      ++_tapSeq,
    );
    final previousSpeech = _transientSpeech;
    final previousOwner = _speechOwner;
    final generation = _presentationGeneration;
    setState(() {
      _transientSpeech = speech;
      _speechOwner = token;
      _mascotReactionTick++;
    });
    // 點兔咪本身才是 tapReaction（問號泡泡＋疑問聲）；打卡不走這條。
    final accepted = _applyPersona(
      MascotContext.tapReaction,
      speechWrite: MascotSpeechWrite.own,
      speechText: speech,
    );
    if (accepted) {
      _claimPersona(token, accepted: true);
      _transientSpeechTimer?.cancel();
      _transientSpeechTimer = Timer(const Duration(seconds: 3), () {
        _transientSpeechTimer = null;
        if (!mounted || generation != _presentationGeneration) return;
        // ── 兩層，刻意分開 ──
        // 本地那一句只看自己的 token：就算全域早就被喝水頁接手，這一句
        // 仍然是首頁的東西，該由這條 expiry 收掉。不收的話它會一直躺在
        // 本地狀態裡，被之後任何一次 inherit 帶回畫面上。
        if (!_releaseLocalSpeechIfOwned(token)) return;
        // 能不能改寫**全域**才看收據；不符就到此為止，不碰別人的狀態。
        if (!_personaStillOurs) return;
        _applyPersona(
          _baselineMascotContext,
          speechWrite: MascotSpeechWrite.clear,
          silent: true,
          force: true,
          holds: false,
        );
      });
    } else {
      // 被優先度擋下來 → 這次點擊沒有發生：還原舊台詞與舊擁有者，
      // 而且**不動**它原本那條 expiry（上面刻意沒有先取消）。
      setState(() {
        _transientSpeech = previousSpeech;
        _speechOwner = previousOwner;
      });
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
    return _progressMascotContext;
  }

  /// 純由進度推導、**完全不看** transient 的情境。
  ///
  /// 完成演出的每一拍都用這個：撤銷 A 之後 B 仍然有效時，B 的 impact
  /// 不該借用 A 留下的 sad 姿勢或 `undone` 語意。
  MascotContext get _progressMascotContext {
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
        // 一律不再發生。但只作廢**這一件**——同一串連打裡其他仍然有效的
        // 完成，資料與那一次 success 回饋都要留著。
        _cancelCompletionForHabit(habit);
        _takeOverSpeech();
        // 撤銷的那一刻，剛才那個 allDone／streak（優先度 30，停留五秒）
        // 已經不再成立了——但它還壓在全域上，會把 `undone`（20）整個擋掉，
        // 兔咪要等兩秒 transient 過期或十秒回神才反應得過來。先以 Home
        // 自己的收據把它收掉；收據不符（其他分頁接手）就整段 no-op。
        _releaseStalePersonaHold();
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
      // 跨進全完成：普通完成的演出整代作廢，不能兩套 MI 反應疊著播。
      // cancelMotion: false ——取消的是「舊那一代」的反應，而全完成的新反應
      // 就在下面同一個 rebuild 裡開始；用 cancelUpTo 分代（見 MascotStage），
      // 順序誰先誰後都不會誤殺新反應。
      _invalidateCompletionPresentation(cancelMotion: false);
      _supersedeTransientMascot();
      _takeOverSpeech();
      setState(() => _mascotReactionCancelUpTo = _mascotReactionTick);
      // 當日全完成加碼（每日一次，service 內建防重複）
      CoinService.award(
        CoinSource.allHabitsDone,
        note: _l10n.hpCoinNoteAllDone,
      );
      // 音效與觸覺是全完成的「事實回饋」，Reduce Motion 下照發；
      // 會位移／縮放／冒粒子的那三件（場景縮放、小跳、星光）才拿掉。
      playFeedback(SfxCue.complete);
      final reduceMotion = _reduceMotion;
      if (!reduceMotion) _celebCtrl.forward(from: 0);
      setState(() {
        _completionReactionStrength = 1.0;
        if (!reduceMotion) _mascotReactionTick++;
      });
      // 第一次全完成 → 回憶事件（冪等；揭曉由 MainPage 佇列稍後接手播）
      unawaited(StoryEvents.onFirstAllDone());
      final accepted = _applyPersona(
        _baselineMascotContext,
        speechWrite: MascotSpeechWrite.generate,
      );
      _claimPersona(
        HomeSpeechToken(
          HomeSpeechSource.milestone,
          _presentationGeneration,
          ++_milestoneSeq,
        ),
        accepted: accepted,
      );
    } else if (!isWeekly && !wasHabitDone && habits[index]['done'] == true) {
      // ★ 本次里程碑的主角：一件普通每日習慣完成，今天還沒做完。
      // 資料已經在上面提交，這裡只排「演出」的時間線。
      //
      // 剛好跨過一半 → 整條弧線升級成 halfDone：由里程碑發出唯一那次
      // 泡泡／語音，而不是先完整演一次普通完成再靜靜換成 half baseline。
      final crossedHalf = progressBefore < 0.5 && _displayProgress >= 0.5;
      // 里程碑接手：普通完成的台詞不能被帶進 halfDone。
      if (crossedHalf) _takeOverSpeech();
      _startCompletionPresentation(
        progressBefore: progressBefore,
        habit: habits[index],
        crossedHalf: crossedHalf,
      );
    } else if (habits[index]['done'] == true) {
      // 每週習慣剛好達標：交給既有的即時回饋，不走打卡編排。
      playFeedback(wasHabitDone ? SfxCue.tap : SfxCue.success);
      setState(() {
        _completionReactionStrength = 1.0;
        if (!_reduceMotion) _mascotReactionTick++;
      });
      _applyPersona(
        _baselineMascotContext,
        speechWrite: MascotSpeechWrite.generate,
      );
    } else if (isWeekly) {
      // 每週習慣累加但還沒達標：是正向操作，給 tap 不給 cancel
      playFeedback(SfxCue.tap);
      setState(() {
        _completionReactionStrength = 1.0;
        if (!_reduceMotion) _mascotReactionTick++;
      });
      _applyPersona(
        _baselineMascotContext,
        speechWrite: MascotSpeechWrite.generate,
      );
    } else {
      playFeedback(SfxCue.cancel);
      // 撤銷的 sad 已由上面的 _showTransientMascot 套用，不再重送一次。
    }
    // 門檻的真相是**目前的進度**，不是弧線成員身上的歷史旗標。使用者可能
    // 撤銷一件根本不屬於這條弧線的舊習慣，進度一樣會掉回一半以下；那時
    // 正在進行的那一次跨越就不成立了，要再講一次里程碑得真的再跨一次。
    _completion.syncAboveThreshold(_displayProgress >= 0.5);
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
      CompletionPresentationController(
        onPhase: _onCompletionPhase,
        isStillValid: _completionStillValid,
      );

  int _mascotNoticeTick = 0;

  /// 「收束 reactionTick <= 這個值的那次反應」。用 tick 而不是單純 +1，
  /// 才不會在同一個 rebuild 裡把剛開始的全完成反應一起殺掉。
  int _mascotReactionCancelUpTo = -1;
  double _completionReactionStrength = 1.0;

  /// 每個習慣目前有效的完成事件；撤銷時只作廢那一件（也用來查它屬於哪條弧線）。
  final Map<String, HomeCompletionEvent> _liveEventByHabit = {};

  /// 進度條在衝擊點之前先按住的值；null = 直接跟著真實進度。
  /// **只影響動畫值**，「3 / 5」那個數字一律即時更新（那是事實不是演出）。
  double? _progressHold;

  /// 目前為止一共建立過幾個完成事件（一次 input 應該只 +1）。
  @visibleForTesting
  int get debugCompletionEventId => _completion.lastEventId;

  /// 連打合併視窗還開著。
  @visibleForTesting
  bool get debugCompletionArcActive => _completion.arcActive;

  /// 還有任何一拍沒播完（含 follower impact／recover／quiet）。
  @visibleForTesting
  bool get debugPresentationActive => _completion.presentationActive;

  /// 首頁實際發出去的語意事件（非 silent 的 persona apply）順序。
  /// 給測試直接觀察「這一次到底是 completedOne 還是 halfDone」。
  final List<MascotContext> _semanticEvents = [];

  /// 每一次語意交付實際掛在哪個成員身上（`habitKey`）。
  ///
  /// 「這次 half 是誰講的」是本輪的驗收條件之一：補送必須由仍然有效、自己
  /// 已 impact 的那一件當 anchor，不是已經被撤銷的那個門檻來源。
  final List<String> _semanticAnchors = [];

  @visibleForTesting
  List<MascotContext> get debugSemanticEvents =>
      List<MascotContext>.unmodifiable(_semanticEvents);

  @visibleForTesting
  List<String> get debugSemanticAnchors =>
      List<String>.unmodifiable(_semanticAnchors);

  @visibleForTesting
  void debugClearSemanticEvents() {
    _semanticEvents.clear();
    _semanticAnchors.clear();
  }

  @visibleForTesting
  HomeSpeechSource? get debugSpeechOwnerSource => _speechOwner?.source;

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

  int? get _dayRevision => widget.dayStamp?.revision;

  static String _habitKeyOf(Map<String, dynamic> habit) =>
      (habit['id'] as String?) ?? (habit['name'] as String? ?? '');

  /// 延後的 phase 要不要真的播。看不到、跨了日、被換掉快照就一律不播。
  bool _completionStillValid(HomeCompletionEvent event) {
    if (!mounted) return false;
    if (!_wasVisible) return false; // 分頁被收起來：不出聲、不震動、不冒泡泡
    // 重載中／跨日結算中：畫面上的清單隨時會被整份換掉，舊演出一律不播。
    if (_mutationsBlocked) return false;
    if (event.dayRevision != _dayRevision) return false;
    return true;
  }

  void _startCompletionPresentation({
    required double progressBefore,
    required Map<String, dynamic> habit,
    required bool crossedHalf,
  }) {
    final doneNow = _dailyHabits.isNotEmpty ? dailyDoneCount : weeklyMetCount;
    final reduceMotion = _reduceMotion;
    // 這一件會併進正在跑的那條弧線，還是自己開一條新的。
    final joinsOpenArc = _completion.arcActive;
    // 新的正向事件明確取代舊的撤銷 transient：redo 之後兩秒，舊 sad 的
    // expiry 不該再把兔咪拉回難過的臉。
    final releasedUndoHold = _supersedeTransientMascot();
    // 開新弧線＝新的一次使用者輸入：先放掉 Home 自己上一段演出留下的佔用。
    // 不放的話，上一條弧線的停留時間會把這一條的第一拍整個擋掉（`_canApply`
    // 是嚴格大於，同情境擋同情境）。併進既有弧線時**不能**放——那會把同一條
    // 弧線裡前一件剛寫好的表情一起清掉。別人的狀態一律不碰。
    if (!joinsOpenArc) _releaseStalePersonaHold();
    // 一定要 setState：poseTransition 由 presentationActive 推導，
    // Reduce Motion 沒有進度按壓也必須讓首頁重建一次，否則衝擊點那一刻
    // 還停在交叉淡入模式。
    setState(() => _progressHold = reduceMotion ? null : progressBefore);
    final key = _habitKeyOf(habit);
    final event = _completion.start(
      habitKey: key,
      dayRevision: _dayRevision,
      crossedHalf: crossedHalf,
      doneCount: doneNow,
      reduceMotion: reduceMotion,
    );
    _liveEventByHabit[key] = event;
    // epoch 屬於整條弧線，由**第一個**成員定下來：後面併進來的成員不該把
    // 語意的時間點往後推，撤銷其中一件也不該讓它消失。
    _completionSpeechEpoch.putIfAbsent(event.arcId, () => _speechSerial);
    // 剛剛放掉的是 Home 自己的撤銷 hold，而這一件併進了既有弧線：
    // 那條弧線可以重新爭取 persona 擁有權。被撤銷的成員留下的「已失去」
    // 標記不該永久毒化整條弧線——否則撤銷過一次之後，同一個 window 裡
    // 再跨過門檻的成員永遠拿不到語意。
    if (releasedUndoHold && joinsOpenArc) {
      _arcPersonaLost.remove(event.arcId);
      _arcPersonaClaim.remove(event.arcId);
    }
    // 這一次輸入結束了上一個撤銷的顯示期，所以欠著的那次跨越現在補得出來。
    // 排在最後：前面 `_releaseStalePersonaHold()` 是「新輸入放掉自己上一段的
    // 佔用」，補送若排在它之前會被當場清掉。新的輸入是**解除阻擋**，不是
    // 取消補送——它也不該變成補送的必要條件（沒有它，兩秒到期照樣會補）。
    if (releasedUndoHold) _retryPendingMilestoneSemantic();
  }

  /// 撤銷單一件：只作廢那一件的演出。同一串連打裡其他仍然有效的完成
  /// （資料、勾勾、那一次 success 回饋、共用的那段動作）都要留著。
  void _cancelCompletionForHabit(Map<String, dynamic> habit) {
    final key = _habitKeyOf(habit);
    final event = _liveEventByHabit.remove(key);
    var outcome = CompletionCancelOutcome.unknown;
    if (event != null) {
      outcome = _completion.cancelEvent(event.id);
      // 語意身分掛在弧線上，不在單一件上：只有整條弧線結束才收掉它的
      // 台詞擁有權與 epoch。撤銷 A、B 還活著時，弧線的語意仍然成立。
      if (outcome == CompletionCancelOutcome.arcEnded) {
        _completionSpeechEpoch.remove(event.arcId);
        _arcPersonaClaim.remove(event.arcId);
        _arcPersonaLost.remove(event.arcId);
        _releaseLocalSpeechIfOwned(_completionTokenFor(event));
      }
    }
    if (!mounted) return;
    setState(() {
      _progressHold = null;
      // 只有最後一個有效成員也沒了，才把共用的那段動作收掉。
      // 用 controller 回報的結果，不用 reaction tick 猜。
      if (outcome == CompletionCancelOutcome.arcEnded) {
        _mascotReactionCancelUpTo = _mascotReactionTick;
      }
    });
  }

  /// 丟掉所有排程與本地演出身分。不碰全域 persona，也不碰資料。
  void _cancelCompletionSchedules() {
    _completion.invalidate();
    _liveEventByHabit.clear();
    _completionSpeechEpoch.clear();
    _arcPersonaClaim.clear();
    _arcPersonaLost.clear();
    _presentationGeneration++;
    _transientSpeechTimer?.cancel();
    _transientSpeechTimer = null;
    _transientMascotTimer?.cancel();
    _transientMascotTimer = null;
    _transientMascotSeq++;
    // 這一代整個作廢了：撤銷的生命週期跟著丟掉，不做 release、也不補送。
    _discardUndoLifecycle();
  }

  /// 收掉「仍然由 Home 擁有的全域兔咪狀態」，**不依賴 widget rebuild**。
  ///
  /// dispose 也走這條：那時候不能 setState，但姿勢、泡泡與台詞仍然可能是
  /// Home 寫進去的，放著不管會一路留到全域十秒回神。
  ///
  /// 條件是整體 persona 擁有權，不是「有沒有台詞」——speech 為 null 的普通
  /// 完成同樣寫過姿勢。狀態與台詞各自 compare-and-clear（見 [_clearOwnedPersona]）：
  /// 收據／租約不符（其他分頁、更新的撤銷、還在講的開場問候）就整段 no-op。
  void _releaseHomePersona() {
    final claim = _personaClaim;
    final lease = _speechLease;
    _speechOwner = null;
    _personaClaim = null;
    _speechLease = null;
    _transientMascot = null;
    _transientSpeech = null;
    if (claim == null) return;
    final settlement = _beginSettlement(claim: claim, lease: lease);
    // dispose 常常發生在樹拆除的那一幀裡：同步寫全域 notifier 一樣會讓
    // 別頁正在 build 的 listener markNeedsBuild。收據已經捕捉好了，
    // 推到這一幀之後收一樣安全。
    if (_inBuildPhase) {
      _schedulePersonaCleanup(settlement);
      return;
    }
    _clearOwnedPersona(settlement);
  }

  /// 現在是不是正在 build／layout 這一幀。
  ///
  /// 跨日與 resume 是從 `MainPage` 的重建流下來的：`didUpdateWidget` →
  /// `loadHabits()` → 這一段。那時同步寫全域 notifier 會讓正在 build 的
  /// listener `markNeedsBuild`，framework 直接拋例外。
  bool get _inBuildPhase {
    final phase = SchedulerBinding.instance.schedulerPhase;
    return phase == SchedulerPhase.persistentCallbacks ||
        phase == SchedulerPhase.midFrameMicrotasks ||
        phase == SchedulerPhase.transientCallbacks;
  }

  /// 收掉**這一筆交易捕捉當下**的那份 Home 擁有權。純函式式：只用交易上的
  /// 收據與租約，不讀任何會在延後期間變動的欄位。
  ///
  /// 兩層各自 compare-and-clear，所以延後執行時若已經被別人接手
  /// （其他分頁、新一代 Home、使用者的新互動），自然整段 no-op。
  ///
  /// 結果只寫回**自己這一筆**交易：遲到又失敗的 stale 收拾不得把更新那一輪
  /// 的收據擦掉——那張收據正是換日要用的東西。
  void _clearOwnedPersona(_PersonaSettlement settlement, {String? assetPath}) {
    if (settlement.superseded) return;
    final claim = settlement.claim;
    if (claim == null) {
      _completeSettlement(settlement, receipt: null);
      return;
    }
    // 先收台詞：清狀態會換一份新的 `current.value`，租約比對必須在那之前。
    final lease = settlement.lease;
    if (lease != null) MascotPersona.clearSpeechIfLease(lease);
    final settled = MascotPersona.clearStateIfClaim(
      claim,
      assetPath: assetPath ?? _baselineMascotAsset,
    );
    _completeSettlement(
      settlement,
      receipt: settled ? MascotPersona.claim : null,
    );
  }

  /// 把「通知 widget tree 的那一步」推到這一幀之後。
  ///
  /// 捕捉當下的立繪——延後期間資料可能整份換掉，用當時的值才對得起
  /// 「收掉的是那一代的東西」。收據與租約掛在交易上。
  /// generation 只用來決定要不要重建畫面。
  void _schedulePersonaCleanup(_PersonaSettlement settlement) {
    final assetPath = _baselineMascotAsset;
    final generation = _presentationGeneration;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _clearOwnedPersona(settlement, assetPath: assetPath);
      if (mounted && generation == _presentationGeneration) setState(() {});
    });
  }

  /// 整個 generation 作廢：離開首頁、開始重載／換快照、跨日、交棒給全完成。
  ///
  /// 分成兩段，順序不能對調：
  ///
  ///   1. **同步、不通知任何人**——排程、generation、mutation 封鎖與本地
  ///      欄位。這些一定要當場失效，否則舊的 impact／SFX／haptic／語音／
  ///      泡泡會在延後期間多活一幀漏出去。
  ///   2. **會通知 widget tree 的那一步**——全域 persona 的 compare-and-clear
  ///      與畫面重建。在 build 階段（跨日／resume 從 MainPage 重建下來）
  ///      必須推到這一幀之後，否則正在 build 的 listener 會 markNeedsBuild。
  void _invalidateCompletionPresentation({bool cancelMotion = true}) {
    _cancelCompletionSchedules();
    final ownsPersona = _personaStillOurs;
    final claim = _personaClaim;
    final lease = _speechLease;
    // 本地狀態**無條件**清掉，不看收據。這一代已經作廢了，留著那句話
    // 只會讓它在下一次沿用時重新冒出來——external 接手期間離開首頁
    // 再回來、做一件 speech-null 的完成，畫面上就會出現一句早該消失的
    // 舊台詞。能不能改寫全域是下面那段的事。
    _progressHold = null;
    _transientMascot = null;
    _transientSpeech = null;
    _speechOwner = null;
    _personaClaim = null;
    _speechLease = null;
    if (cancelMotion) _mascotReactionCancelUpTo = _mascotReactionTick;

    // 這一輪的交易在這裡開，不管收不收得掉：新一天的中性收尾可能比收拾
    // 先到，那時它得有地方登記自己的需求。
    final settlement = _beginSettlement(
      claim: ownsPersona ? claim : null,
      lease: ownsPersona ? lease : null,
    );
    // 從這裡開始一律問**交易上**的 claim，不是本地那個：這一輪自己拿不到
    // 擁有權時，它可能剛從上一筆手上接下一份還沒執行的收拾責任。
    if (settlement.claim == null) {
      if (!settlement.cleanupDone) {
        _completeSettlement(settlement, receipt: null);
      }
      if (mounted && !_inBuildPhase) setState(() {});
      return;
    }
    if (!mounted || _inBuildPhase) {
      // dispose 也走這裡：不能 setState，但那一代擁有的狀態仍然要收，
      // 而且是用**交易捕捉到的**收據，不是之後才讀的欄位。
      _schedulePersonaCleanup(settlement);
      return;
    }
    // 收拾不是互動：不冒泡泡、不出聲、也不重排待機時鐘。
    // 只收 Home 自己那一半——還在講的開場問候留給它自己的期限。
    _clearOwnedPersona(settlement);
    setState(() {});
  }

  /// 這條**弧線**的語意身分。
  ///
  /// 刻意用 arcId 而不是 eventId：speak 綁在領頭那一件上，而領頭可能被撤銷；
  /// recover／quiet 綁在最後加入的那一件上。兩邊用不同的 id，收尾就永遠對不上
  /// 自己發出去的台詞，completion speech 會一路殘留到全域十秒回神。
  /// 弧線 id 不依賴任何成員存活，撤銷其中一件也不會讓它換人。
  HomeSpeechToken _completionTokenFor(HomeCompletionEvent event) =>
      HomeSpeechToken(
        HomeSpeechSource.completion,
        event.generation,
        event.arcId,
      );

  /// 這條弧線現在還有沒有資格動全域 persona。
  ///
  /// 必須在**算台詞之前**問：`_speechForSilentBeat` 這類計算會順手清掉本地
  /// 鏡像，弧線已經沒有擁有權時連算都不該算，否則會留下沒人收的半套狀態。
  ///
  /// - 已經確定失去擁有權 → false，不再搶回來（後續 recover／quiet 一律 no-op）。
  /// - 手上有收據但全域已經被別人改過 → 記成失去擁有權。
  ///   **不能只看 origin**：更新的那個寫入也可能同樣是 Home 的（撤銷就是）。
  /// - 還沒有收據（弧線的第一拍）→ true，交給 [MascotPersona] 的優先度裁決。
  bool _arcPersonaAvailable(int arcId) {
    if (_arcPersonaLost.contains(arcId)) return false;
    final claim = _arcPersonaClaim[arcId];
    if (claim != null && MascotPersona.claim != claim) {
      _arcPersonaClaim.remove(arcId);
      _arcPersonaLost.add(arcId);
      return false;
    }
    return true;
  }

  /// 弧線的 persona 寫入：嚴格 compare-and-apply。
  ///
  /// 第一拍沒有收據，不 force，讓優先度決定——喝水過量、撤銷這種更高優先的
  /// 狀態自然擋得住。收據相符才允許 force：那是「接手自己剛寫的狀態」，
  /// 不是搶別人的。
  ///
  /// 回傳有沒有真的寫進去；被拒絕時**不留下**收據、擁有者或半套狀態。
  bool _applyArcPersona(
    int arcId,
    MascotContext ctx, {
    MascotSpeechWrite? speechWrite,
    String? speechText,
    String? asset,
    HomeSpeechToken? silentBeatFor,
    int silentBeatEpoch = 0,
    bool silent = false,
    bool withVoice = true,
    bool holds = true,
  }) {
    if (!_arcPersonaAvailable(arcId)) return false;
    final applied = _applyPersona(
      ctx,
      speechWrite: speechWrite,
      speechText: speechText,
      asset: asset,
      silentBeatFor: silentBeatFor,
      silentBeatEpoch: silentBeatEpoch,
      silent: silent,
      withVoice: withVoice,
      force: _arcPersonaClaim[arcId] != null,
      holds: holds,
    );
    if (applied) _arcPersonaClaim[arcId] = MascotPersona.claim;
    return applied;
  }

  CompletionDelivery _onCompletionPhase(
    CompletionPhase phase,
    HomeCompletionEvent event,
    CompletionKind kind,
  ) {
    if (!mounted) return CompletionDelivery.obsolete;
    // 語意由 controller 依**這一拍所屬的弧線**解析後傳進來；
    // 這裡不去問任何可能被下一條弧線改寫的全域欄位。
    final milestone = kind == CompletionKind.half;
    final semanticContext = milestone
        ? MascotContext.halfDone
        : MascotContext.completedOne;
    final arcId = event.arcId;
    final token = _completionTokenFor(event);
    final epoch = _completionSpeechEpoch[arcId] ?? 0;
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
        //
        // 資料與成功回饋是這一件自己的事，**不受 persona 是否寫得進去影響**：
        // 使用者確實完成了，被喝水過量的提醒擋住的只是兔咪要不要換臉。
        playFeedback(SfxCue.success, haptic: HapticLevel.light);
        if (_progressHold != null) setState(() => _progressHold = null);
        if (!_arcPersonaAvailable(arcId)) {
          return CompletionDelivery.rejected;
        }
        // 姿勢一律走純進度的 baseline——同一串連打裡別人被撤銷留下的 sad
        // 不該被這一件借去用。
        _applyArcPersona(
          arcId,
          semanticContext,
          asset: _baselineMascotAsset,
          silentBeatFor: token,
          silentBeatEpoch: epoch,
        );
      case CompletionPhase.speak:
        if (!_arcPersonaAvailable(arcId)) {
          return CompletionDelivery.rejected;
        }
        // 整條弧線唯一一次語意事件。台詞在**這一刻**重算，不用建立當下的
        // 快照——撤銷過、或這已經是第二條弧線時，就不會再冒出「今天第一件。」
        final doneNow = _dailyHabits.isNotEmpty
            ? dailyDoneCount
            : weeklyMetCount;
        final line = (!milestone && doneNow == 1)
            ? MascotLines.doneCountLine(doneNow)
            : null;
        // 沒有自己的台詞時沿用 silent beat 的規則：留自己的、留開場問候、
        // 留比自己新的，只收掉比自己舊的 Home 台詞。
        final resolved = line != null
            ? (write: MascotSpeechWrite.own, text: line)
            : _speechForSilentBeat(token, epoch);
        // 先問寫不寫得進去，成功才登記本地台詞：被優先度擋下時什麼都沒發生，
        // 不能在畫面上留一句沒人擁有、也沒人會收的話。
        final spoke = _applyArcPersona(
          arcId,
          semanticContext,
          asset: _baselineMascotAsset,
          speechWrite: resolved.write,
          speechText: resolved.text,
          withVoice: milestone || line != null,
        );
        if (spoke && line != null) {
          setState(() {
            _transientSpeech = line;
            _speechOwner = token;
          });
        }
        // 沿用來的那句話不是這次完成的：不能登記成 completion 的擁有者，
        // 否則它會跟著這條弧線的收尾一起被清掉，而不是由原本的擁有者收。
        _claimPersona(
          token,
          accepted: spoke,
          ownsSpeech: resolved.write == MascotSpeechWrite.own,
        );
        if (spoke) _semanticAnchors.add(event.habitKey);
        return spoke
            ? CompletionDelivery.delivered
            : CompletionDelivery.rejected;
      case CompletionPhase.milestoneHandoff:
        // 弧線已經用普通完成的語意發過了，之後才有成員跨過門檻。
        // 只補一次里程碑語意（泡泡＋語音＋情境），**不重啟**動作。
        //
        // 接手的對象是自己這條弧線的 completedOne，靠 arc 收據證明；
        // 收據不符就代表中間有更高優先或更新的狀態，這拍整個放棄——
        // 但**不消耗交付資格**：後面若有新成員再次跨過門檻，它還能再試。
        if (!_arcPersonaAvailable(arcId)) {
          return CompletionDelivery.rejected;
        }
        // 里程碑是新的語意，不沿用普通完成留在本地的那句話；但還沒講完的
        // 開場問候仍然留著（它有自己的顯示壽命）。
        final keepsOpening = _personaShowsOpening;
        final handed = _applyArcPersona(
          arcId,
          MascotContext.halfDone,
          asset: _baselineMascotAsset,
          speechWrite: keepsOpening
              ? MascotSpeechWrite.preserve
              : MascotSpeechWrite.clear,
        );
        if (!handed) return CompletionDelivery.rejected;
        // 接手成功才收掉舊台詞的擁有權：被擋下時什麼都沒發生，
        // 不能把畫面上別人的那句話記成「已經被我換掉了」。
        _takeOverSpeech();
        _claimPersona(token, accepted: true, ownsSpeech: !keepsOpening);
        _semanticAnchors.add(event.habitKey);
        return CompletionDelivery.delivered;
      case CompletionPhase.recover:
        // 落地：回到「目前進度」推導的 baseline。不再演一次——里程碑的
        // 完整反應已經在 speak 那一拍發過了。
        if (!_arcPersonaAvailable(arcId)) {
          return CompletionDelivery.rejected;
        }
        _applyArcPersona(
          arcId,
          _progressMascotContext,
          asset: _baselineMascotAsset,
          silentBeatFor: token,
          silentBeatEpoch: epoch,
        );
      case CompletionPhase.quiet:
        _completionSpeechEpoch.remove(arcId);
        // 本地那一句只看自己的 token（別人的不歸這裡管）。
        final ownedTail = _releaseLocalSpeechIfOwned(token);
        // 全域的收尾看**弧線收據**，不看有沒有台詞：speech 為 null 的
        // 普通完成同樣寫過姿勢與泡泡，那些也要收。更新的台詞或其他分頁
        // 接手時收據就不符，整段 no-op。
        //
        // 台詞：剛剛收掉的就是自己那一句 → 明確清成沒有文字。否則走跟中間拍
        // 同一套規則，把該留的留著（還沒講完的開場問候、比自己新的 Home
        // 台詞）——它們有自己的顯示壽命，不歸這條弧線的收尾管。
        //
        // 不能直接丟給 `_speechForSilentBeat`：`_speechOwnerSerial` 記的正是
        // 這條弧線自己那次寫入，它會把自己的台詞誤判成「比我更新的別人」。
        final tail = ownedTail
            ? (write: MascotSpeechWrite.clear, text: null)
            : _speechForSilentBeat(token, epoch);
        _applyArcPersona(
          arcId,
          _progressMascotContext,
          asset: _baselineMascotAsset,
          speechWrite: tail.write,
          speechText: tail.text,
          silent: true,
          holds: false,
        );
        _arcPersonaClaim.remove(arcId);
        _arcPersonaLost.remove(arcId);
        // 這條弧線的最後一拍：**無條件**讓首頁重建一次。
        // poseTransition 是從 `_completion.presentationActive` 推導的，
        // 沒有這次 rebuild 的話，speech 為 null 的收尾（上面兩段都可能
        // 整段 no-op）就不會有任何 setState，畫面會一直停在離散換圖模式，
        // 要等下一次無關的互動才修正。
        //
        // 時序：controller 在呼叫這一拍之前就已經把 quietTimer／recoverTimer
        // 設成 null，所以這裡讀到的 presentationActive 已經是最終值。
        if (mounted) setState(() {});
    }
    return CompletionDelivery.delivered;
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
    _invalidateCompletionPresentation();
    _takeOverSpeech();
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
    // 切走分頁：整代 Home 演出作廢——不只是「還有沒有排程」，連已經呈現
    // 但仍由這一代擁有的台詞、姿勢與 expiry timer 都要一起收掉。
    if (!visible && _wasVisible) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _invalidateCompletionPresentation();
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
              // Reduce Motion 整層不掛——它畫的是持續移動的粒子，靜止版本
              // 只會變成一片不會動的雜訊。全完成的語意由立繪、泡泡、台詞與
              // 音效承擔，那些都保留。執行中打開偏好時這層會直接消失。
              if (allDone0 && habits.isNotEmpty && !_reduceMotion)
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
          reactionCancelUpTo: _mascotReactionCancelUpTo,
          // 打卡演出期間換立繪走離散換圖：兩張完整立繪半透明疊在一起
          // 才是衝擊點看到的雙影。其他互動維持全 app 既有的交叉淡入。
          //
          // Reduce Motion 一律走離散換圖，**不能**只看 presentationActive：
          // 全完成會先把 completion 整代作廢（presentationActive 因此是
          // false），最後一勾就會落回交叉淡入——兩張半透明立繪加上
          // AnimatedSwitcher 的 0.92→1.0 縮放，正是這個偏好要拿掉的東西。
          poseTransition: (_reduceMotion || _completion.presentationActive)
              ? MascotPoseTransition.cut
              : MascotPoseTransition.crossFade,
          reduceMotion: _reduceMotion,
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
  ///
  /// [silent] = 只換姿勢，不冒泡泡、不出聲、也不補台詞。
  /// [silentBeatFor] = 同一個事件的中間拍（impact／recover）：一樣 silent，
  /// 但台詞的處理多一層規則，見 [_speechForSilentBeat]。
  bool _applyPersona(
    MascotContext ctx, {
    MascotSpeechWrite? speechWrite,
    String? speechText,
    String? asset,
    HomeSpeechToken? silentBeatFor,
    int silentBeatEpoch = 0,
    bool silent = false,
    bool withVoice = true,
    bool force = false,
    bool holds = true,
  }) {
    final quiet = silent || silentBeatFor != null;
    // 「中間拍不覆寫別人」的把關**不在這裡**：只看 origin 擋不掉更新的
    // Home 寫入（撤銷也是 Home）。改由呼叫端拿弧線收據做嚴格
    // compare-and-apply，見 [_applyArcPersona]。
    var resolved = silentBeatFor != null
        ? _speechForSilentBeat(silentBeatFor, silentBeatEpoch)
        : (write: speechWrite ?? MascotSpeechWrite.clear, text: speechText);
    // 「說要用自己的話、卻沒有話」正規化成「沒有話」。
    if (resolved.write == MascotSpeechWrite.own && resolved.text == null) {
      resolved = (write: MascotSpeechWrite.clear, text: null);
    }
    final applied = MascotPersona.setForContext(
      asset ?? _mascotAsset,
      ctx,
      speechWrite: resolved.write,
      speech: resolved.text,
      silent: quiet,
      withVoice: withVoice,
      force: force,
      origin: MascotStateOrigin.home,
      holds: holds,
    );
    if (!applied) return false;
    // 被 priority 擋下來的事件什麼都沒發生，不該登記成語意事件，
    // 呼叫端也不該因此取得台詞擁有權。
    if (!quiet) _semanticEvents.add(ctx);
    // 收據永遠跟著最後一次成功寫入走，否則自己的中間拍會讓自己失去擁有權。
    // 這是**整體 persona** 的擁有權，跟這次有沒有台詞無關。
    _personaClaim = MascotPersona.claim;
    // Home 又握著活的擁有權了：上一筆交易到此為止。**明確** supersede，
    // 不是等它之後收據碰巧對不上——換日要用的是這一次的 claim。
    _settlement?.superseded = true;
    _settlement = null;
    // 台詞的租約另外記：只有這次真的動過台詞（不是 preserve）才是首頁的。
    if (resolved.write != MascotSpeechWrite.preserve) {
      _speechLease = MascotPersona.speechLease;
    }
    return true;
  }

  /// 中間拍要不要保留現在畫面上那句話。
  ///
  /// 回傳的 `inherited` 是「這句話是別人的、我只是沒把它蓋掉」——呼叫端據此
  /// 決定要不要把台詞的 provenance 一起接管，以及要不要登記成自己的擁有者。
  ///
  /// [epoch] 是這次完成建立當下的台詞序號，用來分辨「比我早」還是「比我晚」：
  /// - 自己的台詞、而且全域狀態還是我們寫的 → 留著（是我的，不是沿用）。
  /// - 來源是開場問候／待機 → 沿用（唯一的外來白名單）。
  /// - 全域狀態已經被其他分頁接手 → 原樣沿用，**絕不**動它。
  /// - 比這次完成**更新**的 Home 台詞（撤銷、之後的點擊、里程碑）→ 沿用：
  ///   還活著的弧線收尾不該清掉後來才發生的事。
  /// - 只有「比這次完成更早」的 Home 舊台詞才收掉，免得被帶進打卡泡泡。
  ({MascotSpeechWrite write, String? text}) _speechForSilentBeat(
    HomeSpeechToken self,
    int epoch,
  ) {
    if (_speechOwner == self && _personaStillOurs) {
      return (write: MascotSpeechWrite.own, text: _transientSpeech);
    }
    // 以下三種都是「那句話是別人的」：整份租約（來源與絕對期限）原封不動。
    if (_personaShowsOpening) {
      return (write: MascotSpeechWrite.preserve, text: null);
    }
    if (!_personaStillOurs) {
      return (write: MascotSpeechWrite.preserve, text: null);
    }
    if (_speechOwnerSerial > epoch) {
      return (write: MascotSpeechWrite.preserve, text: null);
    }
    _transientSpeech = null;
    _speechOwner = null;
    return (write: MascotSpeechWrite.clear, text: null);
  }

  Widget _habitCardContent({
    required double progress,
    required int displayDone,
    required int displayTotal,
    required Color accent,
  }) {
    final reached = displayTotal > 0 && displayDone >= displayTotal;
    // 達標時亮點呼吸，未達標時停住歸零（在 build 同步狀態，含載入時）。
    //
    // Reduce Motion 也算「不該呼吸」：這個光暈持續改變 alpha、模糊與擴散，
    // 只把它藏起來而讓 controller 在背景繼續排幀，等於偏好沒有生效。
    // 動態打開時 MediaQuery 會觸發重建，下面這段當場把它停住並歸零；
    // 關掉之後只要仍然達標就會自己接回一般模式的光暈。
    final glowAllowed = reached && !_reduceMotion;
    if (glowAllowed && !_glowCtrl.isAnimating) {
      _glowCtrl.repeat(reverse: true);
    } else if (!glowAllowed &&
        (_glowCtrl.isAnimating || _glowCtrl.value != 0)) {
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

/// 一次「Home 收拾自己 →（若換日）再收成新一天中性」的交易。
///
/// 存在的理由是**順序無關**：一輪 reload 會產生兩件事——收拾舊 Home 狀態
/// （可能同步、也可能被推到 post-frame）與套用新快照（storage 的 async
/// 續體）——而它們誰先誰後沒有保證。舊版把中間結果放在一個全域欄位上做
/// 兩階段橋接，於是 snapshot 先到時需求整個被丟掉，遲到的 stale 收拾又會
/// 把新一輪的收據擦掉。
///
/// 交易把兩邊的結果寫在同一個物件上：誰後到誰負責收尾，兩種順序收斂到
/// 同一個結果。stale 的 callback 只認得自己那一筆，寫不到現行的那一筆。
class _PersonaSettlement {
  _PersonaSettlement({
    required this.id,
    required this.generation,
    required this.claim,
    required this.lease,
  });

  /// 單調遞增的交易身分。
  final int id;

  /// 建立當下的 presentation generation。
  final int generation;

  /// 捕捉到的舊 Home 收據與台詞租約；null = 這一輪 Home 根本沒有擁有權。
  final MascotClaim? claim;
  final MascotSpeechLease? lease;

  /// 收拾階段已經跑完（成功或失敗都算）。
  bool cleanupDone = false;

  /// 收拾**成功**之後留下的新收據；null = 被 external 或新一代 Home 接手了。
  MascotClaim? settledReceipt;

  /// 已經得知這次快照是新的一天。
  bool needsNeutral = false;

  /// 新一天的中性收尾已經做過。
  bool neutralDone = false;

  /// 更新的一輪已經接手：這一筆只能整個放棄，不得再寫任何東西。
  bool superseded = false;
}

/// 一次撤銷的完整生命週期。
///
/// 撤銷不是「一個 2 秒的 timer」：它同時佔著本地 sad、全域的姿勢／台詞／
/// 停留優先度，並且擋著一次仍然成立的門檻跨越。三件事必須一起結束，而且
/// 只結束一次——所以它們收在同一個物件上，由 [_HomePageState._finishUndoTransient]
/// 這個唯一的 terminal operation 消費。
///
/// 結束有兩個來源（自然到期、被新的正向輸入取代），兩邊走同一段：把
/// 「取消 timer」當成「撤銷結束」的舊模型會讓第二種來源把補送一起吃掉。
class _UndoLifecycle {
  _UndoLifecycle({
    required this.seq,
    required this.generation,
    required this.token,
    required this.claim,
    required this.lease,
  });

  /// 這一次 sad 的本地身分；被更新的 transient 取代之後就不再作數。
  final int seq;

  /// 建立當下的 presentation generation。
  final int generation;

  /// 這一次撤銷在首頁台詞上的擁有者。
  final HomeSpeechToken token;

  /// 寫入成功時拿到的全域收據與台詞租約；null = 這次撤銷根本沒寫進去
  /// （被更高優先的狀態擋下），因此也沒有東西可以放掉。
  final MascotClaim? claim;
  final MascotSpeechLease? lease;

  Timer? timer;

  /// terminal operation 已經跑過了。可重入的保證就在這一格。
  bool finished = false;
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
