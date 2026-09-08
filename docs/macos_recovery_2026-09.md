# Mac NEO 開發環境恢復紀錄（2026-09-08）

這是本次重灌的恢復紀錄，不是產品方向或長期工程規則。

## 已恢復與驗證

- 專案：`/Users/raraku/habit-app`。
- Git 遠端原本仍在：`https://github.com/RarakuMoai/habit-app.git`。
  已重新登入 RarakuMoai，執行 `gh auth setup-git`，push dry-run 成功，
  GitHub API 確認 `permissions.push = true`。
- Git 姓名／email 已依原提交紀錄恢復至使用者設定。
- Flutter 3.41.9／Dart 3.11.5（依備份 `.dart_tool/version` 與
  `ios/Flutter/Generated.xcconfig` 判定），SDK 在 `~/development/flutter`。
- 以 `flutter pub get --enforce-lockfile` 還原依賴，本機生成路徑已更新；
  `pubspec.lock` 未變更。
- `~/.zprofile` 加入 Flutter 與 Homebrew 的 PATH；`~/.zshrc` 載入
  `scripts/habit-shell.zsh`。重開終端機生效。
- 捷徑保持 README 原本行為：`prod` 正式 release、`dev` 測試 release、
  `dev debug` 測試 debug；也支援舊寫法 `dev --debug`。
- 捷徑以 mock Flutter 驗證參數、專案路徑與裝置名稱帶空白的傳遞；
  不允許另帶 `--flavor` 意外改裝另一顆 App。
- VS Code 已安裝 Dart-Code 的 Flutter／Dart 擴充套件。
- Homebrew 6.0.22、Xcode 26.6、CocoaPods 1.17.0、GitHub CLI 2.100.0 已安裝。
- Xcode 授權條款已接受，Developer 目錄已指向完整 Xcode。
- iOS 26.5 模擬器 runtime 已安裝。
- `flutter analyze --no-pub`：No issues found。
- `flutter test --no-pub test/mascot_test.dart test/units_test.dart`：40 tests passed。
- `flutter doctor -v` 的 Flutter、Xcode／CocoaPods、Chrome、裝置與網路檢查通過。
  Android SDK 尚未安裝；本次恢復的是原 iOS 工作環境。
- `flutter build ios --simulator --debug --flavor dev --no-pub` 成功。
  iPhone 17 Pro 模擬器／iOS 26.5／dev debug／全新資料下成功啟動至引導頁，
  文案為「你想開始時，我會陪你。」，截圖尺寸 1206 × 2622 px。
  產物名稱為「兔咪(測試)」，bundle ID 為 `com.yayoi991331.habitapp.dev`。
  首次模擬器初始化曾停在 LaunchServicesMigrator；只重啟該模擬器後完成。

## 尚待完成

1. 使用者已確認 Xcode 登入原 Apple 帳號；有效本機簽署憑證與手機更新仍待驗證。
   Xcode 的舊開發憑證顯示「Not in Keychain」；已引導使用者在
   Manage Certificates 的「＋ → Apple Development」建立新憑證。
   建立時出現「You already have a current Development certificate or a pending
   certificate request」；目前尚未解除，也沒有撤銷舊憑證。
   原專案 team 是 `6NZ675Y2MZ`，
   正式 bundle ID 是 `com.yayoi991331.habitapp`，
   測試 bundle ID 是 `com.yayoi991331.habitapp.dev`。
   不應為了繞過簽署錯誤而改正式版身分或刪掉手機 App。
2. 模擬器的 iOS 編譯與啟動已驗證；手機 release 簽署與更新尚未驗證。
   本次未對實體手機執行安裝或啟動。
   使用者已確認手機正式 App 還在、存檔應該也在；內容尚未實際開啟驗證。

## Codex／Astra

- 使用者已說明要充分使用 Pro 的 Astra，並授權按任務使用合適工具與技能。
- 保留 `gpt-6-astra`，使用者層的 `model_reasoning_effort` 從 `high` 改為 `max`。
  較高推理可能更慢、使用更多額度；既有任務若有覆寫值，以任務設定為準。
- 舊設定已備份在
  `~/.codex/config.toml.before-mac-restore-20260908-074654`。
- 沒有發現手動縮小上下文的設定；既有工具與專案技能可用。
- Codex 內建診斷的設定、登入、資料庫與服務連線正常；
  唯一 fail 是這次非互動工具終端的 `TERM=dumb`，不是 Astra 模型失效。
- 沒有找到重灌前的全域 Codex／zsh 設定備份。

## Codex 手機通知

- 使用 Codex `notify` 的 `agent-turn-complete` 事件通知 ntfy。
  代表本輪已停止，可能完成或需要使用者回覆，不能證明整個任務成功。
  中途進度、工具完成與其他事件不發送；程序當掉、強制結束、網路中斷或
  回合中等待權限，不保證有這個事件或通知。
- 手機 ntfy 訂閱原有的 `https://ntfy.sh`／`habit-tumi-x7k2m9q4`，並開啟通知權限。
  因為舊 topic 已存在專案紀錄，通知只傳固定提醒，不包含對話、程式或檔案路徑。
- 全域 `~/.codex/config.toml` 的 `notify` 改接 dispatcher；原本 computer-use 的
  `turn-ended` 程式完整保留在 `~/.codex/phone-notify/settings.json`，並行呼叫。
  設定備份：`~/.codex/config.toml.before-phone-notify-20260908-084243-250219`。
- dispatcher 安裝到 `~/.codex/phone-notify/dispatch.py`，不受專案切換分支影響。
  網路暫時故障最多嘗試 3 次；以 thread-id + turn-id 加鎖去重，HTTP 成功後才記錄。
  如果伺服器收到但回應遺失，重試仍可能重複；不是保證送達一次的訊息系統。
- `~/.codex/phone-notify/state/notify.log` 記錄伺服器接受或傳送失敗，
  不記錄對話內容。伺服器接受不等於手機已顯示。
- 已通過 9 項離線測試，涵蓋事件篩選、並行去重、失敗後重試、UTF-8、
  不洩漏對話、原 handler 參數保留、設定備份與重複安裝。
  **尚待手機端確認正常回合結束後實際收到通知。** 本次沒有手動傳送完工通知。
- 重開 Codex 確保載入設定，再用一句簡單訊息觸發正常回合結束測試。
  舊的 `scripts/notify_codex_done.sh` 未掛接；目前不使用它猜測完成狀態。
- 重新安裝或更新此設定：
  `python3 scripts/setup_codex_phone_notify.py --topic habit-tumi-x7k2m9q4`。
  若其他外掛改寫 `notify`，可重新執行安裝以保留當時 handler 並恢復 ntfy。
  回復方法：將設定檔頂端的 `notify` 陣列改回 settings.json 的 `original_notify`；
  不需還原整份備份，以免覆蓋後來的其他設定。

官方參考：[Codex notifications](https://learn.chatgpt.com/docs/config-file/config-advanced#notifications)、
[ntfy JSON 發送](https://docs.ntfy.sh/publish/#publish-as-json)、
[ntfy 手機訂閱](https://docs.ntfy.sh/subscribe/phone/)。

## 下次恢復捷徑

在專案資料夾執行 `bash scripts/setup-mac-shell.sh`，再重開終端機。
腳本保留其他設定，修改既有檔案前會備份；重複執行不會重複加入設定。
