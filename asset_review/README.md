# 待審核素材

這裡集中「目前未使用，或很可能不再使用，但仍需本人決定」的素材與相關工具。
**移入不等於決定刪除。** 本目錄納入 Git 管理，且不列入 Flutter 的 `pubspec.yaml`，
不隨 app 打包。2026-09-08 首次整理：13 個素材、1 支舊製作工具；所有移動檔案的
SHA-256 與移動前一致，沒有轉檔、壓縮或覆寫。

你可以逐項或整組決定「刪除／保留備用／恢復使用」，再請 AI 整理。
音效連結可用系統播放器試聽；圖片可直接預覽。正式使用的兔咪語音仍在
[`assets/sounds/`](../assets/sounds/)，沒有移動。

## 以後怎麼使用

1. 先查程式、測試、`pubspec.yaml`、CI／工具，以及 enum、路徑拼接、設定 ID、
   fallback 等間接引用；**只有字串搜尋沒命中，還不能判定沒用到**。
2. 確認目前無引用才移到本目錄；保留檔名，按 audio／images／tools 與用途分類。
   同名檔以批次子目錄區分，不覆寫；空分類不用預先建立。
3. 在這份清單記下原路徑、移入原因、查核依據與建議。無法排除引用的項目先只記錄，
   留在原處。
4. 保留原檔內容，以雜湊確認移動完整。已在使用的音訊原地替換另遵守音訊快取版本規則。
5. 使用者確認刪除後才移除。若決定保留備用，就標註用途並留在這裡；恢復使用時搬回
   正式目錄、更新引用與打包設定，做相關檢查。
6. 不收編譯快取、憑證、金鑰或使用者存檔。可重建產物直接清理，不混入素材審核。

## 兔咪舊音效原檔

未被程式或 pubspec 引用。舊 README 說曾採用此組，但與現行 tumi_voice_*.wav 雜湊不同；可能仍有重製價值，建議先試聽保留。

| 檔案（點擊預覽／試聽） | 原路徑 | 大小／時長 | 決定 |
|---|---|---|---|
| [01_original_1623_happy.wav](audio/tumi_originals/01_original_1623_happy.wav) | `audio_choices/tumi_mi_versions/01_original_1623_happy.wav` | 37.1 KB／0.43 秒 | 待審核 |
| [01_original_1623_neutral.wav](audio/tumi_originals/01_original_1623_neutral.wav) | `audio_choices/tumi_mi_versions/01_original_1623_neutral.wav` | 25.9 KB／0.30 秒 | 待審核 |
| [01_original_1623_question.wav](audio/tumi_originals/01_original_1623_question.wav) | `audio_choices/tumi_mi_versions/01_original_1623_question.wav` | 31.1 KB／0.36 秒 | 待審核 |
| [01_original_1623_sad.wav](audio/tumi_originals/01_original_1623_sad.wav) | `audio_choices/tumi_mi_versions/01_original_1623_sad.wav` | 37.9 KB／0.44 秒 | 待審核 |
| [01_original_1623_sleepy.wav](audio/tumi_originals/01_original_1623_sleepy.wav) | `audio_choices/tumi_mi_versions/01_original_1623_sleepy.wav` | 50.0 KB／0.58 秒 | 待審核 |

## 舊足跡幣音效

SfxCue 與足跡幣演出已使用 absorb／tick；這組沒有程式引用，建議刪除或留作音效素材庫。

| 檔案（點擊預覽／試聽） | 原路徑 | 大小／時長 | 決定 |
|---|---|---|---|
| [sfx_footprint_coin_land_1.wav](audio/coin_effects/sfx_footprint_coin_land_1.wav) | `assets/sounds/sfx_footprint_coin_land_1.wav` | 187.6 KB／1.00 秒 | 待審核 |
| [sfx_footprint_coin_land_2.wav](audio/coin_effects/sfx_footprint_coin_land_2.wav) | `assets/sounds/sfx_footprint_coin_land_2.wav` | 187.6 KB／1.00 秒 | 待審核 |
| [sfx_footprint_coin_reward.wav](audio/coin_effects/sfx_footprint_coin_reward.wav) | `assets/sounds/sfx_footprint_coin_reward.wav` | 35.0 KB／0.18 秒 | 待審核 |
| [sfx_footprint_coin_scatter.wav](audio/coin_effects/sfx_footprint_coin_scatter.wav) | `assets/sounds/sfx_footprint_coin_scatter.wav` | 105.0 KB／0.56 秒 | 待審核 |

## 舊節拍器音色

現行 MetronomeTone 只有 wood／kick／lowWood／bell；未知舊 ID 會回到 wood，不依檔名載入。建議試聽後決定是否保留備用。

| 檔案（點擊預覽／試聽） | 原路徑 | 大小／時長 | 決定 |
|---|---|---|---|
| [metronome_clap.wav](audio/metronome/metronome_clap.wav) | `assets/sounds/metronome_clap.wav` | 5.2 KB／0.06 秒 | 待審核 |
| [metronome_digital.wav](audio/metronome/metronome_digital.wav) | `assets/sounds/metronome_digital.wav` | 4.8 KB／0.05 秒 | 待審核 |
| [metronome_tick.wav](audio/metronome/metronome_tick.wav) | `assets/sounds/metronome_tick.wav` | 3.1 KB／0.03 秒 | 待審核 |

## 未使用圖示

查無檔名引用，亦未發現以目錄掃描載入圖示的流程。建議看圖後刪除或留作設計備用。

| 檔案（點擊預覽／試聽） | 原路徑 | 大小／時長 | 決定 |
|---|---|---|---|
| [game_timer.png](images/icons/game_timer.png) | `assets/icon/tabs/game_timer.png` | 83.9 KB | 待審核 |

## 舊音效製作工具

沒有被其他工具或 CI 呼叫；輸入依賴舊帳號桌面的兩份 mixkit 原檔，專案內未附。建議保留作音效重製參考；目前不能直接執行。

| 檔案（點擊預覽／試聽） | 原路徑 | 大小／時長 | 決定 |
|---|---|---|---|
| [build_lock_rattle.py](tools/build_lock_rattle.py) | `scripts/build_lock_rattle.py` | 3.2 KB | 待審核 |
