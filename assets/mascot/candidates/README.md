# Tumi Mascot Candidates

These files are generated candidate assets only. They are not wired into the app.

For the full emotion/use-case inventory, see `CLASSIFICATION.md`.

For the first-phase 16 high-frequency states with English/Chinese mapping, see `HIGH_FREQUENCY_16_STATES.md`.

For the Chinese ideal 36-state plan, see `STATE_PLAN_ZH.md`.

## Folders

- `high_confidence/`: strong candidates worth reviewing first.
- `needs_review/`: usable direction, but expression or anatomy needs human review.
- `manual_cleanup/`: character direction is acceptable, but shadow or bottom cleanup needs manual work.
- `event_cg/high_confidence/`: event CG candidates with simple scene backgrounds.
- `contact_sheets/`: review-only thumbnail sheets.
- `rejected/`: not a usable direction for the current Tumi style.

## Current Notes

- Current high-confidence sprite candidates: 19.
- Current high-confidence event CG candidates: 5.
- `high_confidence/tumi_streak_candidate_v1_no_shadow.png` is historically misnamed; visually it reads more like worried/question than streak.
- `manual_cleanup/tumi_worried_candidate_v1.png` is historically misnamed; visually it reads more like streak/raised-paw.
- All current generated candidates are white-background RGB drafts, not final `1024x1024` RGBA app assets.
- Manual cleanup is most useful for bottom shadows and feet-edge cleanup. Avoid repainting Tumi's face or body unless explicitly needed.
