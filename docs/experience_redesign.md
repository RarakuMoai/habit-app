# 日常手帳體驗改版

日期：2026-09-10。使用者授權以獨立分支大幅改善全 App 的視覺、操作、動畫與音效，
新版先作可操作的體驗候選，之後再決定整體採用或挑選移植。

## 版本與比較基準

- 實驗分支：`codex/experience-redesign`。
- 基準：`0737a7d`（已整合核准的霧藍月牙睡衣與室友對話）。從最新 `origin/main`
  建立新工作樹後，只把既有開發版本快轉帶入實驗分支；沒有合併或推送主線。
- 本機工作樹：`/Users/raraku/habit-app-redesign`。原本的 `habit-app` 工作目錄與
  `codex/tumi-roommate-direction` 保留，可以獨立比較。未提交的美術候選沒有搬動。
- 本輪沒有重繪兔咪、改動正式 PNG、改習慣／身體資料算法或重新定價。

## 改版方向與各頁處理

主題是有生活感、安靜且可讀的日常手帳。房間與兔咪仍是陪伴的主角，功能介面以
紙色、深綠墨色、低飽和的頁面識別色承接。新增 `app_theme.dart` 統一表單、按鈕、
彈出層與文字；實際數值以 `app_style.dart` 為準。

| 範圍 | 新版行為與目的 |
| --- | --- |
| 主導覽與共用外框 | 浮動導覽、明確選中標籤、分頁短淡入；保留 IndexedStack 狀態、捲動與 iOS 原生返回手勢。紙色功能面板與房間分層，日期在窄版可完整放入。 |
| 首頁 | 今日標題、簡短提示、完成數與進度集中在清單前。新增操作明確，空清單有完整文字與 CTA；每日卡完成前後維持同樣的最小高度及字級，避免點擊後突然縮小。 |
| 計時 | 四模式導覽、設定、主計時舞台與主操作分層。寬版主按鈕，窄版將次操作分行，不把整組按鈕縮成難點的小圓。環形儀表降低強光。 |
| 喝水 | 數字／水瓶／連續進度的主卡，建議不再替換今日數據。全寬加水主操作常駐，少一杯與自訂有文字；近期紀錄可捲讀。 |
| 體重 | 莓果色數據主卡、兩欄可讀指標、趨勢範圍切換與歷史編輯；窄版仍能捲讀指標及操作。 |
| 家庭 | 名冊的姓名與積分分開呈現；孩子任務、獎勵與家長管理頁沿用新的卡面及文字層次。 |
| 衣櫃／音樂盒 | 三欄分類索引、較大的選物卡、明確穿著／選取／主操作。窄版商品退成單欄，保留售價、購買確認、試聽與播放清單規則。 |
| 回顧 | 錢包、週月切換與各功能統計收進同一閱讀捲軸，短螢幕不再被固定工具列吃掉主要閱讀區。 |
| 設定／個人資料 | 清楚的區段、低噪音卡片、可換行標籤，改善長英文、生日列與單位列。資料清除與補登沿用相同紙色。 |
| 前導 | 共同選項卡、清楚的前進箭頭與數字分段進度，保留既有步驟與資料選擇。 |
| 回憶與揭曉 | 空回憶清單不崩潰；短螢幕保留完整插圖並讓字幕捲讀；降低動態時取消縮放／位移。每日報到原有編排保留。 |

## 動畫與聲音

- 新 `AppPressable` 保留原觸控區，只做輕按回饋，不自己觸發業務音效／觸覺。
- 新的切頁、按壓、列表與前導轉場會讀取降低動態偏好；水瓶與計時的持續動畫
  也補上停止／立即呈現狀態的處理。
- 打卡勾的筆尖觸底仍是主觸覺／音效的時間點，原完成事件的語意與租約規則保留。
- 新增四個原創短音檔：點擊 115ms、取消 160ms、成功 400ms、完成 560ms。
  使用短木質起音和柔和的和聲尾音，取消比成功更輕；程式可重建，見
  `scripts/audio/generate_diary_cues.py`。使用新的檔名，不覆蓋舊音檔或依賴舊快取。
- 喝水、兔咪 MI、背景音樂、報到及遊戲的專屬聲音保留；導覽仍只用輕觸覺。
- 修正靜音／取消和非同步播放的競爭：停止後的舊請求不應再播放，靜音會停止
  現有音效及取消待播，解除靜音不復活舊請求；金幣連奏保留獨立聲道。

## 驗證方式

`integration_test/experience_review_test.dart` 使用正式 App root、真實字型／素材、
本機記憶體測試資料，走六個主分頁、設定、足跡、喝水展開／加水及室友入口。只在指定 iOS 模擬器執行，沒有
讀寫正式 App 的使用者資料。輸出 PNG 在測試程序印出的 `experience-review` 目錄。

