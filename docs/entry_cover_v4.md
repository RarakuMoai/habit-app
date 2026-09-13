# V4 動態封面原生整合

2026-09-14 使用者明確回覆「可以實裝了」。本輪延續 `codex/entry-integration`，
將已選定的 HTML 封面轉成 Flutter 呈現層；不是 WebView，也不是重新生成美術。
版本 `1.0.1+2026091401`，僅交付 redesign 測試版；不合併 main、不發布、不安裝實機。

## 呈現與流程

- 新背景、左下真透明葉層、繁中 LOGO 均複製已核可 PNG 原始位元組。
  背景與兔咪不參與形變；LOGO 的 13px 透明邊界由版面裁切，與樣稿一致。
- `EntryCoverLayout` 使用真實全螢幕與 safe area；先計算 BoxFit.cover 的裁切，
  再限制 LOGO 在原圖 y=520 的頭頂保護線上方至少 20pt。語言左下、設定右下，
  按鈕 52×52pt、圖示 30pt，底邊為 `max(24, safeBottom+12)`。
- `entry_foliage.frag` 沿用核可 UV 公式，左側和底部邊界固定，內側葉梢隨風彎動。
  不旋轉整張裁切圖。Runtime shader 不支援時顯示原葉層，不露空洞。
- 一條共用時間軸驅動 6.4 秒 LOGO 微浮動、9 秒掃光、2 秒開始提示、光線、
  門前葉影及 28 顆塵埃。粒子直徑為 2.6–6.6 logical px；臉部淡化。
  葉層與環境效果使用 RepaintBoundary／CustomPainter，不逐幀重建業務頁面。
- 降低動態保留可讀 LOGO、提示及完整操作，停用葉動／環境粒子／掃光；面板開啟、
  路由遮蓋及 App 背景時停止封面時間軸。
- 點封面沿用原新用戶選擇／回訪流程。一般封面不放帳號說明，設定面板可切音樂、音效，
  以及進入帳號與資料；原備份、家庭 PIN、初見與真正 MainPage 未重製。
- 開始文字繁中為「輕觸開始」、英文為「Tap to start」；回訪沿用「繼續一起生活」。
  品牌圖片維持核可繁中 LOGO，沒有擅自生成外語 Logo；可選語言範圍仍依既有設定。
- App root 預載新封面圖層後才顯示，進入主頁的等待底板也使用新圖層。
  原生 LaunchScreen 與短初見沿用既有設計，不改動實體裝置。

## 音訊與授權

