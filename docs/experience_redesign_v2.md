# 親子溫暖體驗改版 V2

更新：2026-09-10。使用者試看第一版後，明確要求 App 更有親子、溫馨、可愛的感覺，
並指出部分分頁收合後的舊版更好用。V2 以這項回饋為目前方向，保留大幅改版的自由，
重新處理功能面板的資訊順序、前導、導覽與兔咪互動。

本輪 `flutter analyze` 無問題、完整 `flutter test` **950 項通過**，另有 **44 張原生
模擬器截圖**及比較頁。新版 release 已建置並通過簽章核對；實機外觀、音訊與手感待本人驗收。

## 版本與比較

- 沿用 `codex/experience-redesign` 及 `/Users/raraku/habit-app-redesign` 工作樹。
- 舊版基準：`0737a7d`；第一版改版：`1ccd098`。V1 的設計與已完成驗證保留在
  [日常手帳體驗改版 V1](experience_redesign.md)，供逐項比較和挑選移植。
- [V2 原生比較頁](../design_trials/experience_redesign/review_v2/index.html) 已包含前導、
  V1／V2 分頁、展開、計時與導覽 A／B；V1 比較頁仍可從上述文件開啟。
- [V2 驗證紀錄](../design_trials/experience_redesign/review_v2/validation.json) 保存本輪測試結果、
  截圖數量、release 身分與執行檔雜湊；編譯產物不加入 Git。
- 既有資料運算、儲存單位、商品價格、購買確認與免費造型規則沿用。兔咪正式 PNG
  不重繪；原版工作樹與美術候選保留。主線採用、分組移植與發布仍待使用者決定。

## 溫暖與清楚並重

奶油底色、蜜桃與暖棕承接房間和兔咪，喝水仍有水藍、體重有莓粉、計時與衣櫃有柔紫
識別。彩色 PNG 主導覽圖示恢復，選中狀態與可讀標籤保留，避免整個介面只剩制式圖示。
字型沿用已打包的 Nunito 與 Baloo 2；實際色彩、圓角及動態 token 以
[`app_style.dart`](../lib/utils/app_style.dart) 和 [`app_theme.dart`](../lib/utils/app_theme.dart) 為準。

足跡幣、聲音與設定工具鈕共用 **48 × 48pt** 外框及 **8pt** 間距。這是工具鈕尺寸，
不是把 AppBar 高度改成 48pt；日期仍依真正剩餘寬度排版。

主導覽預設使用暖色不透明卡面。另保留 `--dart-define=NAV_GLASS=true` 作為建置時的材質
比較選項，使用同一份導覽排版；高對比模式改用實底。這個選項由 Flutter 的
`BackdropFilter`、模糊和半透明表面實作，**不是 Apple 原生 Liquid Glass 元件**，
也不是設定頁中已開放的使用者選項。材質喜好與實機代價待比較，不先把玻璃版定為預設。
喝水及體重的 Scaffold 底色也統一使用 `AppSurfaces.canvas`，避免透出不同底色而出現斷層。
材質實作見 [`navigation_surface.dart`](../lib/widgets/navigation_surface.dart)。

## 面板依真正可用空間安排內容

「收合」在本文件指下方功能面板較小、上方房間展開；「展開」指功能面板向上打開。
主分頁經 `MainPage → SafeArea → MascotPageShell` 排版，不能用整個螢幕高度設計卡片。
以下為六個主分頁開啟時，真實 MainPage widget harness 的量測基準：

| 裝置邏輯尺寸與安全區 | 功能面板收合 | 功能面板展開 |
| --- | --- | --- |
| 320 × 667；上20／下0pt | 內容 y366.1–559，可用192.9pt | 內容 y136–559，可用423pt |
| 430 × 932；上59／下34pt | 內容 y478.2–826，可用347.8pt | 內容 y175–826，可用651pt |

尺寸包含外層 AppBar、導覽與場景的實際影響；430 × 932 另已核對原生畫面。
各頁根據這些可用空間調整資訊結構，不把整張卡或所有文字一起縮小。

