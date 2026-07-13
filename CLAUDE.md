# Claude 專案入口

這裡只保留工作入口。不要把所有領域規則一次載入；任務碰到哪一類，再讀對應文件。

## 必要脈絡

- 產品方向與優先順序：`docs/roadmap.md`（策略來源；實作現況仍以 repo 為準）。
- 兔咪性格與台詞：`docs/tumi_character_guide.md`。
- 單位、SharedPreferences、音訊、視覺、兔咪素材：
  `docs/engineering_guardrails.md` 的相關小節。
- 既有兔咪圖的差分必須以核准底圖做局部修改，不重繪整張。

## 工作流程

- 修改後做與風險相稱的 analyze / test；準備提交前確認 diff 沒有暫存檔或產物。
- 每次 commit 後自動 `git push`，不需再詢問使用者。
- 不手動執行通知腳本；使用 `.claude/settings.local.json` 的 Stop / Notification hooks。
- 版本、規格、價格、政策等可能過時的資訊，查最新官方來源後再回答。

## 維護原則

- 可由程式證實的現況直接更新文件；會改變產品方向的選擇才詢問使用者。
- 已完成或被取代的任務書要標成歷史文件，不再當成現行指令。
