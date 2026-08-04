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
| main／origin/main | `8081a33bba1fd1515b54fc3fb6f04f2513d642d5` |
| 品牌升級前的可追溯程式基準 | `4994742196e9acf5b42e45b6aee43251a8e6c79d`（尚未建立 tag；影像基準見下方 Creative Proof） |
| 最近完成 milestone | `One-Habit Hero`（技術 gate 與 Creative gate 皆已通過） |
| Feature 最終 commit | `203788f53d19c30e53523c4e8309fd9b553098c0` |
| Merge commit | `6c5f4ba1c0588131e18f759525d592f3edbefafb` |
| 技術驗收 | Sol APPROVE；merge 前後 `flutter analyze` 0 issues、`flutter test` 794/794 |
| Creative 驗收 | 2026-08-04 使用者裁決 **KEEP** |
| Production blocker | 0 |
| 當前階段 | 進行中：`兔咪待機生命感`（branch `polish/idle-life`，**未 merge**） |
| 下一個大型 milestone | 已選定＝兔咪待機生命感；它結束前不選下一個 |

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

### One-Habit Hero

- 完成一件習慣的節奏已實作：confirm → notice → anticipate → impact → speak／
  milestone handoff → recover → quiet。
- 勾勾、兔咪動作、SFX、haptic、語意、half／allDone handoff 與 Reduced Motion 有
  共用因果時間線。
- 快速連打、Undo、切頁、reload、logical day、Persona／speech ownership 與外部
  priority 的 production blocker 已關閉。
- Feature 保持 12 個原始 commits，未 squash／rebase；Sol 最終獨立反例與正式
  794 項測試通過後合併 main。

#### Gate 1 — Creative Proof（2026-08-04 完成）

以 iPhone 14 Pro Max、430×932、zh-TW、場景時段固定 13:00、相同 6 個習慣與相同
音量設定，比較 baseline `4994742` 與 candidate `6c5f4ba`：普通完成、跨過 half、
allDone、快速連打、Undo、Reduced Motion 各錄前後對照。

**使用者裁決：KEEP。** 站得住的改善：

- 普通完成的 SFX／haptic 從「手指放開」移到勾勾筆尖觸底，語音與泡泡再晚一拍，
  因果讀得出來（baseline 是勾勾與台詞同一幀出現）。
- Undo 之後正向泡泡立刻讓位給心疼，不再與已歸零的進度並存。這是最清楚的情緒改善。
- allDone 不再與普通完成疊播，且修掉 baseline 的 completion-aura gradient paint
  例外（那個 painter 失敗在 baseline 每一相關 frame 都發生）。
- Reduced Motion 從「靠 framework 壓掉動畫」變成刻意設計的語意順序。

留作未來觀察，**不阻擋 KEEP、也不自動變成下一個 milestone**：

- 普通完成的 notice／anticipate 姿勢差異接近不可見門檻，逐幀圖上幾乎讀不到。
  要處理的話是微調停頓與 2–3px 姿態，不是加特效。
- half 在靜音下與普通完成的層級差距偏小，主要靠閉眼 expect pose 與音符。
- 連打時不重複說「今天第一件」是刻意的克制，但也降低了「每件都被口頭看見」。

證據限制（下次做 Creative Proof 要避開的坑）：

- half 的 A/B 逐幀對照表錨點抓晚，candidate 欄標成 contact 的那一幀件數已經跳完，
  **該張圖不能當 half 的證據**；影片本身沒問題。教訓已寫進 operating system §7。
- 模擬器錄影沒有可信系統音軌，音訊同步是用可見 frame 與 production 觸發時點推得，
  不是聲畫實測；音色、喇叭疲勞與真實 haptic 手感仍待實機確認。
- Reduced Motion 是從 platform dispatcher 注入的決定性 fallback，不是經由
  iOS Settings 端到端傳入的 runtime proof。
- 證據放在 `/private/tmp`，屬於暫存，不隨 repo 保存。

#### Gate 2 — Bible Extraction（2026-08-04 完成）

已被證明的規則寫回最接近的既有 Bible，沒有新增文件：

