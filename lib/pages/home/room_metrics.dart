// 房間場景跨機型版面度量（單一真相來源）。
//
// 2026-07：不只首頁——所有兔咪頁（喝水/體重/計時/衣櫃/家庭/小孩首頁）的
// 背景高都改吃 [roomSceneHeight]，場景區高由 MascotPageShell 預設吃
// [homeSceneRegionHeight]，整個 app 同一個寬度參考系。
//
// 背景圖（assets/scenes/home/home_*.webp，1122×1402）用 BoxFit.cover +
// topCenter 鋪滿，寬度是綁定邊 → 場景內所有東西（地板/地毯線）的螢幕 Y
// 只取決於「螢幕寬」，跟螢幕高無關。但舊版背景高度寫 `screenH × 0.56`、
// 兔咪殼寫 `safeAreaH × 5/11`、特效層寫 `screenH × 0.56 × 0.82`——三個都吃
// 「高度」當參考系，只在 iPhone 14 Pro Max 比例剛好跟「寬度參考系」疊合，
// 換到矮胖機型（SE）就地板被裁、兔咪飄空。
//
// 解法：把這三個高度全部改成跟「螢幕寬」等比，常數一律用 14 Pro Max（作者
// 實機，430×932，top inset 59 / bottom inset 34）的舊版數值 ÷ 430 反推，
// 確保「寬度 = 430（且 14PM 的 inset）」時與舊公式逐位元相同 = 對 14PM 零位移，
// 其他機型才一起變對。對應單元測試見 test/room_metrics_test.dart。
//
// 2026-07-15 二次校正（SE 實測仍有兩個殘差）：
// 1. 純寬度錨點的場景區從「SafeArea 頂」起算，但頂部 chrome（狀態列+AppBar）
//    是固定 pt、不隨寬度縮 → SE（狀態列 20）比 14PM（59）少 39pt，卡片線／
//    兔咪腳相對背景高了 ~24pt（站上地毯上緣）。[sceneRegionHeightAnchored]
//    把「卡片線」改成螢幕座標系的寬度錨點，再扣掉當機實際 chrome。
// 2. 兔咪本體 252pt 寫死、不隨寬度縮 → SE 上兔咪佔螢幕寬 67%（14PM 59%），
//    整個場景看起來被放大。[mascotStageScale] 給場景兔咪一個寬度等比縮放。
library;

import 'dart:math' as math;

// —— 14 Pro Max 校準基準（不可更動，動了就破壞作者唯一的正確基準）——
// 都是 iPhone 14 Pro Max（430×932）模擬器實測值（等同作者實機）。
const double kBaseWidth = 430;
const double kBaseHeight = 932;
// MascotPageShell 在 14PM 拿到的 constraints.maxHeight：螢幕高扣掉狀態列、
// MascotAppBar、home indicator 後 Scaffold+SafeArea 真正留給場景的高度。實測 711。
const double kBaseShellMaxH = 711;
// 14PM 的狀態列高（MediaQuery.padding.top，Scaffold「外」的頁面 context 值）。
const double kBaseStatusBarTop = 59;
// 兔咪頁 AppBar 高：MascotAppBar.preferredSize == kToolbarHeight(56)，
// child_home 的透明 AppBar 也是預設 56。改 AppBar 高度時這裡要跟著動。
const double kSceneAppBarHeight = 56;
// 14PM 的頂部 chrome 總高（狀態列+AppBar）＝ SafeArea 內容的實際起始 Y。
const double kBaseChromeTop = kBaseStatusBarTop + kSceneAppBarHeight; // 115

// 舊公式在 14PM 算出的兩個關鍵值：
//   背景高 = 932 × 0.56；兔咪場景區 = shellMaxH × 5/11。
const double _kBaseBgHeight = kBaseHeight * 0.56; // ≈ 521.92
const double _kBaseSceneRegion = kBaseShellMaxH * 5 / 11; // ≈ 323.18

/// 房間背景 4 層（窗景/背景圖/色罩/光影）的高度：跟螢幕寬等比。
/// 背景圖 cover-by-width，地板線只跟螢幕寬走。`screenWidth == 430` 時
/// == 932 × 0.56，與舊版逐位元相同（對 14PM 零位移）。
double roomSceneHeight(double screenWidth) =>
    screenWidth * (_kBaseBgHeight / kBaseWidth);

