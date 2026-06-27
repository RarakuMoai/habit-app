---
name: tumi-image-variants
description: Preserve-and-edit workflow for Tumi / 兔咪 CG PNG variants and 差分. Use when asked to create, edit, regenerate, or iterate Tumi rabbit assets, emotions, event states, transparent PNGs, or local visual changes where an approved existing image must stay recognizable and must not be redrawn.
---

# Tumi Image Variants

Use this skill with the built-in `imagegen` skill. This skill adds Tumi-specific preservation rules; it does not replace the normal image generation/editing workflow.

## Core Rule

When an approved Tumi image exists, treat variants as edits, not fresh generations.

Critical phrase to include in every edit prompt:

```text
Do not redraw the whole image. Local edit only. 不重繪，只局部修改。
```

## Workflow

1. Identify the exact edit target. If it is a local file, inspect it with `view_image` before using `image_gen`.
2. Label every input image by role. The base Tumi image must be `Image 1: edit target`, not a style reference.
3. Make one targeted change per generation attempt. Do not rewrite the whole creative prompt during iteration.
4. Lock invariants every time: Tumi identity, face shape, almost-no-mouth design, ears, body proportions, silhouette, CG rendering style, color palette, lighting, camera framing, canvas size, and alpha/transparent background when present.
5. Change only the user-specified local area, such as eye state, small accessory, minor pose detail, hand/object contact, event prop, or emotion key frame.
6. Avoid full repainting, style reinterpretation, new character design, new outfit, new props, background changes, fake mouth overlays, fake blink overlays, or extra facial features unless explicitly requested.
7. Prefer a mask when the available image-editing path supports one. If no mask is available, specify the changed region precisely and ask the model to preserve all other areas as much as possible.
8. Save outputs non-destructively with a variant filename. Do not overwrite the approved base unless the user explicitly asks.

## Prompt Template

```text
Use case: identity-preserve / precise-object-edit
Input images: Image 1: edit target, approved Tumi base PNG.
Primary request: <the user's requested variant>
Critical instruction: Do not redraw the whole image. Local edit only. 不重繪，只局部修改。
Local change: Change only <specific region/detail>.
Preserve: Tumi's identity, face shape, nearly mouthless design, ears, body proportions, silhouette, CG style, lighting, color palette, camera framing, canvas size, and transparent background if present.
Avoid: full redraw, restyling, new outfit, new props, background change, mouth/lip animation, fake face overlays, extra characters, watermark, text.
Output: PNG variant consistent with Image 1.
```

## Escalate To Generate Only When Needed

Use fresh generation only when the user explicitly asks for a completely new pose, composition, outfit, environment, or art direction. Warn that this can reduce consistency with the approved base image.