| 頁面 | V2 處理 |
| --- | --- |
| 首頁 | 今日摘要與主操作保持清楚，短面板優先讓習慣清單可讀、可打卡；完成前後的卡片尺寸保持穩定。 |
| 計時 | 從正式 parent constraints 決定摘要、房間旁面盤或展開配置；極矮面板先顯示時間與開始／暫停，次要設定往下捲讀。觸控範圍不跟著面盤縮小，運動、節拍與桌遊也走各自的窄版配置。 |
| 喝水 | 短面板將總量與目標分欄，整張摘要可調目標；加水、復原、自訂改為單列可達操作，近期紀錄與建議在下方。空間足夠時保留水瓶主卡。 |
| 體重 | 主數字先完整顯示，差值、目標和生理指標依序排列；小面板不再把所有指標包進超高主卡。主操作使用「編輯體重／記錄體重」短文案，輔助語意仍描述完整動作。 |
| 家庭 | 收合採姓名、頭像與積分的實用名冊。新增孩子與家長管理位於面板內固定操作列，不再由浮動按鈕遮住孩子；極短面板省去重複標題。 |
| 衣櫃 | 短面板、窄螢幕及大字使用縮圖、名稱與操作並排的完整選物列；空間足夠才使用雙欄圖卡。分類入口固定，保留穿著、購買、試聽、播放清單與回憶操作。 |
| 個人頁與延伸流程 | 設定、個人資料、回顧、表單及揭曉延續暖色表面；檢查小螢幕、長文、鍵盤與捲動，主要操作不得被裁切。 |

新 `compact_panel_layout_test.dart` 載入正式打包字型，覆蓋 MainPage、安全區、兩個尺寸、
中英文、1.3 倍文字、降低動態及兩種面板狀態，驗證首卡與操作列的位置。
計時另由模式專屬測試驗證實際受限高度。這些是版面證據，不能取代原生截圖與本人手感。

## 九步前導

首次開啟以同一條九步流程呈現：歡迎、替兔咪取名、自己的稱呼、喝水、專注、家庭、
選擇習慣、身體資料、準備完成。各步保留真實功能選擇及既有資料保存規則，並以角色、
簡短說明與可辨識的功能預覽建立關係。

前進操作固定在底部，步數清楚顯示；鍵盤出現時保留頂端工具列，暫時省略步驟進度，
內容可捲動，操作列位於鍵盤上方。姓名、身高／體重、生日、活動量及每週習慣頻率仍需完整可操作。
測試與原生擷取以真正的 `OnboardingPage` 走完九步及保存流程，避免只拍靜態示意。

## 兔咪旁的低頻邀請

首頁在兔咪所在的場景內顯示輕提示，由使用者點開後才進入對話；提示不占功能面板。
頁面安定後才允許顯示，並避開打卡演出、報到、編輯、其他對話及非當前頁面。
目前聊天的唯一入口是事件提示；右上固定聊天按鈕已移除。

- 首次相遇在尚未處理過時優先；點開或關閉後記錄，之後不再當作第一次。
- 後續依當天每日習慣完成狀態，選擇小進展或全部完成的情境對話。
- 每個邏輯日最多**處理一次邀請**。只看到提示不算處理；點開或關閉後當天不再邀請，
  包含稍後由小進展變成全部完成的情況。
- 僅保存首次邀請是否處理過及最近處理的邏輯日，不保存對話答案、推論個人輪廓或發放額外獎勵。

規則見 [`roommate_events.dart`](../lib/utils/roommate_events.dart)，事件與台詞的唯一紀錄仍為
[兔咪對話目錄](tumi_dialogue_catalog.md)。降低動態及既有音訊／觸覺歸屬沿用，不為提示
另外增加重複播放的聲音。

## 整合驗證

建置與測試共享 Flutter 資產輸出，本輪原生擷取、一般測試及 release 建置採串行執行，
避免平行更新 `build/flutter_assets` 造成缺件假象。

