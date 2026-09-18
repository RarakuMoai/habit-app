# 回憶美術：蠟筆與淡水彩意象

更新：2026-09-18。使用者提出「不一定要有兔咪，意象也可以」，希望回憶帶有小朋友繪畫感。
七星樣稿獲本人回覆「這圖片可以」，作為本批畫風基準。原封面仍維持核准 CG；本輪僅改回憶圖片。

## 已核可的七星圖

- [七顆星星原圖](../assets/story/streak_7_crayon_v1.png)，1122×1402 PNG，未裁切、未壓縮、未重新生成。
- 圖片本身已由本人核可，App 內尺寸與裁切仍需原生驗證。
- [特殊回憶目錄](../lib/utils/story_catalog.dart) 的 `streak_7` 改用此檔。保留事件 ID、觸發種類、門檻、台詞、收藏與存檔語意。
- 同一圖片自動供衣櫃收藏縮圖、回憶閱讀器及揭曉頁使用；本輪不改排版或增添演出。
- 生成工具為本對話內建 `image_gen`。如實保留工具來源，不宣稱模型為 GPT Image 2.5；本輪沿用使用者明確核可的原始成品，不為更換工具重生成它。
- SHA-256：`00323939d5c221cc8401f00131c1d15fd90cc8b23270aa695ff9de8c0007c4bd`。
- 原始來源：`/Users/raraku/.codex/generated_images/01a0b31b-65e5-71b3-a371-1e495551a86a/exec-52a9f94d-a938-42db-bb99-e05a1e9c2060.png`。

## 畫風原則

蠟筆為主、淡水彩為輔。以斷續的蠟筆線條、紙紋、歪歪的形狀與少量塗出邊界，表現認真畫下來的小記憶。
暖象牙紙色、奶油黃、桃橘、赤陶、鼠尾草綠與淡灰藍；保留未塗滿的紙面。
每張只抓一個主要意象，不要求兔咪入鏡，不強行畫出事件全過程，也不把圖內文字做進圖片。
圖片只是畫頁本身，不加真實桌面、畫筆、照片邊框或手持展示。

## 同批內容

| 事件 | 意象 | 狀態 |
| --- | --- | --- |
| `first_habit` 我們的第一頁 | 打開的本子、兩葉嫩芽 | 新候選，待本人選用；未接入 |
| `first_all_done` 燈都亮起來了 | 三扇暖窗亮起的小屋、淡藍暮色 | 新候選，待本人選用；未接入 |
| `streak_7` 七顆星星的晚上 | 七顆不同形狀的星、小屋暖窗 | 原圖已核可，已接入測試分支 |
| `comeback` 門再次打開的日子 | 半開的門、延伸到門外的暖光 | 新候選，待本人選用；未接入 |

本地圖庫與原始 prompt：
`/Users/raraku/habit-app/design_trials/beta_release_20260918/index.html`。
七星原 prompt 位於 `crayon_v1/prompt.md`，其餘三張的母 prompt／分鏡位於 `crayon_v1/sibling_prompts.md`。
候選圖片未核可前留本機；已核可七星圖隨 App 變更保存版本。
先前三張舊立繪 V1 及四張封面 CG V2 均留作探索紀錄，不再作本批預設方向。

## 核可圖的生成 prompt

