# 回憶圖片：沿用封面形象與渲染方向

2026-09-18。使用者指出第一輪太鎖定舊立繪與繪畫方式，要求以現行 APP 封面分析畫風，再套用到新回憶。
這項授權允許新姿勢、角度與場景；角色保持可辨識，不要求回憶 CG 與原立繪逐像素相同。

## 分析依據

[實裝封面 V6](../assets/scenes/onboarding/entry_living_room_v6_clean_fur.png)；`lib/widgets/entry_cover.dart` 明確引用此圖。V28 只更新覆蓋的字標，不改此美術基底。
以下是從圖片可觀察特徵整理的提示詞，不是找回原始生成 prompt，也不保證重現同一隨機輸出。

- 角色：奶油白與淡灰紫色毛、長垂耳及粉紅內耳、額頭白毛、黑亮眼睛、粉頰、小小珊瑚色 X 嘴型。
- 材質：細短絨毛，圓潤立體體積；木紋、織物與門框有細節及自然接觸陰影。
- 光線：日光／室內暖光與較冷環境光分開，有毛緣透光、柔和反射光，亮部仍有細節。
- 鏡頭：前景、角色及背景有層次，適度景深；動作與空間關係承擔情緒。
- 場景可改構圖，角色可以坐、靠、伸手或走動；每則回憶有自己的事件瞬間，不套用同一正面站姿。

## 本地交付

候選、圖庫、完整提示詞及雜湊：
`/Users/raraku/habit-app/design_trials/beta_release_20260918/`。

`images/` 內四張 V2：`first_habit_v2.png`、`first_all_done_v2.png`、`streak_7_v2.png`、`comeback_v2.png`。
內建 `image_gen` 生成；原始來源留在其回傳目錄，副本保存於專案，沒有覆寫核准素材。
三張 V1 留在 `superseded/` 作製作紀錄，已停止採用，不再要求本人驗收。
候選圖尚未核可／整合，依專案規則留本機，不隨本輪文件 commit；不把它們列為已進遠端的正式資產。

## 實際使用的 V2 母 prompt

```text
Use case: illustration-story / stylized-concept.
Create ONE completely new story-event key art image, portrait 4:5, high-quality opaque PNG, no text, UI, logo, borders or watermark.
Input image 1 is a REFERENCE for Tumi's CHARACTER IDENTITY and the approved cover's RENDERING STYLE, NOT an edit target. User explicitly authorizes new poses, camera angles and compositions. Do not reproduce the doorway composition unless the specific scene calls for it. Do not freeze Tumi in a front-facing sprite pose.
Reverse-engineered visual direction from reference: cinematic stylized 3D animated-feature still, physically believable warm cottage materials, extremely fine clean short velvety rabbit fur, softly rounded volumetric forms, believable wood grain and woven fabric, subtle subsurface light through pink ear interiors, soft bounce light and contact shadows, gentle shallow depth of field. Camera feels inside an inhabited little home, with foreground/midground/background depth. Clear focal story action. High-end cozy game key art, NOT flat watercolor, NOT outlined storybook illustration, NOT a mascot pasted onto a painted background. Warm pearl and ivory fur with delicate cool gray-lilac side patches/shadows rather than muddy gray-brown. Honey-colored wood, cream plaster, sage textiles; preserve nuanced warm/cool light separation and highlight detail, avoid blanket yellow filter.
Tumi identity anchors: recognizable same young gentle lop rabbit from the cover; oversized rounded head, small plump body, extremely long hanging pink-lined ears, light cool-gray side head patches and broad ivory face blaze/tuft, large shiny black eyes, round peach-pink cheeks, tiny coral X-like nose-mouth, small rounded paws. Mouth remains tiny and closed, no teeth, no human fingers. No costume, no new accessories worn on body. Natural body weight and paw contact. Poses and expression may change for story, eyes can close gently. No second rabbit or visible user character.
Compose a lived-in candid moment, not a commemorative portrait. Subject and key story object readable on a phone, keep the key action away from outer 10% and preserve ear tips. Art can use new room angles and furnishings consistent with the cover world. No text baked into the artwork.
```

## 各事件追加 prompt

### first_habit

```text
SCENE first_habit / 我們的第一頁. The first small intention is written down and treasured. Near the cover home's arched window, Tumi sits sideways on a small cushion at a low round wooden table. A blank cream notebook rests open diagonally on the table, with only one small empty checkbox, no writing. Tumi has just drawn the notebook closer with one paw, while the other lightly flattens the page; head bent toward the page, eyes attentive, shy pride in the quiet action. No presenting the book to camera. Camera at tabletop height from a three-quarter angle, intimate medium shot; soft out-of-focus near edge of the table in foreground, face/paws/book sharp, sage gingham sofa and window softened behind. Morning light catches ear fur and the notebook page. A modest pencil lies naturally beside the book. The emotional point is 'I will keep our first page', told through careful hands, not smiling at camera.
```

