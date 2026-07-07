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

## 3. 專屬音效（3 顆）— ElevenLabs 生成教學

| 檔名 | 用途 | 感覺 | 長度 |
|---|---|---|---|
| `sfx_game_pass` | 換人／棋鐘按下 | 實體棋鐘按鈕「喀噠」，木質、乾脆 | 0.3–0.5s |
| `sfx_game_warn` | 警示開始（剩 10 秒） | 柔和木魚／木質 tick，一聲 | ~0.5s |
| `sfx_game_flag` | 超時／旗倒 | 低沉小鑼或沉鈴，明確但不刺耳 | ~1s |

### 操作步驟

1. 開 <https://elevenlabs.io/sound-effects>，用 Google 帳號免費註冊登入
   （免費方案的每月額度出這三顆綽綽有餘）。
2. 進入 Sound Effects 生成頁，介面三個重點：
   - **Prompt 輸入框**：貼下面的英文 prompt。
   - **Duration**：先用 Auto；如果生出來太長，pass 手動設 0.5 秒、
     warn 設 0.5 秒、flag 設 1 秒。
   - **Prompt influence**：拉高到 70% 以上（越高越照字面做，
     不會自由發揮）。
3. 按 Generate，一次會出 3–4 個候選。**全部試聽**，用下面的
   「驗收重點」挑；都不像就換變體 prompt 再生一次。
4. 挑中就下載（免費方案給 MP3 沒關係，**轉 WAV 我來**）。
5. 檔名改成 `sfx_game_pass` / `sfx_game_warn` / `sfx_game_flag`
   （副檔名不拘），丟桌面 `00` 資料夾跟我說一聲即可。

### Prompt（每顆一主二備，主 prompt 不像再換備用）

**① sfx_game_pass（棋鐘喀噠）**

> single mechanical chess clock button press, crisp wooden click, short
> percussive tap, dry recording, no reverb, no background noise, isolated
> one-shot

備用 A：
> vintage wooden chess timer lever click, snappy tactile clack, extremely
> short, clean studio recording

備用 B：
> board game piece tapping hard wood table once, bright knock, tight and
> dry, single hit

驗收重點：夠短夠脆、**沒有尾音殘響**、不能有電子「嗶」感。

**② sfx_game_warn（柔和木質 tick）**

> soft wooden temple block hit, single gentle warm knock, muted
> percussion, short decay, calm, no reverb tail

備用 A：
> single soft woodblock tick, rounded mellow tone, quiet and warm,
> isolated one-shot

備用 B：
> gentle bamboo percussion tap, soft attack, warm low-mid tone, very short

驗收重點：**溫和不嚇人**（它每局會響很多次），比 pass 更悶更圓潤。

**③ sfx_game_flag（旗倒沉鑼）**

> small deep gong single hit, warm low chime, soft mallet, short decay
> under one second, solemn but not harsh, no long tail

備用 A：
> muted brass bowl strike, deep warm resonance, quick fade out, single hit

備用 B：
> low tibetan singing bowl tap, dark warm tone, short controlled decay,
> isolated

驗收重點：低沉有份量但**不刺耳不炸**，一秒內收乾淨，聽起來像
「終局宣告」而不是警報。

### 拿到檔案後的程式對接（Claude 做，不用管）

轉 WAV＋響度對齊現有 `assets/sounds/`、加進 `SfxCue` enum、替換
`table_stage_page.dart` 事件對映（pass→換人/棋鐘換手、warn→警示、
flag→超時/旗倒），骰盤擲骰音也會順路掛 pass。

---

## 已完成、不需素材的部分（避免重工）

- 深色絨布漸層（程序化版）、倒數環、座位環、點擊波紋、接力光點、
  暫停霧面、旗倒警示——全部 Flutter 端繪製，素材到位後只換「背景圖＋
  icon＋音效」三樣，動效不動。
