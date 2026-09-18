# 兔咪好習慣

Flutter 習慣陪伴 app，以 Codex／GPT-6 為主要開發工具。

## 專案入口

- AI 協作規則：[AGENTS.md](AGENTS.md)，依任務查閱詳細規範。
- 產品現況與既有決策：[docs/roadmap.md](docs/roadmap.md)。
- 待補素材：[docs/pending_assets.md](docs/pending_assets.md)。
- 舊素材試聽／預覽與去留審核：[asset_review/README.md](asset_review/README.md)。
- 公開上架檢查：[docs/prelaunch_audit.md](docs/prelaunch_audit.md)。
- Mac 恢復紀錄與通知設定：[docs/macos_recovery_2026-09.md](docs/macos_recovery_2026-09.md)。

`lib/` 放程式，`test/` 放測試，`assets/` 放正式素材，`scripts/` 放維護工具。
`asset_review/` 放待本人審核的舊素材與工具，不隨 app 打包。
模型選擇與個人工具設定留在 Codex 使用者／任務設定，不放進共用專案規則。

## 三個版本與開發入口

版本、Bundle ID、來源分支與封存方式統一見 [docs/version_tracks.md](docs/version_tracks.md)。
舊介面程式在 `codex/dev`，新版程式在 `codex/beta`；`main` 保留原基準。
新首頁、封面、前導與故事都在 `/Users/raraku/habit-app-redesign` 繼續。

| 本人執行的指令 | App | 用途 |
| --- | --- | --- |
| `prod` | 兔咪好習慣 | 舊首頁正式版，release |
| `dev` | 兔咪(測試) | 舊介面 debug，r 熱重載／R 熱重啟 |
| `beta` | 兔咪測試版（原兔咪新體驗） | 新版首頁與故事，release |

三個 App 的 bundle ID 與資料各自獨立。`dev release` 只是舊 dev App 的相容模式，並非 beta。
`flutter test` 是自動測試指令，不是即時開發 App。
以上實機指令由本人操作；AI 的裝置限制見 AGENTS.md。

## 捷徑與版本保存

重新開啟終端機，或執行 `source /Users/raraku/habit-app/scripts/habit-shell.zsh`。
換電腦後執行 `bash scripts/setup-mac-shell.sh` 恢復捷徑；Flutter、Xcode、CocoaPods 需另行安裝。
`flutter clean` 只清本機編譯產物；改名沿用原 bundle ID，不需刪除手機 App。

在對應 dev／beta 分支完成檢查後 commit＋push。合併 main、發布與部署須有本人授權；
停止開發的舊分支已封存為 archive 標籤。固定 dev／beta 不隨日常任務結束而刪除。

## 網頁測試版

[開啟兔咪測試版](https://rarakumoai.github.io/habit-app/)。
網頁從 `codex/beta` 手動建置，`gh-pages` 只存編譯結果；不隨 push 自動部署。
可用網站的 `version.json` 核對來源 commit。瀏覽器測試不能取代本人 iOS 實機驗證。
