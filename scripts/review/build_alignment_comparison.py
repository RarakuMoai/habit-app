#!/usr/bin/env python3
"""Export native alignment review with an immutable V3 comparison baseline."""
import hashlib
import html
import json
from pathlib import Path
import sys
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[2]
OUTPUT = ROOT / 'design_trials/experience_redesign/review_v31'

def figure(path, title):
    return f'<figure><figcaption>{html.escape(title)}</figcaption><a href="{path}"><img loading="lazy" src="{path}" alt="{html.escape(title)}" width="860" height="1864"></a></figure>'

def pair(before, after, title):
    return '<article><h3>'+title+'</h3><div class="compare">'+figure('../review_v3/after/'+before+'.webp','V3')+figure('after/'+after+'.webp','V3.1')+'</div></article>'

def main():
    source = Path(sys.argv[1]).resolve()
    capture = json.loads((source/'capture.json').read_text())
    assert capture['exit_code'] == 0, 'Native matrix must pass before export'
    (OUTPUT/'after').mkdir(parents=True, exist_ok=True)
    images=[]
    for filename in capture['files']:
        src=source/filename; dest=OUTPUT/'after'/f'{src.stem}.webp'
        with Image.open(src) as image:
            image.load(); pixels=image.size
            export=image.convert('RGB'); export.thumbnail((860,1864),Image.Resampling.LANCZOS)
            export.save(dest,quality=94,method=6)
        images.append({'path':str(dest.relative_to(OUTPUT)), 'source_pixels':pixels,
            'source_sha256':hashlib.sha256(src.read_bytes()).hexdigest(),
            'export_sha256':hashlib.sha256(dest.read_bytes()).hexdigest()})
    (OUTPUT/'capture-manifest.json').write_text(json.dumps({
        'baseline':'6a4551c','branch':'codex/experience-redesign',
        'environment':'Tumi Experience Review / iPhone 14 Pro Max / iOS 26.5 / redesign debug',
        'logical_size':[430,932],'locale':'zh','text_scale':1.0,'scene_hour':10,
        'reduced_motion':False,'glass':True,
        'fixture':'Synthetic in-memory records; notification permission and jog sound excluded',
        'capture':capture,'images':images},indent=2)+'\n')
    for name,files,cols in [
        ('exercise-overview',[f'exercise-{kind}-{state}' for state in ['compact','expanded'] for kind in ['tabata','hiit','emom','gym','jog']],5),
        ('jog-comparison',['../review_v3/after/timer-jog-compact','exercise-jog-compact'],2),
        ('other-pages',[f'page-{page}' for page in ['habits','water','weight','family','wardrobe','settings']],3),
    ]:
        sheet=Image.new('RGB',(cols*350,((len(files)+cols-1)//cols)*778),'#fff8ed');draw=ImageDraw.Draw(sheet)
        for i,namepart in enumerate(files):
            path=(OUTPUT/namepart).with_suffix('.webp') if namepart.startswith('..') else OUTPUT/'after'/f'{namepart}.webp'
            with Image.open(path) as im:
                im.thumbnail((326,708),Image.Resampling.LANCZOS);x,y=i%cols*350+12,i//cols*778+35
                sheet.paste(im,(x,y));draw.text((x,y-23),Path(namepart).name,fill='#594438')
        sheet.save(OUTPUT/f'{name}.jpg',quality=94)
    comparisons=''.join(pair(*item) for item in [
        ('timer-jog-compact','exercise-jog-compact','超慢跑：面盤與操作區重新分配'),
        ('timer-exercise-compact','exercise-tabata-compact','運動：圖示與文字回到卡片中心'),
        ('timer-exercise-expanded','exercise-jog-expanded','展開：速度與主操作放在一起'),
        ('timer-metronome-compact','timer-metronome-compact','節拍器：快捷列等寬、左右對稱'),
        ('timer-focus-compact','timer-focus-compact','專注：方案卡內容置中'),
        ('timer-game-compact','timer-game-compact','遊戲：同列等高、內容置中'),
    ])
    matrix=''
    for layout,label in [('compact','收合'),('expanded','展開')]:
        matrix+=f'<h3>{label}・五種運動</h3><div class="matrix">'
        for kind,title in [('tabata','Tabata'),('hiit','HIIT'),('emom','EMOM'),('gym','重訓'),('jog','超慢跑')]:
            matrix+=figure(f'after/exercise-{kind}-{layout}.webp',title)
        matrix+='</div>'
    gallery=''.join(figure(item['path'],Path(item['path']).stem) for item in images)
    page='''<!doctype html><html lang="zh-Hant"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>兔咪 V3.1・對齊與運動計時修正</title><style>
*{box-sizing:border-box}body{margin:0;background:#fff8ed;color:#594438;font:16px/1.7 -apple-system,BlinkMacSystemFont,"PingFang TC",sans-serif}header,main,footer{max-width:1120px;margin:auto;padding:28px}h1{font-size:clamp(28px,5vw,46px);line-height:1.3}h2{font-size:27px}h3{font-size:19px}p{color:#796657}a{color:#a55540}section{margin:28px 0;padding-bottom:30px;border-bottom:1px solid #ecdccb}article{padding:14px 0 30px}.compare{display:grid;grid-template-columns:1fr 1fr;gap:24px;max-width:860px;margin:auto}.matrix,.gallery{display:grid;grid-template-columns:repeat(3,1fr);gap:22px}figure{margin:0;min-width:0}figcaption{font-size:13px;margin:10px 0;font-weight:700}img{display:block;width:100%;height:auto;border:1px solid #ecdccb;border-radius:22px}details{padding:18px;background:#f8edde;border-radius:20px}summary{cursor:pointer}.note{padding:20px;border-radius:20px;background:#f8edde}footer{font-size:12px}a:focus-visible,summary:focus-visible{outline:3px solid #a55540;outline-offset:4px}@media(max-width:650px){header,main,footer{padding:18px}.compare{gap:12px}.matrix,.gallery{grid-template-columns:1fr 1fr;gap:12px}img{border-radius:16px}}
</style><body><header><p>兔咪新體驗 / V3.1</p><h1>把框內的重心，<br>與操作的位置整理好。</h1><p>這輪聚焦 V3 實際看到的對齊問題：快捷卡圖文靠上、超慢跑面盤被壓小，以及右側操作過寬。以下直接使用原生模擬器畫面比較。</p><p><a href="#comparison">看前後差異</a> · <a href="#exercise">五種運動</a> · <a href="#states">運行與暫停</a></p></header><main>
<section id="comparison"><h2>同一個畫面，修正前後</h2>COMPARISONS</section>
<section id="exercise"><h2>五種運動，兩種版面</h2><p>固定左右分欄，避免切到超慢跑就把開始按鈕拉寬。BPM 與主操作放在同一區，五種運動的快捷入口保持可見。</p>MATRIX</section>
<section id="states"><h2>運行、暫停與其他頁面</h2><p>原生矩陣逐一操作五種運動的待機、運行與暫停，並檢查設定與其餘主頁。繁中、430 × 932、預設字級、正常動態；英文 1.3 倍字級另外以真實 parent 的量測測試驗證。</p><details><summary>查看全部原生截圖</summary><div class="gallery">GALLERY</div></details></section>
<div class="note"><p>這些截圖使用記憶體測試資料。通知授權、實機音效、觸覺與 Release 流暢度仍由本人確認；畫面可操作與測試通過不等於視覺偏好已驗收。</p></div>
</main><footer><a href="capture-manifest.json">場景與截圖雜湊</a> · <a href="validation.json">最終驗證紀錄</a> · <a href="../review_v3/index.html">保留的 V3 比較頁</a></footer></body></html>'''
    (OUTPUT/'index.html').write_text(page.replace('COMPARISONS',comparisons).replace('MATRIX',matrix).replace('GALLERY',gallery))
    print(f'Exported {len(images)} native captures to {OUTPUT}')

if __name__=='__main__':
    main()
