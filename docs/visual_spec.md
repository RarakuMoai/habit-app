# 兔咪好習慣 — 視覺規範

> 習慣頁 2026-06-12 定案；後續頁面持續以共用 token 收斂。
> Token 一律集中在 [`lib/utils/app_style.dart`](../lib/utils/app_style.dart)，**不要在頁面裡重新發明**。
> 全 app `Colors.grey` / 純黑歸零（`lib/dev/` 除外）。

## 顏色

**頁面識別色系優先**
- 規範本意是「**禁冷灰純黑**」，不是強制全棕。
- 頁面若有自己的主題色系，次要文字/陰影映射到該色系。例：喝水頁有水藍墨色系
  （`_kInk #17657A` / `_kInkSoft`），不套暖棕 `AppInk`。新頁面比照辦理。

**文字墨色（AppInk）** — 不准用純黑 / `Colors.grey` 系
- 主文字 `strong #453229`（深咖啡）
- 次要 `soft #8C7A6E`
- 淡化/完成 `faint #BDAA9E`
- icon `iconFaint #C9BAAE`

**時段配色（`_sceneColors`，優先序）**
- 全完成綠 > 夜 22–6 靛 > 清晨 6–9 粉金（accent `#F0826E`）> 傍晚 17–22 薰衣草（accent `#A984D6`）> 白天橘 `#FF8A50`。
- 房間背景另疊對應 10–12% 色罩（`_sceneTint` / `sceneTintNow`）。

## 陰影（AppShadows）

一律**暖棕** `#8D6E63` 雙層（對齊插畫慣例 — 用棕非純黑、雙層 ambient + contact）：
- `card`（ambient 16/0.10 + contact 4/0.08）：浮起卡用。
- `flat`（5/0.06）：完成/退場卡用。

## 圓角階梯

浮出層愈大、圓角愈大。四格都在 theme 或 token 供應，**頁面不要自己寫**：

| 層 | 圓角 | 來源 |
|---|---|---|
| 彈出選單 | 14 | `main.dart` `popupMenuTheme` |
| 卡片 | 18 | `AppCardStyle.radius` |
| 底部面板 | **20** | `AppCardStyle.sheetRadius` → `bottomSheetTheme` |
| 對話框 | 22 | `main.dart` `dialogTheme` |

底部面板這一格是 2026-08-04 才補上的：在那之前沒有 theme 預設，32 個
`showModalBottomSheet` 裡 19 個各自手寫圓角、其餘吃 Material 預設，
全 app 同時存在 28／24／20／16 四種。新增面板不寫 `shape` 就是對的。

`bottomSheetTheme` **同時供應底色**（暖白 `#FFFDF9`，與 popup／dialog 同一套
卡面語彙）。所以那 18 個原本吃 Material 預設的面板，底色一併從 seed 推出來的
`#FFF1ED` 換成 `#FFFDF9`；另外 13 個自己傳 `backgroundColor` 的不受影響。

**分格看的是元素類別不是位置。** 四角全圓、帶陰影的浮動卡走卡片那一格（18），
即使它是從底部彈出來的（例：`table_setup_panel` 的鍵盤上方浮動卡）。
面板那一格（20）只給「上緣兩角圓、貼齊畫面底部」的 modal sheet。

## 卡片（AppCardStyle）

- 圓角 **18**。
- 未完成卡帶髮絲線 `hairline`（`#46342B` @4%）。
- 完成卡：淡綠底 `#F1F8E9` + 綠 18% 描邊 + `flat` 陰影。
- 左側「內縮圓角色條」（4 寬、上下內縮 14、圓角 2）**只表類別**
  （橘=一般、藍=連動、靛=每週）；完成時淡到 30% 讓位。
- 原則：**一個元素只說一件事** — 完成狀態由圓圈/底色/劃線表達，不靠色條。

## 字型（AppType）

- 內文：theme 預設（Nunito + 中文系統字）。
- 數字/計數類：`AppType.digits`（Baloo 2，height 1.1）做字型對比。
- ⚠️ **Baloo 2 ascent 特大**，字形在行框內天生偏上 ~1.2pt；膠囊類要**光學置中**
  （見 MascotPill 的 `Transform.translate(0, 1.2)`）。`leadingDistribution` 對它無效（實測像素零變化）。
- Nunito / Baloo 2 已打包進 assets；不要改回執行期下載字型。

## 動效

- 打卡勾 = 300ms easeOutCubic 路徑描繪（`_CheckDrawPainter`），列表載入不重播。
  時長是共用常數 `kCheckDrawDuration`（[`completion_timing.dart`](../lib/pages/home/completion_timing.dart)），
  卡片與編排器都只 import，**不要兩邊各寫一個數字**——勾勾畫完那一刻就是衝擊點。
- 進度列 = 漸層填色 + 尾端白心亮點（10px、accent 描邊 2.5）；達標時 900ms 呼吸光暈 `repeat(reverse)`。
- 兔咪互動（呼吸、彈跳、情緒泡泡、完成星光）由 Flutter 負責。
- 場景環境光、窗景、燈具與家具陰影畫進四時段完整背景，不再由 Flutter 畫光束、
  燈暈或長影；細節見 `four_period_background_plan.md`。

### 完成演出的節奏（2026-08-04 One-Habit Hero 定案）

