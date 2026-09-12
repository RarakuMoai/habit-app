# 最新測試版入口整合

## 本輪基準與範圍

本輪從 `codex/experience-redesign` 的 `a579d106bd7c6b27350fb7b409f0c20ee8e43f2c`
建立整合分支，接續測試版 **1.0.1（2026091105）**。該版入口、六功能主頁、
衣櫃、音訊與可恢復備份的交付依據見 [既有測試版紀錄](entry_and_backup_v1.md)。
版本號、分支與檔案紀錄不能代替本輪原生驗證；實際執行結果另列於本文件交付表。

整合工作區為 `codex/entry-integration`／`/private/tmp/tumi-entry-integration`；
本輪候選版本號為 `1.0.1+2026091201`，整合、模擬器驗證與 signed release build 已完成；
尚未正式發布或安裝實體裝置。
基準的 `2026091105` 是既有 release 產物的 build number；不把較舊 pubspec 預設值
或這次較新的檔案修改時間當成測試版來源。

保留原 Flutter App root、`buildAppTheme()`、正式 `/home` 的 `MainPage`、
`HomePage` 場景與六分頁。僅整合入口及必要的狀態、路由與共用呈現；測試狀態隔離，
正式帳號、旅程、生日與發布流程受保護。本輪沒有合併整條 redesign 到 main，
也沒有以舊 `origin/main` 或 `codex/entry-cover-preview` 作為產品基準。

## 上一輪割裂的實際來源

| 層次 | 上一輪獨立樣品 | 本輪整合方向 |
|---|---|---|
| App root 與樣式 | 另建 `EntryPreviewApp`、MaterialApp、ThemeData.fromSeed | 留在既有 App root，使用原 theme、tokens、共用元件 |
| 路由與房間 | 同一個 preview Scaffold 以 AnimatedSwitcher 切換自製畫面，沒有進 MainPage | 入口接回真實 `/home`、MainPage 與 HomePage |
| 角色與場景 | 固定 `home_day.webp` 加 neutral PNG；大小由局部 artHeight 計算 | 封面使用核准 key art；進入後由真實場景接手四時段、衣櫃、Persona 與地板座標 |
| Safe area 與功能容器 | 自製上下分割、工具列與捲動區 | 保留正式 HomePage 的 SafeArea、MascotPageShell、場景高度與功能卡 |
| 實際操作 | 「整理一個小角落」只切換記憶體 bool；分頁只開說明對話框 | 驗收必須操作至少一個既有功能，不能停在外觀相似的假房間 |
| 帳號、旅程與偏好 | own model 加全域 mock preferences，未承接真正 stores | 正常入口使用既有資料與偏好，模擬只透過明確的測試界面注入 |

上一輪真正重用的是既有圖片位元組、部分 tokens、l10n delegates、tab catalog、
BgmService 與 SfxService；主要畫面與狀態仍另行製作，因此即使相近配色也會像另一個產品。

封面 key art 是固定晨光的門口客廳視角；真正 HomePage 則使用四時段房間與當前衣櫃。
兩者有共同美術元素，但不是同一個鏡頭。轉場應清楚而短暫地交接場景，不用假縮放或
另疊兔咪假裝鏡頭連續，也不強制把正式主場景改成白天。

## 沿用的封面素材

- 正式接入副本：[entry_living_room_v3.png](../assets/scenes/onboarding/entry_living_room_v3.png)。
- 來源：`habit-app-redesign/design_trials/experience_redesign/cover_v3/raw/key_art_living_room_v3_smaller_door_stone_entry.png`。
- 941×1672 PNG，SHA-256 `ef87ee3b7db817a3b6d23135fde9dafba14b3be3d9a22312e1e15b4e2039d26c`。
- 來源與副本逐位元相同，沒有重新生成、重繪、改臉、變更身形或移除兔咪。
- 核准依據：2026-09-12「重新設計測試版封面」task `01a09342-1520-7f81-a127-c036fce288dc`，
  展示上述 V3 後使用者回覆「可以以這張」，並要求考慮 UI 遮擋；後續指示「執行，以美觀為第一重點」。
  採用的是這張 key art，後續 HTML 模擬稿與臨時 Logo 不視為已核准的產品設計。
- 客廳美術曾以既有 `home_morning.webp`、`wardrobe_bg.webp` 作參考；V3 延續較大兔咪，
  修正整扇門比例，將室外厚地墊改為石板門廊。

