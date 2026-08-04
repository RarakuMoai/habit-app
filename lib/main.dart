import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'l10n/app_localizations.dart';
import 'pages/family_page.dart';
import 'pages/home_page.dart';
import 'pages/login_streak_page.dart';
import 'pages/onboarding_page.dart';
import 'pages/story_reveal_page.dart';
import 'pages/timer_page.dart';
import 'pages/wardrobe_page.dart';
import 'pages/water_page.dart';
import 'pages/weight_page.dart';
import 'utils/app_feedback.dart';
import 'utils/app_restart.dart';
import 'utils/app_style.dart';
import 'utils/audio_asset_cache.dart';
import 'utils/audio_settings_service.dart';
import 'utils/bgm_playlist.dart';
import 'utils/bgm_service.dart';
import 'utils/coin_config.dart';
import 'utils/coin_service.dart';
import 'utils/feature_flags.dart';
import 'utils/logical_date.dart';
import 'utils/logical_day_coordinator.dart';
import 'utils/mascot.dart';
import 'utils/notification_service.dart';
import 'utils/parent_pin.dart';
import 'utils/preference_write_guard.dart';
import 'utils/prefs_keys.dart';
import 'utils/sfx_service.dart';
import 'utils/story_catalog.dart';
import 'utils/story_store.dart';
import 'utils/tab_catalog.dart';
import 'utils/usage_stats.dart';
import 'utils/wardrobe_store.dart';
import 'utils/water_habit_link.dart';
import 'utils/weight_records.dart';
import 'widgets/footprint_coin_reward_overlay.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // 打包字型（Nunito / Baloo 2）為 OFL 授權，依授權條款把全文註冊進
  // Flutter licenses 頁（showLicensePage / AboutDialog 可見）。
  LicenseRegistry.addLicense(() async* {
    final nunito = await rootBundle.loadString('assets/fonts/Nunito-OFL.txt');
    yield LicenseEntryWithLineBreaks(const ['Nunito'], nunito);
    final baloo2 = await rootBundle.loadString('assets/fonts/Baloo2-OFL.txt');
    yield LicenseEntryWithLineBreaks(const ['Baloo 2'], baloo2);
  });
  runApp(const RootRestart(child: MyApp()));
}

