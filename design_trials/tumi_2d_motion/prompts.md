# 生成紀錄

使用內建 `image_gen`，以 `referenced_image_paths` 進行既有圖片局部編輯；沒有使用 CLI、API key 或外部代生成服務。
輸出保留原檔並複製到本資料夾。兩張皆為未核准、不可直接整合的 RGB 概念圖，詳見 [README](README.md)。

## 1. 無袖背心

輸入：`assets/mascot/core/tumi_neutral_front.png`。
輸出：`vest-neutral-concept.png`。
生成檔名：`exec-aec63c56-5d41-4fa6-908e-8781f729457a.png`。

```text
Use case: identity-preserve / precise-object-edit. Image 1: edit target, the approved Tumi rabbit base PNG. Make ONE local outfit trial: dress this exact rabbit in a simple muted sage-green sleeveless cotton vest, with warm ivory edging, two tiny wooden buttons, no print or text. The vest covers only the upper torso from just under the chin to above the legs; leave paws, legs and head visible. Keep BOTH existing arms and paws in front of the vest, keep the long ears in their original positions and original occlusion order. This is a 2D sprite production concept, preserve the exact existing soft illustrated CG appearance, not a shiny 3D redesign. Critical instruction: Do not redraw the whole image. Local edit only. 不重繪，只局部修改。 Change only the small torso clothing region; preserve all pixels outside it as closely as possible: exact face, eyes, tiny original mouth mark, ears, original neutral pose, body proportions, silhouette except local cloth edge, fur color and texture, lighting, camera, framing, 1024x1024 canvas. Preserve genuine transparent background and alpha, no opaque white backdrop and no checkerboard artwork. Full rabbit must remain in the same placement and scale. No hat, no scarf, no other props, no shadow beneath feet, no extra face features, no restyling. Output one transparent PNG outfit candidate.
```

## 2. 穿同款背心抬手招呼

輸入：第一張生成圖片。
輸出：`vest-wave-concept.png`。
生成檔名：`exec-88bc467d-e0f8-400d-ba68-339e07ef762e.png`。

```text
Use case: precise-object-edit / identity-preserve. Image 1: edit target, Tumi wearing the sage vest outfit candidate. This is one motion key-pose concept, not a character redesign. Critical instruction: Do not redraw the whole image. Local edit only. 不重繪，只局部修改。 Change ONLY the rabbit's RIGHT arm as seen on the LEFT side of the image: lift that small arm forward and slightly outward into a shy greeting, paw near lower cheek height, maintaining its short plush rabbit anatomy, no human fingers. This hand is in FRONT of the existing long ear and in front of the vest, so the overlap is visible and readable. The arm's shoulder stays attached in the same place just below the chin. Keep the head, expression, exact tiny mouth, face proportions, both long ears, the other arm, body, feet, lighting, fur texture, canvas, placement and background UNCHANGED. Keep the EXACT SAME sage-green sleeveless vest, ivory edging and TWO wooden buttons, same hem and front panels: do not invent clothing folds outside the shoulder contact region, no new outfit. Preserve the original softly illustrated 2D CG look. No captions, no extra props. One image only.
```
