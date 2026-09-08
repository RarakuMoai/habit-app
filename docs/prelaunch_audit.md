# 公開上架前檢查

> 只在準備公開 build 時使用。既有產品決策見 `roadmap.md`，當次上架範圍由使用者確認；技術雷區以
> `engineering_guardrails.md` 為準。最後更新：2026-09-08。

## 🔴 一定會忘記的那一條

- [ ] **`kDevToolsEnabled` 改回 `kDebugMode`** —
      [`lib/utils/feature_flags.dart:22`](../lib/utils/feature_flags.dart)
      目前是 `true`（自用 release 刻意開著），原始碼有 `RELEASE-BEFORE-PUBLISH` 標記。
      忘了改就是把開發者測試頁、SCENE_HOUR 與 seed 鉤子一起送上架。
- [ ] **購買 Apple Developer 付費帳號**（目前還沒買；免費個人帳號簽署只撐 7 天）。

## 產品與內容

- [ ] `MascotEmotion` 的 12 個正式情緒與眨眼關鍵幀皆通過實機視覺驗收。
- [ ] 習慣、計時、喝水、體重、家庭、衣櫃六個主要流程無阻斷問題。
- [ ] 金幣、每日登入、連勝、完成演出與台詞完整走過一次。
- [ ] 衣櫃文案與實際內容一致。**目前只有 `core/`，零套替換造型。**
      若公開版要提供換裝，先完成核准造型；若不提供，就調整文案與入口期待。
- [ ] 繪本回憶圖 ×4 補上（`story_catalog.dart` 有 4 個 `TODO(story-art)`，
      目前暫借場景圖，內容與事件對不上）。
- [x] 中英 ARB 國際化完成（實際字串集合以中英 ARB 為準）。
      剩餘中文字串見 `engineering_guardrails.md` §i18n，那些是刻意不遷的。

## 四時段背景

- [x] 有窗房間的晨／晝／暮／夜完整背景已完成：**home、water、timer、family**。
      ⚠️ **weight、wardrobe、game、onboarding 的畫面裡沒有窗景**，不需要四時段，
      維持單張是正確的——不要當成待補缺口。
- [ ] 相鄰背景 crossfade 不閃白、不跳構圖、不短暫露出錯圖。
- [ ] 兔咪的光向、色溫、接地與透明邊緣在四時段都自然。
- [x] 舊程式光影、動態窗景、glassless 與回退分支已移除
      （`room_ambient_overlay` 已不存在；現行角色融合只剩
      `mascotLightingForScene` 與 `RoomLightGeometry`）。

## 自動檢查

- [ ] `bash scripts/check_units.sh`
- [ ] `flutter analyze`
- [ ] `flutter test`
- [ ] 檢查 pubspec asset 無缺檔，release build 可完成。
- [x] Nunito / Baloo 2 已打包進 assets。
- [x] 本機匿名使用統計 v1 已接入。

## 必須本人實機確認（我做不到的）

- [ ] profile/release 的 BGM、音效與音訊切換正常；debug 有聲不算完成。
- [ ] 節拍器循環等速，計時器通知、鎖屏與回前景行為正確。
- [ ] 滑動、長按、衣櫃換裝、骰盤與主要互動手感正常。
- [ ] **摸頭手感**與**觸覺強度**（分頁切換、面板出現都是 selection）——模擬器摸不出來。
- [ ] 名片頭像的裁切參數。
- [ ] 主力手機與 SE 級小畫面無破版；四時段背景切換不造成明顯記憶體或發熱問題。
- [ ] 家長 PIN 設定、驗證、忘記救援與清空保底走完。
- [ ] 全新安裝的 onboarding 與資料保留／刪除流程走完。
- [ ] App Store 隱私說明、權限文案、截圖、icon、年齡分級與支援資訊齊全。

## 發布範圍與操作

- 當次公開版的功能、內容與免費範圍先由使用者確認；不套用舊文件的固定排程。
- 準備發布時以驗證已確認範圍為主，不順手加入大型新功能。
- 合併 main 與公開部署需使用者明確要求或確認；完成任務後自動 commit／push
  開發分支只保存版本，不代表發布授權。
- GitHub Pages 的 `.github/workflows/deploy.yml` 改為 `workflow_dispatch` 手動觸發。
  此設定需合入 main 才會取代遠端 main 的舊自動部署設定。
  執行部署前確認目標分支與版本，不在一般開發分支 push 時執行。
