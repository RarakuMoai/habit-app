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
| 當前階段 | UI 軌道 U1 Creative gate 已過（`polish/first-glance`）；三條分支都待技術 gate |
| 下一個大型 milestone | 上述兩條完成審查前不再開新的 |

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

> **2026-08-04 暫停。使用者決定先回到 main 的行為，這條分支不 merge。**
> 分支保留不刪；`f029a2d`（依情緒的呼吸）是唯一穩定有效又沒有副作用的改動，
> 未來要撿回來單獨 cherry-pick 即可。停下來的理由見本節最後。

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

### 為什麼暫停（2026-08-04）

五個 commit 的實際狀態：

| commit | 狀態 |
|---|---|
| `f029a2d` 依情緒的呼吸 | ✅ 模擬器實測有效（neutral 7px/2.5s vs sleep 12px/4.0s） |
| `8f1aeb6` 冷啟動回待機姿 | ⚠️ 技術上有效，但**方向與使用者要的相反** |
| `c90c8f7` 凍結前閉眼 | 🟡 機制正確，但只有 `neutral_front` 有閉眼差分，實際幾乎看不到 |
| `d88e5a3` + `5346ee4` | ⬜ 打瞌睡接線失敗、已收掉，程式淨變動為零 |

`8f1aeb6` 是關鍵：改之前冷啟動會停在**會眨眼的中性臉**且不過期，而使用者明確表示
那樣才好。改成依進度推導之後，待機姿變成 sleep／expect／smile／happy——四張都沒有
閉眼差分，兔咪反而永遠不眨眼了。**這條分支唯一穩定生效的行為改動，方向是錯的。**

使用者要的模型是「一個會眨眼的預設 + 少數特殊情境（睡覺＋Zzz）+ 有動作就醒來」。
那個模型現階段做不出來，卡在兩件事，兩件都已查證並釘進程式註解：

1. 待機姿承載進度是**架構承重**的：演出收尾是把狀態清回 baseline，baseline 一旦與
   進度無關，全完成的 `happy` 就留不住（`home_completion_test` 有 26 項在守）。
2. 泛用睜眼立繪只有 `neutral_front` 有閉眼差分。要「待機一定會眨眼」又「待機姿承載
   進度」，需要 `tumi_expect_blink.png`，以及一張睜眼版的「安心」立繪取代過半的
   `smile`。

在那兩張圖到位之前，這個 milestone 沒有能站得住的做法。

## 進行中：介面回饋與導覽

Branch `polish/tab-weight`（從 `ed6a1fd` 開出）。**技術 gate 未過，不得 merge。**
與 `polish/idle-life` 互不相干，可以分開審。

只讀審查的數字（2026-08-04）：

| 發現 | 證據 | 處理 |
|---|---|---|
| 底部分頁切換零回饋 | `_onTabTapped` 只有 `setState` | selection 觸覺，刻意不出聲 |
| 對話框／面板 94% 無聲 | 67 個開啟點只有 4 個有回饋 | 一個 `PopupFeedbackObserver` 全覆蓋 |
| 自訂轉場弄丟返回手勢 | 裸 `PageRouteBuilder` 不走 `pageTransitionsTheme` | 三處改回平台路由 |
| BGM 不為音效讓路 | `bgm_service` 只有淡入淡出 | **未做**，見下方 |

定下的回饋語言：高頻導覽只給觸覺（出聲會變噪音）、面板出現給一次最輕的觸覺、
取消走統一的 `cancel` 語彙、確認刻意不發（讓真正發生的那件事自己出聲）。

兩個查證結果，避免之後重複踩：

- **不要用裸 `PageRouteBuilder` 推頁。** 它不走 theme 的 `pageTransitionsTheme`，
  會默默拿掉 iOS 邊緣滑回手勢與舊頁視差。要做品牌轉場必須從
  `CupertinoPageRoute` 或 `PageTransitionsTheme` 走。已用 `page_transition_test`
  的正反對照釘住。全螢幕揭曉演出（story_reveal、login_streak）不受此限。
- **回饋的「最近剛發過」窗口只給 observer 用，不是全域節流。** 打卡連打每一次
  完成都必須各自發音效與觸覺，全域節流會吃掉第二次。

尚未處理：BGM 為 SFX ducking。`bgm_service` 的救援流程是 release 實機問題的
必要處理，不可為了簡化而移除；動它要用 `flutter run --profile` 在實機驗證，
debug 時序不足以代表 release。留給有實機驗證條件時再做。

待實機確認：觸覺強度（分頁切換與面板出現都是 selection），模擬器摸不出來。

## UI 軌道（2026-08-05 開設）

原本的候選池全部是兔咪／體驗題，沒有任何 UI 與轉場的位置。使用者的長期目標是
「大品牌等級的 UI」，那太大不能當一個 milestone——依 §3.10「一次只證明一件事」
與 §5.3「只選一個英雄場景」，切成一連串場景，一次證明一個。

### 先修正一個歸類：`polish/tab-weight` 不是 milestone

那條分支上的四個 commit（分頁觸覺、面板浮出觸覺、推頁返回手勢、圓角階梯）是
**四個不相干的子系統**，沒有定義過情緒目標、範圍或非目標。它是**一致性修補批次**：
修的都是「本來就該一致卻不一致」的事實錯誤。這類不需要 Creative Proof，
用技術 gate 審過即可合併。**已停止往上追加。**

