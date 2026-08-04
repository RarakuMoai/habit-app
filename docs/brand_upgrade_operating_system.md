# 兔咪好習慣 Brand Studio Operating System

> 本文件保存品牌升級的長期作業規則。它不是一次性 Prompt，也不列當前進度；
> 現行 milestone、commit 與下一個 gate 一律看
> [`brand_upgrade_status.md`](brand_upgrade_status.md)。

## 1. 文件權責

這套作業系統只管理「如何把既有產品持續打磨成同一個工作室製作的高品質陪伴
體驗」。各領域的內容真相仍由既有文件與程式負責：

- 產品方向與功能取捨：[`roadmap.md`](roadmap.md)
- 兔咪人格與說話原則：[`tumi_character_guide.md`](tumi_character_guide.md)
- 事件、反應與台詞：[`tumi_dialogue_catalog.md`](tumi_dialogue_catalog.md)
- 視覺語言：[`visual_spec.md`](visual_spec.md) 與 `lib/utils/app_style.dart`
- 素材規格：[`asset_convention.md`](asset_convention.md)
- 資料、音訊、效能與素材雷區：[`engineering_guardrails.md`](engineering_guardrails.md)
- 程式現況：repository 本身

最新的使用者明確決策優先於文件。發生衝突時先指出，不得暗自用舊 Prompt 改變
產品方向。

## 2. North Star

這不是普通的 Habit Tracker。產品核心是：

> 使用者透過每天完成小事，與兔咪建立長期、溫柔、不帶壓力的陪伴關係。

兔咪不是貼圖、獎勵機器或附加功能，而是產品的情感主角。每一個品牌升級都至少要
回答一個問題：

- 兔咪此刻在陪使用者做什麼？
- 使用者的行動是否被看見，而且回饋是否值得期待？
- 這個畫面、動作與聲音是否像同一個工作室親手調整？
- 改完之後，使用者是否更願意明天再回來？

核心品質公式：

> **Correctness is the floor. Attachment is the goal.**
>
> 正確性是底線，依戀感才是目標。

不能拿情感目標合理化 crash、資料錯誤、無障礙違規或狀態污染；也不能因為追求
理論完美，把所有時間耗在使用者無法感受到的內部純潔性。

## 3. 不可偏離的產品原則

1. **陪伴優先，不做監督。** 不責怪、不評分、不用效率或成功學施壓。
2. **角色先於裝飾。** 動畫、VFX、聲音與文案必須服務兔咪人格，不為炫技存在。
3. **使用者行動是因，回饋是果。** 重要反應必須和可見事件有清楚因果，不搶跑、
   不無故重播。
4. **克制比熱鬧重要。** 高頻互動允許安靜；星光、語音、震動與大動作不能每次全開。
5. **手工節奏，不套模板感。** 動作要有察覺、預備、衝擊、回復與餘韻；不是為了
   遵守術語，而是讓角色有重量與思考時間。
6. **同一個世界。** 色彩、材質、圖示、字體、空間、角色比例與聲音要能被辨認為
   同一品牌，不照抄任何外部作品的資產或 UI。
7. **無障礙是正式體驗。** Reduced Motion、文字可讀性、觸控尺寸與語意不是降級版。
8. **效能是感受的一部分。** 明顯掉幀、發熱、音訊延遲或圖片閃爍會直接破壞陪伴感。
9. **保留已核准資產。** 不因新模型或新技巧重畫已成功的角色、場景與互動語言。
10. **一次只證明一件事。** 不以「全面升級」為名同時重寫動畫、音訊、狀態與所有頁面。

## 4. Studio 角色與決策權

Director 是審查視角，不代表每輪都要建立十個代理。只啟用能揭露該 milestone 主要
風險的最小角色集合，最後整合成沒有重複的判斷。