Future<_StartupState> _loadStartupState() async {
  // 鎖定只支援直向（防止橫向自動翻轉）
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  final prefs = await SharedPreferences.getInstance();
  // 舊版明文 PIN 啟動時就地雜湊遷移（hasPin 內含遷移邏輯）
  await ParentPin.hasPin(prefs);
  final onboardingDone = prefs.getBool(PrefsKeys.onboardingDone) ?? false;
  // 邏輯日必須在任何頁面開始初始化之前就確定：跨日結算（連勝、當日勾選重置、
  // lastOpenDate 推進）全部由 coordinator 負責，首頁只讀結果。這裡 await 它，
  // 首頁第一次載入拿到的就已經是新一天的狀態，不會出現「新一天的報到 + 昨天
  // 的完成狀態」。驗證失敗會維持在啟動畫面，不得帶著未確認的舊日狀態進首頁。
  await LogicalDayCoordinator.instance.start();
  // 玩家取的兔咪名字載進全域 notifier：系統文案用 {name} 佔位，
  // 靠 MascotName.fill 帶入，避免各處寫死「兔咪」（改名後會對不上）
  await MascotName.load(prefs);
  // 冷啟動固定露出兔咪；只載入「展開教學是否看過」。
  await MascotPanelPrefs.load();
  // 金幣餘額載進全域 notifier（UI 反應式讀取）
  await CoinService.load();
  // 衣櫃/音樂盒狀態載進全域 notifier（首頁兔咪皮膚、目前曲在 MainPage build 前就緒）
  await WardrobeStore.load();
  // 回憶本（特殊事件）已解鎖狀態載進全域 notifier
  await StoryStore.load();
  // just_audio 會按 asset 路徑保留抽出後的檔案；音檔原地更新時，正式版的
  // App container 仍在，可能繼續播放舊快取。版本落後時在任何 player 建立前
  // 清一次；失敗不擋啟動，且不寫入版本，所以下次冷啟動會再試。
  try {
    await AudioAssetCache.ensureCurrent(prefs);
  } catch (e, st) {
    debugPrint('Audio asset cache refresh failed: $e\n$st');
  }
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
    // 接上播放清單協調器（換歌鉤子 + loop 行為同步），必須在首播之前，
    // 讓多軌列表循環使用者的冷啟動首曲就帶正確 loop 行為、播完會輪替。
    BgmPlaylist.init();
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

/// 一個常駐頁面的 reload completion barrier。
///
/// failure 只存成狀態並喚醒 waiter，不直接 completeError；如此即使頁面比
/// Main 的 await 更早失敗，也不會先形成未處理的 Future error。
class _PageReloadBarrier {
  _PageReloadBarrier(this.name);

  final String name;
  int? _expected;
  int? _applied;
  Object? _error;
  StackTrace? _stackTrace;
  Completer<void>? _completion;

  void expect(int trigger) {
    if (_applied == trigger) return;
    if (_expected == trigger &&
        (_error != null || !(_completion?.isCompleted ?? true))) {
      return;
    }
    if (!(_completion?.isCompleted ?? true)) _completion!.complete();
    _expected = trigger;
    _error = null;
    _stackTrace = null;
    _completion = Completer<void>();
  }

  void succeed(int trigger) {
    if (_expected != trigger) return;
    _applied = trigger;
    _error = null;
    _stackTrace = null;
    final completion = _completion;
    if (completion != null && !completion.isCompleted) completion.complete();
  }

  void fail(int trigger, Object error, StackTrace stackTrace) {
    if (_expected != trigger) return;
    _error = error;
    _stackTrace = stackTrace;
    final completion = _completion;
    if (completion != null && !completion.isCompleted) completion.complete();
  }

  bool failedFor(int trigger) => _expected == trigger && _error != null;

  void deactivate() {
    if (!(_completion?.isCompleted ?? true)) _completion!.complete();
    _expected = null;
    _applied = null;
    _error = null;
    _stackTrace = null;
    _completion = null;
  }

  Future<void> wait(int trigger) async {
    if (_applied == trigger) return;
    expect(trigger);
    final completion = _completion!;
    await completion.future;
    if (_expected != trigger) return;
    final error = _error;
    if (error != null) {
      Error.throwWithStackTrace(error, _stackTrace ?? StackTrace.current);
    }
    if (_applied != trigger) {
      throw StateError('$name reload did not apply trigger $trigger');
    }
  }

  void dispose() {
    deactivate();
  }
}

/// 截圖／版面驗證用的語言覆寫：`--dart-define=APP_LOCALE=en`。
///
/// 英文比中文長，版面又是照中文寬度調的，所以英文文案改完要能實際渲染一遍。
/// 走編譯期常數而不是 prefs，理由同 `SCENE_HOUR`：模擬器的 cfprefsd 快取會
/// 把外部改的 plist 隨機蓋回去。`kDevToolsEnabled` 關掉後整段是 no-op。
Locale? get _devLocaleOverride {
  if (!kDevToolsEnabled) return null;
  const code = String.fromEnvironment('APP_LOCALE');
  return switch (code) {
    'en' => const Locale('en'),
    'zh' => const Locale('zh', 'TW'),
    _ => null,
  };
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
      // 用 onGenerateTitle 而非 title：MaterialApp.title 求值時 delegate 還沒
      // 掛上，拿不到 AppLocalizations。這是 i18n 遷移的第一個範例。
      onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
      debugShowCheckedModeBanner: false,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      // 目前 zh（繁中，主要語言）與 en。加語言只要在 lib/l10n/ 放新的 arb。
      supportedLocales: AppLocalizations.supportedLocales,
      // ⚠️ 暫時鎖定繁中。英文文案只有骨架，現在放開會變成半中半英。
      // 英文文本完成後移除這行，改為跟隨系統語言。
      // 截圖工作流：--dart-define=APP_LOCALE=en 可暫時切語言驗版面
      // （同 SCENE_HOUR，走編譯期常數；kDevToolsEnabled 閘門，正式版 no-op）。
      locale: _devLocaleOverride ?? const Locale('zh', 'TW'),
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFFF7043)),
        useMaterial3: true,
        fontFamily: 'Nunito',
        scaffoldBackgroundColor: const Color(0xFFF7F3EF),
        cardTheme: CardThemeData(
          elevation: 2,
          shadowColor: const Color(0x1F8D6E63),
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
          titleTextStyle: const TextStyle(
            fontFamily: 'Nunito',
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w700,
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: AppSurfaces.fill,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 14,
          ),
        ),
        // 分隔線統一暖沙色，設定頁等處的裸 Divider 不再是冷灰。
        dividerTheme: const DividerThemeData(color: AppSurfaces.divider),
        // SnackBar 統一暖棕底 + 米白字 + floating，取代預設黑灰浮條。
        snackBarTheme: SnackBarThemeData(
          backgroundColor: const Color(0xFF4E342E),
          contentTextStyle: const TextStyle(
            fontFamily: 'Nunito',
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Color(0xFFFFF6ED),
          ),
          actionTextColor: const Color(0xFFFFC49B),
          behavior: SnackBarBehavior.floating,
          elevation: 4,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
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
      // 動態字體護欄：版面大量使用固定高度膠囊／導覽列，放大不設限一定破版。
      // clamp 到 1.0–1.3：仍尊重系統放大（可讀性 +30%），但不會炸版；
      // 縮小方向不跟（本來字就不大）。
      builder: (context, child) {
        // 使用者還沒替兔咪取名時，預設名要跟著語言走（中文「兔咪」／英文
        // "Tumi"）。MascotName.load 在 runApp 之前跑、拿不到 context，所以補
        // 在這裡：builder 已經在 Localizations 底下，換語言會再跑一次。
        MascotName.applyDefaultName(
          AppLocalizations.of(context).mascotDefaultName,
        );
        final mq = MediaQuery.of(context);
        final scale = mq.textScaler.scale(1.0).clamp(1.0, 1.3);
        return MediaQuery(
          data: mq.copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        );
      },
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
                      style: const TextStyle(
                        fontFamily: 'Nunito',
                        color: Color(0xFF6D4C41),
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
  bool _waterGoalReached = false;
  bool _weightHabitAutoComplete = false;
  bool _loaded = false;
  int _waterReloadTrigger = 0;
  int _dayReloadTrigger = 0;
  // 目前邏輯日（唯一真相在 LogicalDayCoordinator）。收到新的 stamp 時一定要
  // 先把下面兩個 auto-complete 旗標重算完，再連同 stamp 一次 setState 交給
  // 下游；順序反過來的話，昨天的達標旗標會把新一天的連動習慣標成已完成。
  LogicalDayStamp? _dayStamp;
  List<String> _tabOrder = const []; // 使用者自訂的底部分頁順序（TabIds 字串）
  bool _claimingDailyReward = false;
  bool _loginCelebrating = false; // 慶祝頁還在畫面上（揭曉佇列要等它）
  int? _rewardAmount;
  int? _rewardStartBalance;
  int? _rewardTargetBalance;
  Future<void> _settingsTail = Future<void>.value();
  Future<void>? _latestDayApply;
  late final Future<void> _mainReady;
  int? _mainAppliedRevision;
  bool _presentationBarrierPassed = false;
  final _homeReloadBarrier = _PageReloadBarrier('Home');
  final _waterReloadBarrier = _PageReloadBarrier('Water');
  final _weightReloadBarrier = _PageReloadBarrier('Weight');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // 冷啟動的 barrier 在 _loadStartupState 就 await 過了，這裡是冪等的補強：
    // 走 MyApp(startAtHome:) 的測試路徑不經過 startup，也要有邏輯日。
    final coordinator = LogicalDayCoordinator.instance;
    _dayStamp = coordinator.stamp.value;
    coordinator.stamp.addListener(_onLogicalDayChanged);
    final coordinatorReady = coordinator.start();
    final settingsReady = _queueSettings(dayStamp: _dayStamp);
    if (_dayStamp != null) _latestDayApply = settingsReady;
    _mainReady = _initializeMain(coordinatorReady, settingsReady);
    unawaited(_observeReadinessError(_mainReady));
    // 功能開關一改就即時重組頁籤（不必等退出設定頁）
    featureFlagsRevision.addListener(_loadSettings);
    // 特殊事件解鎖 → 佇列有東西就播全螢幕揭曉（story_reveal_page.dart）
    StoryStore.pendingReveal.addListener(_onPendingRevealChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_runInitialPresentation());
    });
  }

  Future<void> _initializeMain(
    Future<void> coordinatorReady,
    Future<void> settingsReady,
  ) async {
    try {
      await Future.wait<void>([coordinatorReady, settingsReady]);
    } catch (_) {
      // Future.wait 已同步替兩條 Future 掛上 error handler。Coordinator 失敗
      // 不能繼續；settings 的一次性失敗則由下方同 revision 重排。
      final coordinatorError = LogicalDayCoordinator.instance.lastError;
      if (coordinatorError != null) throw coordinatorError;
    }
    await _ensureCurrentDayApplied();
    _prepareDependentReloads();
    await _awaitDependentReloads();
  }

  Future<void> _observeReadinessError(Future<void> readiness) async {
    try {
      await readiness;
    } catch (_) {
      // 立即附著 observer，避免 post-frame callback 尚未開始前出現 unhandled
      // Future error；真正的記錄與停止演出由 _runInitialPresentation 處理。
    }
  }

  Future<void> _runInitialPresentation() async {
    unawaited(_ensureMainBgm());
    try {
      await _mainReady;
    } catch (e, st) {
      debugPrint('Main readiness barrier failed: $e\n$st');
      return;
    }
    if (!mounted) return;
    _presentationBarrierPassed = true;
    await _claimDailyLoginReward();
    if (!mounted) return;
    _checkSeasonStories();
    unawaited(_maybeShowStoryReveal()); // 上次沒看完的揭曉（佇列有持久化）啟動補播
  }

  @override
  void dispose() {
    featureFlagsRevision.removeListener(_loadSettings);
    StoryStore.pendingReveal.removeListener(_onPendingRevealChanged);
    // 只取消訂閱；coordinator 是全域單例，生命週期比 MainPage 長（RootRestart
    // 會重建整棵樹），不能在這裡 dispose 掉。
    LogicalDayCoordinator.instance.stamp.removeListener(_onLogicalDayChanged);
    WidgetsBinding.instance.removeObserver(this);
    _homeReloadBarrier.dispose();
    _waterReloadBarrier.dispose();
    _weightReloadBarrier.dispose();
    CoinService.presentationBalance.value = null;
    CoinService.dailyRewardShowing.value = false;
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
    if (state == AppLifecycleState.resumed) {
      unawaited(_handleResumed());
    }
  }

  /// resume 的演出順序是有意義的，不能只靠資料冪等：一定要先讓 coordinator
  /// 把跨日結算做完、首頁換成新一天，才輪到每日登入慶祝頁與節日事件。否則
  /// 使用者會先看到「連續登入第 N 天」的新日報到，關掉之後首頁還停在昨天。
  Future<void> _handleResumed() async {
    try {
      // 與 coordinator 自己的 resume 偵測合併成同一次（in-flight 合流）。
      await LogicalDayCoordinator.instance.ensureCurrent(
        trigger: LogicalDayTrigger.resume,
      );
      await _ensureCurrentDayApplied();
      _retryFailedDependentReloads();
      await _awaitDependentReloads();
    } catch (e, st) {
      debugPrint('Resume logical-day barrier failed: $e\n$st');
      return;
    }
    if (!mounted) return;
    _presentationBarrierPassed = true;
    // 跨日後從背景回來也能領當天的登入獎勵（已領過會直接 no-op）
    await _claimDailyLoginReward();
    if (!mounted) return;
    _checkSeasonStories();
    unawaited(_maybeShowStoryReveal());
  }

  /// coordinator 廣播新的邏輯日：先重算依賴「今天」的自動完成旗標，再把新的
  /// stamp 與 revision 一起交出去（同一個 setState，下游不會看到中間狀態）。
  void _onLogicalDayChanged() {
    _latestDayApply = _queueSettings(
      dayStamp: LogicalDayCoordinator.instance.stamp.value,
    );
  }

  Future<void> _ensureCurrentDayApplied() async {
    while (mounted) {
      final stamp = LogicalDayCoordinator.instance.stamp.value;
      if (stamp == null || _mainAppliedRevision == stamp.revision) return;

      final pending = _latestDayApply;
      if (pending != null) {
        try {
          await pending;
        } catch (_) {
          // 同一 stamp 會在下方重排一次；若仍失敗則讓新 Future 往外拋。
        }
        if (!mounted) return;
        final latestStamp = LogicalDayCoordinator.instance.stamp.value;
        if (latestStamp?.revision != stamp.revision) continue;
        if (_mainAppliedRevision == stamp.revision) return;
      }

      final retry = _queueSettings(dayStamp: stamp);
      _latestDayApply = retry;
      await retry;
    }
  }

  void _prepareDependentReloads() {
    _homeReloadBarrier.expect(_dayReloadTrigger);
    if (_waterEnabled) {
      _waterReloadBarrier.expect(_waterReloadTrigger);
    } else {
      _waterReloadBarrier.deactivate();
    }
    if (_weightTrackingEnabled) {
      _weightReloadBarrier.expect(_dayReloadTrigger);
    } else {
      _weightReloadBarrier.deactivate();
    }
  }

  /// 每次 Water trigger 前進都要同步 armed barrier。WaterPage 可能在下一個
  /// build 立刻完成 reload；若 callback 先於 expect，成功會被當成 stale 丟掉，
  /// 下一次 resume 就會永遠等一個已經消費過的 trigger。
  void _advanceWaterReloadTrigger() {
    _waterReloadTrigger++;
    if (_waterEnabled) {
      _waterReloadBarrier.expect(_waterReloadTrigger);
    } else {
      _waterReloadBarrier.deactivate();
    }
  }

  void _retryFailedDependentReloads() {
    final failed =
        _homeReloadBarrier.failedFor(_dayReloadTrigger) ||
        (_waterEnabled && _waterReloadBarrier.failedFor(_waterReloadTrigger)) ||
        (_weightTrackingEnabled &&
            _weightReloadBarrier.failedFor(_dayReloadTrigger));
    if (!failed || !mounted) return;
    setState(() {
      _dayReloadTrigger++;
      if (_waterEnabled) _advanceWaterReloadTrigger();
    });
    _prepareDependentReloads();
  }

  Future<void> _awaitDependentReloads() async {
    while (mounted) {
      final dayTrigger = _dayReloadTrigger;
      final waterTrigger = _waterReloadTrigger;
      final waitForWater = _waterEnabled;
      final waitForWeight = _weightTrackingEnabled;
      await Future.wait<void>([
        _homeReloadBarrier.wait(dayTrigger),
        if (waitForWater) _waterReloadBarrier.wait(waterTrigger),
        if (waitForWeight) _weightReloadBarrier.wait(dayTrigger),
      ]);
      if (dayTrigger == _dayReloadTrigger &&
          waterTrigger == _waterReloadTrigger &&
          waitForWater == _waterEnabled &&
          waitForWeight == _weightTrackingEnabled) {
        return;
      }
    }
  }

  void _onHomeReloaded(int trigger) => _homeReloadBarrier.succeed(trigger);

  void _onHomeReloadFailed(int trigger, Object error, StackTrace stackTrace) =>
      _homeReloadBarrier.fail(trigger, error, stackTrace);

  void _onWaterReloaded(int trigger) => _waterReloadBarrier.succeed(trigger);

  void _onWaterReloadFailed(int trigger, Object error, StackTrace stackTrace) =>
      _waterReloadBarrier.fail(trigger, error, stackTrace);

  void _onWeightReloaded(int trigger) => _weightReloadBarrier.succeed(trigger);

  void _onWeightReloadFailed(
    int trigger,
    Object error,
    StackTrace stackTrace,
  ) => _weightReloadBarrier.fail(trigger, error, stackTrace);

  @visibleForTesting
  Future<void> debugHandleResumed() => _handleResumed();

  @visibleForTesting
  Future<void> get debugMainReady => _mainReady;

  // 每日登入獎勵：先推全螢幕慶祝頁（兔咪＋連續天數舞台），看完 pop 回來
  // 才輪到金幣飛行吸入 AppBar ＋ 兔咪開心反應。文字只在慶祝頁講一次，
  // 回到首頁後不再重複同一句。
  Future<void> _claimDailyLoginReward() async {
    if (_claimingDailyReward) return;
    _claimingDailyReward = true;
    final startBalance = CoinService.notifier.value;
    // 先凍結 AppBar 顯示；資料仍立即安全入帳，動畫只負責把舊值數到新值。
    CoinService.presentationBalance.value = startBalance;
    // 演出旗標先舉起來（首頁問候橫幅看到會讓路）；沒獎勵馬上放下。
    CoinService.dailyRewardShowing.value = true;
    final reward = await CoinService.claimDailyLogin(
      l10n: AppLocalizations.of(context),
    );
    // 連續登入回憶事件：不論這次有沒有新領（冪等），照登入連勝天數判定
    final prefs = await SharedPreferences.getInstance();
    final loginStreak = prefs.getInt(PrefsKeys.coinLoginStreak) ?? 0;
    unawaited(StoryEvents.onLoginStreak(loginStreak));
    if (reward == null || !mounted) {
      CoinService.presentationBalance.value = null;
      CoinService.dailyRewardShowing.value = false;
      _claimingDailyReward = false;
      return;
    }
    // 冷啟動或跨日真的領到獎勵時，把功能卡收小，確保後續兔咪噴出金幣
    // 與入袋演出完整可見。沒有新獎勵的 resumed 不動使用者目前面板狀態。
    MascotPanelPrefs.revealMascotForDailyReward();
    // 讓開場第一幀先落地；同時把慶祝頁全部音訊載好才亮舞台，
    // 避免首次播放延遲到印章落下時才出聲，和蓋章音誤疊。
    try {
      await Future.wait<void>([
        Future<void>.delayed(const Duration(milliseconds: 350)),
        SfxService.instance.init(),
      ]);
    } catch (e, st) {
      // 音訊失敗不該吃掉已入帳的每日獎勵；頁面仍照常顯示，SFX 自行降級。
      debugPrint('Daily reward audio preload failed: $e\n$st');
    }
    if (!mounted) {
      CoinService.presentationBalance.value = null;
      CoinService.dailyRewardShowing.value = false;
      _claimingDailyReward = false;
      return;
    }
    _loginCelebrating = true;
    try {
      await Navigator.of(
        context,
      ).push(LoginStreakPage.route(streak: loginStreak, reward: reward));
    } finally {
      _loginCelebrating = false;
    }
    if (!mounted) {
      CoinService.presentationBalance.value = null;
      CoinService.dailyRewardShowing.value = false;
      _claimingDailyReward = false;
      return;
    }
    final targetBalance = CoinService.notifier.value;
    setState(() {
      _rewardAmount = reward.totalAmount;
      _rewardStartBalance = startBalance;
      _rewardTargetBalance = targetBalance;
    });
    MascotPersona.setForContext(
      MascotEmotion.happy.assetPath,
      MascotContext.energize,
      force: true,
    );
    _claimingDailyReward = false;
  }

  void _finishRewardAnimation() {
    CoinService.dailyRewardShowing.value = false;
    if (!mounted) return;
    setState(() {
      _rewardAmount = null;
      _rewardStartBalance = null;
      _rewardTargetBalance = null;
    });
  }

  // 節日回憶事件：啟動與回前景時用「真實日曆日」檢查（不跟換日設定走，
  // 節日就是節日；解鎖冪等所以重複檢查沒關係）。
  void _checkSeasonStories() {
    unawaited(StoryEvents.onSeasonDay(DateTime.now()));
  }

  // ── 全螢幕揭曉佇列 ─────────────────────────────────────────
  // 觸發判定只負責把事件排進 StoryStore.pendingReveal；這裡統一播放：
  // 等一拍讓打勾/金幣/問候動畫先落地 → push 揭曉頁 → 看完 consume →
  // 佇列還有就接著播（同一時刻解鎖多個事件會排隊逐一亮相）。
  bool _storyRevealShowing = false;

  void _onPendingRevealChanged() => unawaited(_maybeShowStoryReveal());

  Future<void> _maybeShowStoryReveal() async {
    if (!_presentationBarrierPassed || _storyRevealShowing || !mounted) return;
    if (StoryStore.pendingReveal.value.isEmpty) return;
    _storyRevealShowing = true;
    try {
      await Future<void>.delayed(const Duration(milliseconds: 1100));
      while (mounted && (_rewardAmount != null || _loginCelebrating)) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      while (StoryStore.pendingReveal.value.isNotEmpty) {
        if (!mounted) return;
        final id = StoryStore.pendingReveal.value.first;
        final unlock = StoryStore.unlocked.value.where((u) => u.id == id);
        await Navigator.of(context).push(
          StoryRevealPage.route(
            event: storyEventById(id),
            date: unlock.isEmpty ? null : unlock.first.date,
          ),
        );
        await StoryStore.consumeReveal(id);
      }
    } finally {
      _storyRevealShowing = false;
    }
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

  // 「今天」一律走邏輯日（預設凌晨 4 點換日）：喝水/體重/習慣歷史的
  // 紀錄槽都是邏輯日，這裡若用日曆日，凌晨 0–4 點會寫錯天的 key，
  // 造成打勾被喝水頁的達標回報彈回（金幣判重在 CoinService 內走日曆日，不受影響）。
  String _todayString(SharedPreferences prefs) =>
      _dayStamp?.logicalDate ?? LogicalDate.today(prefs);

  /// 給 listener / callback 用的無參數版本（VoidCallback 相容）。
  Future<void> _loadSettings() => _queueSettings();

  Future<void> _queueSettings({LogicalDayStamp? dayStamp}) {
    final operation = _settingsTail.then(
      (_) => _applySettings(dayStamp: dayStamp),
    );
    // 後一輪一定排在前一輪之後；前一輪失敗不會永久毒死佇列，但它自己的
    // caller 仍會收到錯誤，freshness barrier 因而能停止後續演出。
    _settingsTail = operation.then<void>(
      (_) {},
      onError: (Object e, StackTrace st) {
        debugPrint('Main settings apply failed: $e\n$st');
      },
    );
    return operation;
  }

  Future<void> _applySettings({LogicalDayStamp? dayStamp}) async {
    final prefs = await SharedPreferences.getInstance();
    await LogicalDayCoordinator.instance.synchronizeStorage(
      () => WaterHabitLink.reconcile(prefs),
    );
    // 帶了新 stamp 就用它算「今天」，這樣重算出來的旗標一定屬於新的一天。
    final effectiveStamp = dayStamp ?? _dayStamp;
    final today = effectiveStamp?.logicalDate ?? LogicalDate.today(prefs);
    final weightRecordedToday = await hasSavedWeightRecordForDate(prefs, today);
    // 開關/排序改變前先記住目前選的分頁 id，重組後盡量回到同一頁，
    // 避免重排後 _currentIndex 指向別的分頁（看起來像跳頁）。
    final prevId = (_loaded && _currentIndex < _tabs.length)
        ? _tabs[_currentIndex].id
        : null;
    if (!mounted) return;
    final stampChanged =
        dayStamp != null && dayStamp.revision != _dayStamp?.revision;
    setState(() {
      if (dayStamp != null) {
        // stamp 與兩個 auto-complete 旗標在同一個 setState 落地，下游的
        // didUpdateWidget 只會看到「全部都是新一天」的一致狀態。
        _dayStamp = dayStamp;
        if (stampChanged) {
          // 三個常駐頁面各拿一個新 trigger；barrier 會等它們真正套用後才放行。
          _dayReloadTrigger++;
        }
      }
      _waterEnabled = prefs.getBool(PrefsKeys.waterEnabled) ?? false;
      _timerEnabled = prefs.getBool(PrefsKeys.timerEnabled) ?? true;
      _weightTrackingEnabled =
          prefs.getBool(PrefsKeys.weightTrackingEnabled) ?? false;
      _familyEnabled = prefs.getBool(PrefsKeys.familyEnabled) ?? false;
      _tabOrder = prefs.getStringList(PrefsKeys.tabOrder) ?? const <String>[];
      _waterGoalReached = prefs.getString(PrefsKeys.waterGoalDate) == today;
      _weightHabitAutoComplete = weightRecordedToday;
      if (stampChanged) _advanceWaterReloadTrigger();
      // 開發者工具：指定啟動分頁（kDevToolsEnabled 控制）
      if (kDevToolsEnabled) {
        final tab = prefs.getInt(PrefsKeys.debugStartTab);
        if (tab != null) _currentIndex = tab;
      }
      _loaded = true;
    });
    if (dayStamp != null) _mainAppliedRevision = dayStamp.revision;
    _prepareDependentReloads();
    // 重組後把選中頁對回原本那一頁（首次載入 prevId 為 null，保留 dev 起始分頁）。
    if (prevId != null) {
      final idx = _tabs.indexWhere((t) => t.id == prevId);
      if (idx != -1 && idx != _currentIndex && mounted) {
        setState(() => _currentIndex = idx);
      }
    }
    // 匿名統計：冷啟動的起始分頁也算一次開啟（之後的切換在 _onTabTapped 記）。
    if (prevId == null && _tabs.isNotEmpty) {
      final idx = _currentIndex < _tabs.length ? _currentIndex : 0;
      unawaited(UsageStats.bump(UsageEvents.tab(_tabs[idx].id)));
    }
  }

  Future<void> _handleWaterGoal(bool reached) {
    final coordinator = LogicalDayCoordinator.instance;
    final expectedRevision = _dayStamp?.revision;
    final expectedLogicalDate = _dayStamp?.logicalDate;
    final storageMutation = coordinator.synchronizeStorage<bool>(() async {
      final prefs = await SharedPreferences.getInstance();
      await PreferenceWriteGuard.ensureHealthy(prefs);
      if (expectedRevision != null &&
          coordinator.stamp.value?.revision != expectedRevision) {
        return false;
      }
      final today = expectedLogicalDate ?? LogicalDate.today(prefs);
      await PreferenceWriteGuard.write(
        prefs,
        () => reached
            ? prefs.setString(PrefsKeys.waterGoalDate, today)
            : prefs.remove(PrefsKeys.waterGoalDate),
        PrefsKeys.waterGoalDate,
      );
      return true;
    });
    return _finishWaterGoal(reached, expectedRevision, storageMutation);
  }

  Future<void> _finishWaterGoal(
    bool reached,
    int? expectedRevision,
    Future<bool> storageMutation,
  ) async {
    if (!await storageMutation) return;
    if (reached) {
      // 當日喝水達標 +金幣（每日一次，service 內建防重複）
      await CoinService.award(CoinSource.waterGoal, note: '喝水達標');
    }
    if (!mounted ||
        (expectedRevision != null &&
            LogicalDayCoordinator.instance.stamp.value?.revision !=
                expectedRevision)) {
      return;
    }
    setState(() => _waterGoalReached = reached);
  }

  void _handleWeightRecordsChanged() {
    unawaited(_refreshWeightHabitAutoComplete());
    // 體重變動（含初次記錄）→ 喝水頁重新依最新體重估算建議水量。
    // 喝水頁常駐在 IndexedStack，不 bump 就不會重算建議卡。
    setState(_advanceWaterReloadTrigger);
  }

  Future<void> _refreshWeightHabitAutoComplete() async {
    final prefs = await SharedPreferences.getInstance();
    final done = await hasSavedWeightRecordForDate(prefs, _todayString(prefs));
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
    final entriesKey = PrefsKeys.waterEntries(today);
    final cupsKey = PrefsKeys.waterDay(today);
    final extraKey = PrefsKeys.waterExtra(today);
    if (!prefs.containsKey(entriesKey)) {
      final baseline = _waterEntriesFromLegacy(
        cups: (prefs.getInt(cupsKey) ?? 0).clamp(0, 100),
        cupMl: (prefs.getInt(PrefsKeys.waterCupMl) ?? 250).clamp(1, 12000),
        extraMl: (prefs.getInt(extraKey) ?? 0).clamp(0, 12000),
      );
      // Establish an authoritative old value (including []) before mirrors.
      // This prevents a failed final canonical write from being resurrected as
      // legacy data on the next load.
      await PreferenceWriteGuard.write(
        prefs,
        () => prefs.setString(entriesKey, jsonEncode(baseline)),
        entriesKey,
      );
    }
    // 舊 mirror 先寫、canonical entries 最後 commit；失敗重試不會重複套用。
    await PreferenceWriteGuard.write(
      prefs,
      () => prefs.setInt(cupsKey, cupCount),
      cupsKey,
    );
    await PreferenceWriteGuard.write(
      prefs,
      () => prefs.setInt(
        extraKey,
        (totalMl - cupMlTotal).clamp(0, 12000).toInt(),
      ),
      extraKey,
    );
    await PreferenceWriteGuard.write(
      prefs,
      () => prefs.setString(entriesKey, jsonEncode(entries)),
      entriesKey,
    );
  }

  Future<void> _handleWaterHabitToggle(bool checked) {
    final coordinator = LogicalDayCoordinator.instance;
    final expectedRevision = _dayStamp?.revision;
    final expectedLogicalDate = _dayStamp?.logicalDate;

    // 呼叫當下就保留全域 FIFO slot；不能先 await prefs，否則緊接著開始的
    // settlement 會超車，讓下面捕捉的舊日 key 和新日 goal marker 混在一起。
    final storageMutation = coordinator.synchronizeStorage<bool?>(() async {
      final prefs = await SharedPreferences.getInstance();
      await PreferenceWriteGuard.ensureHealthy(prefs);
      if (expectedRevision != null &&
          coordinator.stamp.value?.revision != expectedRevision) {
        return null;
      }

      final today = expectedLogicalDate ?? LogicalDate.today(prefs);
      final cupMl = prefs.getInt(PrefsKeys.waterCupMl) ?? 250;
      final goalMl = prefs.getInt(PrefsKeys.waterGoalMl) ?? 2000;
      final waterGoal = (goalMl / cupMl).ceil();
      final todayKey = PrefsKeys.waterDay(today);
      final savedKey = PrefsKeys.waterSaved(today);
      final entriesKey = PrefsKeys.waterEntries(today);
      final savedEntriesKey = PrefsKeys.waterEntriesSaved(today);
      final extraKey = PrefsKeys.waterExtra(today);
      late bool reached;

      if (checked) {
        final actual = prefs.getInt(todayKey) ?? 0;
        final extraMl = prefs.getInt(extraKey) ?? 0;
        final currentEntries = prefs.getString(entriesKey);
        await PreferenceWriteGuard.write(
          prefs,
          () => prefs.setInt(savedKey, actual),
          savedKey,
        );
        await PreferenceWriteGuard.write(
          prefs,
          () => prefs.setString(
            savedEntriesKey,
            currentEntries ??
                jsonEncode(
                  _waterEntriesFromLegacy(
                    cups: actual,
                    cupMl: cupMl,
                    extraMl: extraMl,
                  ),
                ),
          ),
          savedEntriesKey,
        );
        await _writeWaterEntries(prefs, today, [
          for (var i = 0; i < waterGoal; i++)
            _waterEntryMap(
              ml: cupMl,
              kind: 'cup',
              at: DateTime.now().add(Duration(seconds: i)),
            ),
        ]);
        reached = true;
      } else {
        final saved = prefs.getInt(savedKey) ?? 0;
        final savedEntries = prefs.getString(savedEntriesKey);
        final entries = savedEntries == null
            ? _waterEntriesFromLegacy(cups: saved, cupMl: cupMl, extraMl: 0)
            : (jsonDecode(savedEntries) as List<dynamic>)
                  .whereType<Map<String, dynamic>>()
                  .map(
                    (entry) => {
                      'ml': ((entry['ml'] as num?) ?? cupMl).round(),
                      'kind': entry['kind'] == 'cup' ? 'cup' : 'custom',
                      'at': entry['at'] is String
                          ? entry['at'] as String
                          : DateTime.now().toIso8601String(),
                    },
                  )
                  .toList();
        await _writeWaterEntries(prefs, today, entries);
        await PreferenceWriteGuard.write(
          prefs,
          () => prefs.remove(savedKey),
          savedKey,
        );
        await PreferenceWriteGuard.write(
          prefs,
          () => prefs.remove(savedEntriesKey),
          savedEntriesKey,
        );
        final restoredTotal = entries.fold<int>(
          0,
          (sum, entry) => sum + ((entry['ml'] as int?) ?? 0),
        );
        reached = restoredTotal >= goalMl;
      }

      await PreferenceWriteGuard.write(
        prefs,
        () => reached
            ? prefs.setString(PrefsKeys.waterGoalDate, today)
            : prefs.remove(PrefsKeys.waterGoalDate),
        PrefsKeys.waterGoalDate,
      );
      return reached;
    });
    return _finishWaterHabitToggle(
      storageMutation,
      expectedRevision,
      expectedLogicalDate,
    );
  }

  Future<void> _finishWaterHabitToggle(
    Future<bool?> storageMutation,
    int? expectedRevision,
    String? expectedLogicalDate,
  ) async {
    try {
      final reached = await storageMutation;
      if (reached == null) return;
      if (reached) {
        await CoinService.award(CoinSource.waterGoal, note: '喝水達標');
      }
      final currentStamp = LogicalDayCoordinator.instance.stamp.value;
      if (!mounted ||
          (expectedRevision != null &&
              (currentStamp?.revision != expectedRevision ||
                  _dayStamp?.revision != expectedRevision)) ||
          (expectedLogicalDate != null &&
              (currentStamp?.logicalDate != expectedLogicalDate ||
                  _dayStamp?.logicalDate != expectedLogicalDate))) {
        return;
      }
      setState(() {
        _waterGoalReached = reached;
        _advanceWaterReloadTrigger();
      });
    } catch (error, stackTrace) {
      // Home 的 callback 是 fire-and-forget；錯誤必須在這裡收口。Water reload
      // 會從 canonical entries 重算並修復 goal flag / Main 狀態。
      debugPrint('Water habit toggle sync failed: $error\n$stackTrace');
      final currentStamp = LogicalDayCoordinator.instance.stamp.value;
      final stillCurrent =
          (expectedRevision == null ||
              (currentStamp?.revision == expectedRevision &&
                  _dayStamp?.revision == expectedRevision)) &&
          (expectedLogicalDate == null ||
              (currentStamp?.logicalDate == expectedLogicalDate &&
                  _dayStamp?.logicalDate == expectedLogicalDate));
      if (mounted && stillCurrent) setState(_advanceWaterReloadTrigger);
    }
  }

  // 依功能開關動態組裝頁籤（標籤走 tabLabel 取 l10n）
  List<_TabItem> get _tabs {
    // 先建「已啟用」分頁（id -> 分頁）。習慣永遠在。
    final enabled = <String, _TabItem>{
      TabIds.habit: _TabItem(
        id: TabIds.habit,
        page: HomePage(
          onSettingsChanged: _loadSettings,
          waterHabitAutoComplete: _waterGoalReached,
          weightHabitAutoComplete: _weightHabitAutoComplete,
          onWaterHabitToggled: _handleWaterHabitToggle,
          onDayReloaded: _onHomeReloaded,
          onDayReloadFailed: _onHomeReloadFailed,
          reloadTrigger: _dayReloadTrigger,
          dayStamp: _dayStamp,
        ),
        icon: Icons.home,
        label: tabLabel(context, TabIds.habit),
      ),
    };
    if (_timerEnabled) {
      enabled[TabIds.timer] = _TabItem(
        id: TabIds.timer,
        page: const TimerPage(),
        icon: Icons.timer,
        label: tabLabel(context, TabIds.timer),
      );
    }
    if (_waterEnabled) {
      enabled[TabIds.water] = _TabItem(
        id: TabIds.water,
        page: WaterPage(
          onGoalStatusChanged: _handleWaterGoal,
          onReloaded: _onWaterReloaded,
          onReloadFailed: _onWaterReloadFailed,
          reloadTrigger: _waterReloadTrigger,
        ),
        icon: Icons.water_drop,
        label: tabLabel(context, TabIds.water),
      );
    }
    // 體重頁籤，依 weight_tracking_enabled 開關決定是否顯示
    if (_weightTrackingEnabled) {
      enabled[TabIds.weight] = _TabItem(
        id: TabIds.weight,
        page: WeightPage(
          onRecordsChanged: _handleWeightRecordsChanged,
          onReloaded: _onWeightReloaded,
          onReloadFailed: _onWeightReloadFailed,
          reloadTrigger: _dayReloadTrigger,
        ),
        icon: Icons.monitor_weight,
        label: tabLabel(context, TabIds.weight),
      );
    }
    if (_familyEnabled) {
      enabled[TabIds.family] = _TabItem(
        id: TabIds.family,
        page: FamilyPage(onSettingsChanged: _loadSettings),
        icon: Icons.family_restroom,
        label: tabLabel(context, TabIds.family),
      );
    }
    // 衣櫃固定分頁：造型/金幣消耗是核心留存迴圈，比照習慣不可停用（roadmap §4）。
    enabled[TabIds.wardrobe] = _TabItem(
      id: TabIds.wardrobe,
      page: const WardrobePage(),
      icon: Icons.checkroom_rounded,
      label: tabLabel(context, TabIds.wardrobe),
    );

    // 依使用者自訂排序排好（未排過的新分頁照預設順序補在後面）。
    final list = [
      for (final id in orderedTabIds(_tabOrder, enabled.keys.toSet()))
        enabled[id]!,
    ];

    return list;
  }

  // 底部列點擊：單排/兩排共用。
  void _onTabTapped(List<_TabItem> tabs, int index) {
    // 離開家庭頁籤時清除家長 Session，下次進入需重新驗證
    final familyIdx = tabs.indexWhere((t) => t.id == TabIds.family);
    if (familyIdx != -1 && _currentIndex == familyIdx && index != familyIdx) {
      parentSession.value = false;
    }
    final wardrobeIdx = tabs.indexWhere((t) => t.id == TabIds.wardrobe);
    if (wardrobeIdx != -1 &&
        _currentIndex == wardrobeIdx &&
        index != wardrobeIdx) {
      unawaited(WardrobePreviewController.restore());
    }
    // 匿名統計：只記真的切過去（重按同分頁不算開啟）。
    if (index != _currentIndex) {
      unawaited(UsageStats.bump(UsageEvents.tab(tabs[index].id)));
      // 分頁切換是全 app 最高頻的操作，過去完全沒有回饋——按下去只有畫面
      // 瞬間換掉，手上沒有任何確認。給一次 selection 觸覺補上那個確認。
      //
      // **刻意不出聲**：一天要按幾十次的東西加音效會很快變成噪音，
      // 「事件愈常發生愈要留白」（見 tumi_dialogue_catalog 執行規則 7）。
      // 重按同一個分頁也不發，那不是一次切換。
      playHaptic(HapticLevel.selection);
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
      extendBody: true,
      body: Stack(
        children: [
          IndexedStack(
            index: _currentIndex,
            children: List.generate(tabs.length, (i) {
              final tab = tabs[i];
              return TickerMode(
                enabled: i == _currentIndex,
                child: KeyedSubtree(key: ValueKey(tab.id), child: tab.page),
              );
            }),
          ),
          if (_rewardAmount case final amount?)
            FootprintCoinRewardOverlay(
              amount: amount,
              startBalance: _rewardStartBalance!,
              targetBalance: _rewardTargetBalance!,
              onFinished: _finishRewardAnimation,
            ),
        ],
      ),
      bottomNavigationBar: _AdaptiveBottomNav(
        tabs: tabs,
        currentIndex: _currentIndex,
        onTap: (index) => _onTabTapped(tabs, index),
      ),
    );
  }
}