```sh
flutter analyze --no-pub
flutter test --no-pub
flutter test integration_test/experience_review_test.dart --flavor dev \
  -d <iOS-simulator-UDID> --dart-define=APP_LOCALE=zh --dart-define=SCENE_HOUR=10
```

原生整合測試結束時會移除測試 App，截圖必須在 teardown 前保存。可用專用工具
自動驗證目標是已開機的模擬器並即時複製 PNG：

```sh
python3 scripts/review/run_simulator_review.py --device <iOS-simulator-UDID> \
  --output /tmp/tumi-experience-review
```

### 2026-09-10 驗證結果

- `flutter analyze --no-pub`：零問題。
- `flutter test --no-pub`：完整 **900 / 900** 通過。
- 原生整合測試：**通過**，保存 11 個新版狀態，並確認喝水由 1000 增為 1250 ml。
  原版基準另跑相同的七頁比較流程並通過。
- 原生環境：iPhone 14 Pro Max、iOS 26.5 模擬器；430 × 932 邏輯尺寸、3 倍像素；
  dev/debug、繁體中文、上午 10 點場景、預設字級、一般動態；128 足跡幣、3 個每日習慣、
  1 個每週習慣、2 個孩子及 14 筆體重紀錄，全部為記憶體 fixture。
- Widget 測試另覆蓋 320 × 667、430 × 932、中英文、1.3 倍文字、降低動態、空／有資料，
  並驗證主導覽、計時及資料操作；不把 widget 通過等同實機觀感或效能結論。
- 已目視檢查原生截圖：六個主頁、設定與四個延伸操作狀態；另經獨立 diff 審查。
- 新音檔可解碼、峰值不削波；靜音與取消的非同步競態測試通過。聲音喜好與實機觸覺待本人試用。

### 新舊比較與音效樣本

[開啟本機比較頁](../design_trials/experience_redesign/review/index.html)，可切換並排／原版／新版，
查看 18 張原生截圖匯出、喝水操作後狀態與四個音效播放器。
[六主頁總覽](../design_trials/experience_redesign/review/overview.jpg)。
圖片為原生 PNG 等比例縮小的 WebP；來源尺寸及雜湊見同目錄 `capture-manifest.json`。
角色眨眼屬即時動畫，截圖間可能不同。比較頁是驗收材料，不是互動 App 或效能錄影。

重建比較頁需 Python 與 Pillow，輸入上述工具保存的 `before/`、`after/` 目錄：

```sh
python3 scripts/review/build_experience_comparison.py /tmp/tumi-redesign-review
```

## 本人試用與選擇

使用獨立的 `redesign` iOS flavor 安裝 **release** 測試版，主畫面名稱為「兔咪新體驗」。
Bundle ID 是 `com.yayoi991331.habitapp.redesign`，與正式版 `.habitapp`、
舊測試版 `.habitapp.dev` 不同，可並存且從獨立的新資料開始；不匯入或覆蓋原版資料。
這是本機裝置測試，不是 App Store／TestFlight 發布。

接上並解鎖 iPhone，在改版工作目錄由使用者本人執行下列指令；多個裝置時選自己的 iPhone。
AI 不對實體裝置安裝或啟動 App。

```sh
cd /Users/raraku/habit-app-redesign
flutter run --release --flavor redesign -t lib/main.dart
```

不要使用既有 `prod`／`dev release` 快捷指令安裝本次候選；那些仍指定原本的 App 身分，
而且 shell 快捷指令可能固定回到原工作目錄。新 flavor 的 Debug／Profile／Release 均使用
獨立 ID；一般 Xcode Run 預設 Debug，release 試用請使用上述完整命令。
新 App ID 的裝置簽署由 Xcode 的開發團隊設定處理；若出現 provisioning 錯誤，保留完整錯誤
再排查，不刪原 App 或變更舊版 ID。

2026-09-10 已完成 `flutter build ios --release --flavor redesign` 的簽署建置，
核對實際產物的名稱、Bundle ID、簽署 application identifier，並通過
`codesign --verify --deep --strict`。三種新版配置的 ID 均獨立，原有配置的 build settings
逐項比對未變。沒有安裝／啟動實體裝置；release 實機體驗仍待本人驗收。

設定方式依 [Flutter 官方 iOS flavors 文件](https://docs.flutter.dev/deployment/flavors-ios)，
新增 shared scheme、三種 build configurations 與 Podfile 對應。

優先走「新增／完成習慣 → 開始／暫停計時 → 加水與復原 → 記體重 → 家庭任務
→ 換裝／試聽 → 回顧」一整圈。觀察主操作是否更容易找到、字是否好讀、完成回饋
是否舒服，以及快速開關聲音／快速放開摸兔咪時是否即時停止。再看小螢幕、放大字、
鍵盤與降低動態下的操作。模擬器不能代替實機聲音、觸覺、啟動耗時、耗電及 release
流暢度的結論。

取得實際使用比較後，再決定整條分支採用或分組移植；主線合併與發布另依使用者確認。
