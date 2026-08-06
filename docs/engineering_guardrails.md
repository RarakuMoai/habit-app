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
- ⚠️ **待機生命感目前卡在兩張缺圖**（2026-08-04 查證，兩件都已釘進程式註解）：
  1. 待機姿承載進度是**架構承重**的——演出收尾把狀態清回 baseline，baseline
     一旦與進度無關，全完成的 `happy` 就留不住（`home_completion_test` 有 26 項在守）。
  2. 泛用睜眼立繪只有 `neutral_front` 有閉眼差分。要同時做到「待機一定會眨眼」
     與「待機姿承載進度」，需要 `tumi_expect_blink.png`，以及一張睜眼版的
     「安心」立繪取代過半的 `smile`。

  在那兩張圖到位之前沒有站得住的做法。**使用者要的模型是「一個會眨眼的預設
  ＋少數特殊情境（睡覺＋Zzz）＋有動作就醒來」**，不是依進度推導待機姿。

## 視覺

- 共用 token 以 `lib/utils/app_style.dart` 為準，細節見 `docs/visual_spec.md`。
- 頁面可以有自己的主題色；核心是避免無意義的冷灰、純黑與散落的重複 token，
  不是把所有頁面強制改成同一個棕色。
- 場景時段方向見 `docs/visual_spec.md` §動效：**完整 CG 背景已經承擔環境光影**，
  Flutter 只做相鄰背景 crossfade 與必要的最小角色融合（`mascotLightingForScene`
  的時段白平衡、`RoomLightGeometry` 的逐房間接地影），**不要再用程式疊第二層
  光束、燈暈或長影**。這是避免重複打光，不是禁止視覺效果。
- 場景效能量測用 `lib/utils/scene_frame_probe.dart`
  （`--dart-define=SCENE_PERF=1`，release 零成本 no-op）。判斷一律以
  profile／release 實機數據為準，debug 數據只能做相對比較。

## 導覽與回饋

- **不要用裸 `PageRouteBuilder` 推頁。** 它不走 theme 的 `pageTransitionsTheme`，
  會默默拿掉 iOS 邊緣滑回手勢與舊頁視差。要做品牌轉場必須從 `CupertinoPageRoute`
  或 `PageTransitionsTheme` 走。`test/page_transition_test.dart` 用正反對照釘住。
  全螢幕揭曉演出（`story_reveal`、`login_streak`）不受此限。
- **回饋的「最近剛發過」窗口只給 `PopupFeedbackObserver` 用，不是全域節流。**
  打卡連打時每一次完成都必須各自發音效與觸覺，全域節流會吃掉第二次。
- 回饋語言：高頻導覽只給觸覺（出聲會變噪音）、面板出現給一次最輕的觸覺、
  取消走統一的 `cancel` 語彙、確認刻意不發（讓真正發生的那件事自己出聲）。
- ⬜ 未做：BGM 為 SFX ducking。動 `bgm_service` 要用 `flutter run --profile`
  實機驗證，留給有實機條件時再做。

## i18n：刻意不遷的字串（動它們會壞掉）

ARB 遷移已完成（1194 key，功能 UI 全部遷完）。`lib/` 裡**還剩的中文字串全部是
下面這幾類，不是漏掉的**。改之前先看這一節。

### 1. 儲存值與識別鍵——翻譯會直接壞掉功能

| 位置 | 是什麼 | 為什麼不能翻 |
|---|---|---|
| `home/home_presets.dart` 的 `kHomePresets` name | 首頁常用習慣名 | 選取後直接存成習慣名；去重（`existing.contains(p.name)`）與喝水／體重連動判定都比對它 |
| `onboarding_page.dart` 的 `_kOnboardingHabits` name | 前導頁習慣清單 | 同上，選了會存成習慣名 |
| `family/family_presets.dart` 的三組 `k*Presets` name | 育兒常用習慣／扣分／獎勵 | `existingNames.contains` 去重、`_deductionPresetPoints(name)` 用名字查分數。翻譯後換語言，已加過的項目會重新出現 → 重複 |
| `family/family_store.dart` 的預設習慣 | 新增小孩時自動建的三個習慣 | 建立時就存進資料，名稱要跟 `kHabitPresets` 對得上才不會重複 |
| `home_page.dart` 的 `_kWaterHabitPresetName` | `'喝足夠的水'` | 喝水連動的識別鍵 |
| `utils/water_habit_link.dart`、`utils/weight_records.dart` | 習慣名常數與別名 | 跨頁比對用 |
| `home/habit_sheets.dart` 的 `'體重紀錄'` 比對 | 決定連動色 | 識別鍵 |
| `home/habit_sheets.dart` 的 `RegExp(...分鐘$)` | 解析已存的習慣名稱 | 時長被編進名稱裡存起來（`habitNameMinutes`），改 l10n 會讓舊名稱解析失敗 |
| `profile_edit_page`／`onboarding_page`／`water_page`／`weight_page` 的性別與活動量 | `'男'`／`'久坐'` 等 | 儲存值；算每日水量與 TDEE 都比對它們。**只換顯示標籤**（`genderMale`、`activityAlmostNone`） |
| `timer/game/table_timer_models.dart` 的 `_legacyZh*` | 舊版自動命名的比對字串 | 判斷「這名字是不是使用者改過的」，必須維持當年輸出 |
| `utils/wardrobe_catalog.dart` 的 `tags` | `'慢'`／`'快'` 等 | 穩定識別字串，顯示走 `bgmTagLabel` 翻譯 |

**要遷這些的話**：得先給 Preset 一個穩定 `id`、把比對改成比 id，再對既有存檔做
一次資料遷移。那是獨立工程，**不要順手改**。

### 2. 兔咪台詞與繪本旁白——等文本定稿

`utils/mascot.dart` 的 `_lines`／`_homeTapLines`、`utils/story_catalog.dart` 的
`captions`、`home_page.dart` 的 `buildGreetingMessage`、`login_streak_page.dart`
的 `_caption`、`onboarding_page.dart` 的 `_speechBubble()` 與各 feature 頁 `bubble`、
`wardrobe_page.dart` 的穿上／購買 `speech`。

### 3. 其他不算 UI 字串的

`widgets/mascot_bubbles.dart` 的 `assert` 訊息、`dev/tumi/tumi_preview_main.dart`
（獨立 dev entry，沒掛 localizations delegate）、註解與正則字元類別
（`utils/lenient_date.dart` 的 `[-/.年]`）。

### 測試注意

頁面用了 `AppLocalizations` 之後，widget 測試要改用 `test/l10n_test_app.dart` 的
`l10nTestApp(home: ...)`，裸 `MaterialApp` 會 crash。
