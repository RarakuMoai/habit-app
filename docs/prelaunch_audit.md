# 上架前總體檢（Phase 0 出口閘門）

> 用途：當 app「差不多了、準備免費上架」時，照這份做最後總盤點，避免帶 bug 上架。
> 清單來源：[`roadmap.md`](roadmap.md) §5 / §6 / §7（Phase 0）。與 roadmap 衝突時以 roadmap 為準。
> 最後更新：2026-06-27。

---

## 怎麼跑（兩個 ultra 各司其職）

| 要查的東西 | 指令 | 性質 |
|---|---|---|
| 程式碼 bug / 邏輯漏洞（針對改動） | `/code-review ultra` | 專做多代理找 bug 的雲端審查 |
| 全 app 廣度體檢、規範一致性、清單對照 | `/effort ultracode` ＋ 下方 prompt | 通用深度＋並行模式 |
| 音訊 / 實機 / 購買 / 手勢 | 本人上實機，AI 代替不了 | 見最後一節 |

建議順序：先 `/effort ultracode` 跑廣度體檢 → 再 `/code-review ultra` 針對改動找 bug → 剩下實機項目本人收尾。
跑完 ultracode 記得 `/effort high` 退回一般，省 token。

---

## A. Phase 0 上架前清單（roadmap §7 出口閘門 = 免費上架）

**核心體驗（要「活的兔咪」級別的完成度）**
- [ ] 兔咪 8 張情緒差分打磨到「近乎完美、可上架」
- [ ] 首頁習慣、喝水、體重、計時、家庭頁不再因新功能大幅岔開，流程順
- [ ] 完成習慣後兔咪有演出 + 台詞，使用者每天回來有感

**留存引擎**
- [ ] 金幣（賺取 / 消耗迴圈完整）
- [ ] 每日登入
- [ ] 連勝（streak）
- [ ] 衣櫃 MVP：造型套用 / 預覽 / 目前穿著 / 預設核心套

**背景 v1**
- [ ] 每頁可換背景；免費層含 2–3 張金幣解鎖
- [ ] Flutter 動態光影 overlay（晨/晝/暮/夜）正常

**國際化 + 字型**
- [ ] 中英 i18n（新字串走 ARB / flutter_localizations，UI 預留長字）
- [ ] **字型打包進 assets**（Nunito / Baloo 2 目前是執行期下載 → 改成打包，roadmap §6）

**數據**
- [ ] 埋本機匿名使用統計（哪些頁被打開、哪些功能被用、衣櫃是否吸引回訪）

**清理**
- [ ] 移除 `debug_fake_tabs` 的記帳 placeholder（roadmap §5，記帳決定不做）
- [ ] 移除 / 隱藏所有 dev 測試入口、debug 工具（dev_test_page、debug_scene_hour 等）

---

## B. 可直接貼給 ultracode 的 prompt

> 先 `/effort ultracode`，再貼下面這段。

```
這是上架前的全 app 總體檢。請對照 docs/roadmap.md §7 的 Phase 0 出口閘門
與 docs/prelaunch_audit.md 的 A 清單，逐項檢查整個專案，目標是「免費上架前
不要帶 bug / 不一致 / 規範違反」。請從多個獨立角度交叉驗證，覆蓋率優先。

重點檢查（這些是本專案踩過的坑，CLAUDE.md 有記）：

1. 單位系統：所有顯示是否一律走 UnitFormat（lib/utils/units.dart）、輸入是否
   先轉公制再驗證、儲存運算是否都用公制。跑 scripts/check_units.sh 應全綠；
   有沒有漏網的硬寫單位字串（少數 // units-ok 例外要合理）。

2. SharedPreferences key：是否全部走 lib/utils/prefs_keys.dart 的 PrefsKeys，
   有沒有呼叫端硬寫 key 字串；帶日期的喝水 key 是否用 helper。

3. BGM 音訊雷區（lib/utils/bgm_service.dart）：有沒有 await _player.play()
   （絕不可 await）、AOT 冷啟動 engage 重試邏輯是否還在、AVAudioSession 是否
   只 configure 一次、play/ensurePlaying 並發是否有互讓。這些 release 才會炸。

4. 積分寫入是否都收斂到 applyPointsBatch 單一入口；音效/震動是否都走
   utils/app_feedback.dart。

5. 視覺一致性：是否都用 lib/utils/app_style.dart 的 token（暖棕陰影、卡片語彙、
   時段配色），有沒有散落的硬寫顏色/陰影。

6. 國際化：有沒有新的硬編碼字串該進 i18n；UI 排版有沒有英/德長字會破版的風險。

7. 清理：debug_fake_tabs 記帳 placeholder、dev 測試入口、debug 工具是否還露在
   正式流程裡。

8. 跨頁穩定性：shell 切頁、單位切換 listener、動畫期間切頁有沒有狀態殘留 bug。

請輸出：(1) 依嚴重度分級的問題清單（含檔案:行號）；(2) 哪些是必修才能上架、
哪些可上架後再修；(3) 哪些項目你無法靠讀 code 確認、需要我本人上實機驗證
（特別是音訊 release 行為、IAP、真實手勢）。不要自己定義「差不多」，以清單為準。
```

---

## C. AI 查不到、必須你本人上實機驗的（別漏）

ultracode / code-review 只看 code，下面這些**讀 code 看不出來**，要真機跑：

- [ ] **release 音訊**：BGM / 音效在 `flutter run --profile`（AOT）下真的有聲音。
      debug 有聲不算數（JIT 時序不同），照 CLAUDE.md「BGM 雷區」。
- [ ] **節拍器等速**：實機聽循環有沒有忽快忽慢。
- [ ] **真實手勢**：滑動、長按、衣櫃換裝、各頁互動實機順不順。
- [ ] **跨裝置破版**：至少切一台 iPhone SE 模擬器看小螢幕有沒有爆版。
- [ ] **App Store 審查素材**：隱私說明、權限用途文案、截圖、icon、年齡分級。
- [ ] **家長 PIN 流程**：設定 / 忘記救援（安全問題重設 + 清空保底）走一遍。
- [ ] **首次安裝體驗**：全新裝置跑 onboarding 全流程一次，無殘留舊資料。

---

## D. 不屬於 Phase 0（別插隊）

以下是 Phase 1+ 才做，上架前**不要**為了「更完整」而現在動：
- 劇情事件、節日活動、回顧/足跡主分頁（Phase 1）
- CloudKit 同步、訂閱三檔、商城（Phase 2）
- 多語言日文、季節商品（Phase 3）

> 提醒：roadmap §7 寫明「最大瓶頸是留存（Phase 1），不是變現」。Phase 0 把核心體驗
> 和留存引擎做扎實、乾淨上架就好，別過度規劃變現。
