// 四時段完整背景（docs/four_period_background_plan.md 的核心元件）。
//
// 設計：一個房間一天 = 四張「同畫布同構圖」的完整 CG（晨/晝/暮/夜），
// 環境光影（天色、窗光、檯燈、長影）全部由圖本身承擔；Flutter 只做
// 相鄰時段的 crossfade——底圖維持不透明、新時段以自身權重淡入，
// 構圖一致時是無亮度凹陷、無重影的 dissolve。
//
// 效能特性：
// - 無自有 ticker。opacity 走 SceneTimeController 的分鐘級 notify
//   （45 分鐘交接 ≈ 每分鐘 2~3% 的透明度差，肉眼看不到步進）。
// - 樹上永遠只有兩張圖：目前時段＋循環下一時段（opacity 0 保持解碼，
//   進交界的第一幀不會等 decode、不閃圖）。解碼駐留 ≈ 2×6.3MB。
// - 純時段時疊圖 opacity == 0，Opacity 會整層略過 paint，raster 零成本。
//
// 推廣方式：其他有窗房間補齊四張圖後，用自己的 [FourPeriodAssets] 建
// 一個 FourPeriodBackground 即可，不需要再寫任何光影程式。
import 'package:flutter/material.dart';

import '../utils/scene_time.dart';

/// 快速恢復開關：false = 退回單張白天圖（不做時段切換），實驗翻車時用。
const bool kFourPeriodBackgroundEnabled = true;

/// 一個房間的四時段背景圖組。四張必須同畫布、同構圖（見 asset_convention）。
class FourPeriodAssets {
  final String morning;
  final String day;
  final String dusk;
  final String night;

  const FourPeriodAssets({
    required this.morning,
    required this.day,
    required this.dusk,
    required this.night,
  });

  String of(ScenePeriod p) => switch (p) {
    ScenePeriod.morning => morning,
    ScenePeriod.day => day,
    ScenePeriod.dusk => dusk,
    ScenePeriod.night => night,
  };
}

class FourPeriodBackground extends StatelessWidget {
  final FourPeriodAssets assets;

  const FourPeriodBackground({super.key, required this.assets});

  // 與既有場景圖同一套版位：cover-by-width + topCenter（room_metrics 的
  // 寬度參考系），超出高度的部分被 ClipRect 裁掉。
  static Widget _cover(String path) {
    return ClipRect(
      child: Align(
        alignment: Alignment.topCenter,
        child: Image.asset(
          path,
          height: double.infinity,
          width: double.infinity,
          fit: BoxFit.cover,
          alignment: Alignment.topCenter,
          gaplessPlayback: true, // 交接結束換 provider 時不閃透明幀
          excludeFromSemantics: true,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!kFourPeriodBackgroundEnabled) return _cover(assets.day);
    return ListenableBuilder(
      listenable: SceneTimeController.instance,
      builder: (_, _) {
        final blend = SceneTimeController.instance.state.layerBlend;
        // 疊圖：交接中 = 淡入方；純時段 = 循環下一時段以 opacity 0 待命
        //（保持解碼駐留，交接第一分鐘不等 decode）。
        final next =
            blend.overlay ??
            ScenePeriod.values[(blend.base.index + 1) %
                ScenePeriod.values.length];
        return Stack(
          fit: StackFit.expand,
          children: [
            _cover(assets.of(blend.base)),
            Opacity(
              opacity: blend.overlayOpacity.clamp(0.0, 1.0),
              child: _cover(assets.of(next)),
            ),
          ],
        );
      },
    );
  }
}
