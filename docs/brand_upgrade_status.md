# 品牌升級現況與下一個 Gate

> 這是會持續更新的執行狀態，不是長期產品聖經。品牌升級的固定規則看
> [`brand_upgrade_operating_system.md`](brand_upgrade_operating_system.md)。
>
> 最後核對：2026-08-04，repository `main`。

## 現行總控狀態

| 項目 | 現況 |
|---|---|
| Repository | `/Users/yayoi991331/habit-app` |
| Remote | `https://github.com/RarakuMoai/habit-app.git` |
| main／origin/main | `6c5f4ba1c0588131e18f759525d592f3edbefafb` |
| 品牌升級前的可追溯程式基準 | `4994742196e9acf5b42e45b6aee43251a8e6c79d`（尚未建立 tag／影像基準） |
| 最近完成 milestone | `One-Habit Hero` |
| Feature 最終 commit | `203788f53d19c30e53523c4e8309fd9b553098c0` |
| Merge commit | `6c5f4ba1c0588131e18f759525d592f3edbefafb` |
| 技術驗收 | Sol APPROVE；merge 前後 `flutter analyze` 0 issues、`flutter test` 794/794 |
| Production blocker | 0 |
| 當前階段 | milestone 之間；補完 One-Habit Hero 的品牌證據 |
| 下一個大型 milestone | **尚未決定，不得直接開工** |

Hash 與測試數是 2026-08-04 的核對結果；未來 main 前進時應更新，不得把舊 hash
誤認成必須回退的固定目標。

## 已完成並合併

### 全專案品質審查

- 已先執行只讀審查，再決定實作順序。
- 保留「不全面重寫、一次一個高影響子系統」的結論。

### Logical-Day Continuity

- 安全可重入的首頁載入。
- LogicalDayCoordinator 成為邏輯日生命週期唯一擁有者。
- dependent state、storage convergence 與失敗重試完成。
- Merge：`8e44576ba5143393344ad4333d612da31ecba0f0`。

### All-Done radial gradient crash hotfix

- 修正 radial gradient stops 數量錯誤造成的 runtime crash。
- Merge：`bc7dca78b514d735deb7f6423d0523ba5357d6d5`。

### One-Habit Hero — 技術部分

- 完成一件習慣的節奏已實作：confirm → notice → anticipate → impact → speak／
  milestone handoff → recover → quiet。
- 勾勾、兔咪動作、SFX、haptic、語意、half／allDone handoff 與 Reduced Motion 有
  共用因果時間線。
- 快速連打、Undo、切頁、reload、logical day、Persona／speech ownership 與外部
  priority 的 production blocker 已關閉。
- Feature 保持 12 個原始 commits，未 squash／rebase；Sol 最終獨立反例與正式
  794 項測試通過後合併 main。

## 尚未完成：One-Habit Hero 品牌閉環

技術 APPROVE 不等於 Creative APPROVE。目前缺少 Master Prompt 要求的兩個 gate：

### Gate 1 — Creative Proof（目前唯一下一步）

以相同模擬器、資料、尺寸與操作比較：

- 基準：`4994742196e9acf5b42e45b6aee43251a8e6c79d`
- 現況：`6c5f4ba1c0588131e18f759525d592f3edbefafb`
- 普通完成
- 跨過 half
- allDone
- 快速連打
- Undo
- Reduced Motion

至少從 Character、Motion、Audio、Emotion、Art 五個視角產出前後證據。這一輪只讀、
不修改 production code、不重新做 lifecycle 理論審查。使用者最後明確裁決：

- **KEEP**：品牌感明顯改善，進入 Bible extraction。
- **ADJUST**：只列可見、可聽、可感受的問題，回原 Opus milestone 對話修正。
- **REVERT／REDESIGN**：若新版主觀體驗反而較差，另行決定回退範圍；不得因測試多
  就強迫保留。

Codex 不得在實體 iPhone／iPad 安裝或執行 App；模擬器證據可由 Codex 準備，實機
手感、聲音與觸覺由使用者本人確認。

### Gate 2 — Bible Extraction

只有 Gate 1 得到 KEEP 後執行。把已被證明的規則寫回最接近的長期文件，至少涵蓋：

- anticipation → impact → recovery → quiet 的目的
- 兔咪先動、台詞後到
- impact 與使用者看到的完成事實同拍
- ordinary／half／allDone 的情緒層級
- SFX、haptic、語音與安靜的分工
- Reduced Motion 保留語意、移除不必要位移
- 高頻互動的克制與餘韻
- Creative gate 與 correctness gate 的分界

不要把目前 class 名稱、每一個 timer 數字或暫時 ownership 實作全部寫成不可更動的
產品規則；細節仍以程式與測試為真相。

## 下一個大型 milestone 的候選池

在兩個 gate 完成前只保留候選，不排序、不開分支：

1. 兔咪待機生命感
2. 每日回歸／開 App 的歡迎感
3. 第一套 Signature Outfit 與身份一致性驗證
4. 每日報到／零食回饋的 CG 一致性
5. 全 App 音效與安靜語言

Gate 2 完成後，使用原始只讀審查與當時的可見產品狀態，依「可察覺程度 × 改善幅度
× 成本／風險」選出唯一下一個 milestone。`roadmap.md` 的功能排序不能取代這次品牌
判斷。

## 現階段禁止事項

- 不重跑 Logical-Day、Gradient 或第一版 One-Habit Hero。
- 不因技術測試已通過就跳過 Creative Proof。
- 不同時啟動待機、造型、音效、回憶圖或 onboarding 素材。
- 不把新的 production correctness 探索偽裝成 Creative Proof。
- 不依賴聊天記憶決定下一步；必須先更新本文件。
- 不把 `roadmap.md` 尚未同步的舊「四時段首頁 pilot」當成下一步；
  `four_period_background_plan.md` 已記錄首頁及喝水、計時、家庭推廣完成。

## AI 分工（現行）

- **總控**：維持方向、判斷風險、產生下一個唯一 Prompt。
- **Opus 5**：架構設計與唯一主要實作者。
- **GPT-5.6 Sol**：獨立唯讀審查、品質驗收、決定能否合併。
- 每個 milestone 使用獨立工作對話與 feature branch。
- 同一 milestone 的 blocker 回原 Opus 對話。
- Sol 與 Opus 不得同時修改同一分支。
- Creative Proof 的最終品牌裁決者是使用者，不是任何模型。

## 每次 milestone 後如何更新本文件

1. 更新 main／origin/main 與 feature／merge hashes。
2. 將通過技術與 Creative gate 的項目移入「已完成並合併」。
3. 明列尚未完成的唯一 gate。
4. 更新測試基準，但不把測試數當成品牌品質分數。
5. 記錄使用者的 KEEP／ADJUST／REVERT 裁決。
6. Bible extraction 完成後，才允許選下一個大型 milestone。
