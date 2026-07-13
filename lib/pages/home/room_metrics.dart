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
library;

// —— 14 Pro Max 校準基準（不可更動，動了就破壞作者唯一的正確基準）——
// 都是 iPhone 14 Pro Max（430×932）模擬器實測值（等同作者實機）。
const double kBaseWidth = 430;
const double kBaseHeight = 932;
// MascotPageShell 在 14PM 拿到的 constraints.maxHeight：螢幕高扣掉狀態列、
// MascotAppBar、home indicator 後 Scaffold+SafeArea 真正留給場景的高度。實測 711。
const double kBaseShellMaxH = 711;

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
