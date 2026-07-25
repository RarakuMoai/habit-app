# 待補素材與生成 prompt

> 程式都已經寫好在等圖，補上就生效。每項都附：用途、規格、底圖、可直接貼給
> ChatGPT 的 prompt、以及「補上後要改哪裡」。
>
> 生圖走**手動 ChatGPT**（用既有訂閱額度，零成本，見 `roadmap.md` §3c）。
> 最後更新：2026-07-25。

## 通用規格

| 類別 | 尺寸 | 格式 | 命名 | 放哪 |
|---|---|---|---|---|
| 兔咪本體／差分 | **1024×1024** | PNG **透明背景** | `tumi_<情緒>.png` | `assets/mascot/core/` |
| 場景／繪本 | **1122×1402** | WebP q95 | `<場景>_<時段>.webp` | `assets/scenes/<房間>/` |
| 道具小圖 | 512×512 | PNG 透明背景 | 見各項 | 見各項 |

**全域風格錨**：暖色系柔和 CG 插畫、圓潤、低對比、手繪繪本感。參考任一張
`assets/mascot/core/tumi_*.png` 與 `assets/scenes/home/home_day.webp`。

---

## ⚠️ 兔咪本體差分的鐵則

兔咪已有核准底圖，**差分一律是「局部編輯」不是重新生成**。完整規範見
`.agents/skills/tumi-image-variants/SKILL.md`，每個 prompt 都必須包含：

```text
Do not redraw the whole image. Local edit only. 不重繪，只局部修改。
```

**永遠不能動的**：嘴／鼻口（那個小 Y 字粉色記號）、臉型、耳朵、身體比例、
剪影、CG 質感、配色、打光、鏡頭取景、畫布尺寸、透明背景。
情緒只能靠**眼睛、眉毛、耳朵角度、肢體姿勢**表達。

---

## 1. 摸頭瞇眼差分 `tumi_pet_bliss.png`

- **用途**：摸兔咪頭夠久時，牠瞇眼享受。目前退回眨眼差分（只有中性站姿有）。
- **底圖**：`assets/mascot/core/tumi_smile.png`（手垂＋笑眼）
- **難度**：低。只改眼睛。

```text
Use case: identity-preserve / precise-object-edit
Input images: Image 1: edit target, approved Tumi base PNG (tumi_smile.png).

Primary request: Create a "blissful squint" variant — the rabbit is being petted
on the head and is enjoying it, eyes narrowed into contented curves.

Critical instruction: Do not redraw the whole image. Local edit only.
不重繪，只局部修改。

Local change: Change ONLY the eyes. Turn the current smiling eyes into softer,
more relaxed blissful squints — slightly flatter curves, a touch more closed,
reading as "melting into the touch". Optionally add the faintest upward tilt at
the outer eye corners. Nothing else moves.

Preserve: Tumi's identity, face shape, the nearly mouthless design (the small
pink Y-shaped nose/mouth mark must stay EXACTLY as-is), ear shape and angle,
arm position (hanging down), body proportions, silhouette, CG rendering style,
lighting, color palette, camera framing, 1024x1024 canvas, transparent background.

Avoid: full redraw, restyling, new outfit, new props, background, any change to
the mouth/nose mark, fake blink overlays, extra facial features, blush changes,
watermark, text.

Output: PNG variant, 1024x1024, transparent background, consistent with Image 1.
```

**補上後**：檔案丟 `assets/mascot/core/`，把 `lib/utils/mascot.dart` 的
`_petBlissReady` 改成 `true` 即全表情生效。

---

## 2. 兔咪拿印章 `tumi_stamp.png`

- **用途**：每日報到卡的主視覺。現在暫用歡呼姿 `tumi_streak.png`，
  補上後可讓兔咪與印章道具合體，不再是兩個分開的元素。
