# Claude Code 任務：番茄鐘 v2 改版

## 目標

請改進 `lib/pages/timer_page.dart`，把目前 MVP 版番茄鐘升級成較完整、穩定、符合「兔咪好習慣」整體風格的番茄鐘頁。

這次重點：

- 計時邏輯更穩
- 支援可設定時長
- UI 更像成品 App
- 保留溫柔陪伴感，不要變成硬派生產力工具

## 目前問題

目前番茄鐘頁：

- 專注/休息時間寫死為 25 / 5 分鐘。
- 沒有長休息。
- 沒有今日完成輪次。
- 計時靠 `Timer.periodic` 每秒扣 1，App 進背景或鎖屏後可能不準。
- 時間到沒有明顯提醒。
- UI 是硬橘/綠 AppBar + 白色圓圈，比較像 Flutter demo。
- 開始/暫停只有 icon，主行動不夠清楚。

## 不要做的事

- 不要改無關頁面。
- 不要改 MainPage tab 結構。
- 不要改首頁、喝水頁、家庭頁、體重頁。
- 不要引入新的狀態管理套件。
- 不要做太大型架構重構。
- 不要做成硬派儀表板風格。
- 不要加入複雜通知權限流程；若要做通知，請先只留 TODO 或簡單可擴充結構。

## 計時邏輯要求

請不要只靠每秒 `secondsLeft--` 當唯一真相。

建議做法：

- 開始時記錄 `_endsAt = DateTime.now().add(Duration(seconds: _secondsLeft))`
- 每秒 tick 時用 `endsAt.difference(DateTime.now()).inSeconds` 計算剩餘
- App 暫停/回到前景時仍可重新計算正確剩餘
- 暫停時保存目前剩餘秒數
- 重設時回到目前模式的初始時長

狀態建議：

```dart
enum TimerMode {
  focus,
  shortBreak,
  longBreak,
}
```

需要處理：

- 專注結束後進入短休息或長休息
- 休息結束後回到專注
- 每完成一輪專注，今日完成輪次 +1
- 每 N 輪後進入長休息

## SharedPreferences key

請新增並使用以下 key：

```text
timer_focus_minutes
timer_short_break_minutes
timer_long_break_minutes
timer_long_break_interval
timer_completed_rounds_yyyy-MM-dd
```

預設值：

```text
focus: 25
short break: 5
long break: 15
long break interval: 4
```

請注意：

- 今日完成輪次依日期儲存。
- 跨日後重新讀取今日資料。
- 不要和喝水、體重、家庭資料混用。

## UI 方向

整體風格要接近首頁與喝水頁：

- 柔和
- 成品感
- 圓角
- 溫暖但不刺眼
- 不要硬橘色大 AppBar

### AppBar

請改成：

- 透明或非常淡背景
- 標題深色
- 右上只保留設定 icon 或 timer 設定 icon
- 若進入全域 `SettingsPage`，請保留原本路由方式

如果新增番茄鐘設定 bottom sheet，建議右上 icon 用 `tune_rounded`。

### 主視覺

請使用大圓形進度環，而不是單純白色圓圈。

要求：

- 中央顯示時間 `25:00`
- 外圈顯示進度
- 專注模式用暖橘/番茄紅，但柔和
- 休息模式用柔和綠/藍
- 進度環需隨時間減少或增加，請選一致且直覺的方向

可用 `CustomPainter` 畫進度環，避免引入套件。

### 狀態資訊

請顯示：

```text
專注中 / 休息中 / 長休息
今日完成 X 輪
```

文案建議：

- focus：`專注一下，兔咪陪你`
- short break：`休息一下，等等再出發`
- long break：`完成幾輪了，好好放鬆`
- idle：`準備開始一輪專注`

### 按鈕

主 CTA 不要只有 icon。

請改成文字清楚的按鈕：

- 未開始：`開始專注`
- 執行中：`暫停`
- 暫停中：`繼續`

次要按鈕：

- `重設`
- `跳過`

次要按鈕請比主 CTA 弱，不要搶焦點。

## 設定 UI

請新增番茄鐘設定 bottom sheet，不要塞到全域設定頁。

欄位：

- 專注時間：分鐘
- 短休息：分鐘
- 長休息：分鐘
- 幾輪後長休息

驗證範圍建議：

```text
focus: 1-120
short break: 1-60
long break: 1-90
long break interval: 2-10
```

儲存後：

- 寫入 SharedPreferences
- 若 timer 沒在跑，更新目前剩餘時間
- 若 timer 正在跑，不要突然重置；可提示「下輪生效」或只更新未來模式

## 音效/提醒

目前專案有 `audioplayers`，但不一定有合適音效資產。

請先做安全處理：

- 如果已有可用音效 asset，可在時間到時播放
- 如果沒有，請不要硬塞不存在的路徑
- 可用 `HapticFeedback.mediumImpact()` 做簡單震動回饋
- 留 TODO 給未來本機通知

## 兔咪連動

這次不要求接 Rive。

但 UI 文案可以有兔咪陪伴感，例如：

- `兔咪陪你專注`
- `兔咪提醒你休息`

不要在番茄鐘頁新增複雜兔咪動畫，避免範圍過大。

## 響應式與可用性

請確認：

- 小螢幕不溢出
- 文字不被截斷
- 按鈕可點擊區足夠
- 計時器進度環不會被 AppBar 或 bottom nav 擠壓
- 深色/淺色文字對比足夠

## 驗收標準

完成後請確認：

- `flutter analyze` 通過
- `flutter test` 通過
- 番茄鐘頁可正常開啟
- 開始/暫停/繼續/重設/跳過正常
- 專注結束後會切到休息
- 每完成一輪專注會增加今日完成輪次
- 第 N 輪後會進入長休息
- 設定能儲存並重新讀取
- App 回前景後剩餘時間不會明顯錯亂
- 不影響首頁、喝水頁、家庭頁

## 建議實作順序

1. 先改資料狀態與計時邏輯。
2. 加 SharedPreferences 設定讀寫。
3. 加今日完成輪次。
4. 改 UI 為進度環與文字 CTA。
5. 加設定 bottom sheet。
6. 加 haptic/time-up 回饋。
7. 跑 `flutter analyze` 和 `flutter test`。

## 關於舊任務文件

目前根目錄可能有：

```text
CLAUDE_TASK_WATER_V3.md
CLAUDE_TASK_WATER_BOTTLE_LAYERING.md
```

這兩份是喝水頁已用過的任務規格。請不要修改它們。若使用者確認，可以之後移到 `docs/archive/`，但這次任務不要處理歸檔。
