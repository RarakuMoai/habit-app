#!/usr/bin/env python3
"""Build the local review from preserved native PNGs (requires Pillow).

python3 scripts/review/build_experience_comparison.py /tmp/tumi-redesign-review
The originals stay in the supplied capture directory; their hashes are recorded.
"""
import hashlib
import html
import json
from pathlib import Path
import sys

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[2]
OUTPUT = ROOT / 'design_trials' / 'experience_redesign' / 'review'
PAGES = [
    ('01-habits', '習慣', '今日進度集中呈現，完成前後保留可讀的卡片尺寸。'),
    ('02-timer', '計時', '模式、計時與開始操作分層；窄螢幕的次操作分行。'),
    ('03-water', '喝水', '今日總量持續顯示，加水主操作常駐，復原與自訂有文字。'),
    ('04-weight', '體重', '數據與指標分組閱讀，主要記錄操作固定可見。'),
    ('05-family', '家庭', '姓名、任務與積分各有位置，長名字可自然換行。'),
    ('06-wardrobe', '衣櫃', '較大的選物卡與分類索引；小螢幕自動改為單欄。'),
    ('07-settings', '設定', '統一紙色、表單與卡片，保留清楚的閱讀層次。'),
]
EXTRA = [
    ('08-review', '足跡回顧'),
    ('09-water-expanded', '展開喝水面板'),
    ('10-water-added', '加水後 1250 ml'),
    ('11-roommate', '兔咪室友'),
]


