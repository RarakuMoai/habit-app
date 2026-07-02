// 首頁（每日／每週習慣打卡 + 兔咪場景）。
// 其餘部分拆在 home/：習慣卡片、新增／編輯 bottom sheet、preset 定義、
// 問候橫幅、共用小元件與場景 painter。
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/app_feedback.dart';
import '../utils/app_style.dart';
import '../utils/coin_config.dart';
import '../utils/coin_service.dart';
import '../utils/habit_history.dart';
import '../utils/input_formatters.dart';
import '../utils/logical_date.dart';
import '../utils/mascot.dart';
import '../utils/prefs_keys.dart';
import '../utils/sfx_service.dart';
import '../utils/story_store.dart';
import '../utils/usage_stats.dart';
import '../utils/weight_records.dart';
import '../widgets/habit_ui.dart';
import '../widgets/mascot_app_bar.dart';
import '../widgets/mascot_page_shell.dart';
import '../widgets/mascot_scene.dart';
import 'home/greeting_banner.dart';
import 'home/habit_card.dart';
import 'home/habit_sheets.dart';
import 'home/home_presets.dart';
import 'home/room_ambient_overlay.dart';
import 'home/room_metrics.dart';
import 'home/room_scene_painters.dart';

class HomePage extends StatefulWidget {
  final VoidCallback? onSettingsChanged;
  final bool waterHabitAutoComplete;
  final bool weightHabitAutoComplete;
  final Future<void> Function(bool)? onWaterHabitToggled;
  const HomePage({
    super.key,
    this.onSettingsChanged,
    this.waterHabitAutoComplete = false,
    this.weightHabitAutoComplete = false,
    this.onWaterHabitToggled,
  });

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with TickerProviderStateMixin {
  final List<Map<String, dynamic>> habits = [];
  bool isLoading = true;
  int streak = 0;
  String _nickname = '你';
  String mascotName0 = '兔咪';
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
  // 首頁場景的低調流動光效改由 RoomSceneEffects 自帶 30fps 節流 ticker 驅動，
  // 不再需要本頁持有 AnimationController（也就沒有 full-rate 重繪 / 漏 RepaintBoundary）。
  // 編輯模式所有卡片共用的抖動驅動（一條 ticker，各卡片用不同相位）。
  // 不放在每張卡上，避免被拖曳 reparent 時帶著正在跑的 ticker 撞 element 生命週期。
  late AnimationController _jiggleCtrl;

  final Set<String> _animatedIn = {};
  // 抖動排序模式（像 iOS 主畫面長按 App）：全卡片抖動＋可拖，底部換成完成鈕。
  // 進入＝長按任一卡片或「⋯」選單的「移動」；退出＝點「完成」。
  bool _editMode = false;

  // ── 首頁裝飾動畫的閒置凍結（省電 / 降溫）─────────────────────
  // 窗景 / 室內光影 / 場景流光是每幀重繪、且每幀跑 MaskFilter.blur 的層，
  // 停在首頁不互動時持續算繪會讓 GPU 一直滿載、機身發熱。沒人在操作時就
  // 凍結這些層，一有觸碰立刻恢復——觀感無損（沒人看才停）。
  // 兔咪本體呼吸不在此列：成本低且是情緒主體，保持活著。
  static const Duration _sceneIdleDelay = Duration(seconds: 20);
  Timer? _sceneIdleTimer;
  bool _sceneIdle = false;
  // 追蹤本頁是否為當前可見分頁（外層 TickerMode），切回來時喚醒場景。
  bool _wasVisible = true;

  // 有互動：取消計時、若正凍結則喚醒，並重排下一次閒置。
  void _markSceneActive() {
    _sceneIdleTimer?.cancel();
    if (_sceneIdle) {
      setState(() => _sceneIdle = false);
    }
    _sceneIdleTimer = Timer(_sceneIdleDelay, _goSceneIdle);
  }

  // 閒置到時：凍結所有裝飾動態層（窗景/光影/流光的 ticker 由 TickerMode 一起靜音）。
  void _goSceneIdle() {
    if (!mounted || _sceneIdle) return;
    setState(() => _sceneIdle = true);
  }

  @override
  void initState() {
    super.initState();
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

    loadHabits();
  }

  @override
  void dispose() {
    MascotPersona.current.removeListener(_handleMascotActivity);
    _sceneIdleTimer?.cancel();
    _celebCtrl.dispose();
    _glowCtrl.dispose();
    _jiggleCtrl.dispose();
    super.dispose();
  }

  void _handleMascotActivity() {
    _markSceneActive();
  }

  Future<void> loadHabits() async {
    final prefs = await SharedPreferences.getInstance();
    HomeSceneDebug.loadFromPrefs(prefs); // debug 截圖用時段覆寫，release no-op
    _dayStartHour = LogicalDate.load(prefs); // 算「今天」前先讀換日設定
    final today = todayString();
    final lastOpen = prefs.getString(PrefsKeys.lastOpenDate);
    streak = prefs.getInt(PrefsKeys.streak) ?? 0;
    _nickname = prefs.getString(PrefsKeys.userNickname) ?? '你';
    mascotName0 = prefs.getString(PrefsKeys.mascotName) ?? '兔咪';
    userBirthday = DateTime.tryParse(
      prefs.getString(PrefsKeys.userBirthday) ?? '',
    );

    final obDateStr = prefs.getString(PrefsKeys.onboardingDate);
    if (obDateStr != null) {
      onboardingDate = DateTime.tryParse(obDateStr);
    } else {
      onboardingDate = DateTime.now();
      await prefs.setString(
        PrefsKeys.onboardingDate,
        onboardingDate!.toIso8601String(),
      );
    }

    final habitsJson = prefs.getString(PrefsKeys.habits);
    if (habitsJson != null) {
      final decoded = jsonDecode(habitsJson) as List<dynamic>;
      habits.addAll(decoded.map((e) => Map<String, dynamic>.from(e as Map)));
    }

    // 遷移：補上穩定 id 與建立日（補打勾 / 統計用）。舊習慣不知道真正的
    // 建立日，退而用 onboarding 日期（至少不會晚於實際），再不行才用今天。
    // 之後新增的習慣會在建立當下就帶 id/createdAt，不靠這裡。
    var habitsMigrated = false;
    final fallbackCreated = onboardingDate != null
        ? _fmtDate(onboardingDate!)
        : today;
    for (final habit in habits) {
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
      await prefs.setString(PrefsKeys.habits, jsonEncode(habits));
    }

    // 跨日結算只在「邏輯日真的往前走」時做（結算昨天連勝 + 重置今天勾選）。
    // 換日時間往後調（夜貓把午夜往後挪）會讓「今天」字串往回跳，那不是真的
    // 新的一天——舊版只比 lastOpen != today，使用者凌晨反覆調換日時間就會反覆
    // 觸發結算，把連勝歸零、勾選清空。改用日期方向判斷，往回跳一律略過。
    // （金幣防重複另走真實日曆日 key，見 CoinService，本來就不受換日設定影響。）
    final lastOpenDay = lastOpen == null ? null : DateTime.tryParse(lastOpen);
    final todayDay = LogicalDate.dayOf(DateTime.now(), _dayStartHour);
    final crossedToNewDay =
        lastOpenDay != null && todayDay.isAfter(lastOpenDay);
    if (crossedToNewDay) {
      final dailyHabits = habits
          .where((h) => (h['frequency'] ?? 'daily') != 'weekly')
          .toList();
      final allDailyDone =
          dailyHabits.isNotEmpty && dailyHabits.every((h) => h['done'] == true);
      yesterdayAllDone = allDailyDone;
      if (dailyHabits.isNotEmpty) {
        if (allDailyDone) {
          // 連勝里程碑金幣已改綁「連續登入」（見 CoinService.claimDailyLogin），
          // 這裡只維持習慣連勝天數本身供顯示用，不再發幣。
          streak++;
        } else {
          streak = 0;
        }
        await prefs.setInt(PrefsKeys.streak, streak);
      }
      for (final habit in habits) {
        if ((habit['frequency'] ?? 'daily') != 'weekly') {
          habit['done'] = false;
        }
      }
      await prefs.setString(PrefsKeys.habits, jsonEncode(habits));
    }

    // 連勝里程碑 → 解鎖回憶事件（冪等：已解鎖會 no-op；既有高連勝用戶下次開啟補發）
    unawaited(StoryEvents.onHabitStreak(streak));
    // 第一個習慣：新增當下也會觸發（_showAddHabitSheet），這裡是補發——
    // 涵蓋 onboarding 建的習慣與既有資料，冪等所以重複呼叫沒關係。
    if (habits.isNotEmpty) unawaited(StoryEvents.onFirstHabitCreated());
    // 久違回來：要在 lastOpen 被覆寫成今天之前算天數（與問候語同一把尺）。
    final daysAwayForStory = _daysSinceDateString(lastOpen, todayDay);
    if (daysAwayForStory != null) {
      unawaited(StoryEvents.onComeback(daysAwayForStory));
    }

    // Always recompute done for weekly habits from weeklyDates
    for (final habit in habits) {
      if ((habit['frequency'] ?? 'daily') == 'weekly') {
        final target = (habit['weeklyTarget'] as int?) ?? 3;
        habit['done'] = _weeklyCount(habit) >= target;
      }
    }

    // 跨頁籤切換時首頁會整頁重建，didUpdateWidget 不會觸發，
    // 因此在這裡依喝水頁達標狀態同步「喝足夠的水」習慣的勾選狀態
    final waterIdx = habits.indexWhere((h) => h['name'] == '喝足夠的水');
    if (waterIdx != -1 &&
        habits[waterIdx]['done'] != widget.waterHabitAutoComplete) {
      habits[waterIdx]['done'] = widget.waterHabitAutoComplete;
      await prefs.setString(PrefsKeys.habits, jsonEncode(habits));
    }
    final weightIdx = habits.indexWhere(
      (h) =>
          (h['frequency'] ?? 'daily') != 'weekly' &&
          isWeightHabitName(h['name'] as String?),
    );
    if (weightIdx != -1 &&
        habits[weightIdx]['done'] != widget.weightHabitAutoComplete) {
      habits[weightIdx]['done'] = widget.weightHabitAutoComplete;
      await prefs.setString(PrefsKeys.habits, jsonEncode(habits));
    }

    // 把今天每日習慣的完成狀態寫進歷史（跨日 reset 後是空集合＝今天重新開始；
    // 同日重開則與當下勾選一致）。歷史只增不洗掉過去的日期。
    await _syncTodayHistory(prefs);

    final isFirstOpenToday = crossedToNewDay || lastOpenDay == null;
    // lastOpen 只往前推進，不因換日設定往回調而回退（否則調回來再開又重觸發結算）。
    if (lastOpenDay == null || todayDay.isAfter(lastOpenDay)) {
      await prefs.setString(PrefsKeys.lastOpenDate, today);
    }
    setState(() => isLoading = false);
    _markSceneActive(); // 內容出現後開始計閒置

    if (isFirstOpenToday && mounted) {
      Future.delayed(const Duration(milliseconds: 400), () {
        if (mounted) showGreeting(prefs, lastOpen);
      });
    }
  }

  void showGreeting(SharedPreferences prefs, String? lastOpen) {
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
      return '你回來了。\n我有把這裡留著。';
    }
    if (daysAway != null && daysAway >= 2) return '你回來了。\n我還在。';

    if (streak >= 30 && streak % 10 == 0) {
      return '連續 $streak 天了。\n你真的一天一天走過來。';
    }
    if (streak == 14) return '連續兩週了。\n這已經是你的節奏了。';
    if (streak == 7) return '連續一週了。\n你一直有回來。';
    if (yesterdayAllDone) return '昨天也完成了。\n兔咪有看到。';

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
    return '早安，$_nickname。\n今天也從一點點開始？';
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
    Future.delayed(const Duration(seconds: 2), () {
      if (entry.mounted) entry.remove();
    });
  }

