import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'pages/family_page.dart';
import 'pages/home/room_ambient_overlay.dart';
import 'pages/home_page.dart';
import 'pages/onboarding_page.dart';
import 'pages/timer_page.dart';
import 'pages/wardrobe_page.dart';
import 'pages/water_page.dart';
import 'pages/weight_page.dart';
import 'utils/audio_settings_service.dart';
import 'utils/bgm_service.dart';
import 'utils/coin_config.dart';
import 'utils/coin_service.dart';
import 'utils/debug_fake_tabs.dart';
import 'utils/feature_flags.dart';
import 'utils/mascot.dart';
import 'utils/notification_service.dart';
import 'utils/parent_pin.dart';
import 'utils/prefs_keys.dart';
import 'utils/sfx_service.dart';
import 'utils/wardrobe_store.dart';
import 'utils/weight_records.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

Future<_StartupState> _loadStartupState() async {
  // 鎖定只支援直向（防止橫向自動翻轉）
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  final prefs = await SharedPreferences.getInstance();
  // 舊版明文 PIN 啟動時就地雜湊遷移（hasPin 內含遷移邏輯）
  await ParentPin.hasPin(prefs);
  final onboardingDone = prefs.getBool(PrefsKeys.onboardingDone) ?? false;
  // 載入兔咪展開/收合偏好（全 app 共用同一個 toggle）
  await MascotPanelPrefs.load();
  // 金幣餘額載進全域 notifier（UI 反應式讀取）
  await CoinService.load();
  // 衣櫃/音樂盒狀態載進全域 notifier（首頁兔咪皮膚、目前曲在 MainPage build 前就緒）
  await WardrobeStore.load();
  await AudioSettingsService.instance.init();
  // 初始化本機通知（計時頁倒數結束鈴用）；權限到第一次排通知才會跳 dialog
  await NotificationService.init();
  // App 冷啟動：兔咪從 openApp 池隨機抽一句問候，每次打開都有變化
  MascotPersona.resetToOpening();
  return _StartupState(startAtHome: onboardingDone);
}

Future<void> _startInitialAudio({required bool onboardingDone}) async {
  try {
    await Future<void>.delayed(const Duration(milliseconds: 900));
    await BgmService.instance.init();
    // 進主頁播使用者在音樂盒選的目前曲（預設仍是 bgm_main，既有用戶無感）；
    // 前導流程固定播 onboarding 曲。
    final asset = onboardingDone
        ? await WardrobeStore.loadCurrentTrackAsset()
        : 'sounds/bgm_onboarding.m4a';
    // 冷啟動兩種情況（新用戶前導 / 既有用戶直接進主頁）都走 deferFade：
    // 先靜音喚醒音訊路由，settle 後再柔和淡入，避免一開就突兀出現。
    await BgmService.instance.play(asset, deferFade: true);
    await SfxService.instance.init();
  } catch (e, st) {
    debugPrint('BGM init/play failed: $e\n$st');
  }
}

class _StartupState {
  final bool startAtHome;
  const _StartupState({required this.startAtHome});
}

class MyApp extends StatefulWidget {
  final bool? startAtHome;
  const MyApp({super.key, this.startAtHome});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late final Future<_StartupState> _startupFuture = widget.startAtHome == null
      ? _loadStartupState()
      : Future.value(_StartupState(startAtHome: widget.startAtHome!));
  bool _initialAudioScheduled = false;

