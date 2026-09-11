# 帳號與備份接線

2026-09-11。這份文件描述獨立 `redesign` 分支的實作與尚未接上的外部服務；**目前沒有 Firebase 專案設定、已部署規則或真實 Google／Apple 登入的端到端驗證**。

## 已實作的邊界

- 訪客直接使用本機存檔，不呼叫匿名 Firebase 登入，不要求網路。
- `AccountService` 提供真實登入 adapter、取消／錯誤狀態、供應商綁定、登出、重新驗證後刪除帳號，以及使用者明確操作的雲端備份。沒有自動上傳計時器或背景上傳。
- Firebase 設定缺漏時，狀態為 `unavailable`，不會假裝建立帳號或備份成功。Apple／Google 的啟用旗標各自獨立；尚未完成原生設定的供應商不能呼叫。
- 帳號登入只讀雲端備份。若已有遠端紀錄，先顯示本機與雲端選擇；沒有 UI 確認就不覆蓋。不同帳號即使雲端為空，也不能自動帶入前一位使用者的本機紀錄。
- 同一台裝置使用單一 `account_device_state_v1` JSON 收據保存 owner UID、確認過的 revision 與備份時間，排除於匯出檔之外。清除本機資料後重進入口會重新載入；遺失或損壞的收據不提供覆寫授權。
- Google 使用官方 `google_sign_in` 取得憑證，再交給 `FirebaseAuth.signInWithCredential`；Apple 使用 `AppleAuthProvider` 的原生流程。綁定使用 `linkWithCredential`／`linkWithProvider`，保留同一個 UID，遇到已屬於另一個帳號的憑證就回報衝突，不把兩份紀錄自行相加。

## 要啟用真實服務的外部設定

1. 選定使用者擁有的 Firebase 專案。建議 redesign 使用獨立測試專案，iOS app 註冊 `com.yayoi991331.habitapp.redesign`。不修改正式 App ID。
2. 啟用 Firebase Authentication 的 Google 與 Apple 供應商；建立 Firestore。此版只有文字紀錄，使用 Firestore 分塊快照，不依賴 Cloud Storage。Cloud Storage 現已要求 Blaze，若未來用它發送大型素材，需另外確認費用方案。
3. Google：取得該 iOS app 的 client ID，在 iOS URL types 加入其 reversed client ID，必要時設定 server client ID；僅要求登入身分，不要求 Google Drive／Contacts 等額外範圍。原生 Google SDK 官方仍要求這些設定，不能把一般 GoogleAuthProvider 的網頁 API 當成 iOS 替代品。
4. Apple：在 Apple Developer 為 redesign App ID 啟用 Sign in with Apple，更新對應 provisioning profile，為 redesign target 指定含 `com.apple.developer.applesignin = ['Default']` 的 entitlement。Firebase Apple provider 所需的 Team ID、Service ID 與 `.p8` private key 設在供應商控制台；private key 絕不可放進 Dart、build define 或 Git。
5. 本輪已完成下方 15 項本機 emulator 規則驗證；接上使用者選定的專案後，仍由使用者明確批准部署 `firestore.rules`。本輪不執行部署。規則目前只對 `tumi_backups_redesign` 放行；若 namespace 改變，須一起審核新 collection 與規則，不能用寬鬆全域權限代替。
6. 確認 Google／Apple 原生登入取消、首次同意、Apple 隱藏信箱、解除綁定與刪除帳號，再以兩個乾淨的模擬器測登入／備份／還原。Release 實機流程由使用者本人驗證。

公用識別設定由 `AccountCloudConfig.fromEnvironment` 讀取：

