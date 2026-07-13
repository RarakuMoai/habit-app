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

- 打卡勾 = 320ms easeOutCubic 路徑描繪（`_CheckDrawPainter`），列表載入不重播。
- 進度列 = 漸層填色 + 尾端白心亮點（10px、accent 描邊 2.5）；達標時 900ms 呼吸光暈 `repeat(reverse)`。
- 兔咪互動（呼吸、彈跳、情緒泡泡、完成星光）由 Flutter 負責。
- 場景環境光、窗景、燈具與家具陰影畫進四時段完整背景，不再由 Flutter 畫光束、
  燈暈或長影；細節見 `four_period_background_plan.md`。

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
