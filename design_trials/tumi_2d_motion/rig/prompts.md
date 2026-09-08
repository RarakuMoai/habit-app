# 補圖提示詞與來源

2026-09-08，內建 `image_gen` 局部編輯。使用者另已明確同意程式裁切、去背與對齊副本；處理方法見 `prepare.py`。

## 身體補圖

輸入：`assets/mascot/core/tumi_neutral_front.png`。輸出：`sources/body-clean-plate.png`（生成檔 `exec-c7f01602-998c-48d0-882a-1ee63c66d628.png`）。只採用左側手臂附近的補圖區域，其他區域回用核准原圖。

```text
Use case: precise-object-edit / inpainting for a 2D rig. Image 1: edit target, the approved Tumi neutral front PNG. Do not redraw the whole image. Local edit only. 不重繪，只局部修改。 One targeted local change: remove only the rabbit's right arm (on the VIEWER'S LEFT, the short gray plush arm and cream paw between roughly x=298..408, y=540..730 in the 1024px source). Reconstruct the small torso side and fur that would be hidden underneath that arm, making a continuous natural gray plush left torso edge from shoulder below the chin down to the hip. Where the removed arm used to extend outside the torso silhouette, leave empty background. Do not remove or change the long left ear: the ear is separate and remains exactly as in the original. Preserve all of the head and face, tiny mouth, both ears, opposite arm, legs, body proportions, lighting, fur texture, composition and original placement. This is a body clean plate to put the original detached arm back on top for animation, NOT an amputee character redesign and NOT a new pose. Do not add clothing. Use a plain solid white background where empty if alpha cannot be preserved, NEVER draw checkerboard squares. Full image, 1024x1024, same scale and registration as input. Only change the small arm-removal and hidden-torso region. Output one PNG.
```

## 背心補圖

輸入：`design_trials/tumi_2d_motion/vest-neutral-concept.png`。輸出：`sources/vest-clean-plate.png`（生成檔 `exec-260dc216-0ce7-48f9-9ed9-83a55e1e86ff.png`）。只擷取背心，完整臉、耳、另一隻手與腿不使用生成版本。

```text
Use case: precise-object-edit, inpainting for a 2D animation rig. Image 1: edit target, Tumi in the approved-for-trial sage sleeveless vest concept. Do not redraw the whole image. Local edit only. 不重繪，只局部修改。 Make ONE local edit: REMOVE ONLY the rabbit's RIGHT arm on the VIEWER'S LEFT (the short gray arm with cream paw below the chin, NOT the long pink-lined ear). Reveal and carefully reconstruct the previously hidden left side panel of the SAME sage vest underneath that arm: simple continuous sage cloth down to the EXISTING ivory hem, with a small armhole at the shoulder but no dangling arm. The outer torso/vest edge should continue naturally from just under the left shoulder down to the left waist. This is a clean plate for reattaching the original arm as a moving layer. Keep both long ears, complete head and face, other arm, legs, all body proportions, EXACTLY TWO wooden buttons, ivory edging, vest shape and all existing visible vest pixels unchanged. Preserve original soft painted CG quality, camera, lighting, palette, placement and 1254 square canvas. Do not change background. Do not add any new outfit, accessories, text, shadow, new gesture or face features. Output one PNG. Only the removed-arm and newly-exposed vest side region should change.
```