共用 [EntryScenery](../lib/widgets/entry_scenery.dart) 使用 `kEntryCoverAsset`、
全幅 `BoxFit.cover` 顯示此原圖。預設無遮罩，呼叫端可選上下閱讀遮罩；widget 不持有
旅程、音訊、路由、動畫或假眨眼。覆蓋 UI 與轉場由真正入口處理。

舊入口的 [entry_home_v1.png](../assets/scenes/onboarding/entry_home_v1.png) 是小屋外觀、
沒有兔咪，仍保留在原位置；它與本輪採用的 V3 是不同素材，不以它替換使用者選定的封面。

原生銜接副本 [launch_bridge.png](../assets/scenes/onboarding/launch_bridge.png) 與既有
`ios/Runner/Assets.xcassets/LaunchImage.imageset/LaunchImage@3x.png` 逐位元相同。
`kEntryLaunchAsset` 供第一個 Flutter 畫面使用，配合滿版 `BoxFit.cover` 對齊原生
`LaunchScreen.storyboard` 的 `scaleAspectFill`；沒有變更原生啟動畫面或 bundle ID。

## 本輪交付與驗證

狀態：**本輪整合候選完成，最終程式檢查、原生情境、普通 main 更新與簽章檢查已完成**。
媒體索引可供檢視；本輪保存於 `codex/entry-integration`，原基準分支保留，不合併主線。
以下區分自動測試、手動操作、模擬資料與本人尚未驗收的視覺手感。

### 修改檔案與目的

| 檔案 | 本輪目的 |
|---|---|
| `lib/main.dart` | 原生首幀 raster 銜接、啟動圖片／資料錯誤、local journey 判讀、原 root 語言偏好；真正 MainPage 與當前時段／造型素材就緒後才移除入口覆蓋層 |
| `lib/pages/app_entry_page.dart` | 真正冷啟動封面、明確 Apple／Google／訪客選擇、回訪繼續、雲端未知／有資料／確認無資料分流、帳號與資料入口、保存失敗重試 |
| `lib/pages/onboarding_page.dart` | 同一頁新增 `compactEntry`，普通新旅程只用原 `hello`／`together`；六幕回憶閱讀與 OnboardingSetup 保存保留 |
| `lib/widgets/entry_scenery.dart`、`entry_meeting.dart`、`entry_controls.dart` | 原圖共用呈現、短對話、沿既有按壓回饋與有限淡化轉場；不另外製作房間或功能頁 |
| `assets/scenes/onboarding/entry_living_room_v3.png`、`launch_bridge.png` | 分別為使用者選定 V3、原生 launch 的逐位元副本 |
| `lib/utils/local_journey.dart` | 唯讀辨識現有旅程；已有記錄但舊完成標記缺漏時接續，有無法判讀資料時進入資料確認，身份與 guest 選擇本身不當旅程證明 |
| `lib/utils/account_service.dart` | 登入後仍需成功讀取才確認雲端是否有資料；初始化失敗可重試，保留真實身份狀態 |
| `lib/utils/app_locale_settings.dart`、`prefs_keys.dart`、`lib/widgets/app_language_sheet.dart`、`lib/pages/settings_page.dart` | 封面與設定共用持久化語言偏好，使用真正 App root 接手；自動／手動只列已完成的繁中 |
| `lib/l10n/app_zh.arb`、`app_en.arb` | 入口、恢復與語言可用狀態的文案；英文文案存在不等於全 APP 英文已完成 |
| `pubspec.yaml` | 本輪測試候選 build number；bundle ID、原生 provider 設定未變更 |
| `test/entry_integration_test.dart`、`entry_arrival_gate_test.dart`、`entry_meeting_test.dart`、`app_entry_flow_test.dart`、`local_journey_test.dart`、`account_service_test.dart`、`app_locale_settings_test.dart` | 入口路由意圖與資料邊界、真正 MainPage 就緒／resume 閘門、旅程／身份分離、重試、偏好及版面／Reduce Motion 檢查；結果見下表 |
| `integration_test/entry_integration_review_test.dart`、`scripts/review/run_entry_integration.py` | 真實 app.main 的自動操作；僅在測試內隔離偏好、身份與通知，host 記錄原生畫面、影片及實際 source hashes |
| `scripts/review/build_entry_integration_gallery.py` | 封存本輪 PNG／MP4／log／JSON／SHA-256 證據，產生本機比較頁；缺證據不補舊圖、不推測通過 |
| `scripts/review/extract_entry_video_frames.swift`、`validate_entry_recordings.py` | 用 AVFoundation 解碼本輪錄影抽樣幀、記錄時長與檔案雜湊並產生核對圖；不代替完整播放、音訊或 FPS 測量 |
| `docs/tumi_dialogue_catalog.md`、本文件、`docs/delivery_plan.md` | 登記短初見沿用文本與本輪交付／驗證狀態 |