- **底圖**：`assets/mascot/core/tumi_streak.png`（雙手高舉雀躍）
- **難度**：**高**——要加道具且處理手部接觸。若生不出來就維持現狀，這不是必要素材。

```text
Use case: identity-preserve / precise-object-edit
Input images: Image 1: edit target, approved Tumi base PNG (tumi_streak.png).

Primary request: The rabbit is holding a small wooden-handle stamp in one paw,
as if it just finished stamping a paw print on a check-in card.

Critical instruction: Do not redraw the whole image. Local edit only.
不重繪，只局部修改。

Local change: Add a small wooden-handle rubber stamp held in ONE raised paw.
The stamp is a simple illustrated prop: light wood handle (#C89158 to #96652F),
dark brown base (#8A5A2B to #6E4A1F), with a hint of gold ink (#D79A2F) on the
stamping face. Adjust ONLY the gripping paw so the contact reads naturally.
Keep the other arm exactly as it is.

Preserve: Tumi's identity, face shape, the nearly mouthless design (pink Y mark
unchanged), eyes and expression, ear shape and angle, body proportions,
silhouette, CG rendering style, lighting direction, color palette, camera
framing, 1024x1024 canvas, transparent background.

Avoid: full redraw, restyling, new outfit, background, changing the facial
expression, adding a check-in card or paper, sparkles or effects (all effects
are drawn in Flutter), watermark, text.

Output: PNG variant, 1024x1024, transparent background, consistent with Image 1.
```

**補上後**：改 `lib/pages/login_streak_page.dart` 的 `_mascotAsset` 常數。

---

## 3. 零食圖 ×3

- **用途**：報到卡的 CTA。現在用 emoji（🍪🥕🎂）頂著，跟 CG 風格有落差。
- **規格**：512×512 PNG 透明背景，**三張同一組**（同光向、同筆觸、同比例）。
- **底圖**：無，但要附一張 `tumi_neutral_front.png` 當風格錨。
- **難度**：低。一次生三張確保成組。

```text
Create a set of THREE illustrated treat icons for a gentle habit-companion app
featuring a soft CG-illustrated rabbit. Attached image is the app's rabbit
character — match its art direction exactly: warm palette, soft rounded forms,
gentle shading, low contrast, hand-painted storybook feel. NOT flat vector,
NOT emoji, NOT glossy 3D.

The three treats, as one consistent set:
1. A small round cookie with a few chocolate chips
2. A carrot with fresh green leafy top
3. A small celebration cake slice or petit four, slightly fancier than the others

Requirements for all three:
- Same lighting direction, same brush treatment, same visual weight
- Each centered, filling roughly 80% of the canvas
- Readable at very small size (they render at ~22pt on a button)
- No plate, no table, no background elements, no text, no sparkles
- 512x512 each, transparent background, PNG

Output: three separate PNG files, transparent background.
```

**補上後**：丟 `assets/icon/treats/`（新目錄），把
`login_streak_page.dart` 的 `_treat` getter 從 emoji 換成 `Image.asset`。

---

## 4. 繪本回憶圖 ×4

- **用途**：四個回憶事件的整頁插圖。**現在暫借場景圖**，程式有 `TODO(story-art)`。
- **規格**：1122×1402 WebP q95（同四時段場景規格）
- **難度**：中。工作量最大的一項。

**我的建議：這四張不要畫兔咪。**

理由：畫兔咪進場景等於新的角色繪製，會有跨圖一致性風險（roadmap §3b 標記
的唯一技術風險）。繪本的情感由旁白承載就夠——而且「空景 ＋ 兔咪的獨白」
反而更有回憶感，像在看牠記得的畫面。