| 規則 | 落點 |
|---|---|
| 弧線七拍的意圖、衝擊點對齊看得到的事實、連打共用弧線 | `visual_spec.md` §動效／完成演出的節奏 |
| 先動起來才開口、層級克制、餘韻、撤銷讓位 | `tumi_character_guide.md` §演出節奏 |
| SFX／haptic／語音三管道職責、安靜是正式回饋、撤銷接手 | `tumi_dialogue_catalog.md` §執行規則 6–8 |
| Reduce Motion 保留語意、移除位移、時間從同一組常數推導 | `engineering_guardrails.md` §兔咪素材與演出 |
| Creative gate 與 correctness gate 的分界 | `brand_upgrade_operating_system.md` §5.5 |
| A/B 證據錨點要自己先驗過 | `brand_upgrade_operating_system.md` §7 |

毫秒數字一律不抄進文件，指向
`lib/pages/home/completion_timing.dart` 與 `completion_presentation_controller.dart`
檔頭時間軸。同時修正兩處文件與程式不同步：`visual_spec.md` 的勾勾時長 320ms →
300ms（實際走 `kCheckDrawDuration`），以及本文件的 main hash。

## 進行中：兔咪待機生命感

Branch `polish/idle-life`（從 `b74dd3a` 開出）。**技術 gate 還沒過，不得 merge。**
使用者已決定：先實作，等 Codex token 恢復後由它冷讀審查——這不是降級，
reviewer 沒看過實作者的推理過程本來就是它的價值來源，只是把 gate 往後移。
所以 commit 要切細、不 squash，晚來的審查才指得到具體位置。

### 情緒目標與範圍

兔咪在使用者盯著看、但沒有事件發生的時候，要像活的。**非目標**：不動打卡演出
（One-Habit Hero 已定案）、不動點擊／摸頭／充電互動、不加粒子或特效、
不動背景場景、不動 20 秒省電凍結。

### 已完成（各自可獨立 revert）

- `f029a2d` 依情緒的待機呼吸。改版前 13 個情緒共用 1300ms／0.013，睡著的兔咪和
  剛全完成的兔咪呼吸一模一樣。分組規則寫進 `MascotEmotion.idleBreath`：越睏越慢
  越深、越振奮越快越淺、低落慢而淺。
- `8f1aeb6` 冷啟動後回到依進度推導的待機姿。只回姿勢不動台詞——問候無期限是
  刻意設計，而且換日收拾的「只能收 state」不變量拿它當探針。

### 模擬器實測（14 Pro Max、430×932、0/6 進度）

不錄影：模擬器錄影幀率不穩，量不了時序。改連拍截圖後用 PIL 掃兔咪頭頂位置，
呼吸是以腳底為錨點的縱向縮放，頭頂位移最大。

| 項目 | 修改前 | 修改後 |
|---|---|---|
| 冷啟動 14 秒後的待機姿 | 睜眼中性臉 | 依進度推導（0 進度＝打瞌睡） |
| neutralFront 呼吸 | 峰谷 7px／週期 2.5s | 同（刻意不動） |
| sleep 呼吸 | 同 neutral | 峰谷 12px／週期 4.0s |

### 中途改過範圍，理由留在這裡

原本判斷「主瓶頸是呼吸共用參數」，**模擬器把它推翻了**。真實使用中兔咪根本走不到
依進度推導的姿勢，所以呼吸差異化幾乎看不到。修好待機姿之後它才有意義——
這正是 Creative gate 存在的理由：測試證明數字對，證明不了看得到。

順帶發現、**沒有處理**的事項，留給 reviewer 與使用者：

- 20 秒後整個場景凍結（`home_page._sceneIdleDelay`，省電／降溫的刻意決定）。
  修好待機姿之後它讀起來好很多——凍住的多半是閉眼姿，像在休息不像當機——
  但它仍然是「待機生命感」的上限。要不要調整需要實機耗電判斷。
- `resetToIdle()` 和修改前的 `resetToOpening()` 形狀相同，也會停在中性臉。
  沒有實測證據所以沒動它，但它是同一個問題的兄弟。