  void _scheduleInitialAudio(bool startAtHome) {
    if (_initialAudioScheduled || widget.startAtHome != null) return;
    _initialAudioScheduled = true;
    // BGM 初始化 + 播放放到第一個 frame 之後再稍微延遲。
    // flutter run --release 安裝後自動拉起 app 時，iOS 音訊路由偶爾還沒穩；
    // 等畫面 settled 再啟動音樂，比 main() 裡立刻 play 更可靠。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_startInitialAudio(onboardingDone: startAtHome));
    });
  }

  Widget _buildHome() {
    final testStartAtHome = widget.startAtHome;
    if (testStartAtHome != null) {
      return testStartAtHome ? const MainPage() : const OnboardingPage();
    }
    return FutureBuilder<_StartupState>(
      future: _startupFuture,
      builder: (context, snapshot) {
        final data = snapshot.data;
        final ready =
            snapshot.connectionState == ConnectionState.done &&
            data != null &&
            !snapshot.hasError;
        if (ready) _scheduleInitialAudio(data.startAtHome);
        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 360),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          child: ready
              ? data.startAtHome
                    ? const MainPage(key: ValueKey('main'))
                    : const OnboardingPage(key: ValueKey('onboarding'))
              : const _StartupSplash(key: ValueKey('startup')),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '兔咪好習慣',
      debugShowCheckedModeBanner: false,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('zh', 'TW')],
      locale: const Locale('zh', 'TW'),
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFFF7043)),
        useMaterial3: true,
        fontFamily: GoogleFonts.nunito().fontFamily,
        scaffoldBackgroundColor: const Color(0xFFF7F3EF),
        cardTheme: CardThemeData(
          elevation: 2,
          shadowColor: Colors.black12,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          color: Colors.white,
        ),
        appBarTheme: AppBarTheme(
          backgroundColor: const Color(0xFFFF7043),
          foregroundColor: Colors.white,
          elevation: 0,
          iconTheme: const IconThemeData(color: Colors.white),
          titleTextStyle: GoogleFonts.nunito(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w700,
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.grey.shade50,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 14,
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
        ),
        // 彈出選單/對話框統一暖白卡面 + 暖棕陰影，跟卡片語彙一致
        popupMenuTheme: PopupMenuThemeData(
          color: const Color(0xFFFFFDF9),
          surfaceTintColor: Colors.transparent,
          elevation: 6,
          shadowColor: const Color(0xFF8D6E63).withValues(alpha: 0.4),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        dialogTheme: DialogThemeData(
          backgroundColor: const Color(0xFFFFFDF9),
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
          ),
        ),
      ),
      home: _buildHome(),
      routes: {
        '/onboarding': (_) => const OnboardingPage(),
        '/home': (_) => const MainPage(),
      },
    );
  }
}

class _StartupSplash extends StatefulWidget {
  const _StartupSplash({super.key});

  @override
  State<_StartupSplash> createState() => _StartupSplashState();
}

