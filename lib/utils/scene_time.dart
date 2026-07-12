// 四時段場景的單一時間引擎（docs/fable5_day_cycle_scene_plan.md §5.1）。
//
// 全 App 的場景時段（早晨/白天/黃昏/夜晚）只從這裡讀：
//   SceneTimeController.instance.state
//
// 設計要點：
// - 四時段用 0~1 權重＋smoothstep 交接（交界區兩個相鄰時段同時存在），
//   權重總和恆為 1，不存在四色瞬切。
// - 正常情況每分鐘 refresh 一次（對齊牆鐘分界），不逐幀讀系統時間；
//   painter 在 paint() 內讀 state.hour，不再直接 DateTime.now()。
// - App resume 立刻 refresh（涵蓋背景期間改系統時間/時區/跨午夜）；
//   前景中時間被改，最晚下一個分鐘 tick 也會自我校正。
// - 分鐘計時器只在「有 listener」時運轉：widget 樹拆掉（含測試）就自動
//   停止，不留 pending timer。
// - 覆寫優先序：debug 預覽小時 > 使用者固定時段 > 真實時間。
import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'feature_flags.dart';
import 'prefs_keys.dart';
import 'scene_frame_probe.dart';

/// 場景四時段。核心時段與交接區間見計劃書 §3。
enum ScenePeriod { morning, day, dusk, night }

/// 四時段交接視窗（小時，起點/終點各為前一時段權重 1→0 的 smoothstep 區間）。
/// 全 App 唯一門檻定義：任何層要判斷時段一律經由 [SceneTimeState] 權重，
/// 不得另寫 if (hour >= …) 分桶。
const double kNightToMorningStart = 5.5, kNightToMorningEnd = 6.5;
const double kMorningToDayStart = 9.0, kMorningToDayEnd = 10.0;
const double kDayToDuskStart = 16.0, kDayToDuskEnd = 17.0;
const double kDuskToNightStart = 18.75, kDuskToNightEnd = 19.75;

double _smoothstep(double a, double b, double x) {
  final t = ((x - a) / (b - a)).clamp(0.0, 1.0);
  return t * t * (3 - 2 * t);
}

/// 某一刻的場景時間狀態（不可變）。權重總和恆為 1。
@immutable
class SceneTimeState {
  final DateTime localNow;

  /// 連續小時值 0~24（含 debug 預覽/固定時段覆寫後的「有效」時間）。
  final double hour;

  final double morningWeight;
  final double dayWeight;
  final double duskWeight;
  final double nightWeight;

  const SceneTimeState._({
    required this.localNow,
    required this.hour,
    required this.morningWeight,
    required this.dayWeight,
    required this.duskWeight,
    required this.nightWeight,
  });

  /// 由連續小時值計算四權重。
  factory SceneTimeState.fromHour(double hour, {DateTime? localNow}) {
    final h = hour % 24;
    final upMorning = _smoothstep(kNightToMorningStart, kNightToMorningEnd, h);
    final upDay = _smoothstep(kMorningToDayStart, kMorningToDayEnd, h);
    final upDusk = _smoothstep(kDayToDuskStart, kDayToDuskEnd, h);
    final upNight = _smoothstep(kDuskToNightStart, kDuskToNightEnd, h);
    final morning = upMorning * (1 - upDay);
    final day = upDay * (1 - upDusk);
    final dusk = upDusk * (1 - upNight);
    // 夜晚取補數，保證總和恆為 1（跨午夜兩端自然都是夜）。
    final night = (1 - morning - day - dusk).clamp(0.0, 1.0);
    return SceneTimeState._(
      localNow: localNow ?? DateTime.now(),
      hour: h,
      morningWeight: morning,
      dayWeight: day,
      duskWeight: dusk,
      nightWeight: night,
    );
  }

  double weight(ScenePeriod p) => switch (p) {
    ScenePeriod.morning => morningWeight,
    ScenePeriod.day => dayWeight,
    ScenePeriod.dusk => duskWeight,
    ScenePeriod.night => nightWeight,
  };

