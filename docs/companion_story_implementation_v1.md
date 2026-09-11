# 第一季故事與回憶預覽實裝

2026-09-11，`codex/experience-redesign`，獨立 `redesign` flavor。

## 可以操作的內容

- 習慣頁兔咪旁出現可忽略的邀請；無習慣也可遇見。關閉提示只在本次畫面／當日暫時收起。
- 14段主線，於第1、4、7、12、18、24、31、38、45、53、62、72、82、90次相處依序遇見；首週另有4段日常。
- 每個App邏輯日最多計一次。看完、主動略過皆計；離開不计、未讀完可以接續。缺席不扣天數。
- 主線間轮替4段日常；累積滿90次後保持日常相處。這批尚不是90天皆有新台詞的內容量。
- 衣櫃回憶分主線、日常與原有特殊事件。略過後列為未讀；正常重播完成只改已讀，不改原選項、首次日期或進度。
- 設定 → 開發者測試 → 回憶 → **暫時開啟全部回憶** → **打開回憶選集**。預覽章節標出ID，回報時可直接引用，如 `story_08`。
- 全開是本次執行中的預覽旗標，不存SharedPreferences。關掉立即恢復真實鎖定；完全關閉App再開也會復原。

## 寫入與改稿

正式來源為 `lib/utils/companion_story_catalog.dart`。每段有穩定episode／beat／choice ID，中文和英文成對保存；
沒有正確答案或選項分數。讀者只能記錄自己實際按過的選項。初遇重播不呼叫取名或功能設定。

`companion_story_progress_v1` 使用一個版本化JSON保存每日credit、收藏、已讀與待續位置。寫入序列化，
`setString`回傳false或throw時不更新記憶體或跳句，重試成功才前進；未知schema或損壞資料保留並阻止覆寫。
未知事件及額外metadata保留，不回退成其他故事。舊4則特殊回憶保留原ID、觸發與日期；預覽讀取不做migration或markRead。

## 此次範圍

本次沿用核准房間與表情，不新增CG；不為黃金鼠或學校增加系統功能。不在閱讀器每句播放音效，
悲傷章節結束也不播通用慶祝音效。新故事式前導、暱稱命名流程、功能全開初始化、兔咪單一房間活動、
帳號登入／備份及公開好感介面仍需另行整合。

## 本人試讀與測試版

先看初遇選項是否像自己的回應；第08段是否尊重失去而不過度煽情；第14段是否有「更熟悉」的感覺。
可隨時返回選集、重新閱讀與改選，正式進度不受影響。中文與英文語氣尚待實際讀者驗收。

由本人連接裝置並執行：

```sh
cd /Users/raraku/habit-app-redesign
flutter run --release --flavor redesign --build-number 20260911 -t lib/main.dart
```

這會更新獨立「兔咪新體驗」（`com.yayoi991331.habitapp.redesign`），保留其既有測試資料並與正式版共存。
AI只操作Mac模擬器與建置，不安裝／啟動實機。實機音訊、觸覺與Release流暢度由本人確認。

## 驗證

- `flutter analyze`：0 issues；完整 `flutter test`：**1008項通過**。
- 原生iPhone 17 Pro／iOS26.5：402×874pt、繁中、預設字級及正常動態，**12張截圖**；真實首頁→續讀／略過→設定→開發者→預覽／恢復鎖定流程通過。
- 中文／英文320×568、2倍字級及Reduce Motion widget測試通過；長選項捲動後仍可點。原生截圖使用合成記憶體資料、靜音、略過通知權限，不代替實機音訊及效能驗收。
- 預覽完整遍歷18段＋4特殊事件，驗證prefs、已讀與usage不變。儲存測試覆蓋false／throw、連點、95日排程、90次上限、未知資料、清空／快照還原重載與等待pending writes。
- App內重啟會重載故事狀態並關閉預覽；3個整批清空／還原入口先等待故事寫入完成，避免舊快取或延遲寫入復活資料。
- Release **142.6MB／arm64／build 20260911**；獨立App ID及既有Apple Development簽章驗證通過，未安裝實機。

[原生畫面選集](../design_trials/experience_redesign/story_review_v1/index.html)・[完整驗證與雜湊](../design_trials/experience_redesign/story_review_v1/validation.json)。