封面使用 [Porch Swing Days – slower / Kevin MacLeod](https://incompetech.com/music/royalty-free/index.html?isrc=USUAN1100715)，
[CC BY 4.0](https://creativecommons.org/licenses/by/4.0/)。原曲檔不重編碼，
App 內設定面板保留作者、曲名與來源／授權連結，資產附 `.LICENSE.txt`。

由 `EntryAudio.open(asset: EntryAudio.coverAsset)` 持有封面曲；短初見仍用原前導曲，
真正進入首頁恢復使用者選曲。巢狀返回、延後初始化與舊路由 dispose 不得蓋掉新曲。
沿用 BgmService 的靜音偏好、25% 目標音量、淡入、背景暫停與既有啟播救援，
沒有重寫底層播放管理。HTML 原先為 28% 音量，原生採既有全 App 音量基準；實機音量待本人確認。

## 資產雜湊

| 素材 | SHA-256 |
| --- | --- |
| `entry_clean_plate_v4.png` | `c4ff83db10920eacdc5d8079e6085cfd7e4c05e13f711af335038c1339f5bf47` |
| `entry_leaves_v4.png` | `0971911240475f6a029bc4222d4ab85d2ea2dbb162089c0acdc1f68211691a07` |
| `entry_logo_zh_v4.png` | `0d4b3902825f22f627c67bac2ee0d7ea3964e4ef29e7f42c9e6f566beacc0f8e` |
| `bgm_entry_porch_v4.mp3` | `f1d2c17ccbbee215561d5930343d8211f0bc34d2d8eee7125214cd2b028963ba` |

前三者在 `assets/scenes/onboarding/`；音訊在 `assets/sounds/`。新增約 12.3 MiB，
原 V3、原 LOGO／CG 試作均保留，未刪除其他素材。未核可試作不隨本輪提交。

## 驗證與下一步

43 項封面／入口／音訊相關測試與 `flutter analyze --no-pub` 通過。
完整回歸發現既有 `test/roommate_dialogue_test.dart` 缺少 `roommate_entry`：
兩個 MainPage 尺寸案例與 daily story invitation 案例，在未修改的 `9fab319`
獨立 worktree 各自單跑均重現；失敗後同檔後續測試會卡住。本輪不改室友故事功能，
也不將完整測試套件宣稱為全綠。排除該檔後，其餘 1,212 項測試全部通過
（`--concurrency=6`，JSON 報告 `cover_v5/regression_v4_without_legacy_roommate.json`）。

原生檢查使用既有 `scripts/review/run_entry_integration.py` 與 `ENTRY_REVIEW_COVER_V4=true`，
驗證真 App root、shader 成功載入、時間推進、LOGO 間距、控制項、初次／回訪與計時頁。
模擬資料僅存在測試程序，不碰真實帳號或雲端寫入。

- iOS 26.5 大尺寸 430×932pt、safe top 59／bottom 34、繁中、無存檔、一般動態：
  11 張原生截圖與新用戶至初見／首頁／計時操作通過。
  `native_v4_large/` 錄製起始於預載與文字縮放最後補強之前；
  最終執行碼另由下列小尺寸流程覆蓋，不把較早來源雜湊當作最終版本。
- 小尺寸 375×667pt、safe top 20、繁中、回訪資料、要求字級 2.0（App 上限 1.3）、
  `reduceMotion`／`disableAnimations`：8 張畫面與流程通過；兩張風動抽樣完全一致，
  符合減少動態預期。第一輪截圖檢查曾把它判為重複畫面，已針對此模式加入精確例外，
  不放寬正常動態的檢查。字級及動態旗標注入 Flutter 測試平台，未修改 OS 設定。
- 原生圖、連續錄影與來源雜湊保存在
  `design_trials/experience_redesign/cover_v5/native_v4_large/`、`native_v4_small/`、
  `native_v4_small_audio/`。最後者在最終執行碼下通過完整原生流程與截圖檢查，
  並以 `ENTRY_REVIEW_COVER_AUDIO=true` 點擊真正音樂開關，驗證原生解碼時長
  216.238 秒、播放進度前進至 1.112 秒、關閉後進度停止；不是只檢查曲目名稱。
  這仍不是實機聆聽、音量或 Release 冷啟動音訊驗收。
  試作與測試產物不加入本輪 Git 提交。
- 兩份通過的連續錄影均由 AVFoundation 成功解碼抽樣：大尺寸 55.657 秒、小尺寸
  含音樂複驗 47.785 秒；錄影本身不是音訊或 FPS 證據。

### Release 產物

在 `/private/tmp/tumi-entry-integration` 執行：

```sh
/Users/raraku/development/flutter/bin/flutter build ios --release --flavor redesign --no-pub --target lib/main.dart
codesign --verify --deep --strict --verbose=2 build/ios/iphoneos/Runner.app
```

兩項成功；Xcode build 444.6 秒，產物 `build/ios/iphoneos/Runner.app` 194.4 MB。
Plist 為 `1.0.1`／`2026091401`、`com.yayoi991331.habitapp.redesign`、iPhoneOS／arm64，
最低 iOS 15.0。正常 `lib/main.dart` entrypoint，沒有測試情境旗標。
產物內三張 PNG 與 MP3 雜湊全部符合上表，葉片 shader 也已編譯打包。
這是已簽章的本機測試產物，不是 TestFlight／App Store 發布，也未安裝或啟動實體手機。

最後由本人在實機確認：冷啟動的 LOGO／瀏海距離、左下葉梢是否自然、音樂開關與
背景返回、首次／回訪進入是否順暢。模擬器不代表 release 音訊、幀率、耗電或手感已驗收。

實作參考：[Flutter runtime fragment shaders](https://docs.flutter.dev/ui/design/graphics/fragment-shaders)。
