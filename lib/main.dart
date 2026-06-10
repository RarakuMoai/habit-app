import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'pages/home_page.dart';
import 'pages/timer_page.dart';
import 'pages/water_page.dart';
import 'pages/weight_page.dart';
import 'pages/onboarding_page.dart';
import 'pages/family_page.dart';
import 'utils/audio_settings_service.dart';
import 'utils/bgm_service.dart';
import 'utils/mascot.dart';
import 'utils/notification_service.dart';
import 'utils/sfx_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 鎖定只支援直向（防止橫向自動翻轉）
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  final prefs = await SharedPreferences.getInstance();
  final bool onboardingDone = prefs.getBool('onboarding_done') ?? false;
  // 載入兔咪展開/收合偏好（全 app 共用同一個 toggle）
  await MascotPanelPrefs.load();
  await AudioSettingsService.instance.init();
  // 初始化本機通知（番茄鐘倒數結束鈴用）；權限到第一次排通知才會跳 dialog
  await NotificationService.init();
  // App 冷啟動：兔咪從 openApp 池隨機抽一句問候，每次打開都有變化
  MascotPersona.resetToOpening();
  runApp(MyApp(startAtHome: onboardingDone));
  // BGM 初始化 + 播放放到第一個 frame 之後再稍微延遲。
  // flutter run --release 安裝後自動拉起 app 時，iOS 音訊路由偶爾還沒穩；
  // 等畫面 settled 再啟動音樂，比 main() 裡立刻 play 更可靠。
  WidgetsBinding.instance.addPostFrameCallback((_) {
    unawaited(_startInitialAudio(onboardingDone: onboardingDone));
  });
}

Future<void> _startInitialAudio({required bool onboardingDone}) async {
  try {
    await Future.delayed(const Duration(milliseconds: 900));
    await BgmService.instance.init();
    await BgmService.instance.play(
      onboardingDone ? 'sounds/bgm_main.m4a' : 'sounds/bgm_onboarding.m4a',
      deferFade: !onboardingDone,
    );
    await SfxService.instance.init();
  } catch (e, st) {
    debugPrint('BGM init/play failed: $e\n$st');
  }
}

class MyApp extends StatelessWidget {
  final bool startAtHome;
  const MyApp({super.key, required this.startAtHome});

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
      ),
      initialRoute: startAtHome ? '/home' : '/onboarding',
      routes: {
        '/onboarding': (_) => const OnboardingPage(),
        '/home': (_) => const MainPage(),
      },
    );
  }
}

class MainPage extends StatefulWidget {
  const MainPage({super.key});

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  int _currentIndex = 0;
  bool _waterEnabled = false;
  bool _timerEnabled = true;
  bool _weightTrackingEnabled = false;
  bool _familyEnabled = false;
  bool _waterGoalReached = false;
  bool _loaded = false;
  int _waterReloadTrigger = 0;

  @override
  void initState() {
    super.initState();
    _loadSettings();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _ensureMainBgm();
    });
  }

  Future<void> _ensureMainBgm() async {
    try {
      await Future.delayed(const Duration(milliseconds: 2800));
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
    setState(() {
      _waterEnabled = prefs.getBool('water_enabled') ?? false;
      _timerEnabled = prefs.getBool('timer_enabled') ?? true;
      _weightTrackingEnabled =
          prefs.getBool('weight_tracking_enabled') ?? false;
      _familyEnabled = prefs.getBool('family_enabled') ?? false;
      _waterGoalReached = prefs.getString('water_goal_date') == _todayString();
      _loaded = true;
    });
  }

  Future<void> _handleWaterGoal(bool reached) async {
    final prefs = await SharedPreferences.getInstance();
    if (reached) {
      await prefs.setString('water_goal_date', _todayString());
    } else {
      await prefs.remove('water_goal_date');
    }
    setState(() => _waterGoalReached = reached);
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
    await prefs.setString('water_entries_$today', jsonEncode(entries));
    await prefs.setInt('water_$today', cupCount);
    await prefs.setInt(
      'water_extra_$today',
      (totalMl - cupMlTotal).clamp(0, 12000).toInt(),
    );
  }

  Future<void> _handleWaterHabitToggle(bool checked) async {
    final prefs = await SharedPreferences.getInstance();
    final cupMl = prefs.getInt('water_cup_ml') ?? 250;
    final goalMl = prefs.getInt('water_goal_ml') ?? 2000;
    final waterGoal = (goalMl / cupMl).ceil();
    final today = _todayString();
    final todayKey = 'water_$today';
    final savedKey = 'water_saved_$today';
    final entriesKey = 'water_entries_$today';
    final savedEntriesKey = 'water_entries_saved_$today';
    final extraKey = 'water_extra_$today';

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
          : (jsonDecode(savedEntries) as List)
                .whereType<Map>()
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
          onWaterHabitToggled: _handleWaterHabitToggle,
        ),
        icon: Icons.home,
        label: '習慣',
      ),
    ];
    if (_timerEnabled) {
      list.add(
        _TabItem(page: const TimerPage(), icon: Icons.timer, label: '番茄鐘'),
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
          page: const WeightPage(),
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
    return list;
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
      body: tabs[_currentIndex].page,
      bottomNavigationBar: tabs.length == 1
          // 只有習慣頁時，用裝飾條取代 bottom nav，
          // 確保版面高度跟「有開其他功能」時一致，兔咪/對話框位置不會跑掉
          ? const _DecorativeFloor()
          : BottomNavigationBar(
              currentIndex: _currentIndex,
              onTap: (index) {
                // 離開家庭頁籤時清除家長 Session，下次進入需重新驗證
                final familyIdx = tabs.indexWhere((t) => t.label == '家庭');
                if (familyIdx != -1 &&
                    _currentIndex == familyIdx &&
                    index != familyIdx) {
                  parentSessionActive = false;
                }
                setState(() => _currentIndex = index);
              },
              type: BottomNavigationBarType.fixed,
              // 使用當前主題的主色，確保切換主題後底部列顏色同步更新
              selectedItemColor: Theme.of(context).colorScheme.primary,
              unselectedItemColor: Colors.grey,
              items: tabs
                  .map(
                    (t) => BottomNavigationBarItem(
                      icon: Icon(t.icon),
                      label: t.label,
                    ),
                  )
                  .toList(),
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

// 「只有習慣頁」時的底部裝飾條。
// 高度跟 BottomNavigationBar 一致，避免功能開關後版面跳動。
// 視覺：warm 漸層 + 中央三顆淡色小裝飾，跟兔咪場景配色呼應。
class _DecorativeFloor extends StatelessWidget {
  const _DecorativeFloor();

  @override
  Widget build(BuildContext context) {
    final hour = DateTime.now().hour;
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
