# 資產（asset）命名與目錄規範

> 兔咪好習慣 app 的 PNG 資產統一規則。
> 走 CG 差分路線後，所有新增 asset 都照此規範丟。
> 實際情緒與路徑以 `lib/utils/mascot.dart` 的 `MascotEmotion` 為單一真相來源。

更新日期：2026-09-10

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
    home/                    # 首頁四時段完整背景
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
| 兔咪解析度 | 正式素材 **1024 × 1024**；AI 輸出尺寸不保證相同，先保存原檔，再於比對／整合副本處理 |
| 場景解析度 | 現行主場景為 **1122 × 1402** 直向；同頁差分必須與底圖完全同尺寸 |
| 背景 | 兔咪本體必須**透明背景**（疊在場景上）；場景圖含完整背景 |
| Alpha | 兔咪 PNG 保留 alpha；iOS app icon 例外（`remove_alpha_ios: true` 自動處理） |

---

## AI 生圖 prompt 共通規格

同一套兔咪情緒必須是**同一隻兔咪**，以核准的正面圖為 edit target 製作局部差分。共通要求：

- 透明背景（`transparent background, isolated subject, no background`）
- 1024×1024 正方形
- 構圖：兔咪居中，頭頂與下巴留約 8% 邊距
- 沿用核准底圖的光源方向，不另訂新打光
- 同一線條粗細、同一渲染風格（高品質 CG）
- 嘴巴維持極小符號感；不要張嘴、露齒、說話口型或嘴巴動畫
- 2026-09-10 使用者停止無服裝底圖下腹修正，保留原始 `tumi_neutral_front.png` 與現行正式素材；下半身的重量感改在穿上造型後局部處理。下腹 v1／v2 不再等待核可或安排替換。是否重製其他表情／動作差分仍屬另行評估，不能當成已核准全面換圖。
- 每次服裝生成及下半身修正都附上下面的固定要求。不要只寫「不要陰影」而抹平整體立體感；固定 prompt 仍需搭配核准參考圖與逐張比對，不能視為大量生成必定一致的保證。

### 服裝下半身固定 prompt

```text
Do not redraw the whole image. Local edit only. 不重繪，只局部修改。
只在指定服裝區域更換衣料；保留核准兔咪的臉、耳朵、頭身比例、姿勢及原本打光。
褲型輕盈、圓順，兩條褲管清楚，布料自然貼合圓潤身體；腿根只保留柔和、必要的接觸陰影。
不要沿用裸身底圖向褲襠中央聚攏的深摺線或積壓陰影。
禁止下墜的袋狀鼓包、尿布形褲襠、像裝著重物的垂墜感，以及深黑 V／U 形褲襠陰影。
不要為了消除重量感而縮小肚子、改變腿長、擦掉自然體積陰影或重畫整隻兔咪。
```

此段與指定造型、改動區域、輸入圖片角色一同使用；覆蓋範圍外維持原圖。必要時只修新服裝的褲襠／褲管，不能回頭修改無服裝底圖。

---

## 工作流程

新增 asset 時的固定 SOP：

使用者指定由網頁生圖時，原檔保存與下載問題排查見 [網頁圖片保存與驗證](browser_image_download.md)。

1. 兔咪差分使用 repo skill `tumi-image-variants` 檢查核准底圖並做局部 edit；
   場景、圖示等其他素材依使用者指定目標製作。
2. 照規範命名（例：`tumi_smile.png`）放進對應資料夾。
3. 新增資料夾時更新 `pubspec.yaml`；新增情緒時同步 `MascotEmotion` 與使用情境。
4. 做與改動相稱的檢查，提供模擬器截圖；實機驗收由使用者本人處理。
5. 提交與推送遵循 `AGENTS.md`，不在本文件重複規定。

## 未使用素材

目前沒有使用或很可能淘汰的素材，依 [`asset_review/README.md`](../asset_review/README.md)
查核後移入待審區，保留原路徑與理由。等使用者審核才刪，不因檔案舊或名稱相似就移除。
