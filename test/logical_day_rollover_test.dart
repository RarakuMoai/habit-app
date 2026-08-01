// 跨日在真實 widget 樹上的行為：MainPage 訂閱 coordinator → 先刷新喝水/體重的
// 自動完成旗標 → 再把 revision 傳給首頁 / 喝水頁 / 體重頁。
//
// 這裡釘住的是「使用者看得到的」那一層：畫面換成新一天、昨天的達標不會污染
// 今天、問候只出現一次、兔咪回到中性。
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:habit_app/main.dart';
import 'package:habit_app/pages/home/greeting_banner.dart';
import 'package:habit_app/pages/home_page.dart';
import 'package:habit_app/pages/water_page.dart';
import 'package:habit_app/utils/coin_service.dart';
import 'package:habit_app/utils/logical_date.dart';
import 'package:habit_app/utils/logical_day_coordinator.dart';
import 'package:habit_app/utils/mascot.dart';
import 'package:habit_app/utils/prefs_keys.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'l10n_test_app.dart';

class _FakeClock {
  DateTime now;
  _FakeClock(this.now);
  DateTime call() => now;
}

Map<String, dynamic> _habit(
  String name, {
  required String id,
  bool done = false,
}) {
  return <String, dynamic>{
    'id': id,
    'name': name,
    'done': done,
    'frequency': 'daily',
    'createdAt': '2026-01-02',
  };
}

/// 昨天（07-31）兩個每日習慣完成了一個，連勝 4（跨日後應歸零）。
///
/// 兩個刻意的選擇：
/// 1. 不用「喝足夠的水」「體重紀錄」當預設資料——它們的勾選會被喝水／體重的
///    當日狀態覆寫（既有行為），會蓋掉這裡想觀察的跨日效果。
/// 2. 不讓每日習慣「全部完成」——那會掛上 all-done 慶祝層，而
///    `RoomSceneEffectsPainter._paintCompletionAura` 有個既有的 radial
///    gradient 參數錯誤，一畫就丟 ArgumentError。那是 all-done／VFX 的問題，
///    不在本 milestone 範圍內；連勝加一的結算路徑改由 coordinator 測試覆蓋。
Map<String, Object> _yesterdayPartlyDone({List<Map<String, dynamic>>? habits}) {
  return {
    PrefsKeys.lastOpenDate: '2026-07-31',
    PrefsKeys.streak: 4,
    PrefsKeys.habitDoneDay('2026-07-31'): jsonEncode(['h1']),
    PrefsKeys.habits: jsonEncode(
      habits ??
          [
            _habit('走路', id: 'h1', done: true),
            _habit('閱讀', id: 'h2'),
          ],
    ),
    // 每日登入獎勵走真實日曆日；先標成今天已領，讓慶祝頁不要插進來。
    PrefsKeys.coinLastLoginDate: _calendarToday(),
  };
}

String _calendarToday() {
  final n = DateTime.now();
  return '${n.year}-${n.month.toString().padLeft(2, '0')}-'
      '${n.day.toString().padLeft(2, '0')}';
}

late _FakeClock _clock;

Future<void> _pumpMain(WidgetTester tester, DateTime at) async {
  _clock = _FakeClock(at);
  LogicalDayCoordinator.debugInstance = LogicalDayCoordinator(
    clock: _clock.call,
  );
  // 冷啟動 barrier：coordinator 先完成第一次驗證，MainPage / HomePage 才開始
  // 初始化（正式路徑在 _loadStartupState 裡 await 同一件事）。
  await LogicalDayCoordinator.instance.start();
  await tester.pumpWidget(l10nTestApp(home: const MainPage()));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 120));
}

/// 推進時鐘並讓 coordinator 重新驗證（等同前景邊界計時器醒來）。
Future<void> _crossTo(WidgetTester tester, DateTime at) async {
  _clock.now = at;
  await LogicalDayCoordinator.instance.ensureCurrent(
    trigger: LogicalDayTrigger.boundaryTimer,
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 120));
}

Future<void> _teardownTree(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 12));
}

List<Map<String, dynamic>> _storedHabits(SharedPreferences prefs) {
  return (jsonDecode(prefs.getString(PrefsKeys.habits)!) as List)
      .map((e) => Map<String, dynamic>.from(e as Map))
      .toList();
}

HomePage _homeWidget(WidgetTester tester) =>
    tester.widget<HomePage>(find.byType(HomePage));

