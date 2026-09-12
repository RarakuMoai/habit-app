#!/usr/bin/env python3
"""Build a local comparison page from this run's native captures (no mock images)."""
import argparse
import json
import shutil
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument('--source', type=Path, required=True)
parser.add_argument('--output', type=Path, required=True)
a = parser.parse_args()
scenes = [
 ('01-first-cover','首次封面'), ('02-auth-simulation','登入模擬面板'),
 ('03-canceled','取消登入'), ('04-login-failed','登入失敗'),
 ('05-first-meeting','短初見'), ('06-optional-name','可省略暱稱'),
 ('07-room','房間落地'), ('08-room-action','一件小事完成'),
 ('09-returning-signed-in','回訪已登入'), ('10-returning-guest','回訪訪客'),
 ('11-restore-unknown','恢復失敗：資料仍未知'), ('12-restored-room','模擬恢復：不重播初見'),
 ('13-offline','離線'), ('14-skipped-meeting','略過初見'),
 ('15-init-failure','初始化失敗'), ('16-init-retried','初始化重試'),
 ('17-large-text-reduce-cover','200% 大字＋降低動態：封面'),
 ('17b-large-text-actions','200% 大字：捲動後的三種入口'),
 ('18-large-text-reduce-room','200% 大字＋降低動態：房間'),
 ('19-english-large-room','英文＋200% 大字：房間'),
 ('20-apple-new-room','Apple 模擬成功：新旅程'),
 ('21-google-restored-room','Google 模擬成功：恢復旅程')]
a.output.mkdir(parents=True, exist_ok=True)
for size in ['small','large','lifecycle']:
 src=a.source/size
 if src.exists():
  shutil.copytree(src,a.output/size,dirs_exist_ok=True)
for size in ['small','large']:
 result=json.loads((a.output/size/'capture.json').read_text())
 assert result['exit_code']==0 and not result['repeated']
 for slug,_ in scenes: assert (a.output/size/(slug+'.png')).is_file()
html='''<!doctype html><html lang="zh-Hant"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>兔咪入口樣品 · 原生驗證</title>
<style>body{margin:0;background:#f4f0e8;color:#443127;font:16px/1.6 system-ui}main{max-width:1200px;margin:auto;padding:28px}h1{margin:0;font-size:28px}p{max-width:900px}select,button{font:inherit;padding:10px;border:1px solid #baa99a;border-radius:10px;background:#fffdf9;color:inherit}select{max-width:100%}.bar{position:sticky;top:0;padding:14px 0;background:#f4f0e8f5;z-index:1;display:flex;gap:8px;flex-wrap:wrap}.pair{display:grid;grid-template-columns:1fr 1fr;gap:24px}.pair figure{margin:0;text-align:center}.pair img{max-width:100%;max-height:76vh;object-fit:contain;box-shadow:0 5px 25px #44312718}figcaption{padding:12px}video{max-width:100%;height:65vh;background:#000;border-radius:16px}.badge{display:inline-block;padding:4px 12px;border-radius:20px;background:#e7ddce}a{color:#80502d}details{padding:12px;border-top:1px solid #d8caba}.videos{display:flex;gap:20px;flex-wrap:wrap}@media(max-width:680px){main{padding:18px}.pair{gap:10px}h1{font-size:23px}}</style>
<main><span class="badge">本輪實際模擬器擷取 · 帳號皆為模擬</span><h1>封面 → 開始／繼續 → 初見／房間</h1>
<p>素材暫以既有房間＋核准兔咪原圖組合；封面候選仍待確認。下列畫面來自同一份 Flutter debug 樣品，沒有用舊畫面代替。正式資料、OAuth、後端與六分頁功能未接入。</p>
<p><a href="handoff.md">修改範圍、操作方式與驗證界線</a> · <a href="evidence.json">擷取與驗證紀錄</a></p>
<div class="bar"><button id="prev">上一個</button><select id="scene"></select><button id="next">下一個</button></div>
<div class="pair"><figure><a id="smallLink"><img id="small" alt="小螢幕原生畫面"></a><figcaption>iPhone SE 3 · 375 × 667 pt · iOS 26.5</figcaption></figure><figure><a id="largeLink"><img id="large" alt="大螢幕原生畫面"></a><figcaption>iPhone 14 Pro Max · 430 × 932 pt · iOS 26.5</figcaption></figure></div>
<p>點圖片可看原始 PNG。大字採樣品 200% 覆寫；長文可捲動，未縮小文字。降低動態採樣品覆寫；系統設定切換、VoiceOver 與實機音訊／觸覺／順暢度未驗收。</p>
<h2>本輪操作錄影</h2><p>自動操作實際控制項，擷取時會停留供檢查；這些測試等待不是 APP 的最低等待時間。simctl 影片沒有聲音軌。</p><div class="videos"><figure><video controls preload="metadata" src="small/walkthrough.mp4"></video><figcaption>小螢幕完整操作</figcaption></figure><figure><video controls preload="metadata" src="large/walkthrough.mp4"></video><figcaption>大螢幕完整操作</figcaption></figure></div>
<h2>獨立程序檢查</h2><div class="videos"><figure><video controls preload="metadata" src="lifecycle/cold-launch-final.mp4"></video><figcaption>debug 冷啟動：必要初始化 → 回訪封面</figcaption></figure></div>
<p>真正背景／前景切換尚未驗證：電腦操作工具回報 Mac 已鎖住，無法操作 Home。lifecycle widget 測試已通過，不能代替原生操作證據。</p><p>僅作流程與構圖證據；debug 模擬器啟動時間不能當成 release 實機效能。</p></main><script>
const scenes=SCENES;const select=document.getElementById('scene');scenes.forEach(([value,label])=>select.add(new Option(label,value)));
function show(){for(const size of ['small','large']){const url=size+'/'+select.value+'.png';document.getElementById(size).src=url;document.getElementById(size+'Link').href=url}}select.onchange=show;
document.getElementById('prev').onclick=()=>{select.selectedIndex=(select.selectedIndex+scenes.length-1)%scenes.length;show()};document.getElementById('next').onclick=()=>{select.selectedIndex=(select.selectedIndex+1)%scenes.length;show()};show();
</script></html>'''.replace('SCENES',json.dumps(scenes,ensure_ascii=False))
(a.output/'index.html').write_text(html)
print(a.output/'index.html')
