# Tumi Mascot Asset Classification

This is a planning inventory for generated Tumi candidates. None of these candidate files are wired into the app yet.

## Count Summary

| Group | Count | Notes |
| --- | ---: | --- |
| Official core PNG files | 8 | 7 main usable CG emotions + 1 blink. `streak` is still missing in official core. |
| High-confidence sprite candidates | 19 | Best current pool for new expression sprites. White-background RGB drafts. |
| Needs-review sprite candidates | 2 | Usable direction, but expression/anatomy may feel too intense or odd. |
| Manual-cleanup sprite candidates | 3 | Character direction can work, but shadow/feet cleanup needs human work. |
| High-confidence event CG candidates | 5 | Scene-based square CGs, separate from sprite emotions. |
| Rejected generated candidates | 2 | Keep only as negative reference. |
| Contact sheets | 2 | Review-only thumbnails, not character assets. |

Total image files under `assets/mascot/`: 41 PNG files.

Practical review pool, excluding rejected/contact sheets: 37 images.

Best first-pass pool, excluding needs-review/manual-cleanup/rejected/contact sheets: 32 images.

## Companion Mascot Rules

Tumi is a companion, not a coach or judge.

Use expressions that feel:

- cute
- soft
- patient
- nonjudgmental
- sleepy or gently pleased
- proud of small progress

Avoid expressions that feel:

- angry
- strict
- disappointed in the user
- panicked
- overexcited
- human-like
- visually uncanny

If an expression risks pressuring the user, use a calmer candidate or the official neutral/sleep/smile asset instead.

## Official Core

| Emotion | File | Use Case | Pressure Risk |
| --- | --- | --- | --- |
| neutral | `assets/mascot/core/tumi_neutral_front.png` | open app, default, empty state fallback | Low |
| neutral blink | `assets/mascot/core/tumi_neutral_front_blink.png` | idle blink only | Low |
| sleep | `assets/mascot/core/tumi_sleep.png` | not started, quiet waiting, rest | Low |
| expect | `assets/mascot/core/tumi_expect.png` | started, halfway anticipation | Low |
| smile | `assets/mascot/core/tumi_smile.png` | completed one, gentle approval | Low |
| happy | `assets/mascot/core/tumi_happy.png` | all done, happy reward | Low |
| sad | `assets/mascot/core/tumi_sad.png` | undo, missed habit, soft concern | Medium if overused |
| night | `assets/mascot/core/tumi_night.png` | late night, rest reminder | Low |

## Recommended Sprite Candidates

These are the most useful high-confidence candidates. They should be reviewed first.

| Category | Emotion | File | Best Use Case | Pressure Risk |
| --- | --- | --- | --- | --- |
| Default / invite | empty_invite | `high_confidence/tumi_empty_invite_candidate_v1.png` | no habits yet, invite user to start | Low |
| Default / waiting | waiting_soft | `high_confidence/tumi_waiting_soft_candidate_v1.png` | not started, app idle, no rush | Low |
| Sleep / wake | wake | `high_confidence/tumi_wake_candidate_v1.png` | first action after idle, morning, gentle wake-up | Low |
| Sleep / rest | deep_sleep | `high_confidence/tumi_deep_sleep_candidate_v1.png` | late idle, rest, deep sleep state | Low |
| Focus | focus_soft | `high_confidence/tumi_focus_soft_candidate_v1.png` | timer running, quiet concentration | Low |
| Timer done | timer_done_tired | `high_confidence/tumi_timer_done_tired_candidate_v1.png` | focus timer finished, soft tired satisfaction | Low |
| Small win | proud | `high_confidence/tumi_proud_candidate_v1.png` | one meaningful completion, gentle pride | Low |
| Big win | pop_happy | `high_confidence/tumi_pop_happy_candidate_v1.png` | all done, small celebration | Low to Medium if overused |
| Streak | streak_clean | `high_confidence/tumi_streak_clean_candidate_v1.png` | streak milestone, quiet victory | Medium; avoid making it feel demanding |
| Progress | progress_gentle | `high_confidence/tumi_progress_gentle_candidate_v1.png` | weight/health progress, body-positive nudge | Low |
| Water | hydrated_happy | `high_confidence/tumi_hydrated_happy_candidate_v1.png` | water goal reached | Low |
| Comeback | comeback | `high_confidence/tumi_comeback_candidate_v1.png` | user returns after some absence | Low |
| Restart | relieved_restart | `high_confidence/tumi_relieved_restart_candidate_v1.png` | missed/undone habit, restarted gently | Low |
| Down | down | `high_confidence/tumi_down_candidate_v1.png` | soft low mood, nonjudgmental comfort | Medium if shown too often |
| Question | question_clean | `high_confidence/tumi_question_clean_candidate_v1.png` | overhydration, unusual input, gentle concern | Medium; keep copy soft |
| Tap reaction | tap_shy | `high_confidence/tumi_tap_shy_candidate_v1.png` | tapping Tumi, shy reaction | Low |
| Wardrobe | wardrobe_shy | `high_confidence/tumi_wardrobe_shy_candidate_v1.png` | wardrobe/skin preview | Low |
| Music / room | relaxed_sway | `high_confidence/tumi_relaxed_sway_candidate_v1.png` | music box, room ambience, calm idle | Low |
| Legacy worried | streak_no_shadow | `high_confidence/tumi_streak_candidate_v1_no_shadow.png` | visually reads as worried/question, not streak | Medium; filename is misleading |

