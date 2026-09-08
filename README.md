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

## 保存版本與發布

新任務從 main 開 `codex/<task>` 短期分支；完成並通過相關檢查後，自動 commit＋push。
合併 main 與公開發布另由你確認，合併完成後清除任務分支。Web 部署使用手動觸發。
停止開發的實驗保存在 `archive/<date>/<topic>` 標籤，需要續作時從標籤開新分支；
未提交的 stash 另行審核。
細節以 [AGENTS.md](AGENTS.md) 為準。

## 重灌／換電腦後恢復捷徑

在專案資料夾執行 `bash scripts/setup-mac-shell.sh`，再重開終端機。
它會把 `prod`／`dev` 加回 `~/.zshrc`，並設定 Homebrew 與
`~/development/flutter/bin` 的 PATH；既有設定若有修改會先備份。
Flutter、Xcode 與 CocoaPods 必須另外安裝。捷徑原始碼保存在
`scripts/habit-shell.zsh`，跟專案一起備份。

## 🚀 裝到手機（實機）— 三個指令

以下指令由使用者本人操作；AI 的裝置限制見 `AGENTS.md`。

| 指令 | 模式 | 哪顆 App | 用途 / 特性 |
|------|------|---------|------------|
| **`prod`** | release | 兔咪好習慣（正式） | 每天真的用；沿用既有資料，更新不會清空 |
| **`dev`** | debug | 兔咪(測試) | 開發用，按 **r** 熱重載／**R** 熱重啟；資料獨立 |
| **`dev release`** | release | 兔咪(測試)＊ | 能脫離電腦獨立跑的測試版 |

＊`dev` 和 `dev release` 是**同一顆**測試 App（同 bundle id），只是 build 模式不同、會互相覆蓋。
平常開發用 `dev`；想要一顆不接電腦也能跑的測試版就 `dev release`。

- 手機上只有**兩顆** App（正式 / 測試）並排，圖示與資料都分開。
- 從任何資料夾都能打（捷徑在 `~/.zshrc`，會自動進專案）；要指定裝置可加參數，例如 `prod -d <裝置名>`。
- 縮寫對照：`prod` = `flutter run --release --flavor prod`、`dev` = `flutter run --debug --flavor dev`、`dev release` = `flutter run --release --flavor dev`。
- 舊寫法 `dev debug`／`dev --debug` 仍可用，與 `dev` 相同；`dev --release` 與 `dev release` 相同。
- ⚠️ **別再用沒帶 flavor 的 `flutter run`**：它會落在「正式版」那顆（蓋過去）。要測就 `dev`／`dev debug`，要更新正式版才 `prod`。

## ⚠️ 免費 Apple 帳號：每 7 天要重簽

App 過 7 天點不開（顯示無法驗證）很正常 → 插線把那顆對應的 `prod` 或 `dev` **再跑一次**就好。
**資料會保留**，除非你「手動刪 App」。兩顆各自 7 天獨立計算。

## 🧹 flutter clean 安全嗎？

安全。只刪 Mac 上的編譯產物，**不碰手機 App、不碰資料、不碰上面這些設定**。
唯一影響：下次跑 `prod`／`dev` 會完整重建（比較久）。平常切換版本**不需要** clean。

## 🔁 prod / dev 程式碼怎麼同步？

**不用同步——它們跑的是同一份程式碼。** prod 和 dev 只差「裝在手機上是哪顆 App ＋各自的資料」，
程式碼（`lib/`）是共用的。所以你改完功能，想讓哪顆有新版本，就**重跑那顆**即可：

- 改完很滿意 → 要套到測試版：再跑一次 `dev`。
- 改完很滿意 → 要更新自己天天用那顆：跑一次 `prod`（**資料保留**）。

prod 那顆**只有你真的跑 `prod` 時才更新**；平常你邊改邊 `dev`，碰不到 prod。
唯一不互通的是**各自的資料**（不同 App = 不同儲存空間）。