  /// 權重最大的時段（交界正中間取排序靠前者，僅供文案/情緒等離散用途；
  /// 視覺一律用權重混合，不要用它做 if/else 配色）。
  ScenePeriod get dominantPeriod {
    var best = ScenePeriod.morning;
    var bestW = morningWeight;
    for (final p in const [
      ScenePeriod.day,
      ScenePeriod.dusk,
      ScenePeriod.night,
    ]) {
      final w = weight(p);
      if (w > bestW) {
        best = p;
        bestW = w;
      }
    }
    return best;
  }

  /// 四時段顏色的權重混合。alpha 加權平均、RGB 以 alpha 加權（透明時段
  /// 不會把黑色混進來），可安全混合「白天 = 全透明」這類色罩。
  Color blendColor({
    required Color morning,
    required Color day,
    required Color dusk,
    required Color night,
  }) {
    final entries = <(double, Color)>[
      (morningWeight, morning),
      (dayWeight, day),
      (duskWeight, dusk),
      (nightWeight, night),
    ];
    var a = 0.0, r = 0.0, g = 0.0, b = 0.0;
    for (final (w, c) in entries) {
      final wa = w * c.a;
      a += wa;
      r += wa * c.r;
      g += wa * c.g;
      b += wa * c.b;
    }
    if (a < 0.0005) return const Color(0x00000000);
    return Color.from(alpha: a, red: r / a, green: g / a, blue: b / a);
  }

  /// 四時段純不透明色的權重混合（漸層背景等用；不牽涉 alpha 權重）。
  Color blendOpaque({
    required Color morning,
    required Color day,
    required Color dusk,
    required Color night,
  }) {
    var r = 0.0, g = 0.0, b = 0.0;
    for (final (w, c) in [
      (morningWeight, morning),
      (dayWeight, day),
      (duskWeight, dusk),
      (nightWeight, night),
    ]) {
      r += w * c.r;
      g += w * c.g;
      b += w * c.b;
    }
    return Color.from(alpha: 1, red: r, green: g, blue: b);
  }

  /// 四時段數值的權重混合（透明度/位置/速度等參數用）。
  double blendValue({
    required double morning,
    required double day,
    required double dusk,
    required double night,
  }) =>
      morningWeight * morning +
      dayWeight * day +
      duskWeight * dusk +
      nightWeight * night;

  /// 量化到「屬於哪一分鐘」後比較（refresh 每分鐘一次，秒級差異不觸發 notify）。
  bool visuallyEquals(SceneTimeState other) =>
      (hour * 60).floor() == (other.hour * 60).floor();
}

/// 單一場景時間 controller（singleton）。所有場景層讀同一份 [state]；
/// 有 listener 時每分鐘對齊牆鐘 refresh 一次並在狀態改變時 notify。
class SceneTimeController extends ChangeNotifier with WidgetsBindingObserver {
  SceneTimeController({DateTime Function()? clock})
    : _clock = clock ?? DateTime.now {
    _state = _compute();
  }

  static SceneTimeController? _singleton;
  static SceneTimeController get instance =>
      _singleton ??= SceneTimeController();

  /// 測試用：替換/重置全域單例。
  @visibleForTesting
  static set debugInstance(SceneTimeController? c) => _singleton = c;

  final DateTime Function() _clock;
  late SceneTimeState _state;
  Timer? _tickTimer;
  bool _observing = false;

  double? _previewHour; // dev 工具的時段預覽（僅 kDevToolsEnabled 生效）
  ScenePeriod? _fixedPeriod; // 使用者「固定場景」設定；null = 跟隨真實時間

  SceneTimeState get state => _state;
  double? get previewHour => _previewHour;
  ScenePeriod? get fixedPeriod => _fixedPeriod;

  /// 固定時段的代表小時（各時段核心時間的中段）。
  static double periodAnchorHour(ScenePeriod p) => switch (p) {
    ScenePeriod.morning => 7.5,
    ScenePeriod.day => 13.0,
    ScenePeriod.dusk => 17.8,
    ScenePeriod.night => 23.0,
  };

