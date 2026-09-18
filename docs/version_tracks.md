# 三個 App 與固定程式來源

更新：2026-09-18。使用者指定只保留以下三個 iOS App 身分；Git 分支不是已安裝 App 的數量。
本頁是版本、路徑與指令的單一入口。前導、封面、新首頁及新故事工作都使用 beta。

| App | 用途 | 模式 / flavor | Bundle ID | 程式來源 |
| --- | --- | --- | --- | --- |
| 兔咪好習慣 | 保留舊首頁的正式 App | release / prod | `com.yayoi991331.habitapp` | `/Users/raraku/habit-app`，`codex/dev` 的舊介面程式；只有本人執行 prod 才更新 |
| 兔咪(測試) | 可即時修改與熱重載的開發 App | debug / dev | `com.yayoi991331.habitapp.dev` | `/Users/raraku/habit-app`，`codex/dev` |
| 兔咪測試版 | 新首頁、封面、故事的獨立測試 App；原名兔咪新體驗 | release / redesign | `com.yayoi991331.habitapp.redesign` | `/Users/raraku/habit-app-redesign`，`codex/beta` |

`flutter test` 執行自動測試；即時看程式變更使用 `flutter run --debug` 的 hot reload。
正式與 dev 目前沿用同一份舊介面程式，但 App 身分、資料及更新時機分開。
beta 程式獨立；更改 beta 不會自動套到正式 App，也不會合併 main。
改顯示名稱保留原 bundle ID；本人下一次更新同一 App 後才會看到新名稱，不需先刪 App。

## 保留的 Git 分支

- `main`：既有主線基準，本次保留 `2689934`，不合併、不改寫。未以手機二進位驗證它等於目前已安裝的正式版本。
- `codex/dev`：由 `codex/tumi-roommate-direction`／`057f2e4` 延續，保留舊介面與 debug 工作。
- `codex/beta`：由最新 `codex/beta-release-plan`／`aa0c5b4` 延續，包含新版首頁、V6 封面、V28 LOGO、七日回憶圖及 Xcode 27 相容性修正。
- `gh-pages`：僅為 GitHub Pages 的編譯輸出，不作程式開發；網站由 `codex/beta` 手動建置發布。

先前 `codex/experience-redesign`／`cb64372` 較舊，普通首次入口仍可能與最新程式不同。
最新 beta 的普通首次旅程是短初見；六幕前導保留於回憶。討論前導時須查 beta 的實際呼叫路徑。
2026-09-18 本輪劇本 A／B／C 為討論草稿，尚未定稿、生成素材或整合。

新任務直接在對應 dev／beta 延續，先檢查工作區，不再自動開額外長期分支。
若需另開隔離分支／worktree，先說明必要性並取得本人同意。
main 合併仍需本人明確要求。已完成改動在對應開發分支 commit＋push；push 不會自動部署網站。

## 本人使用的捷徑

重新開啟終端機，或先執行 `source /Users/raraku/habit-app/scripts/habit-shell.zsh`。

| 指令 | 行為 |
| --- | --- |
| `prod` | 在舊介面目錄執行 `flutter run --release --flavor prod`；更新正式 App 前由本人決定 |
| `dev` | 在舊介面目錄執行 `flutter run --debug --flavor dev`；`r` 熱重載、`R` 熱重啟 |
| `beta` | 在新介面目錄執行 `flutter run --release --flavor redesign`；更新兔咪測試版 |

`dev release` 保留為舊指令相容模式，更新的是同一個 `.dev` App，不是 beta，也不新增第四個 App。
捷徑會檢查來源分支；從 beta 目錄載入腳本，也不會把新版程式誤當作 prod 的來源。
AI 不安裝或啟動實體 iPhone／iPad。網頁檢查也不替代本人實機音訊、觸覺與效能驗證。

## 網頁測試版

- 網址：<https://rarakumoai.github.io/habit-app/>。
- 來源：`codex/beta`；在 GitHub Actions 手動執行 `Deploy Flutter Web to GitHub Pages`，指定此分支。
- 網站的 `version.json` 保存來源分支、完整 commit 與版本號，方便核對是否仍在看快取舊版。
- 瀏覽器資料存於該瀏覽器的網站儲存空間，不會直接同步三個 iOS App。

## 舊分支與本機資料

十個原開發分支已在刪除／改名前封存為 `archive/2026-09-18/<原分支主題>`，並核對 GitHub 標籤指向原 commit。
封存標籤是歷史還原點，不是另行維護的版本。
本機分支／worktree 盤點與 LOGO 未提交驗證檔，保存在
`/Users/raraku/habit-app/design_trials/version_cleanup_20260918/`；壓縮檔已逐檔核對 SHA-256。
既有 stash、主目錄設計試作與 redesign 目錄的封面候選保留，不因刪分支一併丟棄。
