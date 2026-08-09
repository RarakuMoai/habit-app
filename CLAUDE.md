# Claude 專案入口

**工程規則與文件原則以 `AGENTS.md` 為準**——那份是所有 agent 共用的規則來源，
只維護一份，避免兩邊不同步。本檔只放「每次都適用」與「Claude 專屬的差異」。

## 需要時才讀（不要一次全載入）

- 產品方向：`docs/roadmap.md` **只有「現況快照／已完成記錄」仍然有效**；
  變現、排程、功能排序那幾節已標為歷史參考，不要當現行決策——需要方向時直接問使用者。
- 世界觀（這是哪裡、誰住在裡面、東西為什麼存在）：`docs/world_setting.md`。
  動到場景、引導頁、劇情、金幣／造型／回憶本的語彙前必讀。
- 兔咪性格與說話原則：`docs/tumi_character_guide.md`。
- 動到兔咪的對話或反應（台詞／表情／泡泡／語音／觸發）：先讀
  `docs/tumi_dialogue_catalog.md` 的事件總表，先進表再寫程式。
- 單位、SharedPreferences、音訊、視覺、兔咪素材：
  `docs/engineering_guardrails.md` 的對應小節。

## 每次都適用

- 修改後做與風險相稱的檢查：Flutter 至少跑 `flutter analyze`，相關測試優先，
  準備提交前視改動範圍跑完整 `flutter test`；確認 diff 沒有暫存檔或產物。
- 每次 commit 後自動 `git push`，不需再詢問使用者。
- 不手動執行通知腳本；通知交給 `.claude/settings.local.json` 的
  Stop / Notification hooks。（`AGENTS.md` 那條講的是 Codex CLI 的 notify hook。）
- 版本、規格、價格、政策等可能過時的資訊，查最新官方來源後再回答。

## Claude 專屬差異

- 兔咪 PNG／CG 的差分或表情編輯：規範在
  `.agents/skills/tumi-image-variants/SKILL.md`。**那是 Codex 的 skill 目錄，
  我不能用 Skill 工具呼叫它，要自己 Read 那份檔案再照做。**
  一律以核准底圖做局部修改，不重繪整張。
- `AGENTS.md` 對 Codex 的「禁止碰實體 iPhone／iPad」不適用於我；但開模擬器或
  `flutter run` 前要先問使用者。
- 長期偏好、決策記錄與踩雷寫在自動記憶（`MEMORY.md`），本檔不重複。
