// 證明「跟螢幕寬等比」的房間度量在 iPhone 14 Pro Max 基準（螢幕 430×932、
// MascotPageShell 實測 constraints.maxHeight=711）下，與舊公式逐位元（容差 1e-9）
// 相同 = 對作者實機零位移。這支測試就是 Route 1「零風險」的數學保證；改常數
// 若動到 14PM 值會直接 fail。
import 'package:flutter_test/flutter_test.dart';
import 'package:habit_app/pages/home/room_metrics.dart';

void main() {
  group('14 Pro Max 基準零位移', () {
    test('背景高 roomSceneHeight(430) == 舊 screenH×0.56', () {
      const oldBgHeight = kBaseHeight * 0.56; // 932 × 0.56 ≈ 521.92
      expect(roomSceneHeight(kBaseWidth), closeTo(oldBgHeight, 1e-9));
    });

    test('場景區 homeSceneRegionHeight(430) == 舊 shellMaxH×5/11', () {
      const oldRegion = kBaseShellMaxH * 5 / 11; // 711 × 5/11 ≈ 323.18
      expect(homeSceneRegionHeight(kBaseWidth), closeTo(oldRegion, 1e-9));
    });

    test('特效層 roomEffectsSceneHeight(430) == 舊 screenH×0.56', () {
      const oldBgHeight = kBaseHeight * 0.56;
      expect(roomEffectsSceneHeight(kBaseWidth), closeTo(oldBgHeight, 1e-9));
    });
  });

  group('矮胖機型（SE，375 寬）往下露出更多地板', () {
    const seWidth = 375.0;
    const seShellMaxH = 519.0; // SE 模擬器實測 constraints.maxHeight

    test('SE 背景與場景區跟 14PM 同一個「寬度比例」（不再吃高度）', () {
      expect(
        roomSceneHeight(seWidth) / seWidth,
        closeTo(roomSceneHeight(kBaseWidth) / kBaseWidth, 1e-9),
      );
      expect(
        homeSceneRegionHeight(seWidth) / seWidth,
        closeTo(homeSceneRegionHeight(kBaseWidth) / kBaseWidth, 1e-9),
      );
    });

    test('SE 新場景區比舊 shellMaxH×5/11 高 → 卡片下移、兔咪才有地板可踩', () {
      const oldSeRegion = seShellMaxH * 5 / 11; // ≈ 235.9
      expect(homeSceneRegionHeight(seWidth), greaterThan(oldSeRegion));
    });
  });

  group('chrome 修正版 sceneRegionHeightAnchored（2026-07-15）', () {
    const seWidth = 375.0;
    const seStatusBar = 20.0; // SE 狀態列（頁面 context 的 padding.top）
    const seShellMaxH = 519.0;

    test('14PM（狀態列 59）：chrome 相消 == 純寬度錨點 → 零位移', () {
      expect(
        sceneRegionHeightAnchored(kBaseWidth, kBaseStatusBarTop),
        closeTo(homeSceneRegionHeight(kBaseWidth), 1e-9),
      );
    });

    test('SE：卡片線的螢幕 Y（chrome+場景區）跟 14PM 同一個寬度比例', () {
      final seCardLine =
          seStatusBar +
          kSceneAppBarHeight +
          sceneRegionHeightAnchored(seWidth, seStatusBar);
      final baseCardLine =
          kBaseChromeTop +
          sceneRegionHeightAnchored(kBaseWidth, kBaseStatusBarTop);
      expect(seCardLine / seWidth, closeTo(baseCardLine / kBaseWidth, 1e-9));
    });

    test('SE：chrome 修正比純寬度錨點高（卡片下移，兔咪不再站地毯上緣）', () {
      expect(
        sceneRegionHeightAnchored(seWidth, seStatusBar),
        greaterThan(homeSceneRegionHeight(seWidth)),
      );
    });

    test('SE：chrome 修正後護欄仍不觸發（邊界僅 ~5pt，動常數會 fail）', () {
      expect(
        sceneRegionHeightAnchored(seWidth, seStatusBar),
        lessThan(seShellMaxH * kSceneRegionMaxFraction),
      );
    });
  });

  group('mascotStageScale 場景兔咪寬度縮放', () {
    test('14PM：縮放 == 1.0（零位移）', () {
      expect(
        mascotStageScale(
          maxWidth: kBaseWidth,
          maxHeight: homeSceneRegionHeight(kBaseWidth),
        ),
        closeTo(1.0, 1e-9),
      );
    });

    test('SE：跟背景同一個寬度比例 375/430（高度封頂不搶先）', () {
      expect(
        mascotStageScale(
          maxWidth: 375,
          maxHeight: sceneRegionHeightAnchored(375, 20),
        ),
        closeTo(375 / 430, 1e-9),
      );
    });

    test('widget test 800×600 退化面：被場景區高封頂，兔咪不爆出護欄區', () {
      const cappedRegion = 544.0 * kSceneRegionMaxFraction; // 326.4
      final s = mascotStageScale(maxWidth: 800, maxHeight: cappedRegion);
      expect(s, lessThan(800 / 430)); // 寬度比例被封頂
      expect(252 * s, lessThan(cappedRegion)); // 縮放後仍在場景區內
    });
  });

  group('kSceneRegionMaxFraction 護欄在真機永不觸發（零位移保證）', () {
    test('14PM：寬度錨點場景區 < 護欄 → 護欄不生效、基準不動', () {
      expect(
        homeSceneRegionHeight(kBaseWidth),
        lessThan(kBaseShellMaxH * kSceneRegionMaxFraction),
      );
    });

    test('SE（真機最極端的矮胖比例）：護欄仍不生效', () {
      const seWidth = 375.0;
      const seShellMaxH = 519.0;
      expect(
        homeSceneRegionHeight(seWidth),
        lessThan(seShellMaxH * kSceneRegionMaxFraction),
      );
    });

    test('widget test 預設 800×600（寬>高退化面）：護欄要生效，卡片才留在畫面內', () {
      const testSurfaceShellMaxH = 544.0; // 600 − MascotAppBar(56)
      expect(
        homeSceneRegionHeight(800),
        greaterThan(testSurfaceShellMaxH * kSceneRegionMaxFraction),
      );
    });
  });
}