### 操作與狀態

| 狀態 | 真正入口的操作與接手 |
|---|---|
| 首次使用，尚無旅程 | 封面「開始一起生活」→ Apple／Google／明確訪客選擇 → 只有新旅程進短初見 → 真 MainPage |
| 回訪已登入／訪客 | 封面「繼續一起生活」→ 原旅程與真 MainPage；不寫新 guest marker，不重播初見 |
| 有憑證、無本機旅程 | 顯示恢復情境；讀取未確認時可重試，只有成功查詢後才能區分有資料／無資料 |
| 登入取消／失敗 | 停留在選擇流程，不建立旅程；可重試或明確選訪客 |
| 初始化／房間準備失敗 | 保留可操作的錯誤與重試，沒有最低等待時間或假下載進度 |
| 略過初見 | 經原 OnboardingSetup 保存完成，再交接真 MainPage；生日不列入口欄位 |
| 背景回前景 | 實際切到 iOS 設定再返回，MainPage 保留、計時仍執行；不重新走封面或初見 |
| 語言 | 封面地球圖示與設定共用自動／繁中；英文、日文尚未全 APP 完成，不列可點選的正式功能 |
| 聲音／動態 | 仍走原 AudioControlButton、EntryAudio、音訊與動態偏好；錄影 fixture 以隔離偏好靜音，不能當聆聽驗證 |

重跑自動情境時，在本工作區使用已開機的專用 Large 模擬器 UUID，並指定尚不存在的輸出目錄：

```sh
python3 scripts/review/run_entry_integration.py \
  --device A1321A98-4FE6-4DD6-82E8-E5920F9F275F \
  --output /private/tmp/entry-review-first-new \
  --scenario first
```

| 要操作的情境 | `--scenario`／附加參數 |
|---|---|
| 首次訪客、回訪訪客、回訪已登入 | `first`、`returningGuest`、`returningSignedIn` |
| Apple 新旅程、Google 恢復 | `appleNew`、`googleRestore` |
| 取消／登入失敗、有憑證但離線、初始化失敗 | `authErrors`、`credentialsOffline`、`initFailure` |
| 真 OS 背景返回 | `background` |
| 略過初見／大字／Reduce Motion | `first --skip-meeting --large-text --reduce-motion` |

這會操作真正 `app.main`／路由，但資料與 provider 是 integration fixtures。Flutter test
會管理並可能清理測試安裝；**只在專用 Large 執行，不能對保留普通 main 旅程的 Small 執行**。
大字／Reduce Motion 參數是 Flutter 測試注入，真正 OS 設定證據另看手動影片。

### 真實、模擬與未驗證的界線

- **真實程式流程**：原 `RootRestart → MyApp`、入口、同一 OnboardingPage、保存服務、
  `/home`、MainPage、HomePage、原六分頁與計時器；不是另一個 MaterialApp 或假房間。
- **自動情境的隔離**：`SharedPreferences.setMockInitialValues` 僅存在測試 harness，正常
  main 不導入它。自動影片中的帳號、OAuth 成功／取消／失敗、雲端備份與網路失敗使用測試
  backend，畫面明示模擬；通知投遞被 stub。這些不操作正式資料、OAuth 或雲端寫入。
- **普通 main 的手動證據**：`normal-*` 使用專用模擬器、真正原生 preferences、正常
  `lib/main.dart`，沒有 mock。首次明確訪客選擇後保存旅程，冷重啟仍可繼續；首次計時實際
  出現通知權限提示並選「不允許」，計時仍正常。這不是通知投遞、音訊或真實登入驗收。
- **恢復演練**：如果情境使用合成雲端資料，仍可操作真正備份頁與本機還原程式，但其資料來源
  與身份是模擬，不宣稱登入供應商或跨裝置備份已完成驗證。
- **語言現況**：只有完整繁中開放。既有英文 ARB 不等於所有功能文案已完成；英文／日文仍有缺口。
- **大字現況**：真正 App root 保留既有 `1.0–1.3×` 上限。原生測試即使要求 `2×`，也以
  capture.frame 的實際值報告，不能宣稱全 APP 已提供完整 `2×` 大字。
