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
