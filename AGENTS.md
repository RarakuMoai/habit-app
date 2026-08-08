# Codex 專案入口

保持這份檔案短小。只在任務碰到對應領域時，才讀詳細規則，避免把歷史決策與
無關限制一次塞進工作上下文。

## 開始工作

- 產品方向、優先順序：讀 `docs/roadmap.md`。程式現況以 repo 為準；roadmap 是策略，
  不是已完成功能清單。
- **視覺或體驗要做成什麼樣：直接問使用者，不從文件推導。** 這裡刻意沒有常駐的
  「品牌升級方向」文件——2026-08-06 移除，因為那份文件只寫了原則沒寫目標，
  結果是產出一堆使用者感覺不到的微調。目標由使用者當場給，做完用實機截圖給
  使用者裁決。技術護欄仍以 `docs/engineering_guardrails.md` 為準。
- 兔咪性格、說話原則：讀 `docs/tumi_character_guide.md`（含「三種聲音」規則）。
- **調整兔咪的對話或反應行為**（台詞、表情、泡泡、語音、觸發條件、優先度）：
  先讀 `docs/tumi_dialogue_catalog.md` 的事件總表，**先進表再寫程式**；改完
  跑 `flutter test test/mascot_test.dart`，沒進表的新情境與違規台詞都會被擋。
- 修改單位、偏好儲存、音訊、視覺或兔咪素材前：讀
  `docs/engineering_guardrails.md` 的對應小節。
- 既有兔咪 PNG/CG 的差分或表情編輯：必須使用 repo skill
  `tumi-image-variants`，以核准底圖做局部修改。

## UI / Motion 工程核心規則

動 UI、動畫、特效或視覺微調時**一律適用**，不可違反。詳細流程見
`docs/ui_motion_protocol.md`（開工前讀，那份短）。

- **先確認真實 production 約束，不要只相信 preview、mock 或孤立的 widget。**
  必須查明真實 parent layout、實際可用寬高、真實文案（含 l10n），以及
  `Expanded` / `Flex` / `FittedBox` / `Stack` / `Transform` 這些會改變版面的因素。
- **Preview 與 test harness 必須重現 production 的尺寸、約束與真實字串。**
  約束不同就不能拿 preview 的成功證明 production 修好了。
- **小型 UI 任務走 minimal change**：不主動重構、不擴大範圍、不碰無關的商業邏輯。
- **視覺規格由使用者決定。** 除非被要求，不要自行設計多套特效讓使用者挑。
  規格足以實作就直接做。
- **一次只改一個可驗證的視覺問題。**
- 開發期只跑相關測試，完整 suite 留到提交前的最後一關。

**Two-Failure Root-Cause Rule**
同一個可觀察的問題連續改兩次仍未真正解決 → **第三次禁止再用 offset、padding、
alignment、duration、curve、Transform 或任何局部補償做試誤**。必須停止修改，
改成找根因：重新確認 production 約束、parent/child 版面關係、intrinsic size、
不同 state 下的尺寸變化、文案長度與 l10n、Expanded/Flex、FittedBox、Stack fit、
clipping、動畫歸屬、rebuild 邊界、preview 與 production 是否一致。
找到**能解釋所有症狀**的根因之後才能繼續改。

**Evidence Before Confidence**
- 不要因為 preview、單一測試或某個數值量測正常就宣稱問題解決了。
- **宣告「已驗證」時必須同時寫出驗證環境的實際參數**（寬度、文案、state）。
  「在 140pt 下量測無位移」和「無位移」是兩件事，後者會誤導使用者。
- 使用者回報實機仍有問題 → **視為假設已被推翻**，優先回頭檢查驗證環境，
  不要辯護原本的量測結果。

## 工作流程

- 修改後做與風險相稱的檢查；Flutter 程式至少跑 `flutter analyze`，相關測試優先，
  準備提交前再視改動範圍跑完整 `flutter test`。
- Codex 禁止對實體 iPhone / iPad 執行安裝、啟動或 `flutter run`（包含有線與無線）；
  需要執行環境時只使用 Mac 上的 iOS 模擬器，實機驗證由使用者本人處理。
- 每次 commit 後自動執行 `git push`，不需再詢問使用者；若執行環境要求外部操作
  授權，依環境規則處理。
- 不手動執行完工通知腳本。通知交給 Codex CLI 的 `notify` hook，避免重複通知。
- 對可能變動的外部資訊（版本、價格、規格、政策等）直接查最新官方資料，不靠記憶猜。

## 文件原則

- 長期硬規則才放入口文件；階段任務、實驗方案與一次性 prompt 留在各自文件。
- 舊計畫保留時必須清楚標示「歷史／已完成」，不得與現行方向並列成有效指令。
- 發現文件與程式不一致時先指出；可由 repo 證實的現況直接修正，會改變產品方向的
  選擇再詢問使用者。