/// 進度用 state 的 getter 讀，不靠 find.text——同樣的「done / total」字串在
/// 進度列與分段標題各出現一次。
dynamic _homeState(WidgetTester tester) =>
    tester.state(find.byType(HomePage)) as dynamic;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    LogicalDayCoordinator.debugInstance = null;
    LogicalDate.notifier.value = LogicalDate.defaultHour;
    CoinService.dailyRewardShowing.value = false;
  });

  testWidgets('前景跨日：習慣數量不變、勾選全部重置、進度歸零', (tester) async {
    SharedPreferences.setMockInitialValues(_yesterdayPartlyDone());
    await _pumpMain(tester, DateTime(2026, 8, 1, 3, 58));

    expect(_homeWidget(tester).dayStamp!.logicalDate, '2026-07-31');
    expect(_homeState(tester).dailyDoneCount, 1, reason: '跨日前顯示昨天的進度');

    await _crossTo(tester, DateTime(2026, 8, 1, 4, 0, 1));

    expect(_homeWidget(tester).dayStamp!.logicalDate, '2026-08-01');
    expect(_homeState(tester).dailyDoneCount, 0, reason: '新的一天進度歸零');
    expect((_homeState(tester).habits as List).length, 2);

    final prefs = await SharedPreferences.getInstance();
    final habits = _storedHabits(prefs);
    expect(habits.length, 2, reason: '不得出現重複習慣');
    expect(habits.every((h) => h['done'] == false), isTrue);
    expect(prefs.getInt(PrefsKeys.streak), 0, reason: '昨天沒有全完成 → 連勝歸零');

    await _teardownTree(tester);
  });

  testWidgets('前景跨日：今天的歷史清空、昨天的歷史原封不動', (tester) async {
    SharedPreferences.setMockInitialValues(_yesterdayPartlyDone());
    await _pumpMain(tester, DateTime(2026, 8, 1, 3, 58));
    await _crossTo(tester, DateTime(2026, 8, 1, 4, 0, 1));

    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getString(PrefsKeys.habitDoneDay('2026-07-31')),
      jsonEncode(['h1']),
      reason: '昨天的歷史是結算的輸入，絕不能被動到',
    );
    expect(
      prefs.getString(PrefsKeys.habitDoneDay('2026-08-01')),
      isNull,
      reason: '新的一天沒有完成，空集合不留空殼 key',
    );

    await _teardownTree(tester);
  });

  testWidgets('昨天的喝水達標旗標不會帶進今天', (tester) async {
    // 沒有「喝足夠的水」習慣，喝水頁就不會被 WaterHabitLink 自動啟用。
    // 喝水頁自己讀真實時鐘算今天（本 milestone 不改它的功能規則），掛上來會用
    // 真實日期覆寫達標回報，會蓋掉這裡要觀察的東西。
    final base = _yesterdayPartlyDone();
    base[PrefsKeys.waterGoalDate] = '2026-07-31';
    SharedPreferences.setMockInitialValues(base);

    await _pumpMain(tester, DateTime(2026, 8, 1, 3, 58));
    expect(
      _homeWidget(tester).waterHabitAutoComplete,
      isTrue,
      reason: '跨日前昨天確實達標',
    );

    await _crossTo(tester, DateTime(2026, 8, 1, 4, 0, 1));

    expect(
      _homeWidget(tester).waterHabitAutoComplete,
      isFalse,
      reason: 'MainPage 必須先用新的一天重算旗標，才輪到 Home 重載；'
          '順序錯的話昨天的達標會被寫成今天已完成',
    );

    await _teardownTree(tester);
  });

  testWidgets('昨天記過體重不會把今天的體重習慣勾起來', (tester) async {
    final base = _yesterdayPartlyDone(
      habits: [
        _habit('體重紀錄', id: 'h1', done: true),
        _habit('走路', id: 'h2'),
      ],
    );
    base[PrefsKeys.weightRecords] = jsonEncode([
      {'date': '2026-07-31', 'weight': 60.0},
    ]);
    SharedPreferences.setMockInitialValues(base);

    await _pumpMain(tester, DateTime(2026, 8, 1, 3, 58));
    expect(_homeWidget(tester).weightHabitAutoComplete, isTrue);

    await _crossTo(tester, DateTime(2026, 8, 1, 4, 0, 1));

    expect(_homeWidget(tester).weightHabitAutoComplete, isFalse);
    final prefs = await SharedPreferences.getInstance();
    final weight = _storedHabits(
      prefs,
    ).firstWhere((h) => h['name'] == '體重紀錄');
    expect(weight['done'], isFalse);

    await _teardownTree(tester);
  });

  testWidgets('同日 resume 不重置、不重載、不問候', (tester) async {
    SharedPreferences.setMockInitialValues({
      PrefsKeys.lastOpenDate: '2026-08-01',
      PrefsKeys.streak: 4,
      PrefsKeys.habitDoneDay('2026-08-01'): jsonEncode(['h1']),
      PrefsKeys.habits: jsonEncode([
        _habit('走路', id: 'h1', done: true),
        _habit('閱讀', id: 'h2'),
      ]),
      PrefsKeys.coinLastLoginDate: _calendarToday(),
    });
    await _pumpMain(tester, DateTime(2026, 8, 1, 9));
    final revisionBefore = _homeWidget(tester).dayStamp!.revision;
    expect(_homeState(tester).dailyDoneCount, 1);

    // 同一天多次 resume
    for (var i = 0; i < 3; i++) {
      await LogicalDayCoordinator.instance.ensureCurrent(
        trigger: LogicalDayTrigger.resume,
      );
      await tester.pump(const Duration(milliseconds: 60));
    }

    expect(_homeState(tester).dailyDoneCount, 1, reason: '同日不得重置勾選');
    expect(
      _homeWidget(tester).dayStamp!.revision,
      revisionBefore,
      reason: '沒有變化就不該廣播，下游也不該白重載',
    );
    expect(find.byType(GreetingBanner), findsNothing);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt(PrefsKeys.streak), 4);

    await _teardownTree(tester);
  });

  testWidgets('跨日後兔咪回到中性 baseline（無台詞）', (tester) async {
    SharedPreferences.setMockInitialValues(_yesterdayPartlyDone());
    await _pumpMain(tester, DateTime(2026, 8, 1, 3, 58));

    // 模擬昨天全完成留下的兔咪狀態
    MascotPersona.setForContext(
      MascotEmotion.happy.assetPath,
      MascotContext.allDone,
      speech: '今天全部完成了。',
      force: true,
    );
    await tester.pump();
    expect(MascotPersona.current.value.speech, isNotNull);

    await _crossTo(tester, DateTime(2026, 8, 1, 4, 0, 1));

    expect(
      MascotPersona.current.value.speech,
      isNull,
      reason: '新的一天 MI baseline 要回中性，否則會和歸零的進度對不上',
    );
    expect(MascotPersona.current.value.bubble, isNull);

    await _teardownTree(tester);
  });

  testWidgets('跨日問候只出現一次，重複驗證不重播', (tester) async {
    SharedPreferences.setMockInitialValues(_yesterdayPartlyDone());
    await _pumpMain(tester, DateTime(2026, 8, 1, 3, 58));
    expect(find.byType(GreetingBanner), findsNothing);

    await _crossTo(tester, DateTime(2026, 8, 1, 4, 0, 1));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(GreetingBanner), findsOneWidget);

    // 同一個 transition 再驗證幾次（resume、重新訂閱）都不該再冒一次
    for (var i = 0; i < 3; i++) {
      await LogicalDayCoordinator.instance.ensureCurrent(
        trigger: LogicalDayTrigger.resume,
      );
      await tester.pump(const Duration(milliseconds: 60));
    }
    expect(find.byType(GreetingBanner), findsOneWidget);

    await _teardownTree(tester);
  });

  testWidgets('改 dayStartHour：三個頁面拿到同一個 revision，且各只重載一次', (tester) async {
    SharedPreferences.setMockInitialValues({
      PrefsKeys.dayStartHour: 4,
      PrefsKeys.waterEnabled: true,
      PrefsKeys.lastOpenDate: '2026-07-31',
      PrefsKeys.streak: 4,
      PrefsKeys.habitDoneDay('2026-07-31'): jsonEncode(['h1']),
      PrefsKeys.habits: jsonEncode([_habit('走路', id: 'h1', done: true)]),
      PrefsKeys.coinLastLoginDate: _calendarToday(),
    });
    // 凌晨 1 點、換日 4 點 → 今天還是 07-31
    await _pumpMain(tester, DateTime(2026, 8, 1, 1));
    expect(_homeWidget(tester).dayStamp!.logicalDate, '2026-07-31');
    final waterTriggerBefore = tester
        .widget<WaterPage>(find.byType(WaterPage, skipOffstage: false))
        .reloadTrigger;
    final revisionBefore = _homeWidget(tester).dayStamp!.revision;

    // 使用者把換日改成午夜 → 今天變成 08-01
    final prefs = await SharedPreferences.getInstance();
    await LogicalDate.save(prefs, 0); // notifier 只通知 coordinator
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));

    final home = _homeWidget(tester);
    final water = tester.widget<WaterPage>(
      find.byType(WaterPage, skipOffstage: false),
    );
    expect(home.dayStamp!.logicalDate, '2026-08-01');
    expect(home.dayStamp!.dayStartHour, 0);
    expect(
      home.dayStamp!.revision,
      revisionBefore + 1,
      reason: '同一次變更只該廣播一次',
    );
    expect(
      water.reloadTrigger,
      waterTriggerBefore + 1,
      reason: '兩條通知路徑並存的話，喝水頁會連續載入兩次',
    );

    await _teardownTree(tester);
  });

  testWidgets('跨日途中把整棵樹拆掉：不丟 setState 例外', (tester) async {
    SharedPreferences.setMockInitialValues(_yesterdayPartlyDone());
    await _pumpMain(tester, DateTime(2026, 8, 1, 3, 58));

    _clock.now = DateTime(2026, 8, 1, 4, 0, 1);
    final pending = LogicalDayCoordinator.instance.ensureCurrent(
      trigger: LogicalDayTrigger.boundaryTimer,
    );
    await tester.pumpWidget(const SizedBox());
    await pending;
    await tester.pump(const Duration(seconds: 12));

    expect(tester.takeException(), isNull);
  });
}