| Build define | 內容 |
|---|---|
| `TUMI_FIREBASE_API_KEY` | Firebase client API key（公用識別設定，仍須保護後端規則） |
| `TUMI_FIREBASE_APP_ID` | 該 iOS Firebase app ID |
| `TUMI_FIREBASE_PROJECT_ID` | 使用者選定的測試專案 ID |
| `TUMI_FIREBASE_MESSAGING_SENDER_ID` | 專案 sender ID；設定必要欄位，未啟用推播或分析 |
| `TUMI_IOS_BUNDLE_ID` | 預設 `com.yayoi991331.habitapp.redesign` |
| `TUMI_GOOGLE_IOS_CLIENT_ID` | Google iOS client ID |
| `TUMI_GOOGLE_SERVER_CLIENT_ID` | 需要時才填 Google server client ID |
| `TUMI_APPLE_SIGN_IN_ENABLED` | 完成 Apple 原生與控制台設定後才設 `true` |
| `TUMI_GOOGLE_SIGN_IN_ENABLED` | 完成 Google 原生與控制台設定後才設 `true` |
| `TUMI_FIREBASE_AUTH_DOMAIN` | Web build 才需要的 Firebase auth domain |
| `TUMI_BACKUP_NAMESPACE` | 預設 `redesign`；須與審核過的規則匹配 |

設定檔可用 `--dart-define-from-file=/absolute/path/account.redesign.json` 載入。指令仍維持 `--flavor redesign`。這些 define 不會自動建立 Apple capability 或 Google URL scheme，兩者必須以該專案真實識別值設定。

## 快照、還原與衝突

- 內容遵守 `BackupArchive` allowlist、型別、schema 與 checksum 驗證。包含個人稱呼、習慣及刪除墓碑、逐日喝水與體重紀錄、家庭與票券、金幣帳目及領獎判重、計時設定與紀錄、衣櫃與音樂收藏、故事與回憶。排除登入憑證、帳號收據、開發者狀態、家長 PIN、裝置權限及訂閱佔位值。新裝置還原後的家庭保護由 UI 重新設定。
- 單份 UTF-8 存檔上限 20 MiB；以每塊 192 KiB 原始 bytes 轉成最多 256 KiB base64 文件，共最多 107 塊，避開 Firestore 每份文件 1 MiB 上限。拆 bytes 後再 base64，中文字與 emoji 不會被錯切。下載驗證塊數、大小、UTF-8、transport SHA-256，再驗證 `BackupArchive`。
- 寫入先建立不可變 manifest 與 chunks，最後透過 transaction 把 `head` revision 加一，`expectedRevision` 必須等於伺服器目前 revision。斷網、其他裝置已更新或權限錯誤都不寫入「已備份」時間。
- `persistenceEnabled: false` 只停用磁碟快取，記憶體仍會排隊。未發布的 manifest／chunk 每次最多等待 20 秒；逾時後流程退出，重連後遲到的分塊不會自動提交 `head`。head 提交若 20 秒仍未確認，顯示「結果確認中」並解除 UI 忙碌，保留原生操作直到真正結束，其間不允許其他雲端讀寫。原生完成後的確認讀取失敗也進入相同狀態；重新整理必須讀伺服器再判斷衝突，不把逾時宣稱為取消。
- 目前核對 `cloud_firestore` 6.9.0 的 `FLTTransactionStreamHandler.m`：`runTransaction(timeout)` 僅限制 Dart callback 等待，並非整個 RPC 的取消期限；iOS SDK 12.18.0 的 `GrpcConnection::CreateContext` 也未設定本機 deadline。本輪保留原生 CAS、限制為一次嘗試；無法在 SDK 完成前判定的提交持續列為確認中。App 重啟仍須以伺服器狀態和舊本機 receipt 重新比對，不沿用不確定的 revision。
- `head` 保留前一份 snapshot ID；清理保留目前與前版，只清除早於伺服器成功時間一天的其他 snapshot。成功結果不等待清理，每次最多一個清理流程，刪除等待亦有上限；清理失敗不影響已完成備份，下一次使用者備份會重試。受限於掃描上限，長期大量失敗的孤立分塊仍需後端維護檢視。
- 還原交給 `BackupRestore.stage()` 與啟動時的 `recoverPending()`。`AccountService` 不會自行改習慣資料，也不把讀到雲端檔案視為完成還原。只有確定還原完成後才接受該 revision 的 receipt；還原中斷先恢復 journal，不能進入首頁顯示一半的資料。
- `StorageSnapshotGate` 在匯出前等待完整的已追蹤操作，暫緩新的寫入；涵蓋換日協調、金幣／帳目、家庭點數／票券、衣櫃購買／音樂選擇、故事、個人資料及計時。鎖順序固定為 Snapshot → Logical → BackupStorageLock，包含重入與過期 async owner 測試。仍沿用 SharedPreferences 與各 store 原有失敗恢復，不提供既有多 key 寫入的交易回滾，也不是跨裝置即時同步。