- `expect`（進度 0–50%）是唯一睜眼的待機姿，而且沒有閉眼差分，會一直瞪著。
  補 `tumi_expect_blink.png` 一張即可（低難度、只改眼睛）。其餘待機姿
  （sleep／smile／happy）本來就是閉眼造型，不需要差分。

## 下一個大型 milestone 的候選池

兩個 gate 已關閉，可以開始選；但**選定前仍不開分支**，也不要同時啟動多個：

1. 兔咪待機生命感
2. 每日回歸／開 App 的歡迎感
3. 第一套 Signature Outfit 與身份一致性驗證
4. 每日報到／零食回饋的 CG 一致性
5. 全 App 音效與安靜語言

選的時候要用原始只讀審查與**當下**的可見產品狀態，依「可察覺程度 × 改善幅度 ×
成本／風險」選出唯一下一個 milestone。`roadmap.md` 的功能排序不能取代這次品牌判斷。

## 現階段禁止事項

- 不重跑 Logical-Day、Gradient 或第一版 One-Habit Hero。
- 不因技術測試已通過就跳過 Creative Proof。
- 不同時啟動待機、造型、音效、回憶圖或 onboarding 素材。
- 不把新的 production correctness 探索偽裝成 Creative Proof。
- 不依賴聊天記憶決定下一步；必須先更新本文件。
- 不把 `roadmap.md` 尚未同步的舊「四時段首頁 pilot」當成下一步；
  `four_period_background_plan.md` 已記錄首頁及喝水、計時、家庭推廣完成。
- 不把 One-Habit Hero 留下的三項觀察（anticipation 可見度、half 靜音層級、
  連打時的口頭存在感）自動升格成下一個 milestone。它們是使用者實機使用後才決定
  要不要處理的微調，不是已核准的工作項目。

## AI 分工（現行）

- **總控**：維持方向、判斷風險、產生下一個唯一 Prompt。
- **Opus 5**：架構設計與唯一主要實作者。
- **獨立 Reviewer**：唯讀審查、品質驗收、決定能否合併。
- 每個 milestone 使用獨立工作對話與 feature branch。
- 同一 milestone 的 blocker 回原 Opus 對話。
- Reviewer 與 Opus 不得同時修改同一分支。
- Creative Proof 的最終品牌裁決者是使用者，不是任何模型。

### 2026-08-04 分工變更

原本由 Codex CLI 擔任總控、GPT-5.6 Sol 擔任獨立 Reviewer。Codex 的 token 額度用盡，
**總控職責改由 Opus 5 兼任**，與實作者同一個模型。

這個合併有代價，記下來以免之後忘記為什麼要補：**獨立 Reviewer 這一角目前是空的。**
Sol 的價值不在更聰明，在沒看過實作者的推理過程；同一個對話自審會沿用當初說服
自己的理由，這是結構問題，不是更用力就能補的。

因此在選定下一個實作型 milestone 時，必須先決定 Reviewer 怎麼補，選項依獨立性排序：

1. 使用者手動觸發 `/code-review ultra`（多 agent 雲端審查，計費，實作者不能自己叫）。
2. 由實作者開一個乾淨 subagent，只餵 diff 與文件、不餵設計理由。比自審好，但仍是
   同一個模型家族，共通盲點看不到。
3. 明確接受降級——**僅限沒有 correctness 風險的工作**（例如純文件的 Bible
   Extraction 就是這一類，Gate 2 即以此方式完成）。

不得在沒有講清楚採用哪一項的情況下，讓實作者自己宣布通過技術 gate。

## 每次 milestone 後如何更新本文件

1. 更新 main／origin/main 與 feature／merge hashes。
2. 將通過技術與 Creative gate 的項目移入「已完成並合併」。
3. 明列尚未完成的唯一 gate。
4. 更新測試基準，但不把測試數當成品牌品質分數。
5. 記錄使用者的 KEEP／ADJUST／REVERT 裁決。
6. Bible extraction 完成後，才允許選下一個大型 milestone。