| 角色 | KPI |
|---|---|
| 使用者／Creative Director | 決定實際觀感是否值得保留，是品牌感的最終核准者 |
| 總控 | 維持 North Star、拆 milestone、裁決 blocker 是否具有產品風險、產生唯一 Prompt |
| Opus／主要實作者 | 架構設計與唯一 production 寫入者；交付可驗證、可回退的完整實作 |
| Sol／獨立 Reviewer | 唯讀審查、建立獨立反例、判斷技術 gate；通過後才可合併 |
| Character Director | 角色身份、人格、姿勢轉換、生命感與反應重複度 |
| Motion Director | anticipation、impact、weight、recovery、follow-through、interruptibility |
| Audio Director | 聲音材質、同步、分層、安靜、疲勞度與角色／UI 聲音區隔 |
| VFX Director | 特效因果、生成與消散、光源一致性、遮擋與重要性分級 |
| UX／Emotion Director | 每段流程的目標情緒、清楚度、壓力與回歸動機 |
| Art Director | 色彩、材質、字體、間距、圖示、比例與跨頁一致性 |
| Performance／Accessibility Director | 真實裝置可感知的流暢度、耗能與無障礙行為 |
| QA Director | crash、資料、生命週期、回歸與 production 可達的邊界 |

Sol 與 Opus 不得同時修改同一分支。同一 milestone 的 blocker 回到原實作對話；不要
開新實作者重新理解並重寫同一套系統。

## 5. 一個完整 milestone 的固定循環

### 5.1 保存基準

- 記錄起始 commit、branch、測試基準與工作樹狀態。
- 對可見體驗保存修改前畫面；動畫與音訊需要影片或等價的時間證據。
- 沒有基準就不能只憑「好像更豐富」宣稱改善。

### 5.2 先只讀審查

- 先理解現有產品、程式與素材，不得直接全面重做。
- 問題必須指出位置、目前感受、改善後感受、風險與一般使用者能否察覺。
- 排序依據是「可察覺程度 × 改善幅度 × 成本／風險」。
- 同時列出應保留的強項與不值得現在處理的事項。

### 5.3 只選一個英雄場景

- 一個 milestone 只處理一個高影響場景或高度內聚的子系統。
- 必須有清楚的情緒目標、範圍、非目標、驗收證據與退出方式。
- 使用獨立工作對話與獨立 feature branch；不得和其他 milestone 混在一起。

### 5.4 主要實作

Opus 交付三種結果：

1. **程式結果**：修改檔案、理由、依賴、架構與資料影響。
2. **可見結果**：前後畫面、關鍵時序、模擬器驗證；實機驗證由使用者本人進行。
3. **品質結果**：已知不足、效能、聲音疲勞、角色人格、Reduced Motion 與回歸結果。

### 5.5 Creative Proof

- 使用相同資料、畫面尺寸與情境比較基準和候選版本。
- 至少從 Character、Motion、Audio、Emotion、Art 五個視角判斷。
- 使用者明確選擇保留、修正或回退。AI 不得自己宣布品牌感完成。
- 視覺或聽覺無法證明改善時，不以程式量或測試數代替。
- Creative 與 correctness 是兩個 gate，判準不同。Creative Proof 只處理使用者看得到、
  聽得到或感受得到的差異；沒有實際感受差異的內部不完美，這一輪不得放大成阻擋理由。
  反過來，畫面上真的出現 crash、錯誤資料或狀態污染時那是 correctness blocker，
  回技術 gate 處理，不能用「觀感還可以」帶過。

### 5.6 獨立技術 gate

- Sol 保持唯讀，正式反例只寫 `/private/tmp`；不得和 Opus 同時寫 feature。
- 驗證 production 入口、資料、生命週期、無障礙、效能與既有測試。
- APPROVE 前不得合併；BLOCK 必須提供自然操作序列、可觀察結果、期望與根因。
- 通過後依 milestone Prompt 的授權合併、驗證 main、push，並保留 feature branch。

### 5.7 Bible extraction

