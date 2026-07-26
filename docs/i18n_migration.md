# i18n 遷移指南

> 基建已完成（2026-07-25），功能 UI 字串已於 2026-07-26 全部遷完。
> 目標語言：**繁中（主要）＋ 英文**。日文之後再說，韓文／簡中更後面。

## 現況

| 項目 | 狀態 |
|---|---|
| `intl` ＋ `generate: true` | ✅ pubspec 已設 |
| `l10n.yaml` | ✅ 專案根目錄 |
| ARB | ✅ `lib/l10n/app_zh.arb`（模板）、`app_en.arb` |
| `AppLocalizations` 掛上 MaterialApp | ✅ |
| 已遷移的字串 | **1192 個 key**——`lib/` 的功能 UI 字串已全部遷完 |
| **還沒遷移** | 只剩兔咪台詞與繪本旁白（等文本定稿），以及下面「刻意不遷」那幾類 |
| 英文文案 | ⚠️ 目前是直譯，語氣還沒打磨；兔咪台詞的英文是**重寫**（見下） |

第一批（2026-07-25，遷移順序第 1、2 類）：
- 共用對話框按鈕（`app_dialogs` 預設「取消／確定」走 l10n）
- 設定頁、功能開關頁、進階設定頁、資料刪除頁（含 PIN 面板與救援問題）
- 分頁名接線：`TabMeta` 不再帶 label，統一走 `tabLabel(context, id)`
- 基本資料表單（`profile_edit_page`）與 `UserValidators` 錯誤訊息
  （驗證器改收 `AppLocalizations`，測試用 `lookupAppLocalizations`）

第二批（2026-07-26）：計時頁系（專注／運動／節拍器／桌遊計時器全套）、
喝水頁、體重頁、家庭頁系（含家長管理、密碼救援、習慣／獎勵／扣分／積分紀錄）、
衣櫃頁與音樂盒、回顧頁、繪本揭曉頁與回憶本閱讀器、菜園小蛇彩蛋、
骰子對決彩蛋、開發者測試頁、首頁習慣卡與習慣面板、前導頁表單、
夥伴檔案、報到頁、日期選擇器、補打卡頁、剩餘 widgets 與 utils。

注意：頁面用了 `AppLocalizations` 之後，widget 測試要改用
`test/l10n_test_app.dart` 的 `l10nTestApp(home: ...)`，裸 `MaterialApp` 會 crash。
性別／活動量等「儲存值」仍是中文字串（跨頁邏輯比對它們），只換顯示標籤。

## ⚠️ 刻意不遷的字串（動它們會壞掉）

`lib/` 裡還剩的中文字串**全部是這幾類**，不是漏掉的。改之前先看這一節。

### 1. 儲存值與識別鍵——翻譯會直接壞掉功能

| 位置 | 是什麼 | 為什麼不能翻 |
|---|---|---|
| `home/home_presets.dart` 的 `kHomePresets` name | 首頁常用習慣名 | 選取後直接存成習慣名；首頁的去重（`existing.contains(p.name)`）與喝水／體重連動判定（`habit['name'] == p.name`）都比對它 |
| `onboarding_page.dart` 的 `_kOnboardingHabits` name | 前導頁習慣清單 | 同上，選了會存成習慣名 |
| `family/family_presets.dart` 的三組 `k*Presets` name | 育兒常用習慣／扣分／獎勵 | `existingNames.contains(p.name)` 去重、`_deductionPresetPoints(name)` 用名字查分數。翻譯後換語言，已加過的項目會重新出現 → 重複 |
| `family/family_store.dart` 的預設習慣 | 新增小孩時自動建的三個習慣 | 建立時就存進資料，且名稱要跟 `kHabitPresets` 對得上才不會重複 |
| `home_page.dart` 的 `_kWaterHabitPresetName` | `'喝足夠的水'` | 喝水連動的識別鍵（原本散在四處，已抽成常數並加註解） |
| `utils/water_habit_link.dart`、`utils/weight_records.dart` | 習慣名常數與別名 | 同上，跨頁比對用 |
| `home/habit_sheets.dart` 的 `'體重紀錄'` 比對 | 決定連動色 | 識別鍵 |
| `home/habit_sheets.dart` 的 `RegExp(...分鐘$)` | 解析已存的習慣名稱 | 時長被編進名稱裡存起來（`habitNameMinutes`），改成 l10n 會讓舊名稱解析失敗 |
| `profile_edit_page`／`onboarding_page`／`water_page`／`weight_page` 的性別與活動量 | `'男'`／`'久坐'` 等 | 儲存值；`water_page` 算每日水量、`weight_page` 算 TDEE 都比對它們。**只換顯示標籤**（`genderMale`、`activityAlmostNone` 等） |
| `timer/game/table_timer_models.dart` 的 `_legacyZh*` | 舊版自動命名的比對字串 | 用來判斷「這個名字是不是使用者改過的」，必須維持當年輸出 |
| `utils/wardrobe_catalog.dart` 的 `tags` | `'慢'`／`'快'` 等 | 穩定識別字串，顯示時走 `bgmTagLabel` 翻譯 |

**要遷這些的話**：得先給 Preset 一個穩定 `id`、把比對改成比 id，再替既有存檔做一次資料遷移。那是獨立工程，不要順手改。

### 2. 兔咪台詞與繪本旁白——等文本定稿

