# V3.1：對齊與運動計時修正

基準：`6a4551c`（V3）；沿用 `codex/experience-redesign` 與獨立 `redesign` flavor。
這輪是使用者回報 V3 仍有框內未置中、運動計時排列失衡之後的修正。

[原生前後比較](../design_trials/experience_redesign/review_v31/index.html)

## 根因與驗證缺口

- 運動卡高度68pt，child Column 在緊約束下仍從上方排列；`mainAxisSize.min` 並不會讓固定高度內的內容置中。原有測試只看按鈕邊界與點擊，沒有測圖文中心。新增回歸測試在 V3 基準確實失敗（內容中心偏上10pt）。
- 房間版把面盤實際寬度當成左欄寬度；超慢跑多出整列BPM後，面盤從約160pt縮到108pt，右側開始按鈕卻吃掉剩餘寬度，造成同一頁切換運動時比例大幅變動。
- 節拍器三個快捷項使用固定92／116／116pt，即使430pt頁面放得下，仍靠左而留下不對稱空白。
- 遊戲的選項各自決定自然高度，英文換行時同列框高可能不同。這些問題不能以「全部按得到」當成視覺驗收。

## 修正後的布局

保留真實 `MainPage → MascotPageShell → 模式列 → TimerModeFrame`。
430×932、安全區59／34pt、六個主分頁時，收合TimerModeFrame高277.8pt。

- 扣除左右各18pt與中間16pt，面盤欄與操作欄固定44：56。面盤在自己的欄位內置中，大小變化不會再推動右欄。
- 運動快捷列固定68pt、圖文整組置中。header44pt、兩段4pt間距、快捷68pt之後，主區剩157.8pt。
- 超慢跑BPM改放主操作區；52pt開始、48ptBPM、48pt次要操作及兩段4pt間隔，共156pt。水平方向與開始按鈕同寬，面盤約157.8pt，五個快捷項仍完整可點。
- 專注方案統一64pt並置中；遊戲同列依最長文字等高，內容置中；節拍器在足夠寬度下三欄等寬，左右同為18pt。
- 運動設定的種類卡同步置中，最後一排居中；待機主色與所選運動一致。計時引擎、鎖定與保存規則維持原行為。
- 320×667等極矮面板仍使用摘要與可捲動快捷列，不壓縮觸控區。

## 驗證

- 相關計時測試40項通過，包含430pt中英文1.3字級的圖文中心、同列等高、左右留白與五種運動欄位位置。
- `flutter analyze --no-pub`：無問題；完整 `flutter test --no-pub --reporter expanded`：**961項全部通過**。
- 專用iPhone14ProMax／iOS26.5原生模擬器：**45張畫面**，430×932、繁中、預設字級、正常動態，涵蓋五種運動的收合／展開、待機／運行／暫停，以及設定與其餘頁面。畫面使用記憶體測試資料。
- 已逐一檢查截圖與匯出雜湊；設定格線空隙產生一次非致命drag命中警告，父層捲動確實收到操作，前後畫面已確認不同，詳見驗證紀錄。
- 獨立Release `build/ios/iphoneos/Runner.app`（142.5MB、arm64），`codesign --verify --deep --strict`通過。名稱「兔咪新體驗」、App ID `com.yayoi991331.habitapp.redesign`、Team `6NZ675Y2MZ`；使用既有Apple Development簽章供本機測試，未對實機安裝或啟動。
- [最終驗證與產物雜湊](../design_trials/experience_redesign/review_v31/validation.json)。
- 視覺偏好與實機手感仍由本人驗收；優先看超慢跑收合版、五種運動快選及展開設定。

本人連接iPhone後：

```sh
cd /Users/raraku/habit-app-redesign
flutter run --release --flavor redesign -t lib/main.dart
```

更新獨立「兔咪新體驗」，沿用測試版資料；玻璃為預設。
