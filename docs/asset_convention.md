# 資產（asset）命名與目錄規範

> 兔咪好習慣 app 的 PNG 資產統一規則。
> 走 CG 差分路線後，所有新增 asset 都照此規範丟。
> 實際情緒與路徑以 `lib/utils/mascot.dart` 的 `MascotEmotion` 為單一真相來源。

更新日期：2026-07-13

---

## 目錄結構

```
assets/
  mascot/
    core/                    # 正式日常情緒與必要關鍵幀，永遠進 bundle
      tumi_neutral_front.png
      tumi_<emotion>.png
      tumi_<emotion>_blink.png  # 有核准眨眼差分時才加入
    <outfit>/                # 未來整套造型；資料夾名對應 skinKey
      tumi_<emotion>.png
      ...
  scenes/
    home/                    # 首頁背景與同畫布透明差分
    timer/
    water/
    weight/
    family/
  # 星光、情緒泡泡等現行特效由 Flutter 繪製，不需要預設建立 fx/。
```

---

## 命名規則

| 用途 | 範例 | 規則 |
|---|---|---|
| 核心情緒 | `tumi_sleep.png` | 加 `tumi_` 前綴（在 Finder/檔案總管直接認得），snake_case，全小寫 |
| 衣服變化 | `chef/tumi_happy.png` | 衣服名當資料夾，內部沿用 `tumi_<情緒>.png` |
| 四時段場景 | `home_dusk.webp` | `<場景名>_<morning|day|dusk|night>.webp`；四張同畫布同構圖，WebP q95（1122×1402 原圖 ~2.2MB → ~0.3MB，暗部漸層 2× 放大無色帶） |
| 特效 | `confetti.png` | 直接描述用途 |

目前 12 個正式情緒（對應 `MascotEmotion` enum）：
- `neutral_front`
- `sleep`
- `wake`
- `expect`
- `smile`
- `happy`
- `pop_happy`
- `streak`
- `sad`
- `night`
- `invite`
- `question`

另有 `tumi_neutral_front_blink.png` 作為中性站姿眨眼關鍵幀；它不是獨立情緒。
新增或移除狀態時先改 `MascotEmotion`，再同步本文件，不要另立固定數量規則。

---

## 圖片規格

| 項目 | 規範 |
|---|---|
| 格式 | 兔咪等透明資產 **PNG**；不透明的場景背景 **WebP q95**（首頁/喝水/計時/家庭/衣櫃已採用） |
| 兔咪解析度 | **1024 × 1024**（AI 生圖預設大小，剛好對到 mobile 3x retina） |
| 場景解析度 | 現行主場景為 **1122 × 1402** 直向；同頁差分必須與底圖完全同尺寸 |
| 背景 | 兔咪本體必須**透明背景**（疊在場景上）；場景圖含完整背景 |
| Alpha | 兔咪 PNG 保留 alpha；iOS app icon 例外（`remove_alpha_ios: true` 自動處理） |

---

## AI 生圖 prompt 共通規格

同一套兔咪情緒必須是**同一隻兔咪**，以核准的正面圖為 edit target 製作局部差分。共通要求：

- 透明背景（`transparent background, isolated subject, no background`）
- 1024×1024 正方形
- 構圖：兔咪居中，頭頂與下巴留約 8% 邊距
- 同一光源方向（建議右上 30°）
- 同一線條粗細、同一渲染風格（高品質 CG）
- 嘴巴維持極小符號感；不要張嘴、露齒、說話口型或嘴巴動畫

---

## 工作流程

新增 asset 時的固定 SOP：

1. 先用 repo skill `tumi-image-variants` 檢查核准底圖並做局部 edit。
2. 照規範命名（例：`tumi_smile.png`）放進對應資料夾。
3. 新增資料夾時更新 `pubspec.yaml`；新增情緒時同步 `MascotEmotion` 與使用情境。
4. 跑測試並在模擬器／實機驗證身份一致性、透明邊緣與構圖。
5. 確認後 commit + push
