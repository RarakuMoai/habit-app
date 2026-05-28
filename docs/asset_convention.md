# 資產（asset）命名與目錄規範

> 兔咪好習慣 app 的 PNG 資產統一規則。
> 走 CG 差分路線後，所有新增 asset 都照此規範丟。
> 舊路徑（`assets/images/mascot/tumi_*.png`、`assets/images/room/*.png`、`assets/images/water/*.png`）保留到完全遷移完才砍。

更新日期：2026-05-26

---

## 目錄結構

```
assets/
  mascot/
    core/                    # 核心 8 情緒，永遠進 bundle，離線可用
      tumi_neutral_front.png
      tumi_sleep.png
      tumi_expect.png
      tumi_smile.png
      tumi_happy.png
      tumi_streak.png
      tumi_sad.png
      tumi_night.png
    outfit/<outfit>/         # 衣服變化（將來會做的養成系統），可放 CDN
      tumi_<emotion>.png
      ...
  scenes/
    home/                    # 各頁背景場景，可保留現有 assets/images/room/ 直到正式重組
    timer/
    water/
    weight/
    family/
  fx/                        # 特效圖層（彩帶、星光等），不屬於兔咪本體
    confetti.png
    sparkle.png
```

---

## 命名規則

| 用途 | 範例 | 規則 |
|---|---|---|
| 核心情緒 | `tumi_sleep.png` | 加 `tumi_` 前綴（在 Finder/檔案總管直接認得），snake_case，全小寫 |
| 衣服變化 | `chef/tumi_happy.png` | 衣服名當資料夾，內部沿用 `tumi_<情緒>.png` |
| 場景 | `bedroom_day.png` | `<場景名>_<變體>.png`（不加 tumi 前綴，因為是場景不是兔咪本體） |
| 特效 | `confetti.png` | 直接描述用途 |

8 個情緒檔名固定為（對應 `MascotEmotion` enum）：
- `neutral_front`
- `sleep`
- `expect`
- `smile`
- `happy`
- `streak`
- `sad`
- `night`

---

## 圖片規格

| 項目 | 規範 |
|---|---|
| 格式 | **PNG**（透明背景，將來 bundle 痛了再批次轉 WebP） |
| 兔咪解析度 | **1024 × 1024**（AI 生圖預設大小，剛好對到 mobile 3x retina） |
| 場景解析度 | **1536 × 1024**（橫向，符合首頁房間目前比例 1024/1536） |
| 背景 | 兔咪本體必須**透明背景**（疊在場景上）；場景圖含完整背景 |
| Alpha | 兔咪 PNG 保留 alpha；iOS app icon 例外（`remove_alpha_ios: true` 自動處理） |

---

## AI 生圖 prompt 共通規格

兔咪 8 情緒必須是**同一隻兔咪**，所以以「正面情緒」當錨點，其他情緒 prompt 都基於它變體。共通要求：

- 透明背景（`transparent background, isolated subject, no background`）
- 1024×1024 正方形
- 構圖：兔咪居中，頭頂與下巴留約 8% 邊距
- 同一光源方向（建議右上 30°）
- 同一線條粗細、同一渲染風格（高品質 CG）
- 嘴巴維持極小符號感；不要張嘴、露齒、說話口型或嘴巴動畫

---

## 工作流程

新增 asset 時的固定 SOP：

1. **使用者**：用 AI 工具生圖
2. **使用者**：照規範命名（例：`tumi_smile.png`）放進對應資料夾（例：`assets/mascot/core/`）
3. **Claude**：更新 `pubspec.yaml` 的 assets 區塊（如果是新資料夾）
4. **Claude**：更新對應 enum / 邏輯把新 asset 接進 app
5. **使用者**：跑模擬器驗證視覺
6. 確認後 commit + push
