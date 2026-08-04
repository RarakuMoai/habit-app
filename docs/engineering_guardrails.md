# 工程護欄

> 只在修改對應領域時讀該小節。這裡放容易造成資料錯誤或實機故障的穩定規則，
> 不放短期產品規劃與一次性實作方案。

## 單位系統

- 儲存與運算一律使用公制（cm / kg / ml）。
- 顯示使用 `lib/utils/units.dart` 的 `UnitFormat`；輸入先用 `UnitConvert` 或
  `UnitParse` 轉成公制，再驗證與儲存。
- 會顯示或輸入單位的畫面需載入 `UnitSystem`。常駐畫面若要在設定切換後立即更新，
  才監聽 `UnitSystem.notifier`；一般 push 頁面重新開啟時載入即可。
- Dart UI 字串不要硬寫單位。必要常數或說明文字以 `// units-ok` 明確豁免。
- 修改相關程式後跑 `bash scripts/check_units.sh`。

## SharedPreferences

- 持久化 key 集中在 `lib/utils/prefs_keys.dart` 的 `PrefsKeys`，呼叫端不硬寫 key。
- 日期型 key 使用既有 helper / prefix；新增 key 時放進對應區塊。
- 習慣、喝水、體重等每日資料使用 `LogicalDate` 的邏輯日，不自行以日曆日組 key。

## 邏輯日

- 邏輯日生命週期的唯一擁有者是 `lib/utils/logical_day_coordinator.dart`：冷啟動、
  resume、前景邊界計時器、換日設定變更都由它偵測，跨日結算也只有它做。
- 新頁面不得自己加換日計時器或 lifecycle observer，也不要另外監聽
  `LogicalDate.notifier`；改成收 `MainPage` 傳下來的 revision。兩條路並存會讓
  同一次變更載入兩次。
- `MainPage` 收到新的 stamp 後，必須**先**重算依賴「今天」的自動完成旗標
  （喝水達標、體重已記錄），才能把 revision 傳給首頁。順序反過來，昨天的旗標
  會把新一天的連動習慣直接標成已完成並寫進 storage。
- `PrefsKeys.logicalDayJournal` 是冪等的 commit marker，不是跨多個
  SharedPreferences key 的 transaction。它擋住連勝這種累加運算；其餘步驟都要寫成
  可重跑的冪等覆寫。

## 音訊

`lib/utils/bgm_service.dart` 的救援流程是 release 實機問題的必要處理，不可為了簡化而移除：

- 不要 `await _player.play()`；使用 `unawaited(_player.play())`，再分開驗證狀態。
- AOT 冷啟動需要 `_engageCheck` 的 pause → play 重試，確認 `playing == true` 後才淡入。
- `AppAudioSession` 只 configure 一次，之後只 `setActive(true)`。
- 原地替換任何音訊 asset（路徑／檔名不變）時，必須遞增
  `AudioAssetCache.currentVersion`；`just_audio` 會依路徑保留裝置端抽出快取，版本號
  讓新版第一次冷啟動只清一次音訊快取，不影響習慣與其他使用者資料。
- 音訊問題使用 `flutter run --profile` 驗證；debug 時序不足以代表 release。

## 兔咪素材與演出

- 現行方向是高品質 CG/PNG 差分 + Flutter 輕量演出，不以 Rive / 骨架動畫為前提。
- Flutter 可做呼吸、位移、縮放、彈跳、淡入淡出、星光與情緒泡泡；不要在臉上硬畫
  假眨眼、嘴型或眼皮。兔咪幾乎沒有嘴巴，不做說話口型。
- 已有核准底圖時只做局部 edit：鎖定身份、臉型、耳朵、比例、輪廓、CG 質感、
  光照、色盤、構圖、畫布與透明背景。提示詞需明確寫「Do not redraw the whole
  image. Local edit only. 不重繪，只局部修改。」
- 完全新姿勢或新構圖才走 generate，並先說明一致性會下降。
- Reduce Motion 是正式體驗，不是把動畫關掉。位移、縮放、跳躍與會移動的粒子要
  省略，但**事實與語意必須留著**：勾勾照樣畫出來（只縮短，不能只剩換顏色）、
  進度與件數照更新、表情照換、泡泡與台詞照出、SFX 與 haptic 照觸發，先後順序
  也照原本的。縮短後的時間一律從 `lib/pages/home/completion_timing.dart` 的同一組
  常數推導，不要在各處另外寫縮短數字。
- 角色與情緒的程式單一真相來源是 `lib/utils/mascot.dart`；資產規格見
  `docs/asset_convention.md`。

## 視覺

- 共用 token 以 `lib/utils/app_style.dart` 為準，細節見 `docs/visual_spec.md`。
- 頁面可以有自己的主題色；核心是避免無意義的冷灰、純黑與散落的重複 token，
  不是把所有頁面強制改成同一個棕色。
- 場景時段方向以 `docs/four_period_background_plan.md` 為準：完整背景承擔環境光影，
  Flutter 只做相鄰背景 crossfade 與已驗證必要的最小角色融合，不重建程式場景光影。
