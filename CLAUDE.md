# Claude 行為規則

## Git 推送
每次 commit 後自動執行 `git push`，不需要再問用戶。

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
  `_unit` 欄位；切換單位後需重開該頁才反應（目前未做反應式廣播）。

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