### first_all_done

```text
SCENE first_all_done / 燈都亮起來了. A candid end-of-day moment of peaceful completion. Tumi is reclining on the sage gingham sofa, sinking gently into a cream cushion, little feet relaxed and ears draped naturally, eyes peacefully closed, one paw loosely resting on belly. On a low round wooden table in the foreground is a small open notebook with exactly three simple checked boxes and no writing; a plain cup beside it. Lamp in the middle distance glows warmly, cool soft twilight through the window. Camera slightly above sofa-seat height, diagonal three-quarter composition, enough room to feel breathing space. Face and resting pose are the emotional focus; notebook provides secondary completion context. No front-facing standing pose, no excitement, no confetti. The feeling is earned rest together and being seen after small efforts.
```

### streak_7

```text
SCENE streak_7 / 七顆星星的晚上. Tumi is seated in three-quarter profile on a broad upholstered window seat at night, knees tucked comfortably, head tilted slightly up toward a garland of EXACTLY SEVEN large, separate, countable glowing five-point paper star lights across the window. One paw has just released the final star, the other rests on the sill; tiny paws, no fingers. Both eyes gently awake and quietly delighted, face still recognizable from three-quarter angle. All seven lights visible inside central 80% width; no other star symbols anywhere. Outside is deep indigo sky with a simple crescent moon, soft dark trees, no pinprick stars. Warm garland light brushes the fine pale fur against cool blue moonlit ear edges. A cream blanket loosely rests on the seat beside the rabbit, not an outfit. Medium environmental shot from inside the room at rabbit eye level. This is a moment of looking up after seven days together, not a reward splash screen. No numbers, writing or UI.
```

### comeback

```text
SCENE comeback / 門再次打開的日子. Revisit the approved cover's home doorway as an emotionally warmer later moment, but create a different shot and a natural new gesture. View from just outside at rabbit eye level through a HALF-open rounded wooden door. Tumi has stepped out from behind the door into the light, one paw still lightly holding the door edge, other paw making a small tentative welcoming motion toward the room. Weight naturally shifted onto one foot, long ears gently trailing with that movement. Open glossy eyes meeting the viewer with relief and warmth, tiny X mouth, no sad pleading or guilt. The room behind has a softly lit sage sofa, a little table and an inviting cushion, physically detailed wood and cream stone threshold. Late-afternoon side light, airy depth, subtle rim light around ear fur. Character occupies the center third, full body and ears within frame; enough door visible to convey reopening but do not hide half the face behind it. No written welcome sign or lettering, no luggage or invented user body. A welcome that asks for nothing.
```


## 第一頁局部修正

第一個 V2 結果把筆畫在兔咪手中；為符合「你寫下小事，兔咪收好」的既有字幕，
另以該生成圖為 edit target，把筆移到桌上，兔咪改為扶著本子。採用此修正版作本輪候選。

```text
Use case: precise-object-edit. Image 1: edit target, the existing approved-for-this-edit rendered Tumi at notebook composition.
Do not redraw the whole image. Local edit only. 不重繪，只局部修改。
Make one local storytelling correction: Tumi is carefully keeping the user's notebook, not writing the user's habit for them. Remove the pencil from the raised paw, lower that same paw naturally onto the outer lower-left edge of the notebook to hold the page flat. Place that one pencil flat on the wooden table immediately beside the notebook instead. Keep the single small EMPTY checkbox on the page. Keep both eyes, face, tiny X mouth, ears, fur, body proportions, other paw, notebook, camera, room, daylight, colors, depth of field, composition, resolution and all other objects unchanged. No new text, no added checkmarks, no redrawing of character or surroundings.
```

## 美術檢查與限制

已逐張目視核對：兔咪辨識特徵仍在、四種動作有差異、星燈七顆、沒有圖內文字及開嘴露齒。
生成圖並非像素保真的立繪差分；細部毛色、眼睛角度與家具仍有改變，符合這輪重創場景的方向，但本人外觀選用尚未完成。
目前只完成圖片檢查；原生縮圖、閱讀尺寸、與當前皮膚的區別及實機顯示仍待採用後整合驗證。
回憶是固定事件插圖，若角色當下穿睡衣，不能誤稱 CG 已支援動態換裝。

完整範圍與優先順序見 [基礎測試版計畫](beta_release_plan.md)。