| 項目 | V2 狀態與需補證據 |
| --- | --- |
| 靜態分析、單位及完整回歸 | **通過**：`flutter analyze` 無問題，`flutter test --reporter expanded` 950項，`bash scripts/check_units.sh`、`git diff --check` 通過。 |
| 受限版面、前導與事件測試 | **通過**，納入上述950項：320／430pt、中英文、1.3字級、降低動態；九步選擇及保存；事件頻率與非同步請求取消；桌遊文字與盤面不互遮。 |
| iOS 模擬器原生擷取 | **通過**：iPhone 14 Pro Max／iOS 26.5，430 × 932、繁中、1.0字級、正常動態、redesign debug。主流程28張、九步前導與首次回憶／首頁13張。 |
| 導覽材質比較 | **通過**：`NAV_GLASS=true` 的習慣、喝水、衣櫃3張；與預設版同場景和尺寸。高對比的實底回退由程式控制，實機仍待本人。 |
| V2 簽署 release | **通過**：`flutter build ios --release --flavor redesign -t lib/main.dart --dart-define=NAV_GLASS=false`；arm64，142.5MB。`codesign --verify --deep --strict` 通過，名稱「兔咪新體驗」、Bundle ID `com.yayoi991331.habitapp.redesign`、Team ID `6NZ675Y2MZ` 均核對。使用 Apple Development 簽署供本人裝置測試，並非 App Store 分發產物。產物為 `build/ios/iphoneos/Runner.app`。 |
| 本人實機驗收 | **待本人**：可讀性、親子溫暖感、操作手感、音訊、觸覺、冷啟動與 release 流暢度；AI 不安裝或啟動實體裝置。 |

本輪修正了三種驗證缺口：首次完成前導會先開啟回憶揭曉，必須看完後才驗首頁；
iOS 通知視窗可凍結原生畫面，但 Flutter 測試樹仍前進，因此擷取加入前景／送幀檢查與
PNG 像素判重；家庭操作列改用真實 MainPage 雙排導覽驗證，不再找舊 FAB。
桌遊的英文大字另暴露工具列及暫停卡的溢出，依真正可用寬高修正。

主要 harness：`integration_test/onboarding_review_test.dart`、
`integration_test/experience_review_test.dart`；版面與規則包含
`test/compact_panel_layout_test.dart`、`test/onboarding_redesign_test.dart`、
`test/onboarding_flow_test.dart`、`test/timer_page_layout_test.dart`、
`test/game_timer_compact_test.dart`、`test/experience_shell_test.dart`、
`test/roommate_events_test.dart`。測試結果由整合後的實際執行填入，不以清單存在宣稱通過。

## 獨立測試版與下一步

沿用 `redesign` iOS flavor，主畫面名稱 **兔咪新體驗**，Bundle ID
**`com.yayoi991331.habitapp.redesign`**。V2 更新的是同一個獨立候選 App 身分；正式版及
舊 dev 版的識別與資料不變，模擬器 fixture 的空資料也不代表會重設使用者既有的候選資料。
本輪已完成上述 release 建置與驗簽，沒有安裝／啟動實體 iPhone 或 iPad，也沒有公開分發。

最重要的下一步是由本人試用這份獨立 release，確認真實觸控、動畫及音訊手感。
驗收順序以九步前導、六主頁收合，再到展開與主要操作；先判斷「溫暖可愛」和
「小面板更好用」是否同時成立，再決定整條分支採用或分組移植。

本人連接 iPhone 後，在終端機執行以下命令；有多部可用裝置時選自己的 iPhone：

```sh
cd /Users/raraku/habit-app-redesign
flutter run --release --flavor redesign -t lib/main.dart --dart-define=NAV_GLASS=false
```

這會更新獨立的「兔咪新體驗」。已有的候選資料會沿用，因此完成過前導的候選 App 不會
自動重新顯示九步流程，可先用比較頁查看本輪完整前導。不要為了重看前導刪除正式 App。
若要本人試用玻璃材質，將最後的 `NAV_GLASS=false` 改為 `NAV_GLASS=true`；該選項只改導覽
材質，仍是同一份候選 App 身分。不要使用指向原版工作樹的 `dev`／`prod` 捷徑安裝本輪。
更多身分隔離說明保留在 [V1 的本人試用章節](experience_redesign.md#本人試用與選擇)。