## Needs Review

| Emotion | File | Concern | Suggested Decision |
| --- | --- | --- | --- |
| focus | `needs_review/tumi_focus_candidate_v1.png` | eyebrows feel too strict/angry | Prefer `focus_soft` unless user approves this intensity. |
| burst | `needs_review/tumi_burst_candidate_v1.png` | happy emotion works, but legs/feet look odd | Prefer `pop_happy` unless feet are manually fixed. |

## Manual Cleanup

| Emotion | File | Why It Needs Human Cleanup | Suggested Use |
| --- | --- | --- | --- |
| worried/shy | `manual_cleanup/tumi_streak_candidate_v1.png` | bottom/background cleanup needed; filename is misleading | Could become question/worried if cleaned. |
| streak/raised-paw | `manual_cleanup/tumi_worried_candidate_v1.png` | foot shadow remains; filename is misleading | Could become streak if manually cleaned. |
| streak/raised-paw edited | `manual_cleanup/tumi_worried_candidate_v1_no_shadow.png` | cleanup still leaves visible artifacts | Use only after hand cleanup. |

## Event CG Candidates

Event CGs are scene art, not sprite emotions. Use sparingly for milestone moments.

| Event | File | Best Use Case | Pressure Risk |
| --- | --- | --- | --- |
| First habit | `event_cg/high_confidence/event_first_habit_candidate_v1.png` | first habit created | Low |
| First all done | `event_cg/high_confidence/event_first_all_done_candidate_v1.png` | first day all habits completed | Low |
| 7-day streak | `event_cg/high_confidence/event_7_day_streak_candidate_v1.png` | streak milestone | Medium; copy must not imply obligation |
| Late night | `event_cg/high_confidence/event_late_night_candidate_v1.png` | late-night companion/rest moment | Low |
| Long-time return | `event_cg/high_confidence/event_long_time_return_candidate_v1.png` | user returns after absence | Low |

## Suggested Emotional System

For the app, keep the active emotional vocabulary smaller than the asset pool.

Recommended daily set:

- neutral
- waiting_soft
- sleep
- wake
- focus_soft
- smile
- proud
- pop_happy
- down
- question_clean
- night

Recommended special set:

- streak_clean
- comeback
- relieved_restart
- deep_sleep
- tap_shy
- wardrobe_shy
- hydrated_happy
- progress_gentle
- relaxed_sway

Recommended event set:

- event_first_habit
- event_first_all_done
- event_7_day_streak
- event_late_night
- event_long_time_return

## Pressure-Safe Usage Notes

- Use `down` and `question_clean` as care signals, not failure signals.
- Avoid showing `streak_clean` too often; streak should feel like a pleasant surprise.
- Prefer `waiting_soft` over `sad` when the user simply has not started.
- Prefer `relieved_restart` over `sad` after the user comes back.
- Prefer `focus_soft` over the older `focus` candidate.
- Prefer `pop_happy` over the older `burst` candidate.
- Event CG should appear rarely, at meaningful moments, so it feels special rather than gamified pressure.
