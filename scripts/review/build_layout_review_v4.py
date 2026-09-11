#!/usr/bin/env python3
"""Make a clearly versioned gallery from same-device native review captures."""
import html
import json
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'design_trials/experience_redesign/review_v4'
OLD = ROOT / 'design_trials/experience_redesign/onboarding_story_v1'


def main():
    capture = json.loads((OUT / 'capture.json').read_text())
    if capture['exit_code']:
        raise RuntimeError('Native review must pass first')
    image_names = capture['files']
    for name in image_names:
        with Image.open(OUT / name) as im:
            if im.size != (1206, 2622):
                raise ValueError((name, im.size))
            target = OUT / Path(name).with_suffix('.webp')
            if not target.exists() or target.stat().st_mtime < (OUT / name).stat().st_mtime:
                im.save(target, lossless=True, method=6)
            with Image.open(OUT / Path(name).with_suffix('.webp')) as converted:
                if im.convert('RGBA').tobytes() != converted.convert('RGBA').tobytes():
                    raise ValueError('Pixel conversion changed: ' + name)
    comparisons = [
        ('命名與兔咪站位', '04-a-name', '04-a-name', '腳底固定在地毯內，房間取景跟著同一個落點。'),
        ('喝水・收合空狀態', '09-water', '09-water', '水瓶、數據與操作分區，拿掉大底框及提示膠囊。'),
        ('專注・收合待機', '08-timers', '08-timers', '恢復鐘面，開始、設定與快捷仍留在收合面板。'),
    ]
    sections = []
    for title, before, after, desc in comparisons:
        sections.append(f'<section><h2>{title}</h2><p>{desc}</p><div class="comparison">'
                        f'{card("../onboarding_story_v1/" + before + ".png", "修改前 · 故事前導 V1")}'
                        f'{card(after + ".webp", "本輪 · V4")}</div></section>')
    groups = [
        ('六幕前導', [('01-arrival','走進這個家'),('02-hello','第一次打招呼'),('03-a-new-routine','學著生活'),('04-a-name','兔咪的暱稱'),('05-your-name','你的稱呼'),('06-a-beginning','一起開始')]),
        ('計時・收合', [(f'timer-{m}-compact',t) for m,t in [('focus','專注'),('exercise','運動'),('jog','超慢跑'),('metronome','節拍器'),('game','遊戲')]]),
        ('計時・展開與調速', [('timer-jog-adjusted','收合・BPM 加速')] + [(f'timer-{m}-expanded',t) for m,t in [('exercise','超慢跑・展開'),('focus','專注・展開'),('metronome','節拍器・展開'),('game','遊戲・展開')]]),
        ('喝水・記錄與達標', [('water-one-cup-compact','收合・一杯'),('water-expanded','展開・水瓶與紀錄'),('water-goal-compact','收合・達標仍保留水瓶')]),
        ('開發者測試', [('13-developer-preview-entry','單一全回憶開關與前導預覽'),('15-preview-ending','前導草稿只供預覽'),('16-wardrobe-memory-preview','衣櫃正式回憶入口・暫時全開')]),
    ]
    for title, items in groups:
        sections.append('<section><h2>' + title + '</h2><div class="grid">' + ''.join(card(n+'.webp',t) for n,t in items) + '</div></section>')
    page = """<!doctype html><html lang="zh-Hant"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>兔咪 V4 · 站位與收合版面修正</title><style>
:root{color-scheme:light;--bg:#fff8ed;--ink:#604334;--muted:#806e61}*{box-sizing:border-box}body{background:var(--bg);color:var(--ink);margin:0;font:16px/1.7 system-ui,sans-serif}header,main,footer{max-width:1120px;margin:auto;padding:28px 24px}header{padding-bottom:0}h1{font-size:clamp(27px,4vw,42px);font-weight:600;line-height:1.3}h2{font-weight:600;font-size:23px}p,figcaption{color:var(--muted)}.eyebrow{color:#a6634d;font-size:13px;letter-spacing:.12em}section{border-top:1px solid #e7d7c5;margin-top:38px;padding-top:16px}.comparison{display:grid;grid-template-columns:1fr 1fr;gap:28px;max-width:780px;margin:24px auto}.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(230px,1fr));gap:24px}figure{margin:0}figure img{width:100%;display:block;border-radius:18px;box-shadow:0 12px 25px #6043340c}figcaption{font-size:13px;margin:0 0 10px;text-align:center;font-weight:600}a{color:inherit;text-underline-offset:4px}.note{font-size:14px;max-width:820px}details{padding:18px;border:1px solid #e7d7c5;border-radius:18px}summary{cursor:pointer}footer{font-size:13px}@media(max-width:640px){.comparison{gap:12px}.grid{grid-template-columns:repeat(2,minmax(0,1fr));gap:14px}header,main,footer{padding:20px 16px}}
</style><header><div class="eyebrow">兔咪新體驗 · 本輪 V4</div><h1>讓角色站穩，也讓功能留得住</h1><p>先比較這次回報的三個畫面，再往下看六幕前導與各種收合狀態。</p><p class="note">比較兩側皆為 iPhone 17 Pro · iOS 26.5 · 402 × 874 pt · 繁體中文 · 真實 App root。這是原生截圖，觸控、動畫與音訊請在獨立測試 App 確認。</p></header><main>SECTIONS
<section><details><summary>歷史版本：「小習慣，慢慢長大」是哪一頁？</summary><p>這是舊 V2 的歡迎頁，已被六幕故事前導取代，並非目前 App 的開場。本輪上方只展示現行前導，不再混排該舊畫面。</p><a href="../review_v2/onboarding/onboarding-01-welcome.webp" target="_blank">查看 V2 歷史截圖（已停用）</a></details></section></main><footer>開發分支 codex/experience-redesign · 正式版資料獨立。請優先確認命名頁的站位、喝水的資訊比例，以及超慢跑的面盤與 BPM 操作。</footer></html>"""
    (OUT / 'index.html').write_text(page.replace('SECTIONS',''.join(sections)))
    (OUT / 'validation.json').write_text(json.dumps({'native_capture_count':len(image_names),'viewport_pt':[402,874],'image_px':[1206,2622],'format':'lossless WebP','capture_exit_code':capture['exit_code']}, indent=2))


def card(path, title):
    return f'<figure><figcaption>{html.escape(title)}</figcaption><a href="{html.escape(path)}" target="_blank"><img loading="lazy" src="{html.escape(path)}" alt="{html.escape(title)}"></a></figure>'


if __name__ == '__main__':
    main()
