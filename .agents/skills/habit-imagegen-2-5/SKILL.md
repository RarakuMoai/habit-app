---
name: habit-imagegen-2-5
description: Generate or edit raster art for habit-app with a verifiable GPT Image 2.5 workflow. Use for Tumi covers, CG/event art, logos, sprites, room scenes, transparent cutouts, and precise image revisions. Do not use the unverifiable built-in image tool for production candidates.
---

# Habit App Image 2.5

The user selected the explicit API/model path for habit-app artwork. For production candidates, use `gpt-image-2.5-sunburst` at `max` quality through [run_image_2_5.py](scripts/run_image_2_5.py). The wrapper calls the official Images API directly so an older bundled CLI cannot silently apply GPT Image 2 validation rules.

Do not use the built-in `image_gen` wrapper unless its callable schema exposes a model selector, accepts `gpt-image-2.5-sunburst`, and exposes the requested background mode. A prompt that merely says "transparent background" is not proof of true transparency.

## Workflow

1. Decide whether this is a new composition (`generate`) or a local revision (`edit`). If any approved image must remain recognizable, use `edit`.
2. Inspect every input image first. Label Image 1 as the edit target; label any other images as references or supporting inputs.
3. Put the complete prompt in a UTF-8 text file. For edits, describe one local change and list the invariants that must remain unchanged.
4. Run the wrapper once with `--dry-run`. Confirm the printed request contains:
   - `model: gpt-image-2.5-sunburst`
   - `quality: max`
   - the intended endpoint and output path
   - `background: transparent` for cutouts, or `opaque` for full-scene art
   - `output_format: png`
5. Run the same command without `--dry-run`. The API path requires `OPENAI_API_KEY` to be set locally; never ask the user to paste the key into chat.
6. Keep the source and result non-destructive. Never overwrite an approved asset; create a versioned sibling file.
7. Treat the result as a production candidate only when the wrapper succeeds and writes the adjacent `.generation.json` provenance file.
8. For transparent output, the validator must report both an alpha channel and at least one pixel with alpha below 255. A checkerboard painted into RGB is a failed output, not transparency.
9. Visually review subject identity, unwanted objects, edge contamination, layout space for UI, and the exact requested local change. Passing file validation is not visual approval.

If the API key is unavailable and the user asks to use Chrome, the browser path is acceptable only after the visible ChatGPT interface confirms Image 2.5 for that generation/edit. Use the editor's selection area for local revisions, download the original PNG, and run `verify_png.py` before accepting transparent output. If the model cannot be confirmed, stop instead of claiming the result came from 2.5.

## Commands

Generate an opaque cover or event CG:

```bash
python3 .agents/skills/habit-imagegen-2-5/scripts/run_image_2_5.py generate \
  --prompt-file path/to/prompt.txt \
  --size 1024x1536 \
  --background opaque \
  --out path/to/cover-v1.png \
  --dry-run
```

Precisely edit an existing image:

```bash
python3 .agents/skills/habit-imagegen-2-5/scripts/run_image_2_5.py edit \
  --prompt-file path/to/prompt.txt \
  --image path/to/edit-target.png \
  --mask path/to/mask.png \
  --size 1024x1536 \
  --background opaque \
  --out path/to/edited-v2.png \
  --dry-run
```

Generate a true transparent PNG:

```bash
python3 .agents/skills/habit-imagegen-2-5/scripts/run_image_2_5.py generate \
  --prompt-file path/to/prompt.txt \
  --size 1024x1024 \
  --background transparent \
  --out path/to/logo-v1.png \
  --dry-run
```

Remove `--dry-run` only after checking the request. The wrapper fixes the model, quality, and PNG format; callers cannot downgrade them.

## Editing Rules

- Use a mask when the change can be localized. The mask and first image must be PNG files with identical dimensions; the mask must contain real transparency.
- A mask guides the model but is not a pixel-exact boundary. Re-check areas outside the mask after generation.
- Make one targeted change per call. If a second issue remains, edit the accepted result in a new call.
- If the API model is unavailable, authentication is missing, or validation fails, stop and report the blocker. Do not silently fall back to GPT Image 2, a fake checkerboard, or local background removal.

For Tumi identity and prompt invariants, also read [tumi-image-variants](../tumi-image-variants/SKILL.md).

## Official References

- [GPT Image 2.5 Sunburst model](https://developers.openai.com/api/docs/models/gpt-image-2.5-sunburst)
- [Images API reference](https://developers.openai.com/api/reference/resources/images)
- [Image generation and mask guidance](https://developers.openai.com/api/docs/guides/image-generation)
