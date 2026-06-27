# 兔咪高頻 16 狀態英中對照

目前先不處理事件 CG。第一階段只需要把高頻 16 種立繪狀態整理好，讓 App 日常互動先穩定、可愛、低壓力。

## 原則

- 兔咪是陪伴型吉祥物，不是教練。
- 表情要可愛、柔軟、低壓力。
- 不要生氣、嚴厲、失望、過度熱血或詭異人臉。
- 低落類表情只能表達「我還在」，不能表達「你失敗了」。

## 16 狀態

| # | English key | 中文狀態 | 使用場合 | 目前建議來源 |
| ---: | --- | --- | --- | --- |
| 1 | `neutral_front` | 安靜預設 | 打開 App、一般待機、預設表情 | `assets/mascot/core/tumi_neutral_front.png` |
| 2 | `sleep` | 打瞌睡 | 今天還沒開始、兔咪懶懶等你 | `assets/mascot/core/tumi_sleep.png` |
| 3 | `waiting_soft` | 等你但不催 | 還沒開始，但不給壓力 | `assets/mascot/candidates/high_confidence/tumi_waiting_soft_candidate_v1.png` |
| 4 | `empty_invite` | 邀請開始 | 還沒有習慣，邀請新增第一個小習慣 | `assets/mascot/candidates/high_confidence/tumi_empty_invite_candidate_v1.png` |
| 5 | `wake` | 剛醒 | 使用者開始行動，兔咪被喚醒 | `assets/mascot/candidates/high_confidence/tumi_wake_candidate_v1.png` |
| 6 | `expect` | 開始期待 | 使用者完成第一步、進度開始動 | `assets/mascot/core/tumi_expect.png` |
| 7 | `focus_soft` | 專注陪伴 | 計時器、專注中、陪你做事 | `assets/mascot/candidates/high_confidence/tumi_focus_soft_candidate_v1.png` |
| 8 | `smile` | 輕微微笑 | 完成一件習慣，小小肯定 | `assets/mascot/core/tumi_smile.png` |
| 9 | `proud` | 小小驕傲 | 做到有意義的一步，兔咪替你開心 | `assets/mascot/candidates/high_confidence/tumi_proud_candidate_v1.png` |
| 10 | `happy` | 開心 | 今日全部完成、普通完成獎勵 | `assets/mascot/core/tumi_happy.png` |
| 11 | `pop_happy` | 非常開心 | 全部完成或特殊小慶祝，但不要太吵 | `assets/mascot/candidates/high_confidence/tumi_pop_happy_candidate_v1.png` |
| 12 | `streak_clean` | 連續達成 | 連勝、連續回來、里程碑 | `assets/mascot/candidates/high_confidence/tumi_streak_clean_candidate_v1.png` |
| 13 | `down` | 有點低落 | 沒完成、撤銷、需要陪伴，但不責備 | `assets/mascot/candidates/high_confidence/tumi_down_candidate_v1.png` |
| 14 | `question_clean` | 疑問／擔心 | 輸入異常、喝水過量、溫柔提醒 | `assets/mascot/candidates/high_confidence/tumi_question_clean_candidate_v1.png` |
| 15 | `night` | 夜晚小聲 | 深夜打開 App、提醒休息也可以 | `assets/mascot/core/tumi_night.png` |
| 16 | `tap_shy` | 點擊害羞 | 使用者點兔咪時的短暫反應 | `assets/mascot/candidates/high_confidence/tumi_tap_shy_candidate_v1.png` |

## 情緒梯度

### 快樂

| English key | 中文 | 強度 |
| --- | --- | --- |
| `smile` | 輕微微笑 | 低 |
| `proud` | 小小驕傲 | 中低 |
| `happy` | 開心 | 中 |
| `pop_happy` | 非常開心 | 中高 |
| `streak_clean` | 連續達成 | 特殊，不要高頻 |

### 低落／安撫

| English key | 中文 | 語氣 |
| --- | --- | --- |
| `waiting_soft` | 等你但不催 | 我在等你，不急 |
| `down` | 有點低落 | 沒關係，我還在 |
| `question_clean` | 疑問／擔心 | 我有點擔心，但不責備 |
| `night` | 夜晚小聲 | 累了也可以休息 |

## 暫時不放入第一階段

以下狀態先不列入高頻 16，但可以保留候選：

| English key | 中文 | 原因 |
| --- | --- | --- |
| `deep_sleep` | 熟睡 | 可作第二階段 idle/rest 狀態 |
| `timer_done_tired` | 專注完成小疲憊 | 功能專用，第一階段可先用 `proud` 或 `smile` |
| `hydrated_happy` | 喝水達標 | 功能專用 |
| `progress_gentle` | 健康小進步 | 功能專用 |
| `relaxed_sway` | 音樂放鬆 | 功能專用 |
| `wardrobe_shy` | 換裝害羞 | 功能專用 |
| `comeback` | 你回來了 | 特殊情境 |
| `relieved_restart` | 重新開始的安心 | 特殊情境 |

## 不建議第一階段使用

| English key | 中文 | 原因 |
| --- | --- | --- |
| `focus` | 舊版專注 | 眉毛偏兇，可能有壓力 |
| `burst` | 舊版爆開心 | 腳部怪，建議用 `pop_happy` |
| `event_*` | 事件 CG | 第一階段先不需要 CG |