### Milestone U1：開 App 到首頁的第一眼（Creative gate 已通過）

| 欄位 | 內容 |
|---|---|
| **情緒目標** | 按下圖示到看見房間的這幾秒，要像「門正在被打開」——連續、溫暖、有人在等你；不是「程式正在載入」。 |
| **範圍** | iOS 原生啟動畫面；原生畫面與 Flutter 載入畫面之間的接縫；載入完成交棒給第一個目的地。 |
| **非目標** | 不動報到卡本身的演出（既有已核准設計）、不動 onboarding、不改啟動時的實際工作（音訊快取／通知初始化，那是效能題）、不碰兔咪待機（在已暫停的 `polish/idle-life`）。 |
| **驗收證據** | 冷啟動連拍前後對照，至少涵蓋原生第一幀、Flutter 接手幀、交棒幀。**必須用 profile／release build 量**。 |
| **退出方式** | 獨立 branch，只動啟動素材與接縫，可整條丟棄。 |

**狀態：** branch `polish/first-glance`（`d0670da`，2 個 commit）。
2026-08-05 使用者裁決 **KEEP**；Bible extraction 已完成（`visual_spec.md` §啟動接縫）。
**技術 gate 未過，不得 merge。**

實作的是**接縫**不是載入畫面——那一頁本身是好的。原生啟動圖改由
`scripts/gen_launch_image.py` 從 `_StartupSplash` 的規格產生，storyboard 從
`contentMode="center"`（配 1×1 空白圖等於沒有）改成 aspect fill 釘四邊。

接縫位移 **0px，但那是 14 Pro Max 的數字**（獨立審查 H-2 指出原本沒標注）。
原生層是整頁圖走 aspectFill、元素跟著螢幕縮放，Flutter 層固定 138pt，所以
iPhone 15/16 徑差 −8.6%、SE −12.8%、iPad +90.7%。兔咪任何機型都沒被切到，
相對於改版前的整片白每個機型都變好，所以是「贏得不完整」不是回歸。
機型表與真正的修法方向記在 `visual_spec.md` §啟動接縫。

⬜ **待實機**：空白期的實際長度。iOS 不支援模擬器 profile／release，
模擬器只證明接縫存在與否、不證明時間。

#### 只讀審查結果（2026-08-05）

- `ios/Runner/Assets.xcassets/LaunchImage.imageset/` 三張圖都是 **1×1、68 bytes 的
  空白**，README 還是 Flutter 樣板文字——**原生啟動畫面從來沒有被設計過**。
- 模擬器 debug 冷啟動連拍：前八幀全空白，第九幀才出現品牌載入畫面
  （暖色漸層＋兔咪＋標題＋進度條）。**品牌載入畫面本身沒問題，問題是它前面那段
  什麼都沒有的空白。** 修的是接縫，不是重做載入畫面。
- `main.dart` 與 `home_page.dart` 各有一個裸 `CircularProgressIndicator` fallback。
  這次沒拍到它們出現，但一旦出現會是全 app 唯一的 Material 藍。
- ⚠️ **debug 的空白期不代表 release**：AOT 啟動快得多，實際長度必須用
  profile／release 量，不能拿 debug 的秒數當結論。

## 獨立技術 gate（2026-08-05）

由一個乾淨的 Opus 5 對話冷讀三條分支（prompt 明講「作者與總控是同一個模型、
之前沒有任何獨立審查」，要求優先相信自己跑出來的證據）。

**三條全部 APPROVE，沒有任何 BLOCK。** reviewer 自己跑：analyze 全乾淨、
tab-weight 802/802、greeting-life 797/797、first-glance 794/794；
`polish/idle-life` 依指示未審，污染檢查通過。

六項 hardening，其中**四項是在指出作者講的話與事實不符**。已處理五項：

| 項 | 內容 | 處理 |
|---|---|---|
| H-1 | 節拍器逐拍觸覺會吃掉面板浮出觸覺（BPM ≥273 必然） | ✅ `48f3f90` 加 `fromUserAction`，含守門測試 |
| H-2 | 「接縫 0px」沒標注是校準機型 | ✅ `ed67e9e` + 本文件 |
| H-3 | observer 覆蓋率依賴「沒有巢狀 Navigator」的隱含前提 | ✅ `48f3f90` 寫進 doc comment |
| H-4 | `clearSpeechIfLease` 的 lease 比對恆真，註解宣稱的保護不存在 | ✅ `6fdbaca` 註解改成事實 |
| H-5 | `bottomSheetTheme` 同時改了 18 個面板的底色；一張浮動卡被誤歸類 | ✅ `48f3f90` 卡片改回 18；底色範圍寫進 visual_spec。**⬜ 家庭頁那批面板待使用者眼睛過一次** |
| H-6 | U2 仍缺可見證據 | ⬜ 照 reviewer 給的條件在模擬器試三次未重現，停止追。技術面 reviewer 已用四個反例補強 |

**合併順序（reviewer 在 clone 實際模擬過三種順序）：**
`first-glance` → `tab-weight` → `greeting-life`。前者與另兩條零重疊；後兩條
必然在 `main.dart` `_onTabTapped` 同一個 hunk 衝突，解法是兩塊都留。
合併後 main 應為 794 + 9 + 3 = 806 項，數字不對就代表合併弄丟了東西。

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