- **仍待本人**：封面 UI 遮擋、演出節奏與主場景接手的視覺驗收；實機聲音、觸覺、release
  啟動耗時與效能。本輪沒有實體裝置安裝、正式 OAuth 接通、後台部署或正式發布。

### 實際執行的程式檢查

環境為 macOS、`/private/tmp/tumi-entry-integration`。最終完整測試與 analyze 在兩項
Reduce Motion 修正後串行執行，均正常退出。
單項測試已包含於完整測試總數，不重複加總。log 目前保存於列示位置，交付封存時保留原始內容。

| 命令／範圍 | 實際結果 | 證據與限制 |
|---|---|---|
| `flutter test --no-pub` | **1,220／1,220 項通過**，2 分 39 秒，exit 0 | [最終完整 log](/private/tmp/entry-full-tests-serial.log)；不代表實機效能、聲音或 OAuth 已驗證 |
| `flutter test --no-pub test/entry_integration_test.dart` | **10 項通過** | [入口 log](/private/tmp/entry-widget-regression.log)；驗證明確 Guest 才寫入、signed／guest 回訪 prefs 不變、取消不寫入、離線不等於雲端空、錯誤重試及按壓動態。目的地使用簡單測試頁驗路由意圖；真 MainPage／功能操作另看原生證據 |
| `test/entry_arrival_gate_test.dart`（完整測試內） | **3 項通過** | 真 MainPage 等待入場結果後才處理獎勵；resume 不繞過未完成／失敗的閘門，dispose 後不接受遲到的成功訊號。沒有 native audio mock |
| `test/entry_meeting_test.dart` | **2 項通過**，包含於最終完整測試 | [初見回歸 log](/private/tmp/entry-meeting-tests-final.log)；修正 Reduce Motion 的即時文字切換，不把動畫 layout 例外藏起來 |
| `flutter test --no-pub test/mascot_test.dart` | **22 項通過**，另依兔咪守則獨立執行 | [兔咪 log](/private/tmp/entry-mascot-tests.log)；不代替本人對角色表情與音訊的驗收 |
| `flutter analyze --no-pub` | **No issues found**，5.7 秒，exit 0 | [最終分析 log](/private/tmp/entry-analyze-serial.log) |
| `bash scripts/check_units.sh`、`git diff --check` | **exit 0** | [單位 log](/private/tmp/entry-check-units.log)；本輪未變更單位換算，仍補跑既有單位字串掃描 |
| `flutter build ios --release --flavor redesign --no-pub` | **exit 0**，Xcode build 990.6 秒，Runner.app 181.5 MB | [build log](/private/tmp/entry-release-build-final.log)、[產物資料](/private/tmp/entry-release-build-info.json)：1.0.1／2026091201、原 redesign bundle ID、iPhoneOS／arm64；未安裝實體裝置、未發布 |
| `codesign --verify --deep --strict` | **exit 0** | [簽章檢查](/private/tmp/entry-release-codesign-final.log)；簽章有效不等於實機音訊、啟動耗時或效能通過 |

入口版面測試使用實際繁中文案，在 **375×667、320×568 pt，各 1.3×／2.0×** 檢查
保存錯誤可捲動到達並成功重試；Reduce Motion 測試確認按壓比例維持 `1`、duration 為零，
且仍可執行操作。這些是 widget 約束檢查；真正 App 的大字上限仍為 `1.3×`，
不能把元件的 `2.0×` 通過寫成全 APP 已完成大字驗收。

曾嘗試的額外「完整 MyApp → 新增習慣」widget 測試在 native audio fixture 清場掛住，
該 case 與其專用 mock 已移除，不列為通過；完整入口至既有功能的驗收，改採本輪原生
計時開始／暫停證據。

### 修改邊界稽核

以 `a579d10` 的 Git 內容逐位元比較，以下檔案未變更，摘要與 SHA-256 保存於
[範圍稽核 log](/private/tmp/entry-scope-audit.log)：

| 保護範圍 | 核對結果 |
|---|---|
| 六功能頁與導航 | `home_page.dart`、`timer_page.dart`、`water_page.dart`、`weight_page.dart`、`family_page.dart`、`wardrobe_page.dart`、`tab_catalog.dart`、`navigation_surface.dart` 完全相同。`lib/main.dart` 內的 MainPage 只增加入口就緒／錯誤 callback 與 resume 演出閘門 |
| 生日與既有保存 | `profile_edit_page.dart`、`birthday_picker.dart`、`onboarding_setup.dart`、`backup_archive.dart`、`backup_restore.dart` 完全相同；新增入口不寫入／刪除生日，回訪測試比對完整 prefs 保留生日與功能偏好 |
| 原生與登入設定 | `ios/`、`android/` 無追蹤檔差異或新增檔案；`account_backend.dart`、`firebase_account_backend.dart`、`account_cloud_config.dart` 完全相同。AccountService 僅增加 cloud-read 確認狀態及 force-init 失敗保護 |

