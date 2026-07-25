# i18n 遷移指南

> 基建已完成（2026-07-25），可以開始逐頁遷移。
> 目標語言：**繁中（主要）＋ 英文**。日文之後再說，韓文／簡中更後面。

## 現況

| 項目 | 狀態 |
|---|---|
| `intl` ＋ `generate: true` | ✅ pubspec 已設 |
| `l10n.yaml` | ✅ 專案根目錄 |
| ARB | ✅ `lib/l10n/app_zh.arb`（模板）、`app_en.arb` |
| `AppLocalizations` 掛上 MaterialApp | ✅ |
| 已遷移的字串 | **163 個 key**（app 標題、分頁名、設定頁系全部、基本資料表單、驗證錯誤） |
| **還沒遷移** | 各功能頁內文、空狀態說明、兔咪台詞（最後） |

已完成的範圍（2026-07-25，遷移順序第 1、2 類）：
- 共用對話框按鈕（`app_dialogs` 預設「取消／確定」走 l10n）
- 設定頁、功能開關頁、進階設定頁、資料刪除頁（含 PIN 面板與救援問題）
- 分頁名接線：`TabMeta` 不再帶 label，統一走 `tabLabel(context, id)`
- 基本資料表單（`profile_edit_page`）與 `UserValidators` 錯誤訊息
  （驗證器改收 `AppLocalizations`，測試用 `lookupAppLocalizations`）

注意：頁面用了 `AppLocalizations` 之後，widget 測試要改用
`test/l10n_test_app.dart` 的 `l10nTestApp(home: ...)`，裸 `MaterialApp` 會 crash。
性別／活動量等「儲存值」仍是中文字串（跨頁邏輯比對它們），只換顯示標籤。

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

## 遷移順序建議

由穩定到易變，這樣重工最少：

1. **分頁名、按鈕、設定頁**——最穩定，幾乎不會再改（分頁名已完成）
2. 表單標籤、錯誤訊息、單位
3. 空狀態、說明文案
4. **兔咪台詞與繪本旁白——最後**，等文本定稿

判斷「文本定稿」的標準：實機從頭到尾走一遍，沒有任何一句讓你皺眉。