## Firestore 規則候選與驗證

`firestore.rules` 限制 owner UID、非 anonymous identity、指定 collection、manifest 欄位／大小、immutable chunks、head revision +1 與 prior pointer。只有帳號刪除 tombstone 可以刪 head；一般清理不能刪目前或前一份快照。

規則無法在一次 head 寫入中讀完 107 個 chunk 驗證完整性（Firestore security rules 有文件讀取上限）；合法 app 在上傳每塊收到 server acknowledgement 後才提交 head，讀取端也會再次全面驗證。這是使用者自有存檔的完整性保護，不是防作弊或金流驗證。

帳號刪除先重新驗證，Apple authorization code 先交 revoke API，再寫入 deletion tombstone 阻止其他裝置補傳，刪除 snapshots/head，最後刪 Firebase user。本機內容留作訪客存檔。中途失敗可重試；tombstone 僅保留 UID 路徑與刪除布林，不含個人資料。正式上線前需訂定這類技術墓碑的保存期間與清理流程。

本輪帳號／codec／write guard 的 27 項 Dart 測試通過，涵蓋無設定、重複 initialize、訪客綁定、已有雲端需選擇、stale revision、讀取／上傳斷網、取消登入、同 UID 重啟、換帳號空雲端、清空本機收據、還原 revision、存檔分塊損毀與多語言邊界，以及遲到提交、確認讀取逾時與重啟後禁止未經確認的覆寫。Firestore Emulator 1.22.0 已完成 18 項本機合成資料整合測試（全部通過）：未登入與不同 UID 全拒絕、owner 正常建立及讀回、修改 manifest/chunk 拒絕、漏欄位與超限拒絕、head revision 跳號／倒退拒絕、錯 prior pointer 拒絕、目前/前版刪除拒絕、delete tombstone 後新寫入拒絕，並驗證 8 塊正式大小批次符合 rules 存取上限。另以記憶體快取實際重現 manifest／chunk 斷線排隊、等待逾時、重連後分塊送達但 head 不變，也驗證 `disableNetwork` 不能當作 transaction 取消 API。可重跑程式與固定相依版本見 [scripts/firestore_rules](../scripts/firestore_rules/README.md)。

## 官方來源與素材

- [Firebase Flutter 設定](https://firebase.google.com/docs/flutter/setup)：目前要求 iOS 15 以上，CLI 產生的是公用平台識別設定。
- [Firebase Flutter 社群登入](https://firebase.google.com/docs/auth/flutter/federated-auth)：Google 原生 SDK、Apple 原生 provider、綁定與 Apple token revoke。
- [Google iOS plugin 設定](https://pub.dev/packages/google_sign_in_ios)：client ID 與 reversed client ID URL scheme。
- [Google 登入品牌規範](https://developers.google.com/identity/branding-guidelines)：`assets/icon/ui/google_sign_in.png` 使用[官方 G PNG](https://developers.google.com/static/identity/images/g-logo.png)，未自行改色或繪製。
- [Firestore 限制](https://firebase.google.com/docs/firestore/quotas)、[交易與批次寫入](https://firebase.google.com/docs/firestore/manage-data/transactions)、[權限條件](https://firebase.google.com/docs/firestore/security/rules-conditions)。
- [Firestore 離線與記憶體快取](https://firebase.google.com/docs/firestore/manage-data/enable-offline)、[Apple TransactionOptions](https://firebase.google.com/docs/reference/swift/firebasefirestore/api/reference/Classes/TransactionOptions)。
- [Cloud Storage 計費方案要求](https://firebase.google.com/docs/storage/faqs-storage-changes-announced-sept-2024)：本輪不使用 Cloud Storage、不啟用 Blaze。
