# Claude 行為規則

## Git 推送
每次 commit 後自動執行 `git push`，不需要再問用戶。

## 完工通知
**不要手動執行通知腳本。** 完工通知交給 `.claude/settings.local.json` 的 hook：
- Stop hook：每輪結束自動發 ntfy（零 token）。
- Notification hook：需要使用者回覆/授權時通知（零 token）。

手動再跑 `notify_ai_done.sh` 只會重複通知又浪費 token，禁止。

## 主動上網查資料
遇到以下情況，直接用 WebSearch，不要先猜答案：
- 硬體規格、充電功率、價格
- 軟體新版本功能或 UI 變化
- 任何不確定或可能過時的資訊

## 單位系統（公制 / 英制）

App 同時支援公制與英制，使用者可在設定切換。寫新程式碼或修改現有
程式碼時必須遵守：

- **儲存與運算永遠用公制**（cm / kg / ml）。SharedPreferences、JSON
  紀錄、BMR/TDEE/BMI 等公式輸入都當公制。
- **顯示一律用 `UnitFormat`**（`lib/utils/units.dart`）：
  - `UnitFormat.height(cm, unit)`
  - `UnitFormat.weight(kg, unit)`
  - `UnitFormat.volume(ml, unit)`
  - 或 `UnitFormat.weightLabel(unit)` / `volumeLabel(unit)` 拿單位字串。
- **輸入一律先轉公制**再驗證/存：用 `UnitConvert.lbToKg`、`flOzToMl`、
  `ftInToCm`，或 `UnitParse.weightKg(raw, unit)` 等 helper。
- **驗證**：unit-aware 場合用 `UserValidators.weightIn/targetWeightIn/
  heightCm`；單純公制場合維持原本 `weight/height` 等。
- **每個畫面 state** 載入時讀 `UnitSystem.load(prefs)` 並存進
  `_unit` 欄位。單位切換有反應式廣播：`UnitSystem.notifier`
  （`ValueNotifier<UnitSystem>`，`load`/`save` 都會同步它）。需要
  「設定頁切換後立即生效」的常駐頁（喝水、體重）在 initState
  `addListener` + setState、dispose 時 `removeListener`；push 進出的
  頁面（個人資料編輯等）每次開啟重讀即可，不必掛 listener。

## SharedPreferences key 集中管理

所有持久化 key 一律定義在 `lib/utils/prefs_keys.dart` 的 `PrefsKeys`，
呼叫端不准硬寫 key 字串：

- 一般 key 用常數：`prefs.getBool(PrefsKeys.waterEnabled)`。
- 帶日期的喝水 key 用 helper：`PrefsKeys.waterDay(date)` /
  `waterEntries(date)` / `waterExtra(date)` 等；掃 `getKeys()` 時用
  對應的 `*Prefix` 常數（長 prefix 要先比對）。
- 新增 key 時先在 `PrefsKeys` 宣告（順手放進對應區塊）再使用。

### 不准在 Dart 字串字面值裡硬寫單位

禁止寫法（會被 `scripts/check_units.sh` 擋下，pre-commit 直接 fail）：

```dart
Text('70 kg')                              // ❌
Text('${cup} ml')                          // ❌
Text('身高 $h cm')                          // ❌
```

正確寫法：

```dart
Text(UnitFormat.weight(70, _unit))         // ✅
Text('${UnitFormat.volume(cup, _unit)}')   // ✅
Text('身高 ${UnitFormat.height(h, _unit)}') // ✅
```

例外（單位常數定義、設定畫面說明文字等真的必須寫死）請在行尾加
`// units-ok` 顯式豁免。

### 改完跑 checker
新增 / 修改頁面後，可手動跑：

```
bash scripts/check_units.sh
```

新 clone 的環境記得裝 hook：

```
cp scripts/pre-commit .git/hooks/pre-commit
chmod +x .git/hooks/pre-commit
```

## 背景音樂（BGM）雷區 — 改音訊前必讀

`lib/utils/bgm_service.dart`（just_audio + audio_session，iOS `ambient`）有幾個
會害「release 沒聲音」的坑，**「簡化」音訊救援邏輯前先停一下**：

- **絕不 `await _player.play()`**。just_audio 的 `play()` future 是「播到停止才
  完成」，await 它在真的播起來時會永遠卡住後面的淡入＝靜音。一律
  `unawaited(_player.play())` 再另外驗證。
- **AOT（profile/release）冷啟動單次 play 常常不 engage**（`playing` 一直 false）。
  要在音量 0 下反覆 pause→play 重踢到 `playing==true` 才淡入（見 `_engageCheck`）。
  debug 是 JIT 時序不同所以有聲，**別只測 debug**。
- **AVAudioSession 只 configure 一次**（`AppAudioSession`，BGM/SFX 共用）；重複
  configure 會重設輸出路由造成沒聲，之後只 `setActive(true)`。
- Debug 音訊：`flutter run --release` 不印 log，改用 `flutter run --profile`
  （一樣 AOT 會重現問題、且會顯示 log）。