一次「完成一件習慣」不是一個瞬間，是一條有先後的弧線：
**confirm → notice → anticipate → impact → speak → recover → quiet**。

實際毫秒、Reduce Motion 對照與合併視窗寫在
[`completion_presentation_controller.dart`](../lib/pages/home/completion_presentation_controller.dart)
的檔頭時間軸，**那裡才是數字的真相來源**。這裡只鎖不會變的意圖：

- **衝擊點對齊使用者看得到的事實，不對齊輸入。** 主 haptic、SFX、換 pose 與放開
  進度條全部落在勾勾筆尖觸底，不落在手指放開。輸入當下只做安靜確認。
- **每一拍都要有事做，沒事就不要留。** notice 是察覺、anticipate 是蓄勢、
  recover 是落地、quiet 是清乾淨。少了 anticipate 就會退化成「系統打勾」。
- **同一拍不給兩件事。** impact 給身體，speak 給語言。疊在同一幀就沒有因果。
- **連打共用一條動作弧線，但每一件的勾勾各自完成。** 兔咪不從第零幀重蹲，
  重啟弧線會變成抽搐。
- 想加東西之前先問「這一拍解決了哪個讀不出來的問題」。加特效不等於改善節奏。

角色為什麼要這樣反應見 [`tumi_character_guide.md`](tumi_character_guide.md)
的「演出節奏」。

### 啟動接縫（2026-08-05 U1 定案）

原生啟動畫面（iOS `LaunchScreen.storyboard`）在 Flutter 引擎起來之前就顯示，
**它是使用者看到的第一幀**。專案原本用 Flutter 樣板附的 1×1 空白圖，所以那段
時間畫面上什麼都沒有——app 的第一印象是一片白。

- **兩層共用的元素必須在同一個位置。** 原生層的圖由
  [`scripts/gen_launch_image.py`](../scripts/gen_launch_image.py) 從
  `_StartupSplash` 的規格產生，不是手繪也不是一次性產物；改 `_StartupSplash`
  的版面時重跑它。驗收方式是實拍兩層各一幀、量同一個元素的中心差。
- ⚠️ **「0px」是校準機型（14 Pro Max）的數字，不是全機型成立。**
  原生層是一張整頁圖走 `scaleAspectFill`，元素尺寸**跟著螢幕縮放**；
  Flutter 層的圓固定 138pt。所以螢幕愈偏離基準比例，兩層的圓就差愈多：

  | 機型 | 原生圓徑 | 徑差 | 圓心差 |
  |---|--:|--:|--:|
  | 14 Pro Max（基準） | 138.0 | 0% | 0.0pt |
  | iPhone 15／16 | 126.2 | −8.6% | 2.4pt |
  | iPhone SE 3 | 120.3 | −12.8% | 6.1pt |
  | iPad 10.9" | 263.2 | +90.7% | −15.2pt |

  兔咪任何機型都沒有被切到，而且相對於改版前（整片白）每個機型都變好了，
  所以這是「贏得不完整」不是回歸。但 iPad 上原生兔咪接近 Flutter 的兩倍大，
  **跟下一條規則在非基準機型上互相牴觸**。要真正修好的方向是原生層改用
  不隨螢幕縮放的元素（storyboard 放固定尺寸的置中 imageView 疊在漸層 view 上，
  而不是整頁圖 aspectFill）——那是另一個 milestone 的量體。
- 同軸的小事：`_StartupSplash` 在 `MaterialApp.builder` 的 textScaler clamp
  （1.0–1.3）底下，系統字放到最大時 Column 變高，Flutter 那顆圓再往上跑約 5pt。
- **只在 Flutter 層出現的東西要是「加法」，不能是「變化」。** 標題與進度條在
  接手時長出來，讀成「醒過來」；但同一個元素在兩層長得不一樣（例如字型 fallback
  造成的跳字）就會讀成故障。中文標題因此**刻意不進原生層**——Nunito 沒有中日韓
  字，runtime 走系統 fallback，離線工具湊不出一樣的字。
- storyboard 的 imageView 要 `scaleAspectFill` 並釘住四邊。`contentMode="center"`
  搭配 1×1 的圖等於整個原生層什麼都沒有——那正是原本的狀況。
- ⚠️ **空白期長度只能用 profile／release 量**：iOS 不支援模擬器 profile，
  模擬器只證明接縫存在與否，不證明時間。

## 間距 / 留白

- 全部走 **4pt 網格**：卡距 12、區段間隔 20、清單邊距 16。
- 區段標題右側拉 1px 漸隱細線（區段色 25% → 透明）收尾。

## 共用結構

- **下半卡殼**（`mascot_page_shell`，全頁共用）：暖白 `#FFFDF9` @97%、上拋雙層 accent 陰影。**改這裡 = 改所有頁。**
- **選單/對話框**（theme 層，`main.dart`）：popup 暖白 `#FFFDF9`、圓角 14、暖棕陰影、項目帶 icon；dialog 圓角 22、surfaceTint 透明。

## 雷區備忘

- **ListTile**：leading 置中用的是內部算出的內容高度（單行=56），被外層撐高時要設 `minTileHeight` 等於實際高度才會真置中（迴歸測試 `test/habit_card_layout_test.dart`）。
- **像素級對齊驗證**：需要客觀確認時，可從截圖掃目標顏色的 bbox 與中心差；
  一般視覺調整不必預設啟動像素分析。