- `utils/mascot.dart` 的 `_lines` / `_homeTapLines` 台詞池
- `utils/story_catalog.dart` 的 `captions`（繪本旁白）
- `home_page.dart` 的 `buildGreetingMessage`（當日問候分支）
- `login_streak_page.dart` 的 `_caption`
- `onboarding_page.dart` 的 `_speechBubble()` 內容、各 feature 頁的 `bubble`
- `wardrobe_page.dart` 穿上／購買造型的 `speech`

### 3. 其他不算 UI 字串的

- `onboarding_page.dart` 的兔咪名字候選池（38 個中文名）——換語言要重新設計一組
  名字，跟台詞同性質的文本工作，不是翻譯
- `widgets/mascot_bubbles.dart` 的 `assert` 訊息——只給開發者看
- `dev/tumi/tumi_preview_main.dart`——獨立 dev entry（自己的 `main()`、
  沒掛 localizations delegate），註解已標明「不進正式 app」
- 註解、正則裡的字元類別（`utils/lenient_date.dart` 的 `[-/.年]`）

## 沒 context 的地方怎麼拿文案

utils／service 層沒有 `BuildContext`，一律**由呼叫端把組好的字串傳進來**，
service 本身不碰 l10n：

- `WardrobeStore.purchaseOutfit / purchaseTrack` 的 `spendReason`
- `CoinService.debugAdd` 的 `note`、`claimDailyLogin` 的 `l10n` 參數
- `NotificationService.scheduleAt` 的 `channelName` / `channelDescription`
- `ReviewStats.habits` 的 `habitFallbackName`
- `SnakeArcadeRecords.addEntry` 的 `fallbackName`

例外：`AppLocalizations` 物件本身可以直接當參數傳（不需要 context），
`wardrobe_catalog.dart` 的 `moodLabel(l10n, mood)` 就是這樣。

另外，**參數預設值不能是 l10n**（要編譯期常數）。這種地方改成收 `String?`、
進到函式裡再 `?? l10n.xxx`——`verifyParentPinIfNeeded`、`FamilyEmptyInvite`、
`showFamilyPresetSubSheet`、`showAppDatePicker`、`showManualDateDialog` 都是。

引擎層若原則上「不碰 Flutter」（如 `snake_arcade_engine.dart`），l10n 對照要
掛在頁面端的 extension，不要把 `AppLocalizations` 匯進引擎。

`zh` 直接就是**繁體**（主要市場台灣）。未來加簡中用 `app_zh_Hans.arb`——Flutter
要求有 script／country code 的 locale 必須有無後綴的 base 當 fallback。

## 怎麼加一個字串

1. 在 `lib/l10n/app_zh.arb` 加 key 與繁中文案，附 `@key` 的 `description`
   （寫給翻譯者看：這句出現在哪、語氣是什麼）。
2. 在 `app_en.arb` 加同名 key 的英文。
3. 跑 `flutter gen-l10n`（或直接 `flutter run`，build 時會自動產生）。
4. 用 `AppLocalizations.of(context).yourKey`。

帶變數的用 ARB 的 placeholder 語法：

```json
"doneCount": "今天第 {count} 件了。",
"@doneCount": {
  "placeholders": { "count": { "type": "int" } }
}
```

## 遷移原則

- **新字串一律直接寫 ARB**，不要再硬編碼——否則遷移永遠追不上新增。
- **舊字串照「順路遷移」**：改到某一頁的行為時，順手把那頁抽掉
  （同 `AGENTS.md` 的順路拆檔規則）。
- **兔咪台詞最後才遷**。文本還在調的階段先別動，否則每句話要改兩次。

## ⚠️ 英文版兔咪台詞是「重寫」不是「翻譯」

中文的語氣規則（見 `tumi_character_guide.md`）**大半在英文不成立**：

| 中文 | 英文的問題 |
|---|---|
| 「有看到喔。」省略主詞 | 英文必須有 I／You，省不掉 |
| 「嗯...你來了。」 | "Hm... you're here." 慢半拍的味道不見了 |
| 一句 20 字上限 | 英文字數基準完全不同 |
| 「三種聲音」的分界 | 英文的第三人稱自稱是幼兒語，分界要重畫 |

所以英文版要**先重新設計一套語氣規則**，再重寫台詞。這是跟中文那次同等份量
的工作，不是把 ARB 填一填。排程時要當成獨立任務估。

## 產生檔不進版控

`lib/l10n/app_localizations*.dart` 與 `untranslated.json` 已列入 `.gitignore`，
每次 build 會重新產生。**不要手改那些檔案。**

## 目前刻意鎖定繁中

`main.dart` 有一行：

```dart
locale: const Locale('zh', 'TW'),   // ⚠️ 暫時鎖定
```

因為英文只有骨架，放開會變成半中半英。**英文文本完成後移除這行**，改為跟隨
系統語言。

## 接下來還要做什麼

功能 UI 已經遷完，剩下三件事，彼此獨立：

1. **英文語氣打磨**——目前的英文是直譯，可讀但不夠自然。要一頁一頁看過。
2. **兔咪台詞與繪本旁白**——等中文文本定稿後遷（判斷標準：實機從頭到尾
   走一遍，沒有任何一句讓你皺眉）。英文版是**重寫**，見上面那節。
3. **Preset 名稱改用穩定 id**——做完才能翻譯常用習慣／獎勵／扣分那幾組
   內容資料（見「刻意不遷」第 1 節）。需要一次資料遷移。

做完 1 與 2 才能拿掉 `main.dart` 的 locale 鎖定。
