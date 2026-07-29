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
| 已遷移的字串 | **1194 個 key**——`lib/` 的功能 UI 字串已全部遷完 |
| **還沒遷移** | 只剩兔咪台詞與繪本旁白（等文本定稿），以及下面「刻意不遷」那幾類 |
| 英文文案 | 全域問題已統一（術語、大小寫、撞字、標點）；逐句細讀做到首頁／喝水／體重／設定，其餘頁面只掃過篩選器 |

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

- `widgets/mascot_bubbles.dart` 的 `assert` 訊息——只給開發者看
- `dev/tumi/tumi_preview_main.dart`——獨立 dev entry（自己的 `main()`、
  沒掛 localizations delegate），註解已標明「不進正式 app」
- 註解、正則裡的字元類別（`utils/lenient_date.dart` 的 `[-/.年]`）

## 兔咪名字：長度上限用「顯示寬度」而不是字元數

名字會嵌進很多系統文案（「{name}的夥伴檔案」、「{name}造型」…），限長的目的
**只是防破版**，所以該數的是「佔多寬」，不是「幾個字」。CJK 是全寬，一個字約
等於兩個拉丁字元——**中文 6 字與英文 12 字元的視覺寬度相同**。

上限：`kMascotNameMaxUnits = 12`（半寬單位；全寬字算 2、其餘算 1），實作在
`utils/input_formatters.dart` 的 `DisplayWidthLimitingFormatter`。用 formatter
而不是 `TextField.maxLength`，因為 maxLength 只能數字元、做不到依語言不同的
上限，而且 formatter 連混打（「小雲Cloud」）也算得對。

**12 的依據**（2026-07-26 實測 iPhone SE 320pt 寬，載入專案 Nunito 量英文、
中文用 CJK 1em）：

| 位置 | 可用寬 | 固定文字 | 名字能完整顯示到 |
|---|---|---|---|
| 檔案頁 AppBar「{name}的夥伴檔案」 | 288px / 18px 字 | 5 字 | 中文 11 字 |
| 同上（14PM 430pt） | 398px | 5 字 | 中文 17 字 |

12 半寬單位（＝中文 6 字）對最吃緊的 AppBar 留了將近一倍邊際。

順帶修掉的既有瑕疵：衣櫃回憶本副標原本是「{name}替你收好的每一個小小時刻」，
固定文字 12 個中文字又只給一行，SE 上名字超過 4 字就會被截成「…」。已把名字
抽掉（名字在正上方的標題已經出現過），那處不再是限制點。

**加新的「名字 + 固定文字」單行文案時**，先確認固定部分別太長。要驗證就照上面
的方法量：抓該處 `RenderParagraph` 的 `constraints.maxWidth`，除以字級得到可用
em 數，扣掉固定文字的 em 數就是名字的空間。

名字候選池在 ARB 的 `mascotNamePool`（半角 `|` 分隔）。**翻譯時要重新挑一組
目標語言本身好唸的小名，不是逐字翻**（「小雲」翻成 Little Cloud 會很怪）。
預設名走 `mascotDefaultName`（中文「兔咪」／英文 "Tumi"）；`MascotName.fallback`
仍是 const「兔咪」，當沒有 context 時的最後防線。

## 英文文案規則（2026-07-29 定案）

第一批與第二批是分開直譯的，術語與大小寫不一致。以下是統一後的規則，
**加新的英文文案時照這個寫**。

### 術語表——同一個概念只用一個詞

| 概念 | 用 | 不要用 |
|---|---|---|
| 家長密碼 | `passcode` | ~~PIN~~、~~password~~ |
| 足跡幣 | 標籤／餘額用全名 **`Paw coins`**；句子裡前面已經有數字時用 `{n} coins`（不囉唆） | ~~paw-coin~~（連字號）、單獨的 `Coins` 當標籤 |
| 兔咪 | 指角色本身用 `{name}`（使用者可改名）；指「這個角色」這個概念用 `mascot`（如欄位標籤 "Mascot name"）；產品名才是固定的 `Tumi` | 在文案裡寫死 `Tumi` |
| 刪除類 | `delete`＝刪掉某個項目、`clear`＝清空內容但保留容器、`remove`＝從清單移除、`erase`＝整體抹除 | 混用 |

### 大小寫：一律 sentence case

只有第一個字與專有名詞大寫。例外：
- 產品名 `Tumi Habits`
- 縮寫 `BMI` `BMR` `TDEE` `BPM` `AM/PM` `TAP` `Lv.`
- 分頁名（`Show the Water tab`）、能力名（`Hunt bonus`）、人名（`Fischer`）
- 要使用者照打的字（`Type DELETE to confirm`）

### 標點

- 刪節號一律用 `…`（U+2026），不要打三個點
- 完整句子（有主詞動詞）結尾加句點；標籤、按鈕、片語不加
- 破折號用 `—`（em dash），前後留空格

## 怎麼繼續打磨英文（給接手的人／下一個 session）

**專案擁有者英文能力不好，無法驗收英文品質**——所以不要把「你實機看看順不順」
當成驗收方式，品質要由執行者自己扛。

已做完的（全部 1194 個 key 都掃過）：術語統一、大小寫統一、英文撞字、
分號與 Please。規則見上一節。

還沒做的是**逐句細讀**。已完成：首頁、喝水、體重、設定。
未完成：計時、家庭、衣櫃、回顧、小蛇、前導頁、夥伴檔案。

做法（照這個順序，一批一個 commit）：

1. 按 key 前綴 dump 該批的「中文 │ 英文」並排（前綴見各頁 ARB key 命名）
2. 逐條讀，挑出三類問題：
   - 技術詞漏進使用者文案（default、reading、entry 之類）
   - 直譯後不自然（"a cup of 250 ml"、"Not now" 暗示之後會再問）
   - 與其他 key 前後不一致（同一個按鈕在說明裡被寫成別的字）
3. 改完跑 `flutter gen-l10n`＋`flutter analyze`＋`flutter test`
4. commit 時把「為什麼改」寫進訊息，不要只寫「潤稿」

**驗收方式**：每批改完，把 before／after 連同中文原文並排給擁有者看。
他判斷得了「意思有沒有跑掉」，判斷不了「英文順不順」——所以意思務必忠實。

**上架前的建議**：AI 打磨過的英文可用，但要正式面對英語母語使用者，
還是值得找母語人士做一次 proofreading。這一點要如實告知，不要讓擁有者
以為 AI 潤過就等於母語品質。

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

1. **英文語氣打磨（做了一半）**——全域問題已處理完（見「英文文案規則」）：
   術語統一、大小寫統一、英文撞字、分號與 Please。逐句細讀只做了首頁、
   喝水、體重、設定四塊；計時／家庭／衣櫃／回顧／小蛇／前導頁還沒逐句看過
   （只用篩選器掃過明顯問題）。篩選器抓不到「文法對但不像母語人士寫的」，
   那要一句一句讀，或在實機看到實際情境再調。
2. **兔咪台詞與繪本旁白**——等中文文本定稿後遷（判斷標準：實機從頭到尾
   走一遍，沒有任何一句讓你皺眉）。英文版是**重寫**，見上面那節。
3. **Preset 名稱改用穩定 id**——做完才能翻譯常用習慣／獎勵／扣分那幾組
   內容資料（見「刻意不遷」第 1 節）。需要一次資料遷移。

做完 1 與 2 才能拿掉 `main.dart` 的 locale 鎖定。