| 事件 | 檔名 | 畫什麼 | 現在的旁白 |
|---|---|---|---|
| 第一個習慣 | `story_first_habit.webp` | 桌上一張剛寫下第一行字的小紙條，晨光斜照 | 「你寫下第一個想做到的小事。」 |
| 首次全完成 | `story_first_all_done.webp` | 房間裡的燈全部亮著，窗外是傍晚 | 「最後一件小事，也亮起來了。」 |
| 連續 7 天 | `story_streak_7.webp` | 夜空下七顆星星連成一line，房間窗景 | 「數到第七顆時，我就完全醒了。」 |
| 久違回來 | `story_comeback.webp` | 微微推開的房門，門縫透進光，室內積了一點灰塵感 | 「門安靜了一陣子。」 |

```text
Create a storybook illustration for a gentle habit-companion app.
Attached image is an existing room background from the same app — match its art
direction exactly: warm palette, soft rounded forms, gentle shading, low
contrast, hand-painted children's storybook feel, cozy and quiet.

Scene: <從上表挑一列的「畫什麼」填進來>

Requirements:
- NO characters, no rabbit, no people — this is an empty, quiet moment
- Portrait orientation, 1122x1402
- Same room vocabulary as the reference (wooden furniture, soft fabrics,
  warm light) but this specific scene may be a different corner of the room
- Leave the composition calm and uncluttered; the emotion comes from light
  and emptiness, not from detail density
- No text, no watermark, no UI elements, no sparkles or effects

Output: 1122x1402 image.
```

**補上後**：轉成 WebP q95（`cwebp -q 95`），丟 `assets/story/`，
改 `lib/utils/story_catalog.dart` 的 `StoryPage` 路徑並移除 `TODO(story-art)`。

---

## 5. 前導功能說明圖 ×3

- **用途**：前導的喝水／計時／家庭三頁。目前只問「要不要開」，沒說那是什麼。
- **規格**：建議 800×800 PNG 透明背景（實際版面確認後可調）
- **難度**：中。要「一眼看懂」，這比好看更重要。

三張各自的重點：

| 頁面 | 要傳達的一句話 | 畫什麼 |
|---|---|---|
| 喝水 | 記錄每天喝了多少 | 一個水杯陣列，前幾杯已填滿、後面是空的 |
| 專注計時 | 專心時幫你顧著時間 | 一個柔和的沙漏或圓形計時環，旁邊一本攤開的書 |
| 家庭 | **小朋友的獎勵機制** | 一張貼紙獎勵表，幾格已貼上星星貼紙 |

```text
Create THREE illustrated feature explainer images for a gentle habit-companion
app. Attached image is the app's art reference — match it exactly: warm palette,
soft rounded forms, gentle shading, low contrast, hand-painted storybook feel.

The three images, as one consistent set:
1. WATER TRACKING: a row of water glasses, the first few filled with soft blue
   water, the rest empty — instantly readable as "track how much you drink"
2. FOCUS TIMER: a soft hourglass or circular timer ring beside an open book —
   instantly readable as "time your focused work"
3. FAMILY REWARDS: a child's sticker reward chart with several gold star
   stickers already placed — instantly readable as "kids earn stickers for
   small tasks"

Requirements for all three:
- Comprehension over beauty: someone must understand the feature in one glance
- Same lighting, same brush treatment, same visual weight across all three
- No characters, no rabbit, no people, no hands
- No text or numbers anywhere in the image (the app supplies all wording)
- 800x800 each, transparent background, PNG

Output: three separate PNG files, transparent background.
```

**補上後**：丟 `assets/onboarding/`，在前導對應三頁的氣泡下方加圖。

---

## 0. ⭐ 造型一致性驗證（最優先，先做這個）

**這不是素材需求，是風險驗證。** 你的內容供給計畫（一套造型＝一次上新）
建立在一個沒驗證過的假設上：**AI 能跨 13 張圖維持同一隻兔咪、同一套衣服。**
`roadmap.md` §3b 自己也標了這是唯一技術風險。

做不到的話，訂閱要賣什麼得重想——所以**在投入 i18n 那種幾週的工程之前，
先花一小時把這件事試出來**。

### 怎麼驗

不要一次生 13 張。**先生 3 張最極端的**，能過再考慮整套：

