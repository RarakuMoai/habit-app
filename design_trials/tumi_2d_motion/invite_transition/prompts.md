# 局部補圖紀錄

2026-09-08。使用內建 `image_gen`，沒有使用 CLI 或外部影片模型。
輸入已先目視：[核准邀請圖](../../../assets/mascot/core/tumi_invite.png)，角色為 edit target。
輸出副本：[body-clean-plate.png](sources/body-clean-plate.png)。

工具輸出為 1254×1254 RGB，棋盤格已畫入像素，**不是真透明圖**。
依使用者先前明確授權，程式在副本上縮放至共同座標、描出身體邊界，再只採用手臂修補區域。
不採用 AI 整張重畫結果；只有手臂附近修補遮罩參與合成，其餘使用核准 PNG。精確範圍以 `prepare.py` 的 `repair` 遮罩為準。

完整提示詞：

```text
Use case: precise-object-edit. Image 1: edit target, approved Tumi rabbit invite pose, 1024x1024 transparent PNG. Create an animation clean plate by removing ONLY BOTH ARMS / paws below the head, filling the small revealed torso regions with coherent gray/cream plush fur and completing the underlying torso silhouette. Do not redraw the whole image. Local edit only. 不重繪，只局部修改。 Left arm image coordinates approximately x325..460,y532..678; right arm x588..714,y535..688. Remove both arms entirely; leave an armless torso, no nubs. Do not change head, face, tiny x mouth, eyes, ears, legs, feet, chest center, proportions, camera framing, canvas size, lighting, color, rendering or any pixels outside these two local regions. Keep the exact existing invite image as base. Transparent background with real alpha; no fake checkerboard, no white background, no extra objects, no text. This is a technical body clean plate; no new pose or outfit.
```

來源預設保存於 Codex generated_images，以上副本已放入專案；重現不依賴原本的 Codex 保存位置。
