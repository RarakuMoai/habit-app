# 四時段場景系統 Phase 0：現況盤點與效能基準

對應計劃書：`docs/fable5_day_cycle_scene_plan.md` §8 Phase 0。
基準 commit：`fde2985`（+ 工作樹在途修改，與場景無關）。

## 1. 動畫來源盤點（首頁，改造前）

| 動畫來源 | 檔案 | 驅動 | 頻率 | 常駐？ |
|---|---|---|---:|---|
| `WindowBackdrop`（窗外天空/星/雲/日月/灌木） | `room_ambient_overlay.dart` | 自有 `Ticker`（`ThrottledSceneTicker`） | ~30fps | 是（閒置凍結前） |
| `RoomAmbientOverlay`（窗光束/塵埃/檯燈暈/月光） | `room_ambient_overlay.dart` | 自有 `Ticker` | ~30fps | 是 |
| `RoomSceneEffects`（地板光池/燈氛圍/完成特效） | `room_scene_painters.dart` | 自有 `Ticker` | ~30fps | 是 |
| 兔咪呼吸/眨眼等 | `mascot_scene.dart`（`MascotStage`） | 多個 `AnimationController` | 60fps（呼吸慢速） | 是（`MascotIdleScope` 可暫停） |
| 進度亮點光暈 `_glowCtrl` | `home_page.dart` | `AnimationController.repeat` | 60fps | 僅達標時 |
| 慶祝 `_celebCtrl`、抖動 `_jiggleCtrl` | `home_page.dart` | `AnimationController` | 事件觸發 | 否 |
| 時段色罩/背景漸層 | `home_page.dart` `AnimatedContainer` | 隱式動畫 | 事件觸發（600ms） | 否 |

→ **同一個首頁場景常駐 3 條 30fps Ticker ＋ 兔咪多條 controller**，違反「單一場景單一 clock」目標；三條 ticker 各自 notify，雖然 vsync 會合併成同一幀，但三個 painter 每幀都重繪。

## 2. 每幀 GPU 風險盤點（30fps 常駐期間）

| 層 | `MaskFilter.blur` | `BlendMode.plus` | 備註 |
|---|---:|---:|---|
| `WindowBackdrop` | 0 | 0 | 漸層＋path，量小 |
| `_RoomAmbientPainter`（晨/晝） | 3（光束 σ9） | 3 光束＋16 塵埃 | 光束路徑每幀重建 |
| `_RoomAmbientPainter`（夜） | 1（月光 σ11） | 1＋2 燈暈 | |
| `RoomSceneEffectsPainter` | 3–4（陰影 σ18、地板光 σ9×2、燈氛圍 σ16） | 2 光池＋6 條紋＋7 微粒 | 全螢幕 vignette 漸層每幀重算 |

→ 白天最壞情況 **同幀 6–7 個 MaskFilter.blur**，超出計劃書「每場景同時最多 2 個」的規範；且 path/gradient 每幀重新配置。

## 3. 時段判斷不一致盤點（Phase 1 要統一的來源）

| 位置 | 判斷方式 | 門檻 |
|---|---|---|
| `home_page._sceneColors` / `_sceneTint` | 整數小時分桶，瞬切 | 夜 ≥18 或 <6；晨 <8；暮 16–18 |
| `room_ambient_overlay.sceneTintNow()`（其他頁色罩） | 整數小時分桶，瞬切 | 夜 ≥22 或 <6；晨 <9；暮 ≥17 |
| `_windowPalette()`（窗外天空） | 連續 keyframe 插值 | 5.0/6.6/8.5/16.8/18.6/20.4/22.4 |
| `_RoomAmbientPainter`（companionTiming=首頁） | smoothstep | 日光 6–12–16；暮 16–16.8/17.4–18；燈 17.2–18、5.4–6.4；月 21–22.8 |
| `_RoomAmbientPainter`（其他頁） | smoothstep | 光束 5.5–7.5/16–18.8；燈 16.5–18、5–6.5；月 21–22.8、4–5.5 |
| `RoomSceneEffectsPainter` | smoothstep（重複實作） | 同 companionTiming 一套；夜 20–22.5、4.8–6.3 |
| 兔咪夜晚情緒（`home_page` ×2） | 整數小時 | ≥22 或 <6 |

其他問題：

- painter 在 `paint()` 內每幀呼叫 `sceneHourNow()`（即 `DateTime.now()`）。
- 時段色罩（`AnimatedContainer`）只有 rebuild 才更新：閒置凍結時跨過時段交界，色罩會停留在舊時段直到下次互動。
- debug 覆寫 `HomeSceneDebug.hourOverride` 是散落的全域靜態，只在首頁 `loadHabits` 時讀 prefs。
- App resume／時區改變沒有任何場景刷新路徑（只有 mascot/金幣邏輯在 resume 有事）。