```text
Use case: illustration-story.
Create a single portrait 4:5 illustration for a keepsake memory page titled, for context only, "七顆星星的晚上" (The evening of seven stars). No lettering in image.
Art direction: a heartfelt little child's drawing in wax crayon with a very light watercolor wash, on warm ivory drawing paper. Naive, simple, honest, endearingly irregular hand marks. Visible broken wax strokes skipping over paper grain, uneven outlines, imperfect five-point star shapes, some color outside the outlines, a few layered scribbles. Broad white/ivory paper areas remain visible. Small restrained washes of diluted blue watercolor, genuine hand-painted pooling and bleed. Crayon is the dominant medium, watercolor is supporting. The picture should feel made and kept by someone, not a polished commercial vector or sophisticated children's book painting. Avoid exaggerated distress, artificial aging, neat digital brushes, gradients and glossy rendering.
Story and composition: EXACTLY SEVEN large and easily countable hand-drawn stars, in a loose gently ascending arc across the middle and upper page. Every star slightly different in shape and size, colored pale yellow, golden yellow and warm peach with wax crayon, still clearly five pointed. They represent seven small days spent together; some stars slightly overlap the blue wash, all remain separate from each other. Under the stars, in the lower third, a tiny simple cottage outlined with a child's brown crayon, a wonky terracotta triangular roof, one warm yellow square window and a small closed door. A short soft sage-green crayon patch beneath the cottage, only a few strokes. Night is suggested with one loosely brushed pale dusty-blue patch behind the stars, not a full dark sky. Generous breathing room around drawing, asymmetrical natural placement, no exact grid. Do not add any other stars, dots of light, moon, sun or patterned star border; total stars must be seven.
Emotional intent: tender evidence of returning, a small home beneath seven remembered evenings. Imagery only; no rabbit, no human, no mascot, no faces, no text, no numbers, no checkbox, no arrows, no UI, no frame, no mockup desk, no pencils or hands photographed around paper. The full image IS the drawing page. Soft daylight paper tone, no cast shadows or 3D effects. Keep all seven stars and cottage inside safe margins for a portrait memory illustration.
Output: one opaque PNG, portrait 4:5.
```

## 其餘三張的畫風 prompt

```text
Use case: illustration-story. Make ONE new portrait 4:5 memory illustration. Image 1 is a STYLE REFERENCE ONLY: the user-approved crayon and watercolor keepsake page. Match its warm ivory paper, visible wax-crayon grain, childlike uneven outlines and shapes, simple symbolic composition, light watercolor wash and generous unpainted paper. This is a new event, not an edit of the seven-star scene. Do not copy the seven stars or cottage unless the requested scene calls for a cottage.
Handmade child's drawing: broken wax lines, warm brown/ochre outline, imperfect shapes, scribbled fills, occasional coloring slightly outside edges. Crayon dominant, very diluted watercolor supporting. Tender and sparse, not a professional smooth vector or realistic painting. No 3D, no glossy CG, no photorealism, no elaborate botanical accuracy, no perfect geometry. The whole image IS a page, not a photographed sheet on a desk. No hands, art supplies or staged frame around it. No rabbit or other character, no faces, no letters, numbers, words, logos, borders or UI.
Keep the symbolic subject large enough for a phone memory page, leave at least 10% quiet margin around key forms. Palette follows the approved sample: buttery yellow, peach, muted terracotta, sage, pale dusty blue and brown. Output opaque PNG, 4:5 portrait.
```

## 驗證紀錄

本輪只整合一張已核可圖片，不改動其他回憶與故事進度。
`flutter analyze --no-pub` 無問題，完整 `flutter test --no-pub` 1,251 項通過。
原生模擬器流程亦通過：iOS 26.5、430×932pt、繁中、字級 1.0、Debug-redesign（`com.yayoi991331.habitapp.redesign`），使用記憶體內已解鎖回憶 fixture。
從正式 App 入口進入衣櫃／回憶，確認七星收藏縮圖、閱讀器及揭曉頁。縮圖能辨識星星與小屋，兩個大圖畫面完整保留七顆星；真實標題「七顆星星的晚上」與三行正文未遮擋或溢位。
三張 1290×2796 原生截圖、`capture.json`、測試紀錄及本輪暫用控制器存於本地圖庫 `crayon_v1/native/`。未安裝或操作實體裝置；實機觀感仍由本人確認。
來源比對、圖片與文件檢查涵蓋原始 PNG 的完整保存；模擬器與實機結論分開記錄。

下一步：本人查看七星圖的原生呈現，以及另外三張候選的筆觸與意象，再延伸整合。
首波交付範圍見 [基礎測試版計畫](beta_release_plan.md)。