這是程式與隔離狀態的稽核，不宣稱已檢查正式裝置上的個人資料；本輪不讀取、清空或覆寫
正式裝置 container。本人需判斷的畫面與未驗證事項仍以下列證據及限制為準。

### 原生操作與媒體證據

交付媒體索引位置：
[本輪截圖、連續操作與原始證據](/Users/raraku/.codex/visualizations/2026/09/12/01a09392-a6db-7e03-b2f0-5f7f02bbc75a/entry-integration/index.html)
已產生。索引保留各批 `capture.json`、source hashes、原始 PNG／MP4、log 與
解碼紀錄；沒有來源的比較明列未執行，不拿舊 preview 補畫面。
共 **15 批：12 批自動（含整合前基準）＋3 批手動，114 張 PNG／15 段 MP4**。
整合前後僅提供 4 對同條件畫面，其餘沒有 before 的情境明列缺少對照。
比較頁語法、介面與比較切換已實際核對。

環境為 iOS 26.5／redesign debug／繁中。Small 是 SE 3 **375×667 pt**，Large 是
iPhone 14 Pro Max **430×932 pt**。下列 11 批自動操作均記錄 exit 0、`errors: []`，
並操作真正 MainPage 與既有計時器；身份、雲端資料與故障來源仍是明示模擬。

| 情境／capture 目錄尾名 | 已實際走完的操作與結果 |
|---|---|
| 首次 Small `first-final`、Large `first-large-final` | 開始 → 明確訪客 → 兩幕短初見 → 真首頁 → 計時開始／暫停；8 張原生 PNG／批 |
| 回訪訪客 `returning-guest-final`、已登入 `returning-signed-final` | 繼續原旅程 → 首頁／計時，不重播初見；已登入 fixture 的成功備份時間仍為空，沒有把身份當備份 |
| Apple 新旅程 `apple-new-final` | 模擬成功，且查詢成功確認無恢復資料 → 真初見、保存、首頁／計時；沒有額外的確認彈窗 |
| Google 恢復 `restore-final` | 模擬身份／備份 → 真帳號備份頁確認還原 → 真還原與 root restart → 繼續原旅程，不播放新相遇 |
| 取消／登入錯誤 `auth-errors-final` | Apple 取消、Google 未知錯誤、Apple 網路失敗均不建立旅程；明確選訪客後能完成進入 |
| 有憑證但離線 `credentials-offline-final` | 讀取失敗保留「雲端未知」；重試成功查無資料後才提供新旅程，之後可進首頁／計時 |
| 初始化失敗 `init-failure-final` | 注入 prefs 讀取失敗 → 真錯誤畫面 → 重試 → 封面與新旅程，不用動畫掩蓋錯誤 |
| 略過＋大字＋Reduce Motion `skip-accessibility-verified` | Large，要求 2×、App 實際 **1.3×**、`disableAnimations: true`；略過後到真首頁／計時，沒有 layout 例外 |
| 真 OS 背景返回 `background-final` | host 開 iOS 設定、再開原 App；實際 `paused → resumed`，同一 MainPage state、執行中的計時保留，無封面／初見重播 |

以上目錄皆在 `/private/tmp/entry-integration-<尾名>/`。整合前 Small 使用本輪另行啟動的
a579d10：`entry-integration-before-small`，實際繁中 `zh`、1×、Reduce Motion 關；
整合後 Small 為 `zh-TW`、同尺寸與偏好。兩者都是實際 App root，並非舊 preview 截圖。

普通 `lib/main.dart` 另有以下 **手動操作已核對** 的原生證據。manifest 刻意記錄
`manual_review_complete: true`、`test_exit_code: null`，不加進自動通過數：