  String _fmtDate(DateTime d) {
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '${d.year}-$m-$day';
  }

  // 換日線往後挪時，睡前完成的習慣仍算前一天（與喝水/體重一致）。
  String todayString() => LogicalDate.stringFor(DateTime.now(), _dayStartHour);

  List<String> _currentWeekStrings() {
    // 用邏輯日的今天決定本週，weeklyDates 也是用 todayString() 存的。
    final today = LogicalDate.dayOf(DateTime.now(), _dayStartHour);
    final monday = today.subtract(Duration(days: today.weekday - 1));
    return List.generate(7, (i) => _fmtDate(monday.add(Duration(days: i))));
  }

  int _weeklyCount(Map<String, dynamic> habit) {
    final dates = List<String>.from((habit['weeklyDates'] as List?) ?? []);
    final weekSet = _currentWeekStrings().toSet();
    return dates.where(weekSet.contains).length;
  }

  Future<void> saveHabits() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(PrefsKeys.habits, jsonEncode(habits));
  }

  // 把「今天已完成的每日習慣 id」覆寫進歷史。每日習慣以 done 為準（set 語意）；
  // 每週習慣的逐日紀錄另存在 weeklyDates，不在這裡。
  Future<void> _syncTodayHistory(SharedPreferences prefs) async {
    final ids = _dailyHabits
        .where((h) => h['done'] == true)
        .map((h) => h['id'])
        .whereType<String>()
        .toList();
    await HabitHistory.setDoneIdsOn(prefs, todayString(), ids);
  }

  // 互動後 fire-and-forget 更新今天的歷史（取自家的 prefs 實例）。
  Future<void> _recordTodayHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await _syncTodayHistory(prefs);
  }

  void _startMovingHabits() {
    if (_editMode) return;
    setState(() => _editMode = true);
    _jiggleCtrl.repeat();
    playFeedback(SfxCue.tap);
  }

  void _finishMovingHabits() {
    if (!_editMode) return;
    setState(() => _editMode = false);
    _jiggleCtrl
      ..stop()
      ..value = 0;
    playFeedback(SfxCue.tap);
  }

  void _reorderHabitSection({
    required bool weekly,
    required int oldIndex,
    required int newIndex,
  }) {
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
    if (oldWidget.waterHabitAutoComplete != widget.waterHabitAutoComplete) {
      _syncWaterHabit(widget.waterHabitAutoComplete);
    }
    if (oldWidget.weightHabitAutoComplete != widget.weightHabitAutoComplete) {
      _syncWeightHabit(widget.weightHabitAutoComplete);
    }
  }

  void _syncWaterHabit(bool done) {
    final idx = habits.indexWhere((h) => h['name'] == '喝足夠的水');
    if (idx == -1 || habits[idx]['done'] == done) return;
    setState(() => habits[idx]['done'] = done);
    saveHabits();
    unawaited(_recordTodayHistory());
  }

  void _syncWeightHabit(bool done) {
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
  int _mascotReactionTick = 0;

  void _showTransientMascot(
    String name, {
    Duration duration = const Duration(seconds: 2),
  }) {
    setState(() {
      _transientMascot = name;
      _mascotReactionTick++;
    });
    _syncMascotToPersona();
    Future.delayed(duration, () {
      if (mounted) {
        setState(() => _transientMascot = null);
        _syncMascotToPersona();
      }
    });
  }

  void _onMascotTap() {
    _celebCtrl.forward(from: 0);
    final speech = MascotLines.randomHomeTapLineFor(_mascotContext);
    setState(() {
      _transientSpeech = speech;
      _mascotReactionTick++;
    });
    final accepted = _syncMascotToPersona();
    if (accepted) {
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) {
          setState(() => _transientSpeech = null);
          _syncMascotToPersona();
        }
      });
    } else {
      setState(() => _transientSpeech = null);
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

  MascotContext get _mascotContext {
    if (_transientMascot == 'sad') return MascotContext.undone;
    if (_transientSpeech != null) return MascotContext.tapReaction;
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

  void toggleHabit(int index) {
    final wasAllDone = allDone0;
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
      if (wasDone) _showTransientMascot('sad');
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
      // 當日全完成加碼（每日一次，service 內建防重複）
      CoinService.award(CoinSource.allHabitsDone, note: '今日全完成');
      playFeedback(SfxCue.complete);
      _celebCtrl.forward(from: 0);
      setState(() => _mascotReactionTick++);
      // 第一次全完成 → 回憶事件（冪等；揭曉由 MainPage 佇列稍後接手播）
      unawaited(StoryEvents.onFirstAllDone());
    } else if (habits[index]['done'] == true) {
      if (!wasHabitDone) {
        playFeedback(SfxCue.success);
      } else {
        playFeedback(SfxCue.tap);
      }
      setState(() => _mascotReactionTick++);
    } else if (isWeekly) {
      // 每週習慣累加但還沒達標：是正向操作，給 tap 不給 cancel
      playFeedback(SfxCue.tap);
      setState(() => _mascotReactionTick++);
    } else {
      playFeedback(SfxCue.cancel);
    }
    if (habits[index]['name'] == '喝足夠的水') {
      widget.onWaterHabitToggled?.call(habits[index]['done'] as bool);
    }
    _syncMascotToPersona();
  }

  void decrementWeeklyHabit(int index) {
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
    _showTransientMascot('sad');
  }

  void deleteHabit(int index) {
    final habit = habits[index];
    final name = habit['name'] as String;
    final id = habit['id'] as String?;
    final createdAt = habit['createdAt'] as String?;
    final frequency = (habit['frequency'] ?? 'daily') as String;
    _animatedIn.remove(name);
    setState(() => habits.removeAt(index));
    saveHabits();
    // 留一筆墓碑：補打勾仍能顯示「當時存在、後來刪掉」的條目。
    // 同時刷新今天的歷史（刪掉的習慣不該再算在今天的完成集合裡）。
    if (id != null) {
      SharedPreferences.getInstance().then((prefs) async {
        await HabitHistory.addTombstone(
          prefs,
          id: id,
          name: name,
          frequency: frequency,
          createdAt: createdAt ?? todayString(),
          deletedAt: todayString(),
        );
        await _syncTodayHistory(prefs);
      });
    }
    if (name == '喝足夠的水') {
      SharedPreferences.getInstance().then((prefs) async {
        await prefs.setBool(PrefsKeys.waterEnabled, false);
        widget.onSettingsChanged?.call();
      });
    } else if (isWeightHabitName(name)) {
      SharedPreferences.getInstance().then((prefs) async {
        await prefs.setBool(PrefsKeys.weightTrackingEnabled, false);
        widget.onSettingsChanged?.call();
      });
    }
  }

  Future<void> renameHabit(int index) async {
    final ctrl = TextEditingController(text: habits[index]['name'] as String);
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('改名'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLength: kHabitNameMaxLength,
          decoration: const InputDecoration(labelText: '習慣名稱'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('取消', style: TextStyle(color: Colors.grey.shade600)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('儲存'),
          ),
        ],
      ),
    );
    if (result != true) return;
    final name = clampHabitName(ctrl.text);
    if (name.isEmpty) return;
    setState(() => habits[index]['name'] = name);
    unawaited(saveHabits());
  }

  Future<void> _confirmDeleteHabit(int index) async {
    final name = habits[index]['name'] as String;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('刪除習慣'),
        content: Text('確定要刪除「$name」嗎？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('取消', style: TextStyle(color: Colors.grey.shade600)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('刪除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirm == true) deleteHabit(index);
  }

  Future<void> _editHabitSheet(int index) async {
    await showEditHabitSheet(
      context,
      habit: habits[index],
      onSave: (newName, freq, weeklyTarget) {
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
            var settingsChanged = false;
            final prefs = await SharedPreferences.getInstance();
            for (final name in selected.keys) {
              final idx = available.indexWhere((p) => p.name == name);
              if (idx != -1 && available[idx].linkedSetting != null) {
                final already =
                    prefs.getBool(available[idx].linkedSetting!) ?? false;
                if (!already) {
                  await prefs.setBool(available[idx].linkedSetting!, true);
                  settingsChanged = true;
                }
              }
            }
            if (settingsChanged) {
              widget.onSettingsChanged?.call();
            }
            setState(() {
              if (customName.isNotEmpty) {
                final fullName = customMinutes > 0
                    ? '$customName $customMinutes 分鐘'
                    : customName;
                final map = <String, dynamic>{
                  'id': HabitHistory.newId(),
                  'name': fullName,
                  'createdAt': todayString(),
                  'done':
                      isWeightHabitName(fullName) &&
                      widget.weightHabitAutoComplete,
                  'frequency': freq,
                };
                if (freq == 'weekly') {
                  map['weeklyTarget'] = weeklyTarget;
                  map['weeklyDates'] = <String>[];
                }
                habits.add(map);
              }
              for (final entry in selected.entries) {
                final p = available.firstWhere((p) => p.name == entry.key);
                final cfg = entry.value;
                final habitName = (p.defaultMinutes != null && cfg.minutes > 0)
                    ? '${p.name} ${cfg.minutes} 分鐘'
                    : p.name;
                final map = <String, dynamic>{
                  'id': HabitHistory.newId(),
                  'name': habitName,
                  'createdAt': todayString(),
                  'done':
                      isWeightHabitName(habitName) &&
                      widget.weightHabitAutoComplete,
                  'frequency': cfg.frequency,
                };
                if (cfg.frequency == 'weekly') {
                  map['weeklyTarget'] = cfg.weeklyTarget;
                  map['weeklyDates'] = <String>[];
                }
                habits.add(map);
              }
            });
            unawaited(saveHabits());
            unawaited(_recordTodayHistory());
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
              // 窗外景：墊在背景圖之下，透過挖掉的窗玻璃露出來
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: bgH,
                // 閒置時凍結：TickerMode 靜音子樹 ticker，停止每幀重繪。
                child: TickerMode(
                  enabled: !_sceneIdle,
                  child: const WindowBackdrop(),
                ),
              ),
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: bgH,
                child: ClipRect(
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: Image.asset(
                      // 窗玻璃挖透明的版本（原圖保留為 home_bg.png）
                      'assets/scenes/home/home_bg_glassless.png',
                      height: double.infinity,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      alignment: Alignment.topCenter,
                    ),
                  ),
                ),
              ),
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
              // 動態光影層：窗光/塵埃/檯燈暈，讓靜態房間活起來
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: bgH,
                // 最吃 GPU 的層（每幀 MaskFilter.blur）：閒置時一起凍結。
                child: TickerMode(
                  enabled: !_sceneIdle,
                  child: const RoomAmbientOverlay(companionTiming: true),
                ),
              ),
              // 互動狀態效果（完成星光、場景柔光）：最吃 GPU 的全螢幕 blur 層，
              // 比照窗景/光影層做 30fps 節流 + RepaintBoundary，閒置時 TickerMode 凍結。
              Positioned.fill(
                child: TickerMode(
                  enabled: !_sceneIdle,
                  child: RoomSceneEffects(
                    accent: colors.accent,
                    progress: sceneProgress.clamp(0.0, 1.0),
                    allDone: allDone0 && habits.isNotEmpty,
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
      scene: ScaleTransition(
        scale: _celebScale,
        child: PersonaScene(
          accent: colors.accent,
          reactionTick: _mascotReactionTick,
          onTap: _onMascotTap,
          onHeadPet: _onMascotHeadPet,
          paused: _sceneIdle, // 閒置時連兔咪呼吸/眨眼一起凍結 → 畫面全靜止
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

  /// 把首頁當下計算出的兔咪狀態同步到全域 [MascotPersona]。
  /// 只在「使用者互動後」呼叫（toggleHabit / onMascotTap / showTransientMascot）。
  bool _syncMascotToPersona() {
    return MascotPersona.setForContext(
      _mascotAsset,
      _mascotContext,
      speech: _transientSpeech,
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
                    tween: Tween(begin: 0.0, end: progress),
                    duration: const Duration(milliseconds: 700),
                    curve: Curves.easeOut,
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

  // 房間背景圖上的時段色罩（順序與 _sceneColors 一致：全完成 > 夜 > 晨 > 暮）
  Color get _sceneTint {
    final hour = sceneHourNow();
    if (allDone0 && habits.isNotEmpty) {
      return const Color(0xFFFFF3C4).withValues(alpha: 0.10);
    }
    if (hour >= 18 || hour < 6) {
      return const Color(0xFFFFD7A0).withValues(alpha: 0.055);
    }
    if (hour < 8) {
      return const Color(0xFFFFE0B8).withValues(alpha: 0.045);
    }
    if (hour >= 16 && hour < 18) {
      return const Color(0xFFFFB36B).withValues(alpha: 0.075);
    }
    return Colors.transparent;
  }

  // 場景配色：全完成 > 夜晚暖燈 > 清晨 > 黃昏 > 白天
  ({Color top, Color bottom, Color accent}) get _sceneColors {
    final hour = sceneHourNow();
    if (allDone0 && habits.isNotEmpty) {
      return (
        top: const Color(0xFFE8F8E5),
        bottom: const Color(0xFFCDEFCD),
        accent: const Color(0xFF66BB6A),
      );
    }
    if (hour >= 18 || hour < 6) {
      return (
        top: const Color(0xFFFFF4E8),
        bottom: const Color(0xFFEED8C4),
        accent: const Color(0xFFC28A55),
      );
    }
    if (hour < 8) {
      // 清晨：粉金日出
      return (
        top: const Color(0xFFFFF6EA),
        bottom: const Color(0xFFFFE0C5),
        accent: const Color(0xFFF08A62),
      );
    }
    if (hour >= 16 && hour < 18) {
      // 黃昏：陽光收進溫柔金橘
      return (
        top: const Color(0xFFFFEACF),
        bottom: const Color(0xFFF1C9A8),
        accent: const Color(0xFFC47A52),
      );
    }
    return (
      top: const Color(0xFFFFF4E0),
      bottom: const Color(0xFFFFE5C7),
      accent: const Color(0xFFFF8A50),
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
                  '新增習慣',
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
                const Text(
                  '完成排序',
                  style: TextStyle(
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
            shadowColor: Colors.black.withValues(alpha: 0.18),
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
          if (_editMode) {
            playFeedback(SfxCue.tap);
          } else {
            // 首次長按拖曳：本幀後再翻成編輯模式，避免拖曳啟動當下重建清單
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _startMovingHabits();
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
                label: '每日習慣',
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
                label: '每週習慣',
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
                const Text(
                  '還沒有任何習慣',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: AppInk.strong,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  '點上面的「新增習慣」\n從一件小事開始吧',
                  textAlign: TextAlign.center,
                  style: TextStyle(
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
