# 桌遊計時器 AI 素材規格與 Prompt 清單

給下一輪「AI 素材整合」用：素材由 GPT 等生成工具產出（慣例：不用程式土法合成），
拿到檔案後由 Claude 負責裁切、壓縮、整合進 app 與程式對接。

生成後把檔案丟到對應路徑（或先丟任意資料夾說一聲即可）。

---

## 1. 絨布桌面背景（優先度最高）

| 項目 | 規格 |
|---|---|
| 用途 | `TableStagePage` 全螢幕背景，取代目前程序化 radial gradient |
| 尺寸 | 直向 **1536×3072 以上**（會以 cover 縮放適配各機型，安全邊留 10%） |
| 格式 | PNG 或高品質 JPG（整合時轉壓） |
| 落點 | `assets/scenes/game/game_felt_bg.png`（場景圖不加 tumi_ 前綴） |

**內容要求**：深色暖棕絨布／毛氈桌面質感，中央略受光、四周自然暗角。
色彩基準：中央約 `#33261C`、邊緣約 `#19110B`（±10% 可藝術發揮，但必須保持
暖棕基調、不可偏純黑或冷灰）。**畫面不可有任何物件、圖案、文字**——遠看要
均勻，近看有細緻布紋；對比要低，不能搶中央發光數字的戲。
光束／塵埃等光影效果不用畫，Flutter 端 overlay 處理（既有慣例）。

**建議 prompt（英文）**：
> Top-down view of a luxurious dark board game table surface, warm
> espresso-brown felt / velvet texture, softly lit from the center with
> natural vignette darkening toward the edges, subtle fine fabric grain,
> no objects, no text, no patterns, minimal and elegant, deep warm brown
> tones (#33261C center, #19110B edges), photorealistic material texture,
> portrait orientation

---

## 2. 遊戲入口專屬 icon

| 項目 | 規格 |
|---|---|
| 用途 | 入口卡頭像圈＋計時頁模式切換列（取代 `Icons.casino_rounded`） |
| 尺寸 | 1024×1024，透明背景 PNG |
| 落點 | `assets/icon/tabs/game_timer.png`（比照現有 tabs 貼紙感 icon） |

**內容要求**：貼紙感（粗圓潤描邊＋暖色填色，與 `assets/icon/tabs/` 現有
icon 同一家族）。主題：骰子＋沙漏（或骰子＋棋子）的組合。主色可用遊戲藍
`#5B8DEF` 搭暖金，描邊用深暖棕非純黑。無文字。

**建議 prompt（英文）**：
> Cute sticker-style icon of a dice combined with a small hourglass,
> thick rounded dark-brown outline, warm gold and soft blue (#5B8DEF)
> fill colors, flat illustration with slight inner shading, sticker look,
> isolated on transparent background, no text

---

## 3. 專屬音效（3 顆）

| 檔名 | 用途 | 感覺 | 長度 |
|---|---|---|---|
| `sfx_game_pass.wav` | 換人／棋鐘按下 | 實體棋鐘按鈕「喀噠」，木質、乾脆 | <200ms |
| `sfx_game_warn.wav` | 警示開始（剩 10 秒） | 柔和木魚／木質 tick，一聲 | <300ms |
| `sfx_game_flag.wav` | 超時／旗倒 | 低沉小鑼或沉鈴，明確但不刺耳 | <1s |

規格：WAV 44.1kHz、單聲道即可；響度對齊 `assets/sounds/` 現有檔（整合時
我會做音量係數校正）。落點 `assets/sounds/`。

整合時的程式對接（Claude 做）：加進 `SfxCue` enum、替換
`table_stage_page.dart` 的事件對映（pass→advance/棋鐘換手、warn→warn、
flag→expire/旗倒），並把入口卡與模式切換列換成新 icon。

---

## 已完成、不需素材的部分（避免重工）

- 深色絨布漸層（程序化版）、倒數環、座位環、點擊波紋、接力光點、
  暫停霧面、旗倒警示——全部 Flutter 端繪製，素材到位後只換「背景圖＋
  icon＋音效」三樣，動效不動。
