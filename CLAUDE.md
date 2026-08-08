# Claude 專案入口

**工程規則與文件原則以 `AGENTS.md` 為準**——那份是所有 agent 共用的規則來源，
只維護一份，避免兩邊不同步。本檔只放「每次都適用」與「Claude 專屬的差異」。

## 需要時才讀（不要一次全載入）

- 產品方向：`docs/roadmap.md` 只放**現況快照與紅線**（策略段已於 2026-08-06
  刪除）。**需要方向時直接問使用者，不要從文件推導。**
- **視覺或體驗要做成什麼樣：也是直接問使用者。** 這裡刻意沒有常駐的品牌方向
  文件，理由寫在 `AGENTS.md`；做完用實機截圖給使用者裁決。
- **動 UI、動畫、特效或視覺微調：開工前讀 `docs/ui_motion_protocol.md`**（很短）。
  不可違反的核心原則在 `AGENTS.md` 的「UI / Motion 工程核心規則」——包含
  Two-Failure Root-Cause Rule 與 Evidence Before Confidence。
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
- **UI／動畫的三個硬觸發。** 全文在 `AGENTS.md`「UI / Motion 工程核心規則」，
  這裡只放「什麼時候該停下來」——因為這三個時機都不是我會主動去翻文件的時機：
  1. **開工前**：先算出真實 production 約束（往上追 Expanded／格線／padding／
     FittedBox）與真實 l10n 字串，preview 與測試都用那組數字。
  2. **同一症狀改兩次仍沒解決**：第三次禁止再調 offset／padding／curve 試誤，
     停下來找能解釋**所有**症狀的根因（Two-Failure Root-Cause Rule）。
  3. **回報時**：宣告「已驗證」要一併寫出驗證環境的實際參數；使用者說實機仍有
     問題，優先懷疑驗證環境，不要辯護原本的量測結果。

## Claude 專屬差異

- 兔咪 PNG／CG 的差分或表情編輯：規範在
  `.agents/skills/tumi-image-variants/SKILL.md`。**那是 Codex 的 skill 目錄，
  我不能用 Skill 工具呼叫它，要自己 Read 那份檔案再照做。**
  一律以核准底圖做局部修改，不重繪整張。
- `AGENTS.md` 對 Codex 的「禁止碰實體 iPhone／iPad」不適用於我。**開 iOS 模擬器
  與 `flutter run` 也不必先問**（2026-08-08 解禁）——動效與版面這類東西不跑起來
  就驗不了，該開就開。實體裝置仍由使用者自己處理。
- 長期偏好、決策記錄與踩雷寫在自動記憶（`MEMORY.md`），本檔不重複。
