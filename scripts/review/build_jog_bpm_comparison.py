#!/usr/bin/env python3
"""Export the native BPM review without changing the V3.1 baseline."""
import hashlib
import html
import json
from pathlib import Path
import sys

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[2]
OUTPUT = ROOT / 'design_trials/experience_redesign/review_v32'


def figure(path, title):
    return (f'<figure><figcaption>{html.escape(title)}</figcaption>'
            f'<a href="{path}"><img loading="lazy" src="{path}" '
            f'alt="{html.escape(title)}" width="860" height="1864"></a></figure>')


def main():
    source = Path(sys.argv[1]).resolve()
    capture = json.loads((source / 'capture.json').read_text())
    assert capture['exit_code'] == 0, 'Native review must pass before export'
    (OUTPUT / 'after').mkdir(parents=True, exist_ok=True)
    images = []
    for filename in capture['files']:
        src = source / filename
        dest = OUTPUT / 'after' / f'{src.stem}.webp'
        with Image.open(src) as image:
            image.load()
            pixels = image.size
            export = image.convert('RGB')
            export.thumbnail((860, 1864), Image.Resampling.LANCZOS)
            export.save(dest, quality=94, method=6)
        images.append({
            'path': str(dest.relative_to(OUTPUT)), 'source_pixels': pixels,
            'source_sha256': hashlib.sha256(src.read_bytes()).hexdigest(),
            'export_sha256': hashlib.sha256(dest.read_bytes()).hexdigest(),
        })
    (OUTPUT / 'capture-manifest.json').write_text(json.dumps({
        'baseline': '6d79c63', 'branch': 'codex/experience-redesign',
        'environment': 'Tumi Experience Review / iPhone 14 Pro Max / iOS 26.5 / redesign debug',
        'logical_size': [430, 932], 'locale': 'zh', 'text_scale': 1.0,
        'scene_hour': 10, 'reduced_motion': False, 'glass': True,
        'fixture': 'Synthetic in-memory records; notification permission and jog sound excluded',
        'capture': capture, 'images': images,
    }, indent=2) + '\n')
    pairs = [
        ('../review_v31/after/exercise-jog-compact.webp', 'V3.1'),
        ('after/exercise-jog-compact.webp', 'V3.2'),
    ]
    sheet = Image.new('RGB', (760, 870), '#fff8ed')
    draw = ImageDraw.Draw(sheet)
    for i, (path, label) in enumerate(pairs):
        with Image.open(OUTPUT / path) as image:
            image.thumbnail((352, 763), Image.Resampling.LANCZOS)
            sheet.paste(image, (i * 380 + 14, 55))
            draw.text((i * 380 + 14, 23), label, fill='#594438')
    sheet.save(OUTPUT / 'jog-comparison.jpg', quality=94)
    comparisons = ''.join(figure(*pair) for pair in pairs)
    alignment = ''.join(figure(f'after/exercise-{kind}-compact.webp', label)
                        for kind, label in [('tabata', 'Tabata'), ('jog', '超慢跑')])
    states = ''.join(figure(f'after/{name}.webp', title) for name, title in [
        ('jog-compact-step', '點加減：立即調整'),
        ('jog-compact-editor', '點數字：精準輸入'),
        ('jog-compact-precise', '確認後：200 BPM'),
        ('jog-compact-running', '運動中：保持節奏'),
        ('jog-running-adjusted', '運動中仍可調整'),
        ('jog-compact-paused', '暫停：原位置繼續'),
        ('exercise-jog-expanded', '展開：同一組上方控制'),
        ('jog-expanded-editor', '展開的精準輸入'),
        ('jog-expanded-paused', '展開暫停'),
    ])
    page = '''<!doctype html><html lang="zh-Hant"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>兔咪 V3.2・超慢跑 BPM</title><style>
*{box-sizing:border-box}body{margin:0;background:#fff8ed;color:#594438;font:16px/1.7 -apple-system,BlinkMacSystemFont,"PingFang TC",sans-serif}header,main,footer{max-width:1080px;margin:auto;padding:28px}h1{font-size:clamp(28px,5vw,44px);line-height:1.35}h2{font-size:26px}p{color:#796657}a{color:#a55540}section{margin:28px 0;padding-bottom:32px;border-bottom:1px solid #ecdccb}.compare{display:grid;grid-template-columns:1fr 1fr;gap:24px;max-width:780px;margin:auto}.gallery{display:grid;grid-template-columns:repeat(3,1fr);gap:22px}figure{margin:0;min-width:0}figcaption{font-size:14px;margin:10px 0;font-weight:700}img{display:block;width:100%;height:auto;border:1px solid #ecdccb;border-radius:22px}.note{padding:20px;border-radius:20px;background:#f8edde}footer{font-size:12px}a:focus-visible{outline:3px solid #a55540;outline-offset:4px}@media(max-width:650px){header,main,footer{padding:18px}.compare{gap:12px}.gallery{grid-template-columns:1fr 1fr;gap:12px}img{border-radius:16px}}
</style><body><header><p>兔咪新體驗 / V3.2</p><h1>讓 BPM 小巧好調，<br>開始按鈕回到一致的位置。</h1><p>BPM 放進既有的上方工具列：左右點按或長按調速，點數字精準輸入。操作區少一整列，面盤與開始、重設、跳過各自保有空間。</p><p><a href="#comparison">修正前後</a> · <a href="#alignment">切換運動的位置</a> · <a href="#controls">操作與狀態</a></p></header><main>
<section id="comparison"><h2>超慢跑，修正前後</h2><p>V3.1 的 BPM 在開始與重設之間，增加一整列高度。V3.2 使用原有標題列的 44pt 膠囊；右側主操作從 156pt 回到與其他運動一致的 104pt。</p><div class="compare">COMPARISONS</div></section>
<section id="alignment"><h2>切換運動，主要按鈕維持原位</h2><p>同一個 430 × 932 原生畫面：面盤欄、開始、重設及五種快捷入口維持相同布局。BPM 不再推動右側操作。</p><div class="compare">ALIGNMENT</div></section>
<section id="controls"><h2>小空間，保留完整調整</h2><p>加減 1 BPM、長按連續調整、點數字輸入 30–240 BPM，運動中也可調整。設定入口與五種運動快選仍保留。</p><div class="gallery">STATES</div></section>
<div class="note"><p>畫面來自專用 iPhone 14 Pro Max／iOS 26.5 模擬器，繁中、預設字級、正常動態。320／430pt 的中英文 1.3 倍字級與鍵盤另以真實 parent 約束測試。極矮面板仍採摘要與捲動，保留觸控大小。</p><p>使用記憶體測試資料；實機音效、觸覺與 Release 手感待本人確認。</p></div>
</main><footer><a href="capture-manifest.json">全部截圖與場景紀錄</a> · <a href="validation.json">驗證結果</a> · <a href="../review_v31/index.html">保留的 V3.1 比較頁</a></footer></body></html>'''
    (OUTPUT / 'index.html').write_text(page.replace('COMPARISONS', comparisons)
                                     .replace('ALIGNMENT', alignment).replace('STATES', states))
    print(f'Exported {len(images)} native captures to {OUTPUT}')


if __name__ == '__main__':
    main()
