# UI & Motion Execution Protocol

動 UI、動畫、特效或視覺微調時的執行流程。**不可違反的核心原則寫在 `AGENTS.md`
的「UI / Motion 工程核心規則」**，這份是展開後的做法。

刻意保持短。這份文件本身也是每次任務的成本，太長就會被略讀。

---

## Phase 1 — Reality Check（動手前）

**目標是拿到「真實約束」，不是產出架構研究報告。** 幾個 grep 就該結束。

必須查明：

- 真實呼叫位置與 parent hierarchy
- **實際可用的 width / height**（往上追到 `Expanded` / `Flexible` / 格線 / padding）
- 真實的 l10n 字串（不是我隨手編的示意文字）
- **不同 state 下內容尺寸會不會變**——這是最常被忽略的一項
- `FittedBox`、`Stack` / `StackFit`、`Transform`、clipping
- `AnimatedSwitcher` 或 implicit animation 是否已經在作用
- Reduce Motion 要怎麼降級
- 動畫與音效的歸屬（誰負責觸發，避免兩處各播一次）

把算出來的數字寫下來，後面的 harness 與測試都用它。

## Phase 2 — Visual Contract

- 使用者已經描述了要什麼 → **嚴格照做**，不要「順便做得更漂亮」。
- 規格足以實作 → 直接實作，不要先生一堆方案。
- 規格真的不足以實作 → **問一句**，不要用四套自製方案代替提問。

## Phase 3 — Minimal Implementation

- 最小合理改動；保留既有架構。
- 可行時把呈現層隔離成獨立 widget（外部只餵狀態，widget 不持有商業邏輯）。
- 一段演出用**一條** timeline，時間點集中成常數，不要散在各處寫分數。
- 不做無關重構、不做預先抽象。
- **不要 hardcoded 補償**，除非那個數字本身就是刻意的設計值（並寫清楚為什麼）。

## Phase 4 — Verification Fidelity

Preview / harness / widget test 的環境必須夠接近 production，至少對齊：

**width、height、真實文案、textScale、parent constraints、state、theme、l10n。**

> ⚠️ 寬鬆的環境會讓 bug 消失。**約束放寬 = 把要驗的東西驗掉了。**

約束不同時，不得用 preview 的成功宣稱 production 已修好。回報時一併寫出
驗證環境的實際參數。

## Phase 5 — Failure Escalation

| 第幾次 | 該做什麼 |
|---|---|
| 第 1 次失敗 | 修最可能的直接原因 |
| 第 2 次同症狀 | **重新驗證原本的假設**，不要換個參數再試 |
| 第 3 次之前 | **強制觸發 Two-Failure Root-Cause Rule** |

禁止進入 `offset → padding → alignment → transform → 又一個 offset` 的補償迴圈。

觸發時必須先回答：

1. 我現在認為根因是什麼？
2. 有什麼證據支持？
3. 什麼觀察可以推翻這個假設？
4. **能不能用一個修正同時解釋所有症狀？**
5. 如果不能 → 代表還沒找到根因，繼續找。

## Phase 6 — Efficient Validation

- 開發時只跑最相關的測試；完整 regression 留到最後一關。
- **可以自動化的視覺量測不要人工重複做。** 同一套錄影 / 抽格 / 對時流程重複超過
  兩次，就寫成可重用腳本。
- 截圖與抽格**合併成單張接觸表再看**，不要一張一張讀——讀圖很貴。
- 已經確認過的 layout 約束不要重算，除非有新證據推翻它。

## Phase 7 — Performance

**先量再改。** 不要憑直覺假定瓶頸是 blur、`CustomPainter`、rebuild 或
animation controller 之中的哪一個。

做法：寫一支對照 harness（靜態基準線 vs 演出中）拿到每幀數字 → 一項一項拆掉
驗證 → 前後各跑數次取最小值（機器有負載時單次可以差 5 倍）。

---

## Definition of Done

UI / Motion 任務要全部成立才算完成：

- [ ] 在 **production 約束**下正確
- [ ] 真實 l10n 字串下正確
- [ ] state 轉換正確
- [ ] 沒有不必要的位置／尺寸跳動
- [ ] Reduce Motion 有合理降級（若適用）
- [ ] 相關測試通過
- [ ] **沒有堆積症狀式補償**
- [ ] 能清楚解釋「為什麼這樣做」

---

## Historical note

2026-08-08 `UnlockMorphButton`：preview 用 140pt、production 實際約 84.75pt，
`FittedBox` 的 `scaleDown` 因此在兩邊行為不同，導致多輪錯誤的視覺判斷與
「測試綠燈但實機仍有問題」。Reality Check、Verification Fidelity 與
Two-Failure Root-Cause Rule 由此事件建立。
