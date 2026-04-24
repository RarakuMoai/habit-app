import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'pages/home_page.dart';
import 'pages/timer_page.dart';
import 'pages/water_page.dart';
import 'pages/weight_page.dart';
import 'pages/onboarding_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  final bool onboardingDone = prefs.getBool('onboarding_done') ?? false;
  runApp(MyApp(startAtHome: onboardingDone));
}

class MyApp extends StatelessWidget {
  final bool startAtHome;
  const MyApp({super.key, required this.startAtHome});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '習慣養成',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFFF7043)),
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFFFF8F0),
        cardColor: Colors.white,
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFFFF7043),
          foregroundColor: Colors.white,
          iconTheme: IconThemeData(color: Colors.white),
          titleTextStyle: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w500,
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
  bool _waterEnabled = true;
  bool _timerEnabled = true;
  bool _weightTrackingEnabled = false;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      // 若 onboarding 尚未執行過（key 不存在），預設顯示所有頁籤
      _waterEnabled = prefs.getBool('water_enabled') ?? true;
      _timerEnabled = prefs.getBool('timer_enabled') ?? true;
      _weightTrackingEnabled = prefs.getBool('weight_tracking_enabled') ?? false;
      _loaded = true;
    });
  }

  // 依功能開關動態組裝頁籤
  List<_TabItem> get _tabs {
    final list = <_TabItem>[
      _TabItem(page: HomePage(onSettingsChanged: _loadSettings), icon: Icons.home, label: '習慣'),
    ];
    if (_timerEnabled) {
      list.add(_TabItem(page: const TimerPage(), icon: Icons.timer, label: '番茄鐘'));
    }
    if (_waterEnabled) {
      list.add(_TabItem(page: const WaterPage(), icon: Icons.water_drop, label: '喝水'));
    }
    // 體重頁籤，依 weight_tracking_enabled 開關決定是否顯示
    if (_weightTrackingEnabled) {
      list.add(_TabItem(page: const WeightPage(), icon: Icons.monitor_weight, label: '體重'));
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
          // 只有習慣頁時不顯示底部列
          ? null
          : BottomNavigationBar(
              currentIndex: _currentIndex,
              onTap: (index) => setState(() => _currentIndex = index),
              type: BottomNavigationBarType.fixed,
              // 使用當前主題的主色，確保切換主題後底部列顏色同步更新
              selectedItemColor: Theme.of(context).colorScheme.primary,
              unselectedItemColor: Colors.grey,
              items: tabs
                  .map((t) => BottomNavigationBarItem(icon: Icon(t.icon), label: t.label))
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
