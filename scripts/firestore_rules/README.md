# Firestore 備份規則本機測試

這組測試只使用 `demo-tumi-account-rules` 與 `127.0.0.1:8097` 的合成資料，不需要 Firebase 帳號，不會部署規則。測試程式在缺少 localhost emulator endpoint 時直接中止，避免 SDK 退回真正雲端。

2026-09-11 實測環境：Node 24.19.0、pnpm 11.19.0、Temurin JRE 21.0.12.1、Firestore Emulator 1.22.0。**18 個測試全部通過**。可攜式 JRE 與相依套件在 `/tmp` 安裝，沒有更改系統 Java。未把模擬器通過視為真實供應商登入或雲端部署完成。

在 Node、pnpm、Java 21 已可由 PATH 執行的環境，從此目錄執行：

```bash
pnpm install --frozen-lockfile --ignore-scripts
FIREBASE_EMULATORS_PATH=/tmp/tumi-firestore-emulator-cache pnpm test
```

測試結束後 `emulators:exec` 會停止模擬器。第一輪可能需下載官方 emulator JAR。依賴與暫存不加入 Git；本目錄的 lockfile 只固定測試工具版本，不改 Flutter 發行套件。

每例會明確等待所有 Firestore context 的 `terminate()`，最後再執行測試環境 `cleanup()`。SDK 仍可能保留背景 handle，因此指令使用 Node 官方 [`--test-force-exit`](https://nodejs.org/api/cli.html#--test-force-exit)，等全部 tests／hooks 完成後退出；assertion 失敗仍回傳非零，不用 `process.exit(0)` 掩蓋失敗。

覆蓋情境：

- 擁有者建立快照、分塊及 head 後讀回；Apple／Google 相同 UID 存取同一路徑。
- 未登入、匿名身分與不同 UID 拒絕讀寫／刪除。
- 已建立 manifest／chunk 不可修改；額外欄位、大小上限、錯誤 chunk index、缺少 manifest 都拒絕。
- head 必須指向既有且相符的 manifest；revision 必須從 1 開始、逐次加 1，previousSnapshotId 必須是上一份。
- 實際 transaction 以 revision 比對，另一台裝置拿旧 revision 不可提交。
- 清理不可刪目前與前一份快照；過舊快照允許刪除。
- 刪除帳號 tombstone 阻止遲到上傳，允許明確清理，不能撤銷 tombstone。
- 8 塊最多 256 KiB 的正式寫入批次可通過 security-rule 文件讀取上限。
- 其他 collection、正式版 namespace 與任意個人資料欄位沒有放行。
- 記憶體快取的 manifest／chunk 寫入在斷線後仍排隊；等待逾時、重連送達後，不會連帶發布 head。
- `disableNetwork` 停止一般 streams 後，transaction 仍可使用直接 RPC，不能把它當成取消提交的方法。App 使用明確 pending 保護；遲到成功／失敗及確認讀取逾時另外由 Dart write guard 測試覆蓋。

規則檢查資料歸屬與寫入結構。107 塊的完整性無法全靠一次 head 規則讀取驗證，app 的上傳完成流程與下載 checksum/schema 驗證仍是必要部分。

官方說明：[規則單元測試](https://firebase.google.com/docs/rules/unit-tests)、[Local Emulator Suite](https://firebase.google.com/docs/emulator-suite/install_and_configure)、[Temurin 安裝](https://adoptium.net/installation/)。