class _StartupSplashState extends State<_StartupSplash>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFF6EE),
      body: Stack(
        fit: StackFit.expand,
        children: [
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Color(0xFFFFF7EE),
                  Color(0xFFFFE5D3),
                  Color(0xFFEAF5EF),
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),
          SafeArea(
            child: Center(
              child: AnimatedBuilder(
                animation: _controller,
                builder: (context, child) {
                  final lift =
                      -6 * Curves.easeInOut.transform(_controller.value);
                  return Transform.translate(
                    offset: Offset(0, lift),
                    child: child,
                  );
                },
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 138,
                      height: 138,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.82),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: const Color(
                              0xFFB97856,
                            ).withValues(alpha: 0.18),
                            blurRadius: 28,
                            offset: const Offset(0, 16),
                          ),
                        ],
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(18),
                        child: Image.asset(
                          MascotEmotion.happy.assetPath,
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                    const SizedBox(height: 22),
                    Text(
                      '兔咪好習慣',
                      style: GoogleFonts.nunito(
                        color: const Color(0xFF6D4C41),
                        fontSize: 25,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 18),
                    const SizedBox(width: 96, child: _StartupLoadingBar()),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StartupLoadingBar extends StatelessWidget {
  const _StartupLoadingBar();

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(99),
      child: LinearProgressIndicator(
        minHeight: 5,
        backgroundColor: Colors.white.withValues(alpha: 0.78),
        color: const Color(0xFFFF8A65),
      ),
    );
  }
}

class MainPage extends StatefulWidget {
  const MainPage({super.key});

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> with WidgetsBindingObserver {
  int _currentIndex = 0;
  bool _waterEnabled = false;
  bool _timerEnabled = true;
  bool _weightTrackingEnabled = false;
  bool _familyEnabled = false;
  bool _wardrobeEnabled = true;
  bool _waterGoalReached = false;
  bool _weightHabitAutoComplete = false;
  bool _loaded = false;
  int _waterReloadTrigger = 0;
  Set<String> _debugFakeTabIds = const {}; // debug：模擬功能分頁開關（release 不讀）

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadSettings();
    // 功能開關一改就即時重組頁籤（不必等退出設定頁）
    featureFlagsRevision.addListener(_loadSettings);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _ensureMainBgm();
      _claimDailyLoginReward();
    });
  }

  @override
  void dispose() {
    featureFlagsRevision.removeListener(_loadSettings);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // App 退到背景就清除家長 Session，回前景需重新驗證密碼，
    // 避免家長驗證後把手機交給小孩時 Session 還活著
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      parentSession.value = false;
    }
    // 跨日後從背景回來也能領當天的登入獎勵（已領過會直接 no-op）
    if (state == AppLifecycleState.resumed) {
      _claimDailyLoginReward();
    }
  }

  // 每日登入獎勵：兔咪報喜。延遲一拍讓開場問候先落地，再換成領獎台詞。
  Future<void> _claimDailyLoginReward() async {
    final reward = await CoinService.claimDailyLogin();
    if (reward == null || !mounted) return;
    await Future<void>.delayed(const Duration(milliseconds: 900));
    if (!mounted) return;
    final line = reward.graceUsed
        ? '昨天我幫你看家了～金幣照領，+${reward.amount}！'
        : reward.level >= CoinConfig.loginMaxLevel
        ? '連續報到 Lv.${reward.level}！今天 +${reward.amount} 金幣。'
        : '你來了！見面禮 +${reward.amount} 金幣。';
    MascotPersona.set(MascotEmotion.happy.assetPath, line, force: true);
  }

  Future<void> _ensureMainBgm() async {
    try {
      await Future<void>.delayed(const Duration(milliseconds: 2800));
      if (!mounted) return;
      await BgmService.instance.ensurePlaying('sounds/bgm_main.m4a');
    } catch (e, st) {
      debugPrint('Main BGM ensure failed: $e\n$st');
    }
  }

  String _todayString() {
    final now = DateTime.now();
    final m = now.month.toString().padLeft(2, '0');
    final d = now.day.toString().padLeft(2, '0');
    return '${now.year}-$m-$d';
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final today = _todayString();
    final weightRecordedToday = await hasSavedWeightRecordForDate(prefs, today);
    setState(() {
      _waterEnabled = prefs.getBool(PrefsKeys.waterEnabled) ?? false;
      _timerEnabled = prefs.getBool(PrefsKeys.timerEnabled) ?? true;
      _weightTrackingEnabled =
          prefs.getBool(PrefsKeys.weightTrackingEnabled) ?? false;
      _familyEnabled = prefs.getBool(PrefsKeys.familyEnabled) ?? false;
      _wardrobeEnabled = prefs.getBool(PrefsKeys.wardrobeEnabled) ?? true;
      _waterGoalReached = prefs.getString(PrefsKeys.waterGoalDate) == today;
      _weightHabitAutoComplete = weightRecordedToday;
      // debug 截圖用：指定啟動分頁（release 不讀）
      if (kDebugMode) {
        final tab = prefs.getInt(PrefsKeys.debugStartTab);
        if (tab != null) _currentIndex = tab;
        _debugFakeTabIds =
            (prefs.getStringList(PrefsKeys.debugFakeTabs) ?? const <String>[])
                .toSet();
      }
      _loaded = true;
    });
  }

  Future<void> _handleWaterGoal(bool reached) async {
    final prefs = await SharedPreferences.getInstance();
    if (reached) {
      await prefs.setString(PrefsKeys.waterGoalDate, _todayString());
      // 當日喝水達標 +金幣（每日一次，service 內建防重複）
      await CoinService.award(CoinSource.waterGoal, note: '喝水達標');
    } else {
      await prefs.remove(PrefsKeys.waterGoalDate);
    }
    setState(() => _waterGoalReached = reached);
  }

  void _handleWeightRecordsChanged() {
    unawaited(_refreshWeightHabitAutoComplete());
  }

  Future<void> _refreshWeightHabitAutoComplete() async {
    final prefs = await SharedPreferences.getInstance();
    final done = await hasSavedWeightRecordForDate(prefs, _todayString());
    if (!mounted) return;
    setState(() => _weightHabitAutoComplete = done);
  }

  Map<String, Object> _waterEntryMap({
    required int ml,
    required String kind,
    DateTime? at,
  }) {
    return {
      'ml': ml, // units-ok
      'kind': kind,
      'at': (at ?? DateTime.now()).toIso8601String(),
    };
  }

  List<Map<String, Object>> _waterEntriesFromLegacy({
    required int cups,
    required int cupMl,
    required int extraMl,
  }) {
    final now = DateTime.now();
    return [
      for (var i = 0; i < cups; i++)
        _waterEntryMap(
          ml: cupMl,
          kind: 'cup',
          at: now.add(Duration(seconds: i)),
        ),
      if (extraMl > 0)
        _waterEntryMap(
          ml: extraMl,
          kind: 'custom',
          at: now.add(Duration(seconds: cups)),
        ),
    ];
  }

  Future<void> _writeWaterEntries(
    SharedPreferences prefs,
    String today,
    List<Map<String, Object>> entries,
  ) async {
    final cupCount = entries.where((entry) => entry['kind'] == 'cup').length;
    final cupMlTotal = entries
        .where((entry) => entry['kind'] == 'cup')
        .fold<int>(
          0,
          (sum, entry) => sum + ((entry['ml'] as int?) ?? 0),
        ); // units-ok
    final totalMl = entries.fold<int>(
      0,
      (sum, entry) => sum + ((entry['ml'] as int?) ?? 0), // units-ok
    );
    await prefs.setString(PrefsKeys.waterEntries(today), jsonEncode(entries));
    await prefs.setInt(PrefsKeys.waterDay(today), cupCount);
    await prefs.setInt(
      PrefsKeys.waterExtra(today),
      (totalMl - cupMlTotal).clamp(0, 12000).toInt(),
    );
  }

  Future<void> _handleWaterHabitToggle(bool checked) async {
    final prefs = await SharedPreferences.getInstance();
    final cupMl = prefs.getInt(PrefsKeys.waterCupMl) ?? 250;
    final goalMl = prefs.getInt(PrefsKeys.waterGoalMl) ?? 2000;
    final waterGoal = (goalMl / cupMl).ceil();
    final today = _todayString();
    final todayKey = PrefsKeys.waterDay(today);
    final savedKey = PrefsKeys.waterSaved(today);
    final entriesKey = PrefsKeys.waterEntries(today);
    final savedEntriesKey = PrefsKeys.waterEntriesSaved(today);
    final extraKey = PrefsKeys.waterExtra(today);

    if (checked) {
      final actual = prefs.getInt(todayKey) ?? 0;
      final extraMl = prefs.getInt(extraKey) ?? 0;
      final currentEntries = prefs.getString(entriesKey);
      await prefs.setInt(savedKey, actual);
      await prefs.setString(
        savedEntriesKey,
        currentEntries ??
            jsonEncode(
              _waterEntriesFromLegacy(
                cups: actual,
                cupMl: cupMl,
                extraMl: extraMl,
              ),
            ),
      );
      await _writeWaterEntries(prefs, today, [
        for (var i = 0; i < waterGoal; i++)
          _waterEntryMap(
            ml: cupMl,
            kind: 'cup',
            at: DateTime.now().add(Duration(seconds: i)),
          ),
      ]);
      await _handleWaterGoal(true);
    } else {
      final saved = prefs.getInt(savedKey) ?? 0;
      final savedEntries = prefs.getString(savedEntriesKey);
      final entries = savedEntries == null
          ? _waterEntriesFromLegacy(cups: saved, cupMl: cupMl, extraMl: 0)
          : (jsonDecode(savedEntries) as List<dynamic>)
                .whereType<Map<String, dynamic>>()
                .map(
                  (entry) => {
                    'ml': ((entry['ml'] as num?) ?? cupMl).round(), // units-ok
                    'kind': entry['kind'] == 'cup' ? 'cup' : 'custom',
                    'at': entry['at'] is String
                        ? entry['at'] as String
                        : DateTime.now().toIso8601String(),
                  },
                )
                .toList();
      await _writeWaterEntries(prefs, today, entries);
      await prefs.remove(savedKey);
      await prefs.remove(savedEntriesKey);
      final restoredTotal = entries.fold<int>(
        0,
        (sum, entry) => sum + ((entry['ml'] as int?) ?? 0), // units-ok
      );
      await _handleWaterGoal(restoredTotal >= goalMl);
    }
    setState(() => _waterReloadTrigger++);
  }

  // 依功能開關動態組裝頁籤
  List<_TabItem> get _tabs {
    final list = <_TabItem>[
      _TabItem(
        page: HomePage(
          onSettingsChanged: _loadSettings,
          waterHabitAutoComplete: _waterGoalReached,
          weightHabitAutoComplete: _weightHabitAutoComplete,
          onWaterHabitToggled: _handleWaterHabitToggle,
        ),
        icon: Icons.home,
        label: '習慣',
      ),
    ];
    if (_timerEnabled) {
      list.add(
        _TabItem(page: const TimerPage(), icon: Icons.timer, label: '計時'),
      );
    }
    if (_waterEnabled) {
      list.add(
        _TabItem(
          page: WaterPage(
            onGoalStatusChanged: _handleWaterGoal,
            reloadTrigger: _waterReloadTrigger,
          ),
          icon: Icons.water_drop,
          label: '喝水',
        ),
      );
    }
    // 體重頁籤，依 weight_tracking_enabled 開關決定是否顯示
    if (_weightTrackingEnabled) {
      list.add(
        _TabItem(
          page: WeightPage(onRecordsChanged: _handleWeightRecordsChanged),
          icon: Icons.monitor_weight,
          label: '體重',
        ),
      );
    }
    if (_familyEnabled) {
      list.add(
        _TabItem(
          page: FamilyPage(onSettingsChanged: _loadSettings),
          icon: Icons.family_restroom,
          label: '家庭',
        ),
      );
    }
    if (_wardrobeEnabled) {
      list.add(
        const _TabItem(
          page: WardrobePage(),
          icon: Icons.checkroom_rounded,
          label: '衣櫃',
        ),
      );
    }
    // debug：像正式功能開關一樣，開哪個模擬功能就真的多哪個分頁（release 不讀）。
    if (kDebugMode && _debugFakeTabIds.isNotEmpty) {
      for (final spec in debugFakeTabSpecs) {
        if (_debugFakeTabIds.contains(spec.id)) {
          list.add(_debugFeatureTab(spec));
        }
      }
    }
    return list;
  }

  _TabItem _debugFeatureTab(DebugFakeTabSpec spec) {
    return _TabItem(
      page: _DebugFeaturePage(spec: spec),
      icon: spec.icon,
      label: spec.label,
    );
  }

  // 底部列點擊：單排/兩排共用。
  void _onTabTapped(List<_TabItem> tabs, int index) {
    // 離開家庭頁籤時清除家長 Session，下次進入需重新驗證
    final familyIdx = tabs.indexWhere((t) => t.label == '家庭');
    if (familyIdx != -1 && _currentIndex == familyIdx && index != familyIdx) {
      parentSession.value = false;
    }
    final wardrobeIdx = tabs.indexWhere((t) => t.label == '衣櫃');
    if (wardrobeIdx != -1 &&
        _currentIndex == wardrobeIdx &&
        index != wardrobeIdx) {
      unawaited(WardrobePreviewController.restore());
    }
    setState(() => _currentIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final tabs = _tabs;
    // 確保 index 不超界
    if (_currentIndex >= tabs.length) _currentIndex = 0;

    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: List.generate(tabs.length, (i) {
          final tab = tabs[i];
          return TickerMode(
            enabled: i == _currentIndex,
            child: KeyedSubtree(key: ValueKey(tab.label), child: tab.page),
          );
        }),
      ),
      bottomNavigationBar: tabs.length == 1
          // 只有習慣頁時，用裝飾條取代 bottom nav，
          // 確保版面高度跟「有開其他功能」時一致，兔咪/對話框位置不會跑掉
          ? const _DecorativeFloor()
          : _AdaptiveBottomNav(
              tabs: tabs,
              currentIndex: _currentIndex,
              onTap: (index) => _onTabTapped(tabs, index),
            ),
    );
  }
}

