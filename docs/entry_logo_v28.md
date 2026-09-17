# 五字平衡 LOGO：測試版實裝

2026-09-17：本人選擇 27「暖奶油・五字平衡」，要求兩片葉子稍微鮮豔，再直接實裝測試。
延續最新已保存封面基準 `codex/entry-integration`／`37bf62d`；舊 tmp 目錄仍有檔案但
已遺失 `.git`，因此保留原目錄，另建 `/Users/raraku/habit-app-entry-logo`，
分支 `codex/entry-logo-fresh-leaves`。舊目錄 `entry_cover.dart` 與該基準 SHA-256 相同。

## 本輪範圍

- 使用 `redesign` flavor，bundle ID `com.yayoi991331.habitapp.redesign`，
  版本 `1.0.1+2026091701`；不更新正式版、不安裝或啟動實體手機、不合併 main 或發布。
- 圖片是 27 的局部生成編輯；保留五字構圖、暖奶油字色、白底橘勾、兩道金光及柔布感，
  只要求加強左側兩葉的綠色。生圖仍有微小紋理差異，不宣稱保護區逐像素一致。
- 新檔 `assets/scenes/onboarding/entry_logo_zh_v28.png`；舊 V4 LOGO 保留，可回退。
  來源為 `design_trials/tumi_logo_styles_20260917/logo_28b.png`（原主工作區）。
- 內建 image_gen 編輯，沒有宣稱特定 API／Image 2.5 模型。提示詞保存於
  [entry_logo_v28_prompt.txt](entry_logo_v28_prompt.txt)。首輪配色偏保守，未採用。
- 1536×1024 RGBA，alpha 0–254；alpha ≥128 外框 `(200,122)–(1412,916)`，
  SHA-256 `df0864495ac55b435e889d559c75a93b3c1dbf17d283bec030fc8080bdfa5f09`。

## 真實版面

`AppEntryPage` 的 Scaffold body → `EntryCover` → 全畫面 LayoutBuilder／ClipRect／Stack。
保留原 `EntryCoverLayout`、背景 BoxFit.cover、頭頂保護線、safe area、LOGO 微浮動／掃光、
提示、52pt 語言／設定按鈕。新 PNG 按實際字形範圍等比置中於原標題區，
不以整張含透明留白的 PNG 寬度決定字的大小，也不額外加陰影。

430×932pt、safe top 59／bottom 34：原標題區仍是 x=32.25、y=75、width=249.4，
height=249.4×963/1233。新字形可見寬度 249.4pt、高度約 163.4pt，置中於該區。
背景、門口兔咪、短初見、前景葉叢、配樂與使用者存檔流程沒有修改。
繁中開始文案「輕觸開始」，回訪「繼續一起生活」；既有英文模式仍使用同一核可中文品牌圖。

## 編譯相容性

首次 Xcode 27 編譯因 Pods 的 iOS 9–13 deployment target 失敗。
帶入目前主工作區 `057f2e4` 的同一 Podfile 修正，僅把低於 15 的 plugin targets 提升至 15；
原 Runner 已為 15，無需變更 bundle ID、簽章或套件版本。

## 驗證

靜態分析無問題。完整回歸共 1,251 項：1,250 項通過，唯一失敗為本輪新增的圖形比例
量測把微旋轉後的外接矩形誤當作字圖邊長（1.5089 vs 1.5）。改為量測轉換後兩邊的
向量長度，沒有修改產品動畫；其後封面／入口／初見／音訊 49 項全部通過。
新 PNG 的實際解碼、透明 alpha 外框、等比縮放、safe area、五種螢幕尺寸與控制項
均有測試覆蓋。完整回歸與最終精準測試分開保存，未宣稱修正後重跑整套全綠。

單元測試改在獨立暫存 worktree 執行，避免與 iOS 編譯共用 `build/` 導致資產暫時缺失。
最終受測的 Dart、測試、pubspec 與 PNG 均逐位元等同實裝工作目錄。
記錄在 `design_trials/logo28_regression.json`、`logo28_targeted_final.json` 與
`logo28_analyze_final.log`，保留本機、不納入資產包。

原生驗證通過：iOS 26.5 專用模擬器、430×932pt、safe top 59／bottom 34、
繁中、字級 1.0、一般動態，使用真正 App root 與 process-local 測試資料，非 HTML 合成。
封面、風動、語言、設定、開始選擇、兩幕初見、真正首頁、計時開始／暫停共 11 張
原生截圖，測試 exit 0、擷取錯誤 0。已檢視封面：字圖沒有裁切、沒有遮住兔咪，
兩片葉子有鮮綠點綴、白底橘勾可辨識，左右下角控制與原背景保留。
證據：`design_trials/logo28_native_large_v2/01-cover.png` 與同目錄 `capture.json`。
編譯產物 Info.plist 核對 bundle ID 與 build number 均符合本頁。

其後以正常 `lib/main.dart`／Debug-redesign 在同一模擬器啟動（非 integration test），
增量編譯 41.3 秒成功；已擷取無測試標籤的
`design_trials/logo28_native_main.png`（1290×2796 像素／430×932pt），並解除 debugger
連線、保留 App 運行，可在模擬器直接操作。當時尚未建立實機 Release 產物。

模擬器只驗證構圖、互動與流程；實機冷啟動、字的第一眼份量、葉子色彩及手感仍由本人確認。

## 2026-09-17 Release 編譯排查與交付

本人回報 `Running Xcode build...` 長時間沒有進度。Xcode 結果檔顯示前兩次
Release-redesign build 分別約 872.4 秒、93.5 秒後以 `cancelled` 結束，均為 0 errors；
不能把取消紀錄當作編譯成功，也沒有證據顯示是簽章失敗。
此次保留既有編譯快取，在本工作區執行
`flutter build ios --release --flavor redesign --no-pub -v`，觀察到 Dart frontend／AOT
實際運算，最後 Xcode build 118.9 秒成功，Flutter exit 0。

產物 `build/ios/iphoneos/Runner.app` 為 191.6 MB，`codesign --verify --deep --strict`
通過；Info.plist 確認「兔咪新體驗」、`com.yayoi991331.habitapp.redesign`、
`1.0.1 (2026091701)`、最低 iOS 15。包內 V28 LOGO 與來源 SHA-256 相同。
本輪沒有修改 App 程式或簽章設定，沒有安裝或啟動實體手機。

本人可直接安裝並啟動已簽署產物，跳過 Xcode build：

```zsh
cd /Users/raraku/habit-app-entry-logo
flutter run --release --flavor redesign --no-pub -d 00008120-000279CE1A9B401E --use-application-binary=/Users/raraku/habit-app-entry-logo/build/ios/iphoneos/Runner.app
```

這是目前產物的安裝指令；日後改過程式或素材、清除 build、簽章過期時須重新編譯。
實機安裝、啟動、既有測試存檔與聲音／操作手感仍待本人驗證。