| 順序 | 底圖 | 為什麼挑它 |
|---|---|---|
| 1 | `tumi_neutral_front.png` | 站姿中性，當這套造型的**新基準** |
| 2 | `tumi_pop_happy.png` | 雙手高舉——**衣服在動作下會不會走樣** |
| 3 | `tumi_sleep.png` | 打瞌睡姿——**遮擋與角度變化下衣服還在不在** |

三張擺在一起看：是不是同一隻兔子、同一套衣服、同一個布料質感。
**只要有一張讓你覺得「這好像別隻」，這條路就要重新評估。**

### Prompt（第一張，建立新基準）

```text
Use case: identity-preserve / precise-object-edit
Input images: Image 1: edit target, approved Tumi base PNG (tumi_neutral_front.png).

Primary request: Dress this rabbit in a simple outfit — <你想要的造型，例如
"a soft mustard-yellow knitted sweater with a small wooden button at the collar">.

Critical instruction: Do not redraw the whole image. Local edit only.
不重繪，只局部修改。

Local change: Add ONLY the clothing onto the existing body. The garment must
follow the body's existing silhouette and volume, with soft fabric folds that
match the CG painting style. Keep head, face, ears and paws fully visible and
unchanged.

Preserve: Tumi's identity, face shape, the nearly mouthless design (the small
pink Y-shaped nose/mouth mark must stay EXACTLY as-is), eyes, ear shape and
angle, body proportions, overall silhouette, pose, CG rendering style, lighting
direction, camera framing, 1024x1024 canvas, transparent background.

Avoid: full redraw, restyling, changing the pose, changing the face, hats or
accessories unless requested, background, sparkles or effects, watermark, text.

Output: PNG variant, 1024x1024, transparent background, consistent with Image 1.
```

### Prompt（第二、三張，跟第一張對齊）

**關鍵：把第一張生好的圖也附上去當造型基準**，否則第二張會長出不一樣的衣服。

```text
Use case: identity-preserve / precise-object-edit
Input images:
  Image 1: edit target, approved Tumi base PNG (tumi_pop_happy.png).
  Image 2: outfit reference — the SAME rabbit already wearing the target outfit.

Primary request: Dress the rabbit in Image 1 with the EXACT SAME outfit shown in
Image 2, adapted naturally to Image 1's different pose.

Critical instruction: Do not redraw the whole image. Local edit only.
不重繪，只局部修改。

Local change: Add ONLY the clothing from Image 2 onto Image 1's existing body.
Same garment type, same colour, same knit texture, same collar detail, same
button. Let the fabric folds follow Image 1's raised-arms pose naturally.

Preserve: everything about Image 1 except the added clothing — identity, face,
the pink Y nose/mouth mark, eyes, ears, pose, proportions, silhouette, CG style,
lighting, framing, 1024x1024 canvas, transparent background.

Avoid: full redraw, changing the pose, changing the face, different garment
colour or texture from Image 2, background, effects, watermark, text.

Output: PNG variant, 1024x1024, transparent background.
```

### 驗完之後

- **三張都像同一隻** → 這條路可行，再補剩下 10 張湊成完整一套
  （放 `assets/mascot/<outfit>/tumi_<emotion>.png`，資料夾名對應 skinKey）。
- **有一張走鐘** → 先別投內容。我們改討論替代方案（減少情緒張數、
  只換配件不換整套、或者造型改成非角色的房間裝飾）。

---

## 補素材的流程

1. 從上面挑一項，把 prompt 連同「底圖」欄指定的圖一起貼給 ChatGPT。
2. **兔咪差分**要把底圖標成 `Image 1: edit target`，不是風格參考。
3. 拿到圖之後丟給我，我負責轉檔、命名、放進正確目錄、改程式、跑測試。
4. 兔咪差分收到後我會先 `Read` 圖確認嘴／耳朵／比例沒被動到，再整合。
