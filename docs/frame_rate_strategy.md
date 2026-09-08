# 上架幀率策略評估

2026-09-08。回應使用者對 30／60／120 FPS、自動選擇與可調整設定的討論。
這是建議與程式盤點，尚未增加幀率選單、修改平台偏好或取得實機效能／耗電結果。

## 建議

**第一版預設自動同步平台，60 FPS 是主要互動品質目標，高更新率裝置在條件允許時使用更高幀率。**
不把整個 App 固定為 30 FPS，也不把持續 120 FPS 當作陪伴 App 的必要條件。
這裡的 60 是驗證目標，不是自動模式的上限，更不是每台裝置的保證。

| 層級 | 建議 | 原因 |
| --- | --- | --- |
| 捲動、拖曳、按鈕與對話面板 | 跟隨 Flutter／平台的 VSync；優先確保 60 FPS 品質，另驗證高更新率裝置 | 直接操作對不穩定幀距敏感 |
| 兔咪分層／網格動作 | 時間驅動，按可用畫面更新時機取樣 | 同一條動作不因 30／60／120 改變速度，不需三套素材 |
| 兔咪逐格素材／預渲染短片 | 先以 30 張／秒打樣；若需要特定逐格節奏，再比較其他取樣率 | 圖稿數和 App 畫面更新率是兩件事；不能宣稱把 30 張重複播放就多出 120 個姿勢 |
| 環境粒子 | 依實際可見需求單獨降低更新頻率 | 不為慢速背景動態要求全場景最高更新率 |
| 閒置、離頁、背景 | 停止不必要的動畫排程，保留必要的資料／時間更新 | 效益需實機量測；停止場景動畫不等於面板變成 0 Hz |

30 FPS 每幀約 33.33 ms，60 FPS 約 16.67 ms，120 FPS 約 8.33 ms。
素材以較低影格率呈現可以是美術選擇；主介面同時仍可平滑捲動。
即時網格只儲存圖片、幾何與動作時間軸，增加取樣次數主要增加執行負載，不需要增加同等數量的圖片。

## 使用者能否自行調整

可以做偏好設定，但平台決定最後能提供什麼，不應提供假的「保證 120 FPS」開關。
第一版建議先保留自動；若實機比較發現流暢與續航差異值得提供選擇，再加入：

- **自動（預設）**：遵循平台可用更新率與使用者的系統限制。
- **省電**：減少環境效果與持續待機動態，視平台能力提出較低更新率偏好；仍保持操作回饋。
- **高流暢度（有測量依據再提供）**：支援裝置偏好較高更新率，發熱、低耗電與系統政策仍可限制。

暫不提供任意數字滑桿。固定 30／60／120 偏好需要各平台整合與實測，不能只靠 Dart 計時器或
`AnimationController.duration` 達成。降低動態效果是輔助使用需求，與省電／幀率選擇分開；
使用者要求降低動態時，即使高流暢模式也不能重新打開位移動畫。

## 專案現況

本機 Flutter 3.41.9，engine revision `42d3d75a56efe1a2e9902f52dc8006099c45d937`。

- [iOS Info.plist](../ios/Runner/Info.plist)：`CADisableMinimumFrameDurationOnPhone = true` 已存在，允許請求高於系統預設的幀率；不代表正式 App 已穩定輸出 120 FPS。
- [兔咪動畫](../lib/widgets/mascot_scene.dart)：主要使用有 VSync 的 `AnimationController`，沒有自訂全 App 30 FPS 上限。
- [場景時鐘](../lib/widgets/scene_clock.dart)：共享時鐘限制通知約 20 FPS，自有時鐘約 30 FPS。這是通知／重畫節流，Ticker 本身仍在執行，不能從常數直接推論 Flutter 排幀或面板更新率已降低。
- [首頁](../lib/pages/home_page.dart)與[場景共用容器](../lib/widgets/mascot_page_shell.dart)：已有約 20 秒閒置停動及 TickerMode 機制。是否涵蓋所有可見動態，仍需按場景確認。
- [既有測量工具](../lib/utils/scene_frame_probe.dart)：目前固定以 raster > 16.7 ms 統計超時，尚不能完整判斷 120 FPS；UI 超時、實際幀距也需一起看。10 秒內回報的 frame 數是 Flutter 回報樣本數，不是實測面板 Hz；沒有樣本也不能單靠此證明顯示器或所有 App 工作停止。
- 本輪搜尋 `lib`、iOS Runner、Android app 與 pubspec，未找到 App 自訂全域更新率偏好設定。

另讀取本機 Flutter engine 的 `vsync_waiter_ios.mm`：啟用上述 Info key 時，
`setMaxRefreshRate` 會對 display link 設定範圍及偏好最大值，最低偏好以至少 60 為基準。
因此未來若要做「限制 30／60」，需要確認 Flutter 引擎與平台如何協作；另建一個原生 display link
不等於改到 Flutter 實際使用的時鐘。本輪沒有修改 Flutter SDK。

## 上架前如何定案

由使用者本人在實體裝置操作 profile／release，AI 不安裝或啟動實體 iPhone／iPad。
模擬器可判斷畫面與銜接，不能代替這份效能／耗電驗證。

1. 同一版本、同一場景、相同亮度與操作，比較一台 60 Hz 裝置、一台高更新率裝置及最低支援等級的代表機型。
2. 測量首頁待機、列表捲動、AVG 對話、兔咪動作與換裝、完成演出，以及離頁／背景；分開記錄正常與低耗電設定。
3. 記錄 UI／raster 中位數、P95、尾端慢幀與實際幀距。按當時目標幀預算判斷，不只看平均 FPS；8.33 ms 的高更新率預算不能沿用 16.7 ms 判定。
4. 以相同負載進行足夠時間的耗電／溫度比較，記錄系統降頻與熱狀態；多次比較，不挑最快的一次。
5. 若高更新率頻繁掉幀，先定位瓶頸再優化或降負載；只有持續穩定並有合理耗電表現，才把高流暢模式列為可選功能。

## 官方依據

- [Flutter：效能測量](https://docs.flutter.dev/perf/ui-performance)：60／120 FPS 目標及實機 profile 驗證要求。
- [Flutter：AnimationController](https://api.flutter.dev/flutter/animation/AnimationController-class.html)：每次裝置準備顯示新畫面時推進值；取樣率與動畫時長不同。
- [Apple：Info key](https://developer.apple.com/documentation/bundleresources/information-property-list/cadisableminimumframedurationonphone)：開啟高於系統預設的幀率請求能力。
- [Apple：preferredFrameRateRange](https://developer.apple.com/documentation/quartzcore/cadisplaylink/preferredframeraterange)：偏好範圍是盡力提供，硬體、低耗電、熱狀態與使用者設定會影響結果。
- [Android：Frame rate API](https://developer.android.com/media/optimize/performance/frame-rate)：內容可提出幀率偏好，系統綜合其他因素選擇顯示更新率。這不表示原生 View 的設定可以直接當作 Flutter 全域 FPS 開關。

以上描述平台能力；兔咪的具體產品策略是本輪建議，尚未經實機比較定案。