// 頁籤資料結構
class _TabItem {
  final Widget page;
  final IconData icon;
  final String label;
  const _TabItem({required this.page, required this.icon, required this.label});
}

class _DebugFeaturePage extends StatelessWidget {
  final DebugFakeTabSpec spec;
  const _DebugFeaturePage({required this.spec});

  @override
  Widget build(BuildContext context) {
    final color = spec.color;
    return ColoredBox(
      color: Color.alphaBlend(color.withValues(alpha: 0.06), Colors.white),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 28),
          children: [
            Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Icon(spec.icon, color: color, size: 28),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        spec.label,
                        style: const TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF3E3029),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        spec.subtitle,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF8C7A70),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            _DebugFeatureCard(
              color: color,
              icon: Icons.dashboard_customize_rounded,
              title: '${spec.label}首頁',
              body: '這裡會放${spec.label}的主要內容、狀態摘要與常用操作。',
            ),
            const SizedBox(height: 10),
            _DebugFeatureCard(
              color: color,
              icon: Icons.tune_rounded,
              title: '功能面板',
              body: '這個頁面會跟正式功能一樣進入底部列，可用來檢查關閉其他功能後的排版。',
            ),
            const SizedBox(height: 18),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _DebugFeatureChip(color: color, text: spec.label),
                _DebugFeatureChip(color: color, text: '功能頁'),
                _DebugFeatureChip(color: color, text: '版面預覽'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DebugFeatureCard extends StatelessWidget {
  final Color color;
  final IconData icon;
  final String title;
  final String body;
  const _DebugFeatureCard({
    required this.color,
    required this.icon,
    required this.title,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withValues(alpha: 0.14)),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 21),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF3E3029),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  body,
                  style: const TextStyle(
                    fontSize: 12.5,
                    height: 1.45,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF8C7A70),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DebugFeatureChip extends StatelessWidget {
  final Color color;
  final String text;
  const _DebugFeatureChip({required this.color, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w800,
          color: color,
        ),
      ),
    );
  }
}

