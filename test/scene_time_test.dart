// SceneTimeController / SceneTimeState 單元測試
// （四時段權重、交界平滑、分鐘 tick、resume 刷新、覆寫優先序）。
import 'package:fake_async/fake_async.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:habit_app/utils/scene_time.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SceneTimeState 權重', () {
    test('權重總和恆為 1（全天掃描）', () {
      for (var h = 0.0; h < 24.0; h += 0.05) {
        final s = SceneTimeState.fromHour(h);
        final sum =
            s.morningWeight + s.dayWeight + s.duskWeight + s.nightWeight;
        expect(sum, closeTo(1.0, 1e-9), reason: 'hour=$h');
      }
    });

    test('核心時段權重為 1、dominant 正確', () {
      expect(SceneTimeState.fromHour(7.5).morningWeight, closeTo(1, 1e-9));
      expect(SceneTimeState.fromHour(13.0).dayWeight, closeTo(1, 1e-9));
      expect(SceneTimeState.fromHour(17.5).duskWeight, closeTo(1, 1e-9));
      expect(SceneTimeState.fromHour(23.0).nightWeight, closeTo(1, 1e-9));
      expect(SceneTimeState.fromHour(2.0).nightWeight, closeTo(1, 1e-9));
      expect(SceneTimeState.fromHour(7.5).dominantPeriod, ScenePeriod.morning);
      expect(SceneTimeState.fromHour(13.0).dominantPeriod, ScenePeriod.day);
      expect(SceneTimeState.fromHour(17.5).dominantPeriod, ScenePeriod.dusk);
      expect(SceneTimeState.fromHour(23.0).dominantPeriod, ScenePeriod.night);
    });

    test('定案里程碑時間會進入完整時段', () {
      expect(SceneTimeState.fromHour(5.0).morningWeight, closeTo(1, 1e-9));
      expect(SceneTimeState.fromHour(9.0).dayWeight, closeTo(1, 1e-9));
      expect(SceneTimeState.fromHour(16.0).duskWeight, 0);
      expect(SceneTimeState.fromHour(17.0).duskWeight, closeTo(1, 1e-9));
      expect(SceneTimeState.fromHour(19.0).nightWeight, closeTo(1, 1e-9));
    });

    test('交界區間兩時段共存且互補（18:15–19:00 黃昏→夜）', () {
      final s = SceneTimeState.fromHour(18.625); // 交界正中
      expect(s.duskWeight, closeTo(0.5, 1e-9));
      expect(s.nightWeight, closeTo(0.5, 1e-9));
      expect(s.morningWeight, 0);
      expect(s.dayWeight, 0);
    });

    test('正式時段邊界：交界起點前新時段權重必為 0', () {
      expect(SceneTimeState.fromHour(4.24).morningWeight, 0);
      expect(SceneTimeState.fromHour(4.24).nightWeight, closeTo(1, 1e-9));
      expect(SceneTimeState.fromHour(8.24).dayWeight, 0);
      expect(SceneTimeState.fromHour(15.99).duskWeight, 0);
      expect(SceneTimeState.fromHour(18.24).nightWeight, 0);
    });

    test('layerBlend：純時段單圖、交界回傳相鄰底圖+疊圖', () {
      final pure = SceneTimeState.fromHour(13.0).layerBlend;
      expect(pure.base, ScenePeriod.day);
      expect(pure.overlay, isNull);
      expect(pure.overlayOpacity, 0);

      final mid = SceneTimeState.fromHour(16.5).layerBlend; // 晝→暮正中
      expect(mid.base, ScenePeriod.day);
      expect(mid.overlay, ScenePeriod.dusk);
      expect(mid.overlayOpacity, closeTo(0.5, 1e-9));

      final wrap = SceneTimeState.fromHour(4.625).layerBlend; // 夜→晨（跨序）
      expect(wrap.base, ScenePeriod.night);
      expect(wrap.overlay, ScenePeriod.morning);
      expect(wrap.overlayOpacity, closeTo(0.5, 1e-9));
    });

    test('計劃書指定檢查點無跳變（相鄰一分鐘權重差 < 0.05）', () {
      // 交界正中與交界外緣、跨午夜
      for (final h in [
        4.6,
        5.0,
        8.6,
        9.0,
        16.5,
        17.0,
        18.6,
        19.0,
        23.983,
        0.0,
      ]) {
        final a = SceneTimeState.fromHour(h);
        final b = SceneTimeState.fromHour((h + 1 / 60) % 24);
        for (final p in ScenePeriod.values) {
          expect(
            (a.weight(p) - b.weight(p)).abs(),
            lessThan(0.05),
            reason: 'hour=$h period=$p',
          );
        }
      }
    });

    test('跨午夜連續：23:59 與 00:00 幾乎相同', () {
      final a = SceneTimeState.fromHour(23.9999);
      final b = SceneTimeState.fromHour(0.0);
      expect(a.nightWeight, closeTo(b.nightWeight, 1e-3));
    });

    test('blendColor：白天全透明不污染其他時段', () {
      const night = Color(0xFF3F456B);
      final s = SceneTimeState.fromHour(23.0);
      final c = s.blendColor(
        morning: const Color(0x1AFFC4AD),
        day: const Color(0x00000000),
        dusk: const Color(0x1AC9A1E8),
        night: night.withValues(alpha: 0.12),
      );
      expect(c.a, closeTo(0.12, 1e-6));
      expect(c.r, closeTo(night.r, 1e-6));
      // 白天正中：完全透明
      final noon = SceneTimeState.fromHour(13.0).blendColor(
        morning: const Color(0x1AFFC4AD),
        day: const Color(0x00000000),
        dusk: const Color(0x1AC9A1E8),
        night: night.withValues(alpha: 0.12),
      );
      expect(noon.a, closeTo(0, 1e-6));
    });

    test('blendOpaque / blendValue 在交界取中間值', () {
      final s = SceneTimeState.fromHour(18.625); // 黃昏/夜 各 0.5
      final v = s.blendValue(morning: 0, day: 0, dusk: 1.0, night: 0.5);
      expect(v, closeTo(0.75, 1e-9));
      final c = s.blendOpaque(
        morning: const Color(0xFF000000),
        day: const Color(0xFF000000),
        dusk: const Color(0xFFFFFFFF),
        night: const Color(0xFF000000),
      );
      expect(c.r, closeTo(0.5, 1e-6));
    });
  });

  group('SceneTimeController', () {
    tearDown(() => SceneTimeController.debugInstance = null);

    test('分鐘 tick：只在有 listener 時運轉，跨分鐘會 notify', () {
      fakeAsync((async) {
        final base = DateTime(2026, 7, 12, 18, 40, 30);
        final ctrl = SceneTimeController(clock: () => base.add(async.elapsed));
        var notified = 0;
        expect(ctrl.state.hour, closeTo(18 + 40.5 / 60, 1e-6));

        void listener() => notified++;
        ctrl.addListener(listener);
        // 無跨分鐘前不 notify
        async.elapse(const Duration(seconds: 10));
        expect(notified, 0);
        // 跨過 18:41 分界 → notify 一次
        async.elapse(const Duration(seconds: 25));
        expect(notified, 1);
        expect(ctrl.state.hour, closeTo(18 + 41 / 60, 1e-3));
        // 連續 3 分鐘 → 各一次
        async.elapse(const Duration(minutes: 3));
        expect(notified, 4);

        // 移除 listener → timer 停止，不再 notify
        ctrl.removeListener(listener);
        async.elapse(const Duration(minutes: 5));
        expect(notified, 4);
        ctrl.dispose();
      });
    });

    test('系統時間被改（前景）：下一個分鐘 tick 自我校正', () {
      fakeAsync((async) {
        var base = DateTime(2026, 7, 12, 10, 0, 10);
        final ctrl = SceneTimeController(clock: () => base.add(async.elapsed));
        ctrl.addListener(() {});
        expect(ctrl.state.dominantPeriod, ScenePeriod.day);
        // 模擬使用者把時鐘改到夜晚
        base = DateTime(2026, 7, 12, 22, 0, 10).subtract(async.elapsed);
        async.elapse(const Duration(seconds: 61));
        expect(ctrl.state.dominantPeriod, ScenePeriod.night);
        ctrl.dispose();
      });
    });

    test('App resume 立刻 refresh（跨午夜/改時區情境）', () {
      var now = DateTime(2026, 7, 12, 23, 50);
      final ctrl = SceneTimeController(clock: () => now);
      var notified = 0;
      ctrl.addListener(() => notified++);
      // 背景期間跨午夜到早晨
      ctrl.didChangeAppLifecycleState(AppLifecycleState.paused);
      now = DateTime(2026, 7, 13, 7, 30);
      ctrl.didChangeAppLifecycleState(AppLifecycleState.resumed);
      expect(notified, greaterThanOrEqualTo(1));
      expect(ctrl.state.dominantPeriod, ScenePeriod.morning);
      expect(ctrl.state.hour, closeTo(7.5, 1e-6));
      ctrl.dispose();
    });

    test('覆寫優先序：debug 預覽 > 固定時段 > 真實時間', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final ctrl = SceneTimeController(clock: () => DateTime(2026, 7, 12, 13));
      expect(ctrl.state.dominantPeriod, ScenePeriod.day);

      await ctrl.setFixedPeriod(ScenePeriod.night, prefs: prefs);
      expect(ctrl.state.dominantPeriod, ScenePeriod.night);
      expect(
        ctrl.state.hour,
        SceneTimeController.periodAnchorHour(ScenePeriod.night),
      );

      ctrl.setPreviewHour(6.5); // dev 預覽壓過固定時段
      expect(ctrl.state.hour, closeTo(6.5, 1e-9));

      ctrl.setPreviewHour(null); // 收回預覽 → 回到固定時段
      expect(ctrl.state.dominantPeriod, ScenePeriod.night);

      await ctrl.setFixedPeriod(null, prefs: prefs);
      expect(ctrl.state.dominantPeriod, ScenePeriod.day);
      ctrl.dispose();
    });

    test('loadFromPrefs 還原固定時段與 debug 預覽', () async {
      SharedPreferences.setMockInitialValues({
        'scene_fixed_period': 'dusk',
        'debug_scene_hour': 22.0,
      });
      final prefs = await SharedPreferences.getInstance();
      final ctrl = SceneTimeController(clock: () => DateTime(2026, 7, 12, 13));
      ctrl.loadFromPrefs(prefs);
      // debug 預覽（22.0）優先於固定時段（dusk）
      expect(ctrl.state.dominantPeriod, ScenePeriod.night);
      ctrl.setPreviewHour(null);
      expect(ctrl.state.dominantPeriod, ScenePeriod.dusk);
      ctrl.dispose();
    });

    test('refresh 同一分鐘內不重複 notify、force 例外', () {
      var now = DateTime(2026, 7, 12, 13, 0, 5);
      final ctrl = SceneTimeController(clock: () => now);
      var notified = 0;
      ctrl.addListener(() => notified++);
      final n0 = notified;
      now = DateTime(2026, 7, 12, 13, 0, 40); // 同一分鐘
      ctrl.refresh();
      expect(notified, n0);
      ctrl.refresh(force: true);
      expect(notified, n0 + 1);
      ctrl.dispose();
    });
  });
}
