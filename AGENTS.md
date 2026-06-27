# Codex 行為規則

## Git 推送
每次 commit 後自動執行 `git push`，不需要再問用戶。

## 完工通知
**不要手動執行通知腳本。** 完工通知交給 Codex CLI 的 `notify` hook 自動處理
（`~/.codex/config.toml` → `codex_notify_chain.sh` → `notify_codex_done.sh`）：
每輪結束時觸發、零 token、不進命令沙盒（所以不會被 DNS 擋）；問使用者選項而結束
該輪時同樣會通知。手動再跑 `notify_ai_done.sh` 只會重複通知、浪費 token、又踩沙盒，禁止。

## 主動上網查資料
遇到以下情況，直接用 WebSearch，不要先猜答案：
- 硬體規格、充電功率、價格
- 軟體新版本功能或 UI 變化
- 任何不確定或可能過時的資訊

## 單位系統（公制 / 英制）— 寫/改程式碼必守

App 同時支援公制與英制，使用者可在設定切換。

- **儲存與運算永遠用公制**（cm / kg / ml）：SharedPreferences、JSON、
  BMR/TDEE/BMI 公式輸入都當公制。
- **顯示一律用 `UnitFormat`**（`lib/utils/units.dart`）：`UnitFormat.height(cm, unit)`、
  `weight(kg, unit)`、`volume(ml, unit)`，或 `weightLabel(unit)` / `volumeLabel(unit)`。
- **輸入先轉公制**再驗證/存：`UnitConvert.lbToKg` / `flOzToMl` / `ftInToCm`，
  或 `UnitParse.weightKg(raw, unit)`。
- **每個畫面 state** 載入時讀 `UnitSystem.load(prefs)` 存進 `_unit`。
- **禁止在 Dart 字串字面值裡硬寫單位**（`Text('70 kg')`、`'$cup ml'`…）。
  `scripts/check_units.sh` 會擋下、pre-commit 直接 fail。真的必須寫死的（單位常數、
  設定說明文字）在行尾加 `// units-ok` 豁免。改完可手動跑 `bash scripts/check_units.sh`。

## 背景音樂（BGM）雷區 — 改音訊前必讀

`lib/utils/bgm_service.dart`（just_audio + audio_session，iOS `ambient`）：
- **絕不 `await _player.play()`** — just_audio 的 `play()` future 是「播到停止才完成」，
  await 它會卡住後面淡入＝靜音。一律 `unawaited(_player.play())` 再驗證狀態。
- **AOT（profile/release）冷啟動單次 play 常不 engage**（`playing` 一直 false）→
  音量 0 下反覆 pause→play 重踢到 `playing==true` 才淡入（見 `_engageCheck`）。別只測 debug。
- **AVAudioSession 只 configure 一次**（`AppAudioSession`），之後只 `setActive(true)`。
- Debug 音訊：`flutter run --release` 不印 log，用 `flutter run --profile`。

## 兔咪素材方向
兔咪近期不走 Rive / 骨架動畫路線。

目前產品方向是「高品質 CG 立繪差分 + Flutter 輕量演出」：
- 使用多張 PNG/CG 差分表達兔咪狀態、情緒與事件。
- Flutter 負責呼吸、輕微位移、縮放、彈跳、淡入淡出、星光等演出。
- 不在兔咪臉上硬畫 overlay，例如假眨眼或嘴型。
- 兔咪刻意保持幾乎沒有嘴巴，不做說話口型。
- 若需要眨眼、睡覺、開心、難過等動畫感，優先新增對應 PNG 關鍵幀。
- Rive 僅作為遠期可能升級，不作為目前實作前提。

## 兔咪生圖 / 差分編輯守則
涉及兔咪既有 PNG/CG 素材的差分、表情、狀態、事件圖時，優先使用 repo skill
`tumi-image-variants`。

- 只要已有核准的兔咪底圖，預設是 **edit / 局部修改**，不是重新 generate。
- 生圖提示詞必須明確寫出等效約束：**Do not redraw the whole image. Local edit only.
  不重繪，只局部修改。**
- 每次都要把底圖標成 `Image 1: edit target`；若是本機檔案，先用 `view_image`
  檢查，讓圖片進入上下文。
- 鎖定不變項：兔咪身份、臉型、耳朵、身體比例、整體輪廓、CG 質感、光照、色盤、
  構圖、畫布尺寸與透明背景（若原圖有）。
- 只改使用者指定的局部區域；避免改衣服、姿勢、道具、背景、畫風或表情結構，
  除非使用者明確要求。
- 禁止把原圖當「風格參考」後重畫一張新兔咪；使用者要完全新姿勢 / 新構圖時才可
  走 generate，且要先說明這會降低與原圖一致性。
