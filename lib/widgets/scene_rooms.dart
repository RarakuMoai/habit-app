// 有窗房間註冊表：每個房間的四時段圖組＋光源幾何＋空氣層幾何，
// 單一真相來源（docs/engineering_guardrails.md §視覺 的推廣形態）。
//
// 新增房間的流程：
//   1. 依 asset_convention 補四張同畫布同構圖的時段圖（WebP q95）。
//   2. 看圖決定光源幾何：窗在哪（清晨影子往反方向）、有沒有檯燈
//      （黃昏/夜晚影子往燈的反方向、燈近影實）。
//   3. 量清晨光束起點與夜圖星點座標（圖比例），填 SceneAirSpec。
//   4. 頁面掛 [FourPeriodRoomScene]＋PersonaScene 傳 lightGeometry。
// 不需要再寫任何光影程式；兔咪造型也零調整（融合乘在任何立繪上）。
import 'package:flutter/material.dart';

import 'four_period_background.dart';
import 'mascot_page_shell.dart' show AutoPausingTickerMode;
import 'mascot_scene.dart' show RoomLightGeometry;
import 'scene_air_layer.dart';

/// 一個有窗房間的完整場景設定。
@immutable
class FourPeriodRoom {
  final FourPeriodAssets assets;
  final RoomLightGeometry light;
  final SceneAirSpec air;

  const FourPeriodRoom({
    required this.assets,
    required this.light,
    required this.air,
  });

  /// 首頁（習慣頁）：窗在左、床頭檯燈在右（暮/夜影子偏左、夜裡燈近影最實）。
  static const home = FourPeriodRoom(
    assets: FourPeriodAssets(
      morning: 'assets/scenes/home/home_morning.webp',
      day: 'assets/scenes/home/home_day.webp',
      dusk: 'assets/scenes/home/home_dusk.webp',
      night: 'assets/scenes/home/home_night.webp',
    ),
    light: RoomLightGeometry(
      morningDx: 7,
      dayDx: 0,
      duskDx: -6,
      nightDx: -9,
      duskOpacity: 0.25,
      nightOpacity: 0.28,
    ),
    air: SceneAirSpec(
      beamStart: Offset(0.13, 0.18),
      stars: [
        // (x, y, phase)：home_night 亮點聚類實測座標
        (0.1356, 0.0733, 0.0),
        (0.1680, 0.1163, 1.3),
        (0.0232, 0.1188, 2.4),
        (0.1573, 0.1644, 3.6),
        (0.0615, 0.0777, 4.4),
        (0.1310, 0.2489, 5.2),
      ],
    ),
  );

  /// 喝水頁：窗在左、無檯燈——整天光都從左窗來（黃昏晚霞、夜晚月光），
  /// 影子全天偏右、夜晚最柔。
  static const water = FourPeriodRoom(
    assets: FourPeriodAssets(
      morning: 'assets/scenes/water/water_morning.webp',
      day: 'assets/scenes/water/water_day.webp',
      dusk: 'assets/scenes/water/water_dusk.webp',
      night: 'assets/scenes/water/water_night.webp',
    ),
    light: RoomLightGeometry(
      morningDx: 7,
      dayDx: 0,
      duskDx: 5,
      nightDx: 3,
      nightOpacity: 0.23,
    ),
    air: SceneAirSpec(
      beamStart: Offset(0.14, 0.16),
      stars: [
        (0.148, 0.031, 0.4),
        (0.193, 0.073, 1.7),
        (0.207, 0.096, 2.9),
        (0.111, 0.104, 3.8),
        (0.198, 0.145, 4.6),
        (0.085, 0.170, 5.5),
      ],
    ),
  );

  /// 計時頁：窗在左、書桌檯燈也在左（夜晚燈亮）——影子全天偏右，
  /// 夜裡檯燈近、影子比無燈房間實一點。
  static const timer = FourPeriodRoom(
    assets: FourPeriodAssets(
      morning: 'assets/scenes/timer/timer_morning.webp',
      day: 'assets/scenes/timer/timer_day.webp',
      dusk: 'assets/scenes/timer/timer_dusk.webp',
      night: 'assets/scenes/timer/timer_night.webp',
    ),
    light: RoomLightGeometry(
      morningDx: 7,
      dayDx: 0,
      duskDx: 5,
      nightDx: 6,
      nightOpacity: 0.26,
    ),
    air: SceneAirSpec(
      beamStart: Offset(0.15, 0.15),
      stars: [
        (0.132, 0.109, 0.8),
        (0.143, 0.111, 2.1),
        (0.159, 0.102, 3.3),
        (0.129, 0.150, 4.2),
        (0.106, 0.068, 5.6),
      ],
    ),
  );

  /// 家庭頁（含孩童首頁）：小窗在左上、無檯燈，夜晚整室暖光很均勻——
  /// 影子偏移最小、夜晚最淡。
  static const family = FourPeriodRoom(
    assets: FourPeriodAssets(
      morning: 'assets/scenes/family/family_morning.webp',
      day: 'assets/scenes/family/family_day.webp',
      dusk: 'assets/scenes/family/family_dusk.webp',
      night: 'assets/scenes/family/family_night.webp',
    ),
    light: RoomLightGeometry(
      morningDx: 6,
      dayDx: 0,
      duskDx: 4,
      nightDx: 2,
      nightOpacity: 0.22,
    ),
    air: SceneAirSpec(
      beamStart: Offset(0.10, 0.12),
      stars: [
        (0.109, 0.050, 0.6),
        (0.127, 0.062, 1.9),
        (0.111, 0.080, 3.1),
        (0.103, 0.098, 4.5),
        (0.116, 0.098, 5.4),
      ],
    ),
  );
}

/// 房間場景（背景 + 空氣層）一件式元件：給首頁以外的兔咪頁用，
/// 放進原本擺 MascotSceneBackground 的 Positioned 即可。
/// 內建閒置自動凍結（AutoPausingTickerMode，與其他場景層同一套規則）；
/// 首頁因為要與完成星光共享 20fps 時鐘，維持自己組層。
class FourPeriodRoomScene extends StatelessWidget {
  final FourPeriodRoom room;

  const FourPeriodRoomScene({super.key, required this.room});

  @override
  Widget build(BuildContext context) {
    return AutoPausingTickerMode(
      child: Stack(
        fit: StackFit.expand,
        children: [
          FourPeriodBackground(assets: room.assets),
          SceneAirLayer(spec: room.air),
        ],
      ),
    );
  }
}
