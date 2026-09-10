#!/usr/bin/env python3
"""Build a V2/V3 comparison from a successful native simulator capture batch."""
import hashlib
import html
import json
from pathlib import Path
import sys
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[2]
OUTPUT = ROOT / 'design_trials/experience_redesign/review_v3'

def figure(path, title):
    return f'<figure><figcaption>{html.escape(title)}</figcaption><a href="{path}"><img loading="lazy" width="860" height="1864" src="{path}" alt="{html.escape(title)}"></a></figure>'

def pair(name, title):
    return '<div class="pair compare"><div class="old">' + figure('../review_v2/after/' + name + '.webp', title + ' · V2') + '</div><div class="new">' + figure('after/' + name + '.webp', title + ' · V3') + '</div></div>'

def main():
    source = Path(sys.argv[1]).resolve()
    capture = json.loads((source / 'capture.json').read_text())
    assert capture['exit_code'] == 0 and capture['glass'] is True
    (OUTPUT/'after').mkdir(parents=True, exist_ok=True)
    manifest = {'baseline': '41131ee', 'branch': 'codex/experience-redesign',
        'environment': 'iPhone 14 Pro Max / iOS 26.5 / redesign debug',
        'logical_size': [430, 932], 'locale': 'zh', 'text_scale': 1.0,
        'scene_hour': 10, 'reduced_motion': False, 'glass': True,
        'fixture': 'In-memory records; notification authorization/scheduling stubbed for visual capture',
        'note': 'Native UI evidence; real-device release audio, haptics and performance remain user review',
        'capture': capture, 'images': []}
    fingerprints = set()
    for filename in capture['files']:
        original = source/filename
        digest = hashlib.sha256(original.read_bytes()).hexdigest()
        fingerprints.add(digest)
        destination = OUTPUT/'after'/f'{original.stem}.webp'
        with Image.open(original) as image:
            image.load()
            pixels = image.size
            exported = image.convert('RGB')
            exported.thumbnail((860, 1864), Image.Resampling.LANCZOS)
            exported.save(destination, quality=94, method=6)
        manifest['images'].append({'image': str(destination.relative_to(OUTPUT)),
            'source_pixels': pixels, 'source_sha256': digest,
            'export_sha256': hashlib.sha256(destination.read_bytes()).hexdigest()})
    assert len(fingerprints) > 1, 'Frozen native surface'
    (OUTPUT/'capture-manifest.json').write_text(json.dumps(manifest, indent=2)+'\n')
    for name, files in [
        ('timer-overview', ['timer-focus-compact', 'timer-exercise-compact', 'timer-metronome-compact', 'timer-game-compact']),
        ('overview', ['01-habits', '02-timer', '03-water', '04-weight', '05-family', '06-wardrobe']),
    ]:
        columns = 2 if len(files) == 4 else 3
        sheet = Image.new('RGB', (columns*350, 1550), '#FFF8ED')
        draw = ImageDraw.Draw(sheet)
        for i, filename in enumerate(files):
            with Image.open(OUTPUT/'after'/f'{filename}.webp') as image:
                image.thumbnail((326, 708), Image.Resampling.LANCZOS)
                x,y=i%columns*350+12,i//columns*765+34
                sheet.paste(image, (x,y));draw.text((x,y-22),filename.upper(),fill='#594438')
        sheet.save(OUTPUT/f'{name}.jpg', quality=94)
    for version, path in [('v2', ROOT/'design_trials/experience_redesign/review_v2/glass/nav-water.webp'),
                          ('v3', OUTPUT/'after/03-water.webp')]:
        with Image.open(path) as image:
            crop=image.crop((0,int(image.height*0.885),image.width,image.height))
            crop.save(OUTPUT/f'navigation-{version}.webp', quality=96)
    timer = ''.join('<article><h3>'+title+'</h3>'+pair('timer-'+mode+'-compact', title)+'</article>'
        for mode,title in [('focus','專注 · 四個方案'),('exercise','運動 · 五種快選'),
                           ('metronome','節拍器 · TAP／拍號／細分'),('game','遊戲 · 玩家／骰子／玩法')])
    extra = ''.join(figure('after/'+name+'.webp', title) for name,title in [
        ('timer-jog-compact','超慢跑 · 即時速度與類型'),('timer-jog-adjusted','直接加快 1 BPM'),
        ('timer-chess-compact','快選棋鐘 · 原人數規則保留')])
    galleries = ''.join(figure('after/'+Path(name).stem+'.webp', Path(name).stem) for name in capture['files'])
    document = '''<!doctype html><html lang="zh-Hant"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>兔咪 V3 · 收合也能好好用</title><style>
:root{--paper:#fff8ed;--ink:#594438;--soft:#796657;--accent:#a55540;--line:#ecdccb}*{box-sizing:border-box}body{margin:0;background:var(--paper);color:var(--ink);font:16px/1.7 -apple-system,BlinkMacSystemFont,"PingFang TC",sans-serif}header,main,footer{max-width:1060px;margin:auto;padding:36px 28px}header{padding-top:64px}h1{font-size:clamp(32px,5vw,50px);line-height:1.3;letter-spacing:-.03em}h2{font-size:27px}h3{font-size:19px}.eyebrow{font-size:12px;color:var(--accent);letter-spacing:.12em}p{color:var(--soft)}a{color:var(--accent)}section{padding:20px 0 38px;border-bottom:1px solid var(--line);scroll-margin-top:85px}.toolbar{position:sticky;top:0;z-index:2;border-block:1px solid var(--line);background:#fff8edf5;backdrop-filter:blur(14px)}.tools{max-width:1060px;margin:auto;padding:10px 28px;display:flex;gap:12px;justify-content:space-between;flex-wrap:wrap}button{min-height:40px;border:0;border-radius:16px;background:#f8edde;color:var(--ink);padding:8px 13px;cursor:pointer}button[aria-pressed=true]{background:#a55540;color:white}nav{display:flex;gap:16px;align-items:center;font-size:13px}nav a{text-decoration:none}.pair{display:grid;grid-template-columns:1fr 1fr;gap:24px;max-width:860px;margin:auto}.gallery{display:grid;grid-template-columns:repeat(3,1fr);gap:24px 18px}figure{margin:0;min-width:0}figcaption{font-size:13px;font-weight:700;margin:12px 0 8px}img{width:100%;height:auto;display:block;border-radius:24px;border:1px solid var(--line);box-shadow:0 8px 26px #59443808}.nav img{border-radius:18px}.note{padding:22px;background:#f8edde;border-radius:22px}body[data-mode=v3] .compare .old,body[data-mode=v2] .compare .new{display:none}body:not([data-mode=both]) .compare{grid-template-columns:1fr;max-width:430px}footer{font-size:12px}details{margin-top:24px}summary{cursor:pointer}a:focus-visible,button:focus-visible{outline:3px solid var(--accent);outline-offset:4px}@media(max-width:650px){header,main,footer{padding-inline:18px}.pair{gap:12px}.gallery{grid-template-columns:1fr 1fr}.tools{padding-inline:18px}img{border-radius:16px}}
</style><body data-mode="both"><header><div class="eyebrow">TUMI / EVERYDAY TOGETHER / V3</div><h1>小小的畫面，<br>也能把日常照顧好。</h1><p>以你的 V2 試用回饋為準：玻璃導覽變成主角，收合時把基本操作留在眼前。水瓶回來了，首頁也明亮了一點。</p><p>iPhone 14 Pro Max · 430 × 932 · 繁中 · 預設字級 · 原生模擬器畫面</p></header><div class="toolbar"><div class="tools"><div><button data-mode="both" aria-pressed="true">V2 / V3 並排</button> <button data-mode="v3" aria-pressed="false">只看 V3</button> <button data-mode="v2" aria-pressed="false">只看 V2</button></div><nav><a href="#glass">玻璃</a><a href="#timers">計時</a><a href="#water">水瓶</a><a href="#home">首頁</a><a href="#settings">設定</a></nav></div></div><main>
<section id="glass"><h2>玻璃更輕，選中更清楚</h2><p>V3 預設採玻璃；未選中圖示淡至 42%，標籤保留閱讀對比。選中項目以亮面膠囊與完整彩色圖示辨識。下方為原生截圖的導覽局部，左側是 V2 玻璃候選。</p><div class="pair nav"><figure><figcaption>V2 玻璃候選</figcaption><img src="navigation-v2.webp" alt="V2 玻璃導覽"></figure><figure><figcaption>V3 預設玻璃</figcaption><img src="navigation-v3.webp" alt="V3 玻璃導覽"></figure></div></section>
<section id="timers"><h2>收合，也能直接用</h2><p>主要操作與快捷列優先分配空間，面盤再使用剩餘高度。下方說明與統計仍可捲動；窄尺寸與英文大字另以版面及操作測試驗證。</p>TIMERS<h3>超慢跑和棋鐘，直接切換</h3><div class="gallery">EXTRA</div></section>
<section id="water"><h2>水瓶回到畫面中心</h2><p>收合仍看得到真實水位與主要加水操作，展開後水瓶更大；目標設定與自訂水量保持可達。</p>WATER<h3>展開後</h3>WATER_FULL</section>
<section id="home"><h2>把日常調亮一點</h2><p>杏桃與珊瑚搭配清新的完成綠，保留溫暖，減少深棕混色造成的暗濁感。</p>HOME</section>
<section id="settings"><h2>圖示和文字，一起對齊</h2><p>圖示與標題／說明整組垂直置中，標題與說明共用左緣；長文字可自然換行。</p>SETTINGS<div class="pair">SETTINGS_DETAIL</div></section>
<section><h2>交給手上的感受</h2><div class="note"><p>這份比較使用本機記憶體測試資料，通知授權與排程未納入原生畫面 fixture。實機 Release 的音訊、觸覺與流暢度仍由本人確認。</p><p>優先感受四種計時的快捷完整性、水瓶大小，以及玻璃的選中辨識。已有的「兔咪新體驗」資料會沿用。</p></div><details><summary>查看本輪全部原生畫面</summary><div class="gallery">GALLERY</div></details></section>
</main><footer>codex/experience-redesign · <a href="capture-manifest.json">截圖環境與雜湊</a> · <a href="../review_v2/index.html">V2 全部比較與前導</a></footer><script>document.querySelectorAll('button[data-mode]').forEach(button=>button.addEventListener('click',()=>{document.body.dataset.mode=button.dataset.mode;document.querySelectorAll('button[data-mode]').forEach(item=>item.setAttribute('aria-pressed',String(item===button)));}));</script></body></html>'''
    for key,value in {'TIMERS':timer,'EXTRA':extra,'WATER_FULL':pair('09-water-expanded','喝水展開'),
        'WATER':pair('03-water','喝水收合'),'HOME':pair('01-habits','習慣首頁'),
        'SETTINGS_DETAIL':figure('after/07-settings-details.webp','V3 · 設定下半部'),
        'SETTINGS':pair('07-settings','設定'),'GALLERY':galleries}.items():
        document=document.replace(key,value)
    (OUTPUT/'index.html').write_text(document)
    print(f'Built V3 review with {len(manifest["images"])} validated native image exports: {OUTPUT}')

if __name__=='__main__':
    main()