/// 兔咪場景區（MascotPageShell 的 sceneHeight）：同樣只吃「螢幕寬」等比，
/// 讓卡片頂緣／兔咪腳跟背景地板同一個參考系。**刻意不碰 inset**——舊版
/// 吃 `shellMaxH × 5/11`（含上下安全區）只在 14PM 比例疊合，換機型就飄；
/// 而 `_buildMascotScene` 拿到的 `padding.top` 還是 Scaffold 外的狀態列值，
/// 拿來補償只會更錯（曾因此把 14PM 卡片移了 58px）。改用純寬度錨點：
/// `screenWidth == 430` 時 == 舊的 `711 × 5/11` 的 323.18，零位移；矮胖機型
/// （SE 375）算出更高的場景區、卡片下移露出地板，兔咪才踩得到地毯。
double homeSceneRegionHeight(double screenWidth) =>
    screenWidth * (_kBaseSceneRegion / kBaseWidth);

/// 場景區高（chrome 修正版，2026-07-15 起七個兔咪頁一律用這個）。
///
/// [homeSceneRegionHeight] 的殘差：場景區從 SafeArea 頂起算，但 SafeArea 頂
/// 的螢幕 Y（狀態列+AppBar）是固定 pt、不隨寬度縮，所以「卡片線的螢幕 Y」
/// 在窄機上仍比背景的寬度參考系高一截（SE 差 ~24pt，兔咪站上地毯上緣）。
/// 這裡改成先把「卡片線」定在螢幕座標系的寬度錨點上
/// （14PM：chrome 115 + 場景區 323.18 ≈ 438.18），再扣掉當機的實際 chrome，
/// 卡片線／兔咪腳就在每台機器都落在背景圖同一條線。14PM 時 chrome 相消，
/// 與 [homeSceneRegionHeight] 相等（零位移）。
///
/// [statusBarTop] 傳「頁面 context（Scaffold 外）的 MediaQuery.padding.top」
/// ——那是真狀態列高（14PM 59 / SE 20）。**不要**傳 Scaffold body 內
/// （含 AppBar 的 133/92）或 SafeArea 內（0）的值；AppBar 的 56 由
/// [kSceneAppBarHeight] 補，因為七頁的 AppBar 高度一致且已知。
double sceneRegionHeightAnchored(double screenWidth, double statusBarTop) {
  final chromeTop = statusBarTop + kSceneAppBarHeight;
  return (kBaseChromeTop + _kBaseSceneRegion) * (screenWidth / kBaseWidth) -
      chromeTop;
}

/// 場景兔咪（PersonaScene 內的 MascotStage 252×252）的縮放係數。
///
/// 兔咪本體是固定 252pt，背景卻 cover-by-width 跟著螢幕寬縮 → 窄機上
/// 兔咪相對房間過大（SE 佔螢幕寬 67%，14PM 只有 59%）。取「寬度等比」
/// 讓兔咪跟背景同一個縮放（14PM == 1.0 零位移）；再用「場景區高等比」
/// 封頂，擋 widget test 800×600 這種寬>高的退化面（場景區被
/// [kSceneRegionMaxFraction] 護欄壓扁時兔咪跟著縮，不會爆出區外）。
/// 真機 iPhone 上兩者相等（都是寬度錨點），取 min 不影響。
double mascotStageScale({required double maxWidth, required double maxHeight}) =>
    math.min(maxWidth / kBaseWidth, maxHeight / _kBaseSceneRegion);

/// 特效層（RoomSceneEffectsPainter）內部用的場景高，與 [roomSceneHeight] 同義，
/// 但 painter 拿到的是「全螢幕 size」，所以獨立提供以螢幕寬換算的版本。
double roomEffectsSceneHeight(double screenWidth) =>
    roomSceneHeight(screenWidth);

/// 場景區佔「可用高」的安全上限（MascotPageShell 用）。寬度錨點在「寬>高」
/// 的退化面（widget test 預設 800×600、iPad 分割視窗）會算出比可用高還高的
/// 場景、把功能卡整張推出畫面。真機 iPhone 最極端的 SE（375 寬）也只佔
/// ~0.55，所以 0.60 在所有真機上永遠不觸發（14PM 佔 ~0.45，零位移不變），
/// 純粹是退化面的護欄。
const double kSceneRegionMaxFraction = 0.60;
