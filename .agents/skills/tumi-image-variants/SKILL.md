---
name: tumi-image-variants
description: Edit approved Tumi / 兔咪 PNG or CG images into local variants while preserving identity. Use for image edits, not dialogue or reaction-code changes.
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
4. Preserve Tumi identity and all properties outside the requested change: face shape, almost-no-mouth design, ears, body proportions, silhouette, CG rendering style, color palette, lighting, camera framing, canvas size, and alpha/transparent background when present. Do not lock a property that the user explicitly asks to edit.
5. Change only the user-specified local area, such as eye state, small accessory, minor pose detail, hand/object contact, event prop, or emotion key frame.
6. Avoid full repainting, style reinterpretation, new character design, new outfit, new props, background changes, fake mouth overlays, fake blink overlays, or extra facial features unless explicitly requested.
7. Prefer a mask when the available image-editing path supports one. If no mask is available, specify the changed region precisely and ask the model to preserve all other areas as much as possible.
8. Save outputs non-destructively with a variant filename. Do not overwrite the approved base unless the user explicitly asks.
9. Compare the result with the base at the same scale. Check the requested edit and unintended changes to identity, framing, and transparency; show the candidate and disclose remaining differences. Generation alone does not establish approval or App integration.

## Prompt Template

Adapt the preservation and exclusion fields to the request; for example, a requested outfit change must not also be forbidden by the prompt.

```text
Use case: identity-preserve / precise-object-edit
Input images: Image 1: edit target, approved Tumi base PNG.
Primary request: <the user's requested variant>
Critical instruction: Do not redraw the whole image. Local edit only. 不重繪，只局部修改。
Local change: Change only <specific region/detail>.
Preserve: Tumi's identity and <properties outside the requested edit>.
Avoid: full redraw, <unrequested changes or additions>.
Output: PNG variant consistent with Image 1.
```

## Escalate To Generate Only When Needed

Fresh generation is outside this local-variant workflow. When the user explicitly requests a completely new pose, composition, outfit, environment, or art direction, use the imagegen workflow and retain the relevant Tumi identity constraints. A new outfit request alone does not require redrawing the character; prefer editing the approved base when it can achieve the request. Explain consistency limitations when fresh generation is needed.
