# 兔咪 Rive 學習與實作路線

> 狀態：暫停 / 歷史文件。
>
> 目前兔咪近期方向已改為「高品質 CG 立繪差分 + Flutter 輕量演出」，不再以 Rive / 骨架動畫作為近期主線。此文件僅保留為未來若重新評估 Rive 時的參考，不應作為當前實作前提。

更新日期：2026-05-23

## 目標

把目前 Flutter 裡的「兔咪假動畫」逐步升級成真正的角色動畫系統。

你不需要先成為專業動畫師。第一個目標是能做出：

- idle 呼吸
- 眨眼
- 點擊反應
- 完成習慣 cheer
- 失落/安慰
- 睡覺
- Flutter 依 App 狀態觸發 Rive state machine

## 最佳工作流

AI 額度還有時：

- 跟 ChatGPT 討論產品方向、動畫狀態、角色個性、UI 美感
- 讓 ChatGPT 產出 Claude Code 指令
- 讓 Claude Code 實作 Flutter、資料同步、測試
- 讓 ChatGPT 做美感與互動 review

AI 額度用完時：

- 學 Rive Editor
- 練角色拆件
- 做 idle / blink / cheer
- 看 Rive state machine
- 整理兔咪動畫需求清單

## 7 天學習路線

### Day 1：熟悉 Rive 介面

目標：知道 Rive 裡 Artboard、Timeline、Keyframe、State Machine 在哪裡。

練習：

- 建一個新 Rive 檔
- 畫一個簡單圓形角色
- 做上下輕微呼吸動畫
- 匯出 `.riv`

完成標準：

- 你能播放一段 2 秒 loop 動畫
- 你知道 Timeline 和 State Machine 的差別

### Day 2：拆角色部件

目標：理解兔咪未來要拆成哪些層。

建議拆件：

- body
- head
- left_ear
- right_ear
- left_arm
- right_arm
- left_eye
- right_eye
- mouth
- cheek

練習：

- 用簡單形狀做一隻假兔咪
- 每個部件獨立命名
- 嘗試只移動耳朵或眼睛

完成標準：

- 你能單獨控制頭、耳朵、眼睛

### Day 3：idle + blink

目標：做出「活著」的最低成本動畫。

idle：

- 身體上下 2-4 px
- 頭部慢慢跟著動
- 耳朵延遲一點點

blink：

- 眼睛閉合 2-3 幀
- 很快張開
- 不要太頻繁

完成標準：

- idle loop 看起來自然
- blink 不會像閃爍 bug

### Day 4：cheer 完成習慣動畫

目標：做出完成習慣時的短反應。

動作節奏：

- 先微微壓低
- 往上彈
- 手/耳朵打開
- 回到 idle

建議時長：

- 600-900 ms

完成標準：

- 動作有「壓縮 -> 彈起 -> 回穩」
- 不只是單純放大縮小

### Day 5：sad / comfort

目標：做出撤銷、久未完成、安慰用的表情。

sad：

- 耳朵下垂
- 眼睛變小
- 身體稍微下沉

comfort：

- 回到微笑
- 小幅點頭
- 表情溫柔，不要責備

完成標準：

- 看起來是陪伴，不是懲罰

### Day 6：State Machine

目標：把動畫整理成可被 App 控制的狀態機。

建議 State Machine 名稱：

`TumiStateMachine`

建議 inputs：

- `tap` trigger
- `complete` trigger
- `allDone` trigger
- `sad` trigger
- `sleep` boolean
- `mood` number

建議 states：

- idle
- blink
- tap_react
- cheer
- all_done
- sad
- sleep

完成標準：

- 點 trigger 可以從 idle 進入 cheer
- 動畫結束後回到 idle

### Day 7：接進 Flutter

目標：讓 Flutter 可以載入 `.riv` 並觸發 state machine。

任務：

- 把 `.riv` 放進 `assets/animations/`
- 在 `pubspec.yaml` 確認 assets 已包含該資料夾
- 讓首頁用 Rive 替代目前 PNG 兔咪
- 完成習慣時觸發 `complete`
- 點兔咪時觸發 `tap`
- 夜晚時切 `sleep`

完成標準：

- App 裡的兔咪不是播放單一動畫，而是會依狀態反應

## 兔咪第一版 Rive 動畫清單

優先順序：

1. idle
2. blink
3. tap_react
4. complete_cheer
5. all_done_celebrate
6. sad
7. sleep
8. wake_up
9. water_complete
10. streak

第一批只需要做前 4 個。做太多會分散品質。

## 動畫品質檢查表

每個動畫都檢查：

- 動作是否有壓縮和回彈
- 是否有停頓，不是一路等速
- 表情是否符合兔咪個性
- 動作結束是否能自然回 idle
- 是否不會太吵、太頻繁
- 是否能在小手機上看清楚

## 給 Claude Code 的整合任務格式

```text
目標：
把首頁兔咪從 PNG 動畫替換成 Rive state machine。

輸入：
assets/animations/tumi.riv
State Machine: TumiStateMachine
Triggers: tap, complete, allDone, sad
Boolean: sleep

要求：
- 保留目前首頁背景與習慣列表
- 點兔咪觸發 tap
- 勾選每日習慣觸發 complete
- 每日習慣全完成觸發 allDone
- 取消勾選觸發 sad
- 夜晚時 sleep = true
- 不要重構無關頁面

驗收：
- flutter analyze 通過
- flutter test 通過
- 首頁可正常進入
- Rive asset 找不到時要有 fallback，不要白屏
```

## 官方參考資料

- Rive Flutter runtime：https://rive.app/docs/runtimes/flutter/flutter
- Rive State Machine overview：https://rive.app/docs/editor/state-machine
- Rive State Machine playback：https://rive.app/docs/runtimes/state-machines
- Rive states：https://rive.app/docs/editor/state-machine/states

## 現階段判斷

目前 App 已經完成第一階段：AI + Flutter 原型。

下一階段不是繼續堆 Flutter 假動畫，而是學 Rive，把兔咪做成真正能被狀態控制的角色。
