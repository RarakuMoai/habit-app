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

## 下次恢復捷徑

在專案資料夾執行 `bash scripts/setup-mac-shell.sh`，再重開終端機。
腳本保留其他設定，修改既有檔案前會備份；重複執行不會重複加入設定。