- 只有通過 Creative Proof 與技術 gate 的經驗，才升格成長期規則。
- 原則寫入最接近的既有 Bible；沒有合適位置時才建立新文件。
- 保存可重用的節奏、判斷與反例，不把暫時 class 名稱或偶然實作鎖成產品真理。
- 更新 [`brand_upgrade_status.md`](brand_upgrade_status.md)，再選下一個 milestone。

## 6. 技術 blocker 與 hardening 的分界

以下通常阻擋合併，即使發生機率低：

- crash、framework exception、資料遺失或 history／邏輯日錯誤
- 一般 production 操作可造成核心語意遺失、重播或錯誤回饋
- 跨頁 ownership 覆寫、無法自行恢復的殘留狀態
- Reduced Motion 或其他無障礙需求實際失效
- 合理使用量下的明顯效能、記憶體、音訊或電量問題
- 隱私、安全、付款或不可逆操作風險

以下不得單獨阻擋，應列 hardening 或未來觀察：

- 畫面、聲音與資料都正確，只是內部 identity 或抽象不完美
- 只能直接呼叫 private／debug API、production 無法自然形成
- 有明確 generation／頁面／日期上限且沒有可觀察影響的理論累積
- 短暫純裝飾差異，能自行收斂且不影響語意或無障礙
- 沒有現行 caller 的預防性 API 完整化

若同一個不變量家族連續兩輪修正後仍再生，停止增加特例，回到資料模型重新設計或
簡化。這是架構重評 gate，不是降低品質。

## 7. 證據標準

一個 milestone 不能只用一句「已完成高品質體驗」交付。最低證據如下：

| 類型 | 最低要求 |
|---|---|
| Git | 起始／結束 hash、branch、remote、clean 狀態、無意外 merge |
| 程式 | 修改範圍、狀態／資料影響、依賴與回退方式 |
| 視覺 | 同條件前後對照；動畫需包含關鍵時間段，不能只給靜態截圖 |
| 聲音／觸覺 | 事件同步、安靜策略、重複使用疲勞與實機待驗事項 |
| 無障礙 | Reduced Motion 等正式替代行為，不以「不播放」草率代替 |
| 品質 | analyze、相關測試、完整測試，以及與風險相稱的 runtime 驗證 |
| 判斷 | 哪些變好、哪些仍不足、為何值得保留 |

測試證明正確性，前後證據與使用者核准證明品牌改善；兩者不能互相代替。

**A/B 證據的錨點要自己先驗過再交出去。** 逐幀或前後對照裡標成「事件前」的那一幀，
必須真的看得到事件前的狀態（例如完成前的件數）。錨點抓晚了，整排 frame 都會落在
事件之後，看起來像「兩版沒有差別」或「一開始就是最終狀態」——那是取樣錯誤，不是
產品行為，而且它會安靜地推翻該情境的全部結論。兩個版本各自手動挑時間點時最容易
發生，因為每一版的操作時機本來就不會一樣。
（2026-08-04 One-Habit Hero Creative Proof 的 half 對照表即為實例：candidate 欄
標示的 contact 幀件數已經跳完，該情境的逐幀證據因此不成立。）

## 8. 防止方向漂移

- 每次開新品牌 milestone 前，必須先讀本文件與現行 status。
- status 若還有未完成 gate，不得直接開始下一個大型實作。
- 一次性 Prompt、聊天摘要與模型記憶都不是長期真相來源。
- 新模型可以提出不同實作，但不得自行改寫 North Star、兔咪人格或已核准的品牌規則。
- 使用者改變方向時，先更新對應權威文件與 status，再開始實作。
- 對外部作品只借品質判斷語言，不複製角色、素材、介面或可識別表現。

## 9. 本文件的更新條件

只在以下情況修改本文件：

- 使用者明確改變 Brand Studio 的長期工作方式
- 至少一個已核准 milestone 證明某條流程規則需要新增或修正
- 現有規則造成重複失敗，且已完成原因分析

單次 blocker、當前 commit、暫時 Prompt、候選功能與階段百分比不得寫入本文件；
它們屬於 status 或 milestone 文件。
