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
- 角色與情緒的程式單一真相來源是 `lib/utils/mascot.dart`；資產規格見
  `docs/asset_convention.md`。

## 視覺

- 共用 token 以 `lib/utils/app_style.dart` 為準，細節見 `docs/visual_spec.md`。
- 頁面可以有自己的主題色；核心是避免無意義的冷灰、純黑與散落的重複 token，
  不是把所有頁面強制改成同一個棕色。
- 場景時段方向以 `docs/four_period_background_plan.md` 為準：完整背景承擔環境光影，
  Flutter 只做相鄰背景 crossfade 與已驗證必要的最小角色融合，不重建程式場景光影。