// 「只有習慣頁」時的底部裝飾條。
// 高度跟 BottomNavigationBar 一致，避免功能開關後版面跳動。
// 視覺：warm 漸層 + 中央三顆淡色小裝飾，跟兔咪場景配色呼應。
class _DecorativeFloor extends StatelessWidget {
  const _DecorativeFloor();

  @override
  Widget build(BuildContext context) {
    // 跟首頁場景共用時段（debug 覆寫時「早中晚」連裝飾條一起變）
    final hour = sceneHourNow().floor();
    final isNight = hour >= 22 || hour < 6;
    final bottomPad = MediaQuery.of(context).padding.bottom;
    return Container(
      height: kBottomNavigationBarHeight + bottomPad,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isNight
              ? const [Color(0xFFD8DCEE), Color(0xFFB6BFE0)]
              : const [Color(0xFFFFEDD3), Color(0xFFFFD9A8)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: Padding(
        padding: EdgeInsets.only(bottom: bottomPad),
        child: Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: List.generate(3, (i) {
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Icon(
                  isNight ? Icons.nightlight_round : Icons.favorite,
                  size: 11,
                  color: Colors.white.withValues(alpha: 0.65),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}

// 自訂底部導航：2~5 個維持單排，6~10 個自動換兩排。
// 按壓回饋改為低調膠囊底色，避免 Ink ripple 在格線邊界被裁切。
class _AdaptiveBottomNav extends StatefulWidget {
  const _AdaptiveBottomNav({
    required this.tabs,
    required this.currentIndex,
    required this.onTap,
  });

  final List<_TabItem> tabs;
  final int currentIndex;
  final ValueChanged<int> onTap;

  @override
  State<_AdaptiveBottomNav> createState() => _AdaptiveBottomNavState();
}

class _AdaptiveBottomNavState extends State<_AdaptiveBottomNav> {
  static const double _twoRowHeight = 48;
  int? _pressedIndex;

  @override
  void didUpdateWidget(covariant _AdaptiveBottomNav oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_pressedIndex != null && _pressedIndex! >= widget.tabs.length) {
      _pressedIndex = null;
    }
  }

  void _setPressed(int? index) {
    if (_pressedIndex == index || !mounted) return;
    setState(() => _pressedIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selectedColor = theme.colorScheme.primary;
    const unselectedColor = Colors.grey;

    final n = widget.tabs.length;
    final isTwoRow = n > 5;
    final columnCount = isTwoRow ? (n / 2).ceil() : n;
    final rowHeight = isTwoRow ? _twoRowHeight : kBottomNavigationBarHeight;
    final bottomIdx = [
      for (var i = 0; i < (isTwoRow ? columnCount : n); i++) i,
    ];
    final topIdx = [
      if (isTwoRow)
        for (var i = columnCount; i < n; i++) i,
    ];
    final rows = isTwoRow ? [topIdx, bottomIdx] : [bottomIdx];

    return Material(
      elevation: 8,
      color:
          theme.bottomNavigationBarTheme.backgroundColor ?? theme.canvasColor,
      child: SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final cellW = constraints.maxWidth / columnCount;

            Widget cell(int index) {
              final t = widget.tabs[index];
              final isSel = index == widget.currentIndex;
              final isPressed = index == _pressedIndex;
              final color = isSel ? selectedColor : unselectedColor;
              final indicatorAlpha = isPressed ? 0.14 : (isSel ? 0.09 : 0.0);
              final indicatorMaxWidth = isTwoRow ? 64.0 : 76.0;
              final indicatorWidth = (cellW - 8)
                  .clamp(48.0, indicatorMaxWidth)
                  .toDouble();
              final indicatorHeight = isTwoRow ? 42.0 : 48.0;
              final iconSize = isTwoRow ? 20.0 : 22.0;
              final fontSize = isTwoRow ? 10.5 : 11.5;

              return SizedBox(
                width: cellW,
                height: rowHeight,
                child: InkWell(
                  onTap: () => widget.onTap(index),
                  onTapDown: (_) => _setPressed(index),
                  onTapUp: (_) => _setPressed(null),
                  onTapCancel: () => _setPressed(null),
                  splashFactory: NoSplash.splashFactory,
                  highlightColor: Colors.transparent,
                  hoverColor: Colors.transparent,
                  focusColor: selectedColor.withValues(alpha: 0.08),
                  child: Center(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 120),
                      curve: Curves.easeOutCubic,
                      width: indicatorWidth,
                      height: indicatorHeight,
                      padding: const EdgeInsets.symmetric(horizontal: 5),
                      decoration: BoxDecoration(
                        color: selectedColor.withValues(alpha: indicatorAlpha),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(t.icon, size: iconSize, color: color),
                          const SizedBox(height: 2),
                          SizedBox(
                            width: double.infinity,
                            child: Center(
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  t.label,
                                  maxLines: 1,
                                  style: TextStyle(
                                    fontSize: fontSize,
                                    height: 1.0,
                                    color: color,
                                    fontWeight: isSel
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                                  ),
                                ),
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

            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final row in rows)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: row.map(cell).toList(),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}