| 手動 capture | 實際觀察與資料界線 |
|---|---|
| `normal-first-small` | 語言選繁中 → 明確訪客 → 略過短初見 → 真首頁／計時；通知選「不允許」。切設定再返回仍為同一 PID、倒數繼續，可暫停 |
| `normal-return-small` | terminate／launch 換新 PID，啟動畫面後顯示「繼續一起生活」；既有 5 幣與旅程保留、不播初見。前後 13 項原生偏好逐值相同，包含旅程完成、日期、訪客、語言、靜音與幣紀錄 |
| `normal-final-small` | 最終普通 main 原地更新同 bundle；真 iOS Reduce Motion 開、最大字級滑桿 100% → 冷啟動／繼續 → 既有 5 幣的真首頁／計時 → 切設定再返回，同 PID 52216 倒數仍為 24:11，可在 24:02 暫停。未 instrument MediaQuery，`textScale` 為未知；App 原有 1.3× cap 保留。測後已恢復原系統設定並讀回 |

`normal-final-small` 的 [正常 build log](/private/tmp/entry-normal-build-final.log) 為 exit 0。
`simctl install` 原地更新時，iOS 將資料 container UUID 從 `2B2BF8F5…` 搬到
`F66AFFC9…`；13 項指定原生偏好在更新前、更新後及操作後的值與型別均相同。
沒有 uninstall、reset 或 erase；這是指定鍵的核對，不宣稱完整 container 的所有資料都已稽核。
安裝已停止舊程序，所以後續 terminate 回報「沒有可終止程序」，不把它記為成功終止；
接著真正冷啟動與前背景操作成功。早期 `normal-accessibility-small` 保留作歷史證據，
主要索引採用 `normal-first-small`、`normal-return-small`、`normal-final-small`。

**來源版本不混用**：`first-large-final`、`apple-new-final`、`background-final`、
`skip-accessibility-verified`、`normal-final-small` 的 runtime hashes 與最終修正相同：
main `1b888633…`、entry_meeting `3daa92d4…`。其他上表早期自動批次與
`normal-first-small`、`normal-return-small`、歷史 `normal-accessibility-small` 是在兩項
Reduce Motion 修正以前的 binary（main `163b120e…`、entry_meeting `8ad28b8c…`）；
保留原 manifest，不能因目錄有 `final` 就宣稱它們全部攝於同一份最終 source。

**實際失敗與修正**：早期 `skip-accessibility-final` 為 exit 1，只取得封面與登入選擇，
不列為通過。Reduce Motion 的零秒 `AnimatedSize` 在 layout 中修改自身；另發現零秒
`AnimatedOpacity.onEnd` 會在父層建置時回呼。修正為減少動態時直接顯示文字／靜態 opacity，
由下一個 frame 完成接手。其後上述最終來源的略過、大字、Reduce Motion 原生批次與
1,220 項完整測試均成功。較早的並行 build／test 干擾 log 不當作成功證據。

**媒體與結論的限制**：主索引 15 段影片已用 AVFoundation 解碼各 4 個指定時點；
`normal-final-small` 為 215.30 秒、錄影正常停止，沒有音軌。
PNG 保留原始截圖。這是可解碼與抽樣核對，不等於逐幀完整影片驗收；錄影不足以判定原生
launch 至 Flutter 第一幀的整段 fade 品質。手動長片含 CUA／工具等待，不能當啟動或
操作耗時量測；影片沒有音軌，不宣稱音訊已聆聽通過。實機音訊、觸覺、流暢度與 release
啟動效能未測，最終封面遮擋、演出節奏與場景交接仍請本人觀看判斷。
Codex 內嵌瀏覽器在播放 MP4 時發生 page crash，比較頁內與獨立影片皆重現，不能列為
播放通過；Chrome 的首次流程原片已播放至 `0:39 / 0:39` 的真正計時頁結尾，
但沒有完整播放全部 15 段。

### 回退與範圍風險

目前變更只在 `codex/entry-integration`；原 `codex/experience-redesign`／a579d10 保留。
若不採用本輪入口，可繼續使用原測試版；若需程式回退，在整合分支 revert 本輪入口提交，
或從 a579d10 建立另一個測試 checkout。**不 reset 使用中的工作區、不刪 App、不清 container
或 preferences**，也不需要變更 bundle ID。

本輪沒有正式資料遷移；新增語言偏好不影響舊版讀取，短初見仍沿用既有完成保存格式。
回退程式不等於回退日常已產生的使用者資料，也不應刪除那些紀錄。剩餘風險集中在不同尺寸／
偏好與中斷的視覺交接、真實 provider／後台尚未開啟，以及原有大字上限。
本輪整合與驗證完成後即停止，不延伸全 APP 改版、正式登入全面接通、後端部署或公開發布。