// 頁籤資料結構
class _TabItem {
  final String id;
  final Widget page;
  final IconData icon;
  final String label;
  const _TabItem({
    required this.id,
    required this.page,
    required this.icon,
    required this.label,
  });
}

// 底部列「單排」高度。從 kBottomNavigationBarHeight(56) 加厚到 72，讓底部
// 更穩重，也縮小與兩排(96)的落差——tab 數增減換排時的跳動較小。
const double _kSingleRowNavHeight = 72;

// 自訂底部導航：寬度夠就單排（含 6 格），窄到每格 < 54 才換兩排。
// 底欄用淡暖毛玻璃收邊；選中態靠低調膠囊承接彩色貼紙 icon。
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
    const unselectedColor = AppInk.soft;
    final backgroundColor =
        theme.bottomNavigationBarTheme.backgroundColor ?? theme.canvasColor;
    final surfaceTop = Color.alphaBlend(
      selectedColor.withValues(alpha: 0.045),
      Colors.white,
    );
    final surfaceBottom = Color.alphaBlend(
      selectedColor.withValues(alpha: 0.070),
      backgroundColor,
    );

    final n = widget.tabs.length;

    return ClipRect(
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: backgroundColor.withValues(alpha: 0.54),
            gradient: LinearGradient(
              colors: [
                surfaceTop.withValues(alpha: 0.76),
                surfaceBottom.withValues(alpha: 0.58),
              ],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
            border: Border(
              top: BorderSide(
                color: AppSurfaces.divider.withValues(alpha: 0.72),
                width: 0.7,
              ),
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF8D6E63).withValues(alpha: 0.08),
                blurRadius: 22,
                offset: const Offset(0, -6),
              ),
              BoxShadow(
                color: selectedColor.withValues(alpha: 0.05),
                blurRadius: 18,
                offset: const Offset(0, -3),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: SafeArea(
              top: false,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  // 單排塞得下就維持單排：6 格在一般手機寬度都放得下，也比兩排飽滿；
                  // 只有窄到每格 < 54 才退成兩排，避免小螢幕擠壓。
                  final width = constraints.maxWidth;
                  final isTwoRow = bottomNavUsesTwoRows(
                    width: width,
                    itemCount: n,
                  );
                  final columnCount = isTwoRow ? (n / 2).ceil() : n;
                  final rowHeight = isTwoRow
                      ? _twoRowHeight
                      : _kSingleRowNavHeight;
                  final bottomIdx = [
                    for (var i = 0; i < (isTwoRow ? columnCount : n); i++) i,
                  ];
                  final topIdx = [
                    if (isTwoRow)
                      for (var i = columnCount; i < n; i++) i,
                  ];
                  final rows = isTwoRow ? [topIdx, bottomIdx] : [bottomIdx];
                  final cellW = width / columnCount;

                  Widget cell(int index) {
                    final t = widget.tabs[index];
                    final isSel = index == widget.currentIndex;
                    final isPressed = index == _pressedIndex;
                    final color = isSel ? selectedColor : unselectedColor;
                    // 貼紙圖示是彩色的，沒法像線稿那樣靠變色標示選中；選中態
                    // 用暖色膠囊、細邊與一點浮起感提示所在位置，避免底欄視覺過重。
                    final indicatorAlpha = isPressed
                        ? 0.24
                        : (isSel ? 0.16 : 0.0);
                    final indicatorMaxWidth = isTwoRow ? 64.0 : 76.0;
                    final indicatorWidth = (cellW - (isSel ? 8 : 14))
                        .clamp(isSel ? 56.0 : 50.0, indicatorMaxWidth)
                        .toDouble();
                    final indicatorHeight = isTwoRow
                        ? (isSel ? 44.0 : 40.0)
                        : (isSel ? 54.0 : 48.0);
                    final iconSize = isTwoRow
                        ? (isSel ? 25.5 : 23.5)
                        : (isSel ? 29.0 : 25.5);
                    final fontSize = isTwoRow
                        ? (isSel ? 11.0 : 10.5)
                        : (isSel ? 12.0 : 11.2);
                    final labelColor = isSel
                        ? Color.lerp(selectedColor, AppInk.strong, 0.10)!
                        : unselectedColor.withValues(alpha: 0.82);
                    final indicatorTopAlpha = (indicatorAlpha + 0.035)
                        .clamp(0.0, 0.30)
                        .toDouble();
                    final indicatorBottomAlpha = (indicatorAlpha * 0.48)
                        .clamp(0.0, 0.16)
                        .toDouble();
                    final showIndicator = isSel || isPressed;

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
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            decoration: BoxDecoration(
                              color: selectedColor.withValues(
                                alpha: indicatorAlpha,
                              ),
                              gradient: showIndicator
                                  ? LinearGradient(
                                      colors: [
                                        selectedColor.withValues(
                                          alpha: indicatorTopAlpha,
                                        ),
                                        selectedColor.withValues(
                                          alpha: indicatorBottomAlpha,
                                        ),
                                      ],
                                      begin: Alignment.topCenter,
                                      end: Alignment.bottomCenter,
                                    )
                                  : null,
                              borderRadius: BorderRadius.circular(18),
                              border: isSel
                                  ? Border.all(
                                      color: selectedColor.withValues(
                                        alpha: 0.30,
                                      ),
                                    )
                                  : null,
                              boxShadow: isSel
                                  ? [
                                      BoxShadow(
                                        color: selectedColor.withValues(
                                          alpha: 0.13,
                                        ),
                                        blurRadius: 14,
                                        offset: const Offset(0, 5),
                                      ),
                                    ]
                                  : null,
                            ),
                            child: AnimatedSlide(
                              duration: const Duration(milliseconds: 140),
                              curve: Curves.easeOutCubic,
                              offset: Offset(0, isSel ? -0.025 : 0),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  TabGlyph(
                                    tabId: t.id,
                                    fallbackIcon: t.icon,
                                    fallbackColor: color,
                                    size: iconSize,
                                    selected: isSel,
                                  ),
                                  const SizedBox(height: 3),
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
                                            color: labelColor,
                                            fontWeight: isSel
                                                ? FontWeight.w800
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
          ),
        ),
      ),
    );
  }
}