def main():
    captures = Path(sys.argv[1]).resolve()
    for side in ['before', 'after']:
        result = json.loads((captures / side / 'capture.json').read_text())
        if result['exit_code'] != 0:
            raise RuntimeError(f'{side} native capture did not pass')
    OUTPUT.mkdir(parents=True, exist_ok=True)
    manifest = {'baseline': '0737a7d', 'branch': 'codex/experience-redesign',
                'environment': 'iPhone 14 Pro Max / iOS 26.5 / Flutter dev debug',
                'logical_size': [430, 932], 'locale': 'zh', 'scene_hour': 10,
                'data': 'In-memory fixture; no real user records', 'images': []}
    for side, rows in [('before', PAGES), ('after', PAGES + EXTRA)]:
        (OUTPUT / side).mkdir(exist_ok=True)
        for row in rows:
            name = row[0]
            source = captures / side / f'{name}.png'
            with Image.open(source) as im:
                im.load()
                size = list(im.size)
                exported = im.convert('RGB')
                exported.thumbnail((860, 1864), Image.Resampling.LANCZOS)
                destination = OUTPUT / side / f'{name}.webp'
                exported.save(destination, quality=94, method=6)
            manifest['images'].append({'image': f'{side}/{name}.webp',
                'source_pixels': size, 'source_sha256': hashlib.sha256(source.read_bytes()).hexdigest(),
                'export_sha256': hashlib.sha256(destination.read_bytes()).hexdigest()})
    (OUTPUT / 'capture-manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
    sheet = Image.new('RGB', (1050, 1590), '#E9E8E0')
    pen = ImageDraw.Draw(sheet)
    for i, row in enumerate(PAGES[:6]):
        with Image.open(OUTPUT / 'after' / f'{row[0]}.webp') as im:
            im.thumbnail((326, 708), Image.Resampling.LANCZOS)
            x = (i % 3) * 350 + 12
            y = (i // 3) * 785 + 42
            sheet.paste(im, (x, y))
            pen.text((x, y - 22), row[0].upper(), fill='#343E38')
    sheet.save(OUTPUT / 'overview.jpg', quality=94)
    sections = []
    for name, title, note in PAGES:
        sections.append(f'''<section class="comparison" id="{name}">
        <div class="section-head"><h2>{html.escape(title)}</h2><p>{html.escape(note)}</p></div>
        <div class="pair"><figure class="before"><figcaption>原版 <span>0737a7d</span></figcaption>
        <a href="before/{name}.webp"><img src="before/{name}.webp" loading="lazy" alt="原版{title}"></a></figure>
        <figure class="after"><figcaption>新版 <span>體驗候選</span></figcaption>
        <a href="after/{name}.webp"><img src="after/{name}.webp" loading="lazy" alt="新版{title}"></a></figure></div></section>''')
    extra = ''.join(f'<figure><figcaption>{title}</figcaption><a href="after/{name}.webp"><img src="after/{name}.webp" loading="lazy" alt="{title}"></a></figure>' for name, title in EXTRA)
    sounds = ''.join(f'<article class="sound"><h3>{title}<small>{duration} ms</small></h3><audio controls preload="none" src="../../../assets/sounds/sfx_diary_{name}.wav"></audio></article>' for name, title, duration in [('tap','輕點',115),('cancel','取消',160),('success','成功',400),('complete','完成',560)])
    nav = ''.join(f'<a href="#{name}">{title}</a>' for name, title, _ in PAGES)
    document = '''<!doctype html><html lang="zh-Hant"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>兔咪・日常手帳體驗比較</title><style>
:root{color-scheme:light;--ink:#343e38;--soft:#687063;--paper:#f5f3ec;--green:#396b5d;--line:#dedfd4}
*{box-sizing:border-box}html{scroll-behavior:smooth;scroll-padding-top:104px}body{margin:0;background:var(--paper);color:var(--ink);font:16px/1.7 -apple-system,BlinkMacSystemFont,"PingFang TC",sans-serif}a{color:var(--green)}header,main,footer{max-width:1000px;margin:auto;padding:44px 28px}header{padding-top:64px;padding-bottom:24px}.eyebrow{font-size:12px;letter-spacing:.2em;color:var(--green);font-weight:700}h1{font-size:clamp(30px,4.7vw,50px);line-height:1.25;letter-spacing:-.04em;margin:18px 0}header p{max-width:690px;color:var(--soft)}.facts{display:flex;flex-wrap:wrap;gap:10px;margin-top:24px}.facts span{padding:7px 13px;border:1px solid var(--line);border-radius:30px;font-size:12px;background:#fffefa}.toolbar{position:sticky;top:0;z-index:2;border-block:1px solid var(--line);background:#f5f3ecf5;backdrop-filter:blur(14px)}.tools{max-width:1000px;margin:auto;padding:12px 28px;display:flex;gap:16px;justify-content:space-between;align-items:center;flex-wrap:wrap}.modes{display:flex;gap:4px;background:#e8e9e0;padding:4px;border-radius:13px}button{font:inherit;font-size:13px;border:0;min-height:40px;padding:6px 12px;border-radius:10px;background:transparent;color:var(--ink);cursor:pointer}button[aria-pressed=true]{background:var(--green);color:white}nav{display:flex;gap:14px;flex-wrap:wrap}nav a{font-size:13px;text-decoration:none}main{padding-top:8px}.comparison{padding:30px 0 40px;border-bottom:1px solid var(--line)}.section-head{display:flex;align-items:baseline;justify-content:space-between;gap:24px}h2{font-size:25px;letter-spacing:-.02em;margin:6px 0 18px}.section-head p{color:var(--soft);font-size:14px;margin:0 0 18px}.pair{display:grid;grid-template-columns:1fr 1fr;gap:26px;max-width:860px;margin:auto}figure{margin:0;min-width:0}figcaption{display:flex;justify-content:space-between;align-items:center;font-size:14px;font-weight:700;padding:9px 4px}figcaption span{font-size:11px;font-weight:500;color:var(--soft)}img{display:block;width:100%;height:auto;border-radius:24px;border:1px solid var(--line);box-shadow:0 8px 32px #343e3808}body[data-mode=after] .pair .before,body[data-mode=before] .pair .after{display:none}body:not([data-mode=both]) .pair{grid-template-columns:1fr;max-width:430px}.extras{display:grid;grid-template-columns:repeat(4,1fr);gap:18px}.extra-section,.audio-section,.acceptance{padding:40px 0;border-bottom:1px solid var(--line)}.extra-section>p,.audio-section>p,.acceptance p{color:var(--soft);font-size:14px}.sounds{display:grid;grid-template-columns:1fr 1fr;gap:18px}.sound{background:#fffefa;border:1px solid var(--line);border-radius:20px;padding:18px}h3{font-size:16px;margin:0 0 12px;display:flex;justify-content:space-between}small{color:var(--soft);font-size:12px;font-weight:500}audio{width:100%;height:38px}.checks{display:grid;grid-template-columns:repeat(3,1fr);gap:14px}.checks div{border-top:2px solid var(--green);padding-top:12px}.checks b{display:block;font-size:25px}.checks span{font-size:13px;color:var(--soft)}footer{font-size:12px;color:var(--soft);padding-top:12px;padding-bottom:32px}:focus-visible{outline:3px solid #396b5d;outline-offset:4px}@media(max-width:650px){header,main,footer{padding-inline:18px}.tools{padding:10px 18px;gap:7px}nav{gap:12px}.section-head{display:block}.pair{gap:12px}figcaption{font-size:12px}figcaption span{display:none}img{border-radius:16px}.extras{grid-template-columns:1fr 1fr}.sounds{grid-template-columns:1fr}.checks{gap:8px}.checks b{font-size:20px}}@media(prefers-reduced-motion:reduce){html{scroll-behavior:auto}}
</style><body data-mode="both"><header><div class="eyebrow">TUMI / EXPERIENCE STUDY / 2026.09.10</div><h1>同一個日常，<br>新的節奏。</h1><p>以安靜的紙色、清楚的文字層次與更容易操作的按鈕，重新整理兔咪的每一天。這裡是原生模擬器截圖與音效樣本，供你比較整體採用或局部移植。</p><div class="facts"><span>獨立分支 codex/experience-redesign</span><span>430 × 932 · iPhone 14 Pro Max</span><span>繁體中文 · 上午 10 點場景</span><span>相同測試資料</span></div></header>
<div class="toolbar"><div class="tools"><div class="modes" role="group" aria-label="比較方式"><button data-mode="both" aria-pressed="true">並排比較</button><button data-mode="after" aria-pressed="false">只看新版</button><button data-mode="before" aria-pressed="false">只看原版</button></div><nav aria-label="頁面索引">NAV</nav></div></div><main>SECTIONS
<section class="extra-section"><h2>實際操作後的狀態</h2><p>延伸走完足跡入口、喝水面板展開、加水，以及室友入口；加水後由 1000 增為 1250 ml。</p><div class="extras">EXTRA</div></section>
<section class="audio-section"><h2>把回饋，留在剛好的地方</h2><p>四段原創短音效。下方播放器可比較聲音質地；App 內另有各事件音量與觸覺時機，需由本人實機確認整體感受。</p><div class="sounds">SOUNDS</div></section>
<section class="acceptance"><h2>已驗證，以及下一次試用</h2><div class="checks"><div><b>900 / 900</b><span>完整 Flutter 測試通過</span></div><div><b>0 issues</b><span>Flutter analyze</span></div><div><b>11 個狀態</b><span>原生 iOS 模擬器流程通過</span></div></div><p>測試涵蓋 320 × 667 與 430 × 932、繁中／英文、放大字與降低動態，並驗證靜音及取消播放的競爭情境。原生截圖採預設字級、未降低動態；動態角色的眨眼可能不同。</p><p>優先實際走一輪：完成習慣 → 開始／暫停計時 → 加水與復原 → 記體重 → 家庭任務 → 換裝／試聽 → 回顧。判斷主操作是否清楚、資訊是否好讀、動畫和音效是否舒服，再決定整體採用或移植。實機聲音、觸覺、耗電與 release 流暢度尚待本人驗證。</p></section></main><footer>本機體驗候選 · 正式素材與原工作樹保留 · <a href="capture-manifest.json">截圖來源與雜湊</a></footer><script>document.querySelectorAll('button[data-mode]').forEach(button=>button.addEventListener('click',()=>{document.body.dataset.mode=button.dataset.mode;document.querySelectorAll('button[data-mode]').forEach(item=>item.setAttribute('aria-pressed',String(item===button)));}));</script></body></html>'''
    document = document.replace('NAV', nav).replace('SECTIONS', '\n'.join(sections)).replace('EXTRA', extra).replace('SOUNDS', sounds)
    (OUTPUT / 'index.html').write_text(document)
    print(f'Built {len(manifest["images"])} images and comparison at {OUTPUT}')


if __name__ == '__main__':
    main()
