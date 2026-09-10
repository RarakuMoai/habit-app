#!/usr/bin/env python3
"""Preserve the family redesign's native captures and build a local review.

Requires Pillow. Input contains after/, onboarding/ and glass/ captures from
run_simulator_review.py. Each native test must pass before an artifact is made.
"""
import hashlib
import html
import json
from pathlib import Path
import sys

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[2]
OUTPUT = ROOT / 'design_trials/experience_redesign/review_v2'
PAGES = [
    ('01-habits', '習慣', '把空間還給每天的小習慣，收合時縮短標題區。'),
    ('02-timer', '計時', '依面板真正可用的高度切換排版，開始與暫停保持好按。'),
    ('03-water', '喝水', '短面板保留完整總量、目標與單列操作。'),
    ('04-weight', '體重', '先讀體重與變化，再看指標；記錄入口維持可見。'),
    ('05-family', '家庭', '孩子名冊更緊湊，新增與管理固定在面板內。'),
    ('06-wardrobe', '衣櫃', '收合時用橫向選物列，一眼看完圖片、名稱與操作。'),
    ('07-settings', '設定', '奶油紙色與暖棕文字，統一操作層次。'),
]
ONBOARDING = [
    ('01-welcome', '01・初次見面'), ('02-name', '02・替兔咪取名'),
    ('03-nickname', '03・你的暱稱'), ('04-water', '04・喝水陪伴'),
    ('05-focus', '05・專注時光'), ('06-family', '06・家庭日常'),
    ('07-habits', '07・選幾個小習慣'), ('07-frequency', '07・每週頻率'),
    ('08-profile', '08・認識你一點'), ('08-keyboard', '08・輸入中的版面'),
    ('09-ready', '09・準備好了'), ('10-first-memory', '完成・第一份回憶'),
    ('11-home', '完成・回到日常'),
]


def figure(path, title):
    return f'<figure><figcaption>{html.escape(title)}</figcaption><a href="{path}"><img width="860" height="1864" loading="lazy" src="{path}" alt="{html.escape(title)}"></a></figure>'