## 4. 省電機制現況（保留並沿用）

- 首頁：20 秒無操作 → `TickerMode(enabled:false)` 凍結三層＋兔咪 `paused`；觸碰喚醒。
- 其他兔咪頁：`MascotSceneBackground` 內建 `_AutoPausingTickerMode`（20 秒）。
- 非當前分頁：`main.dart` IndexedStack 每個分頁包 `TickerMode(enabled: i == current)` → 0fps。
- App 背景：engine 停 vsync，ticker 不再收 callback → 0fps。
- 總開關：`kRoomAmbienceEnabled = false` 全部退回純背景圖。

## 5. 量測方法（可重現）

探針：`lib/utils/scene_frame_probe.dart`，`--dart-define=SCENE_PERF=1` 啟用，
每 10 秒印一個視窗的幀數、UI/raster 平均、P95、最大值與超預算幀數；
無幀時印 `0 frames`（驗證閒置 0fps）。

場景腳本（每輪同一裝置、同一亮度）：

1. 冷啟動停在首頁，前 20 秒（w0–w1）＝活躍基準（閒置計時器尚未觸發）。
2. 不觸碰持續 60 秒：w2 起應為 0 frames（20 秒閒置凍結生效）。
3. 觸碰一下喚醒，再記 2 個視窗。
4. 依序切到喝水/計時/體重/衣櫃/家庭分頁各 20 秒（用 `debug_start_tab`
   seed 重啟，或手動點底欄）。
5. 10 分鐘停留：記電量（實機 Settings/Instruments Energy Log）與記憶體
   （DevTools / Xcode memory gauge）。

指令：

```bash
flutter run --profile -d <device> --dart-define=SCENE_PERF=1   # 實機
# 模擬器不支援 profile，只能 debug（數據僅作相對比較）：
flutter run -d <simulator> --dart-define=SCENE_PERF=1
```

時段截圖：dev prefs `debug_scene_hour`（`PrefsKeys.debugSceneHour`）寫入
容器 plist → `launchctl kickstart` 踢 cfprefsd → 重啟 App →
`xcrun simctl io booted screenshot`。四個基準時間：6.5 / 12.0 / 17.5 / 22.0。

## 6. 基準數據

### 6.1 iPhone 14 Pro Max 模擬器（debug，僅相對比較用）

2026-07-12 實測（iOS 26.5 模擬器、macOS host、debug + SCENE_PERF=1；
首頁、真實時間約 11:30＝白天光束/塵埃/地板光池全開）：

| 情境 | 幀率 | UI avg/p95 (ms) | raster avg/p95 (ms) | 備註 |
|---|---:|---:|---:|---|
| 冷啟動首 10s（w0） | 41.7fps | 8.9 / 9.1（max 1158） | 8.8 / 14.4 | 啟動 jank 含在內 |
| 首頁活躍（w1） | **55.8fps** | 2.7 / 5.9 | 7.3 / 15.0 | 超預算幀 21/558 |
| 閒置凍結生效（w2） | 3.3fps | 5.7 / 15.0 | 5.3 / 8.9 | 20 秒門檻在視窗中段觸發 |
| 閒置 >20s（w3–w23） | **0fps** | – | – | 連續 210 秒 0 frames ✅ |

重要發現：雖然三條場景 ticker 各自「節流 30fps」，但相位互不對齊、
兔咪呼吸 AnimationController 又是全速 60fps，合成後**活躍時整頁以
~56–60fps 排幀**。Phase 2 單一 20fps clock 的改善空間比帳面（30→20）大。

註：此輪量測時 Phase 1 的時間來源接線可能已編入（kernel 編譯與改檔並行），
但繪製結構、ticker 數量與 30fps 節流皆與基準版相同，幀數據可視為改造前基準。

### 6.2 實機 profile（待補）

無實體 iPhone 連線時無法取得；腳本與探針已備妥，插上實機執行 §5 指令即可。
10 分鐘耗電/溫度/記憶體趨勢亦需實機。

## 7. Phase 0 結論

- 結構性問題與計劃書 §2 描述一致：三條 30fps ticker、blur 超額、
  時間判斷 7 處門檻不一致、paint 期間讀 `DateTime.now()`、閒置時色罩停格。
- 省電骨架（閒置凍結/分頁凍結/總開關）已可沿用，Phase 1/2 在其上重構。