  /// 啟動時載入持久化設定（dev 預覽小時、固定時段）。冪等。
  void loadFromPrefs(SharedPreferences prefs) {
    SceneFrameProbe.ensureAttached(); // SCENE_PERF=1 才生效，正式版 no-op
    if (kDevToolsEnabled) {
      // 截圖工作流：--dart-define=SCENE_HOUR=17.5 直接鎖定預覽小時。
      // 從外部改模擬器 prefs plist 會被 cfprefsd 快取隨機蓋回，不可靠；
      // dart-define 走編譯期常數，確定性 100%（同 GAME_SHOT 模式）。
      const forced = String.fromEnvironment('SCENE_HOUR');
      final forcedHour = double.tryParse(forced);
      if (forcedHour != null) {
        _previewHour = forcedHour;
      } else {
        // 只有 prefs 真的有值才覆蓋，避免洗掉程式裡手動設的預覽值。
        final v = prefs.getDouble(PrefsKeys.debugSceneHour);
        if (v != null) _previewHour = v;
      }
    }
    final fixed = prefs.getString(PrefsKeys.sceneFixedPeriod);
    _fixedPeriod = ScenePeriod.values.asNameMap()[fixed];
    refresh();
  }

  /// dev 工具的預覽小時覆寫（null = 回到真實時間）。持久化由 dev 頁負責。
  void setPreviewHour(double? hour) {
    if (!kDevToolsEnabled) return;
    _previewHour = hour;
    refresh(force: true);
  }

  /// 使用者「固定場景」：null = 跟隨真實時間。會持久化。
  Future<void> setFixedPeriod(
    ScenePeriod? period, {
    SharedPreferences? prefs,
  }) async {
    _fixedPeriod = period;
    refresh(force: true);
    final p = prefs ?? await SharedPreferences.getInstance();
    if (period == null) {
      await p.remove(PrefsKeys.sceneFixedPeriod);
    } else {
      await p.setString(PrefsKeys.sceneFixedPeriod, period.name);
    }
  }

  /// 重算目前狀態；有變化（分鐘級）才 notify。[force] 用於覆寫切換，
  /// 即使剛好同分鐘也強制廣播一次。
  void refresh({bool force = false}) {
    final next = _compute();
    final changed = !next.visuallyEquals(_state);
    _state = next;
    if (changed || force) notifyListeners();
  }

  SceneTimeState _compute() {
    final now = _clock();
    final preview = kDevToolsEnabled ? _previewHour : null;
    final fixed = _fixedPeriod;
    final hour = preview != null
        ? preview % 24
        : fixed != null
        ? periodAnchorHour(fixed)
        : now.hour + now.minute / 60 + now.second / 3600;
    return SceneTimeState.fromHour(hour, localNow: now);
  }

  // ── 分鐘 tick：只在有 listener 時運轉 ─────────────────────────
  @override
  void addListener(VoidCallback listener) {
    super.addListener(listener);
    _syncTicking();
  }

  @override
  void removeListener(VoidCallback listener) {
    super.removeListener(listener);
    _syncTicking();
  }

  void _syncTicking() {
    if (hasListeners) {
      if (_tickTimer == null) {
        refresh();
        _scheduleNextTick();
      }
      if (!_observing) {
        _observing = true;
        WidgetsBinding.instance.addObserver(this);
      }
    } else {
      _tickTimer?.cancel();
      _tickTimer = null;
      if (_observing) {
        _observing = false;
        WidgetsBinding.instance.removeObserver(this);
      }
    }
  }

  /// 對齊下一個牆鐘分界（+20ms 裕度）。每次 tick 重讀真實時間再排下一次，
  /// 系統時間/時區被改也會在 ≤60 秒內自我校正。
  void _scheduleNextTick() {
    final now = _clock();
    final nextMinute = DateTime(
      now.year,
      now.month,
      now.day,
      now.hour,
      now.minute,
    ).add(const Duration(minutes: 1));
    _tickTimer = Timer(
      nextMinute.difference(now) + const Duration(milliseconds: 20),
      () {
        refresh();
        if (hasListeners) {
          _scheduleNextTick();
        } else {
          _tickTimer = null;
        }
      },
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // 背景期間跨午夜/改時間/改時區 → 回前景立刻校正並重排分鐘 tick。
      refresh();
      if (hasListeners) {
        _tickTimer?.cancel();
        _scheduleNextTick();
      }
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      // 背景不留計時器（省電）；observer 保持掛著，等 resume 補 refresh。
      _tickTimer?.cancel();
      _tickTimer = null;
    }
  }

  @override
  void dispose() {
    _tickTimer?.cancel();
    _tickTimer = null;
    if (_observing) {
      _observing = false;
      WidgetsBinding.instance.removeObserver(this);
    }
    super.dispose();
  }
}