def main():
    source_root = Path(sys.argv[1]).resolve()
    manifest = {
        'baseline': '1ccd098 (V1)', 'branch': 'codex/experience-redesign',
        'environment': 'iPhone 14 Pro Max / iOS 26.5 / Flutter redesign debug',
        'logical_size': [430, 932], 'text_scale': 1.0, 'locale': 'zh',
        'scene_hour': 10, 'reduced_motion': False,
        'data': 'Process-local in-memory fixture, no real user records',
        'note': 'Native UI snapshots, not release performance or audio measurements',
        'captures': {}, 'images': [],
    }
    for group in ['after', 'onboarding', 'glass']:
        capture = json.loads((source_root / group / 'capture.json').read_text())
        if capture['exit_code'] != 0:
            raise RuntimeError(f'{group} native test did not pass')
        fingerprints = [hashlib.sha256((source_root / group / filename).read_bytes()).hexdigest()
                        for filename in capture['files']]
        if len(fingerprints) > 1 and len(set(fingerprints)) == 1:
            raise RuntimeError(f'{group} captures are frozen on one frame; inspect the native simulator')
        manifest['captures'][group] = capture
        (OUTPUT / group).mkdir(parents=True, exist_ok=True)
        for filename in capture['files']:
            source = source_root / group / filename
            destination = OUTPUT / group / f'{source.stem}.webp'
            with Image.open(source) as im:
                im.load()
                size = list(im.size)
                exported = im.convert('RGB')
                exported.thumbnail((860, 1864), Image.Resampling.LANCZOS)
                exported.save(destination, quality=94, method=6)
            manifest['images'].append({
                'image': str(destination.relative_to(OUTPUT)), 'source_pixels': size,
                'source_sha256': hashlib.sha256(source.read_bytes()).hexdigest(),
                'export_sha256': hashlib.sha256(destination.read_bytes()).hexdigest(),
            })
    (OUTPUT / 'capture-manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')

    for name, files in [
        ('overview', [('after', p[0]) for p in PAGES[:6]]),
        ('onboarding-overview', [('onboarding', 'onboarding-' + p[0]) for p in ONBOARDING[:6]]),
    ]:
        sheet = Image.new('RGB', (1050, 1550), '#FFF8ED')
        pen = ImageDraw.Draw(sheet)
        for i, (group, filename) in enumerate(files):
            with Image.open(OUTPUT / group / f'{filename}.webp') as im:
                im.thumbnail((326, 708), Image.Resampling.LANCZOS)
                x, y = i % 3 * 350 + 12, i // 3 * 765 + 34
                sheet.paste(im, (x, y))
                pen.text((x, y - 22), filename.upper(), fill='#594438')
        sheet.save(OUTPUT / f'{name}.jpg', quality=94)

    sections = []
    for name, title, note in PAGES:
        sections.append(f'<section id="{name}"><h2>{title}</h2><p>{note}</p><div class="pair compare">'
                        f'<div class="v1">{figure("../review/after/" + name + ".webp", "上一版 V1")}</div>'
                        f'<div class="v2">{figure("after/" + name + ".webp", "這一版・溫馨日常")}</div></div></section>')
    onboarding = ''.join(figure(f'onboarding/onboarding-{name}.webp', title) for name, title in ONBOARDING)
    expanded = ''.join(figure(f'after/{name}.webp', title) for name, title in [
        ('20-habits-expanded', '習慣'), ('21-timer-expanded', '計時'),
        ('22-water-expanded', '喝水'), ('23-weight-expanded', '體重'),
        ('24-family-expanded', '家庭'), ('25-wardrobe-expanded', '衣櫃'),
    ])
    timers = ''.join('<div class="timer-pair"><h3>' + title + '</h3><div class="pair">' +
                     figure(f'after/timer-{mode}-compact.webp', '房間可見・收合面板') +
                     figure(f'after/timer-{mode}-expanded.webp', '房間收起・展開面板') + '</div></div>'
                     for mode, title in [('focus', '專注'), ('exercise', '運動'), ('metronome', '節拍器'), ('game', '遊戲')])
    events = figure('after/11-invitation.webp', '事件提示・點擊才開始') + figure('after/11-roommate.webp', '進入對話後')
    glass = figure('after/03-water.webp', 'A・暖色實底（預設）') + figure('glass/nav-water.webp', 'B・柔霧玻璃（可選）')
    running = figure('after/timer-focus-running.webp', '專注進行中') + figure('after/timer-focus-paused.webp', '暫停後')
    nav = ''.join(f'<a href="#{name}">{title}</a>' for name, title in [('onboarding', '前導'), ('01-habits', '六分頁'), ('timers', '計時'), ('events', '事件'), ('glass', '導覽 A/B')])
    document = '''<!doctype html><html lang="zh-Hant"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>兔咪・溫馨日常 V2</title><style>
:root{color-scheme:light;--ink:#594438;--soft:#796657;--paper:#fff8ed;--accent:#b85f43;--line:#ecdccb}*{box-sizing:border-box}html{scroll-padding-top:110px}body{margin:0;background:var(--paper);color:var(--ink);font:16px/1.75 -apple-system,BlinkMacSystemFont,"PingFang TC",sans-serif}a{color:var(--accent)}header,main,footer{max-width:1000px;margin:auto;padding:40px 28px}header{padding-top:66px;padding-bottom:28px}.eyebrow{color:var(--accent);font-size:12px;font-weight:700;letter-spacing:.16em}h1{font-size:clamp(34px,5vw,54px);line-height:1.3;letter-spacing:-.03em;margin:14px 0 20px}h2{font-size:28px;margin:0 0 8px}h3{font-size:20px}p{color:var(--soft);margin:0 0 22px}header p{max-width:700px}.chips{display:flex;flex-wrap:wrap;gap:8px}.chips span{border:1px solid var(--line);border-radius:24px;padding:6px 12px;font-size:12px;background:#fffdfa}.toolbar{position:sticky;top:0;z-index:3;background:#fff8edf5;border-block:1px solid var(--line);backdrop-filter:blur(12px)}.tools{max-width:1000px;margin:auto;padding:10px 28px;display:flex;justify-content:space-between;gap:14px;flex-wrap:wrap}nav,.modes{display:flex;gap:12px;align-items:center;flex-wrap:wrap}nav a{font-size:13px;text-decoration:none}.modes{gap:4px}button{font:inherit;font-size:13px;min-height:40px;padding:6px 12px;border:0;border-radius:14px;background:#f8edde;color:var(--ink);cursor:pointer}button[aria-pressed=true]{background:var(--accent);color:white}section{padding:34px 0 40px;border-bottom:1px solid var(--line)}main{padding-top:0}.pair{display:grid;grid-template-columns:1fr 1fr;gap:22px;max-width:850px;margin:auto}.gallery{display:grid;grid-template-columns:repeat(3,1fr);gap:24px 18px}.onboarding{grid-template-columns:repeat(4,1fr)}figure{margin:0;min-width:0}figcaption{font-weight:700;font-size:13px;padding:8px 2px}img{display:block;width:100%;height:auto;border-radius:23px;border:1px solid var(--line);box-shadow:0 10px 28px #59443808}.timer-pair{margin-top:24px}.note{padding:20px 24px;border-radius:20px;background:#f8edde}.note p:last-child{margin:0}.link{display:inline-block;margin-top:18px;font-size:14px}body[data-mode=v2] .compare .v1,body[data-mode=v1] .compare .v2{display:none}body:not([data-mode=both]) .compare{grid-template-columns:1fr;max-width:430px}footer{font-size:12px;color:var(--soft)}:focus-visible{outline:3px solid var(--accent);outline-offset:4px}@media(max-width:650px){header,main,footer{padding-inline:18px}.tools{padding:10px 18px}.pair{gap:12px}.gallery,.onboarding{grid-template-columns:1fr 1fr}img{border-radius:15px}h2{font-size:24px}}@media(prefers-reduced-motion:reduce){html{scroll-behavior:auto}}
</style><body data-mode="both"><header><div class="eyebrow">TUMI / FAMILY DAYS / V2</div><h1>一起慢慢長大，<br>從每天的小事開始。</h1><p>這一輪把親子、溫馨與可愛帶回整個日常。重新走過九步前導，整理房間下方有限的操作空間，讓兔咪在有事情想說時，才輕輕邀請你。</p><div class="chips"><span>原生模擬器截圖</span><span>430 × 932 · iPhone 14 Pro Max</span><span>繁體中文 · 預設字級</span><span>獨立測試 App：兔咪新體驗</span></div></header><div class="toolbar"><div class="tools"><div class="modes"><button data-mode="both" aria-pressed="true">V1 / V2 並排</button><button data-mode="v2" aria-pressed="false">只看 V2</button><button data-mode="v1" aria-pressed="false">只看 V1</button></div><nav>NAV</nav></div></div><main>
<section id="onboarding"><h2>第一次見面，就開始陪伴</h2><p>九步前導使用同一個花園舞台，功能選擇、習慣頻率與身體資料都有自己的閱讀節奏。下方操作固定；輸入時保留正在編輯的欄位。輸入狀態截圖呈現 Flutter 可視區，未包含系統鍵盤圖層。</p><div class="gallery onboarding">ONBOARDING</div></section>
SECTIONS
<section id="expanded"><h2>需要更多空間時</h2><p>把房間收起後，六個分頁回到完整面板；收合和展開各自安排資訊密度。</p><div class="gallery">EXPANDED</div></section>
<section id="timers"><h2>四種計時，按鈕都要好按</h2><p>以實際可用寬高分配時間、主操作與快捷設定，不再把整組按鈕等比例縮小。窄尺寸與 1.3 字級另由版面測試驗證。</p>TIMERS<div class="pair">RUNNING</div></section>
<section id="events"><h2>有事情想說，再輕輕邀請</h2><p>右上角回到金幣、音量與設定，皆為 48pt、間距 8pt。事件提示出現在兔咪旁，點擊才進對話；可關閉，不會自動打斷操作。這一版先採初次見面、今日小進展、全部完成，每個邏輯日最多一次邀請。</p><div class="pair">EVENTS</div></section>
<section id="glass"><h2>底部導覽，兩種質地</h2><p>建議先保留 A：暖色實底和彩色小圖示更貼近親子日常，也更容易辨認。B 是可選的 Flutter 柔霧玻璃，以模糊和半透明呈現；不是 Apple 原生 Liquid Glass。</p><div class="pair">GLASS</div></section>
<section><h2>下一輪，交給手上的感受</h2><div class="note"><p>這些是 iOS 模擬器的實際畫面，含動態角色與真實操作狀態；測試資料只在記憶體內。截圖通過不代表實機 Release 的流暢度、音訊或觸覺已驗收。</p><p>優先感受：前導是否舒服、收合時是否一眼找到主操作、四種計時是否好按，以及事件提示是否打擾。最後再比較導覽 A / B。</p></div><a class="link" href="../review/index.html">查看原版與第一輪比較、音效試聽 →</a></section>
</main><footer>codex/experience-redesign · 本機候選，尚未合併主線 · <a href="capture-manifest.json">原生截圖環境與雜湊</a></footer><script>document.querySelectorAll('button[data-mode]').forEach(button=>button.addEventListener('click',()=>{document.body.dataset.mode=button.dataset.mode;document.querySelectorAll('button[data-mode]').forEach(item=>item.setAttribute('aria-pressed',String(item===button)));}));</script></body></html>'''
    for key, value in {'NAV': nav, 'ONBOARDING': onboarding, 'SECTIONS': ''.join(sections), 'EXPANDED': expanded, 'TIMERS': timers, 'RUNNING': running, 'EVENTS': events, 'GLASS': glass}.items():
        document = document.replace(key, value)
    (OUTPUT / 'index.html').write_text(document)
    print(f'Built {len(manifest["images"])} verified native captures at {OUTPUT}')


if __name__ == '__main__':
    main()
