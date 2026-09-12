#!/usr/bin/env python3
"""Archive this round's native captures and build a local, evidence-led gallery.

Example:
  python3 scripts/review/build_entry_integration_gallery.py \
    --capture before-small=/tmp/entry-integration-before-small \
    --capture first-small=/tmp/entry-integration-first-small \
    --capture returning-large=/tmp/entry-integration-returning-large \
    --output /tmp/entry-integration-gallery

Inputs use run_entry_integration.py's capture.json schema. Missing/failed runs
remain visibly incomplete. Originals are copied without conversion or editing;
this tool does not record, decode videos, run the app, or certify native tests.
An empty invocation may check page structure, but produces no native evidence.
Manual reviews use manual_review_complete=true and test_exit_code=null; they
remain explicitly separate from successful automated integration tests.
"""

import argparse
from datetime import datetime, timezone
import hashlib
import html
import json
from pathlib import Path
import re
import shutil
import struct


BASELINE = 'a579d106bd7c6b27350fb7b409f0c20ee8e43f2c'
SCENARIOS = {
    'first': '首次使用',
    'returningGuest': '回訪訪客',
    'returningSignedIn': '回訪已登入（身份模擬）',
    'credentialsOnly': '有憑證、無本機旅程（身份模擬）',
    'cancelled': '取消登入（模擬）',
    'canceled': '取消登入（模擬）',
    'offline': '離線（模擬）',
    'initializationFailed': '初始化失敗（注入故障）',
    'authErrors': '取消登入／失敗／離線（模擬）',
    'initFailure': '初始化失敗與重試（注入故障）',
    'credentialsOffline': '有憑證、雲端未確認 → 重試（模擬）',
    'appleNew': 'Apple 登入後新旅程（身份模擬）',
    'googleRestore': 'Google 登入後恢復旅程（身份與雲端資料模擬）',
    'background': '背景回前景',
}
EVIDENCE_SUFFIXES = {'.log', '.json', '.sha256'}
SCREENS = {
    '00-ios-reduce-motion': 'iOS 設定：減少動態效果已開啟',
    '00b-ios-max-text': 'iOS 設定：最大輔助使用字體',
    '00-init-error': '初始化失敗',
    '01-cover': '封面',
    '02-account-choice': '登入與開始',
    '03-first-meeting': '短初見',
    '04-real-home': '真正主畫面',
    '05-real-timer': '既有計時功能',
    '06-real-timer-running': '計時運行',
    '07-real-timer-paused': '計時暫停',
    '02b-login-cancelled': '登入取消，尚未建立旅程',
    '02c-login-failed': '登入失敗',
    '02d-offline-login': '離線登入失敗',
    '02-cloud-unknown': '雲端資料尚未確認',
    '02b-cloud-empty-confirmed': '重試後才確認雲端無資料',
    '02b-cloud-found': '找到可恢復資料',
    '02b-restore-existing': '既有帳號／資料恢復頁',
    '02c-restore-confirmation': '恢復前確認',
    '02d-restored-cover': '恢復後返回封面',
}
COMPARISON_SCREENS = ('01-cover', '03-first-meeting', '04-real-home', '05-real-timer')


def esc(value):
    return html.escape(str(value), quote=True)


def sha256(path):
    result = hashlib.sha256()
    with path.open('rb') as source:
        for block in iter(lambda: source.read(1024 * 1024), b''):
            result.update(block)
    return result.hexdigest()


def safe_file(directory, name):
    if not isinstance(name, str) or Path(name).name != name or name in ('', '.', '..'):
        raise ValueError('Capture filenames must be plain basenames: ' + repr(name))
    path = directory / name
    if path.is_symlink():
        raise ValueError('Capture evidence must be a file, not a symlink: ' + str(path))
    return path


def png_size(path):
    with path.open('rb') as source:
        header = source.read(24)
    if len(header) != 24 or header[:8] != b'\x89PNG\r\n\x1a\n' or header[12:16] != b'IHDR':
        raise ValueError('Invalid PNG header: ' + path.name)
    width, height = struct.unpack('>II', header[16:24])
    if not width or not height:
        raise ValueError('Empty PNG dimensions: ' + path.name)
    return [width, height]


def archive_run(label, source, output):
    destination = output / 'captures' / label
    destination.mkdir(parents=True)
    run = {'label': label, 'source_directory': str(source), 'capture': {},
           'status': 'missing', 'issues': [], 'images': [], 'video': None, 'archives': []}

    def copy_file(path):
        digest = sha256(path)
        target = destination / path.name
        shutil.copy2(path, target)
        if sha256(target) != digest:
            raise RuntimeError('Archive copy differs from source: ' + str(path))
        item = {'path': target.relative_to(output).as_posix(), 'sha256': digest,
                'bytes': target.stat().st_size}
        run['archives'].append(item)
        return item

    if not source.is_dir():
        run['issues'].append('來源目錄不存在，未執行。')
        return run
    for path in sorted(source.iterdir()):
        if path.is_file() and not path.is_symlink() and path.suffix in EVIDENCE_SUFFIXES:
            copy_file(path)
    manifest = source / 'capture.json'
    if not manifest.is_file() or manifest.is_symlink():
        run['issues'].append('沒有 capture.json；可能仍在建置，未列為原生驗證。')
        return run
    try:
        capture = json.loads(manifest.read_text(encoding='utf-8'))
        if not isinstance(capture, dict):
            raise ValueError('capture.json must contain an object')
        run['capture'] = capture
    except (ValueError, OSError) as error:
        run['issues'].append('無法讀取 capture.json：' + str(error))
        return run
    manual_complete = capture.get('manual_review_complete') is True and capture.get('test_exit_code') is None
    if manual_complete and not capture.get('errors'):
        run['status'] = 'manual'
    else:
        run['status'] = 'passed' if capture.get('test_exit_code') == 0 and not capture.get('errors') else 'failed'
    run['issues'].extend(str(error) for error in capture.get('errors', []))
    if capture.get('test_exit_code') != 0 and not manual_complete:
        run['issues'].append('原生測試 exit code：' + str(capture.get('test_exit_code', '未記錄')))
    frames = {frame.get('name'): frame for frame in capture.get('frames', []) if isinstance(frame, dict)}
    seen = set()
    for recorded in capture.get('captures', []):
        try:
            path = safe_file(source, recorded['file'])
            if path.name in seen:
                raise ValueError('重複列出的 PNG：' + path.name)
            seen.add(path.name)
            if path.suffix.lower() != '.png' or not path.is_file():
                raise ValueError('缺少 PNG：' + path.name)
            pixels = png_size(path)
            if recorded.get('sha256') != sha256(path):
                raise ValueError('PNG 與 capture.json 雜湊不符：' + path.name)
            item = copy_file(path)
            item.update({'name': path.stem, 'pixels': pixels, 'frame': frames.get(path.stem, {})})
            run['images'].append(item)
        except (KeyError, ValueError, OSError, TypeError) as error:
            run['issues'].append(str(error))
            run['status'] = 'failed'
    recorded_video = capture.get('video')
    if isinstance(recorded_video, dict):
        try:
            path = safe_file(source, recorded_video.get('file'))
            if path.suffix.lower() != '.mp4' or not path.is_file() or not path.stat().st_size:
                raise ValueError('沒有非空的原始 MP4。')
            if recorded_video.get('bytes') != path.stat().st_size:
                raise ValueError('MP4 大小與 capture.json 不符。')
            item = copy_file(path)
            item['decoded'] = recorded_video.get('decoded') is True
            run['video'] = item
        except (ValueError, OSError, TypeError) as error:
            run['issues'].append(str(error))
            run['status'] = 'failed'
    if not run['images']:
        run['issues'].append('沒有可核對的原生 PNG。')
        run['status'] = 'failed'
    return run


def meta(run):
    return run['capture'].get('metadata', {})


def frame_text(frame):
    size = frame.get('size') or []
    parts = []
    if len(size) == 2:
        parts.append(f'{size[0]:g} × {size[1]:g} pt')
    if frame.get('locale'):
        parts.append(str(frame['locale']))
    if isinstance(frame.get('textScale'), (int, float)):
        parts.append(f"字級 {frame['textScale']:g}×")
    else:
        parts.append('字級未量測')
    if isinstance(frame.get('requestedTextScale'), (int, float)):
        parts.append(f"測試要求 {frame['requestedTextScale']:g}×")
    if isinstance(frame.get('disableAnimations'), bool):
        parts.append('Reduce Motion 開' if frame['disableAnimations'] else 'Reduce Motion 關')
    elif isinstance(frame.get('reduceMotion'), bool):
        state = '開' if frame['reduceMotion'] else '關'
        parts.append(f'Reduce Motion {state}（iOS 設定；MediaQuery 未量測）')
    else:
        parts.append('Reduce Motion 未量測')
    if frame.get('nativeContentSize') == 'accessibility-extra-extra-extra-large':
        parts.append('iOS 最大輔助使用字體')
    if frame.get('surface'):
        parts.append(str(frame['surface']))
    return ' · '.join(parts) or '未記錄畫面環境'


def run_title(run):
    data = meta(run)
    title = SCENARIOS.get(data.get('scenario'), data.get('scenario', run['label']))
    if data.get('skipMeeting'):
        title += ' · 略過初見'
    return ('整合前' if data.get('before') else '整合後') + ' · ' + title


def image_card(run, item, title=None):
    caption = title or SCREENS.get(item['name'], item['name'])
    return f'''<figure><a href="{esc(item['path'])}" target="_blank" rel="noopener">
<img src="{esc(item['path'])}" loading="lazy" alt="{esc(caption)}"></a>
<figcaption><strong>{esc(caption)}</strong><span>{esc(frame_text(item['frame']))}</span>
<span>{esc(run['label'])} · {item['pixels'][0]} × {item['pixels'][1]} px · 原始 PNG</span></figcaption></figure>'''


def match_key(run, item):
    frame = item['frame']
    # The baseline ARB's `zh` is the same Traditional Chinese content now
    # identified as `zh-TW`. Preserve the exact reported tag in every caption.
    locale = 'zh-TW' if frame.get('locale') == 'zh' else frame.get('locale')
    return (meta(run).get('scenario'), tuple(frame.get('size') or []), locale,
            frame.get('textScale'), frame.get('disableAnimations'), item['name'])


def comparison_html(runs):
    before = {}
    for run in runs:
        if meta(run).get('before'):
            for item in run['images']:
                before.setdefault(match_key(run, item), (run, item))
    cards, unmatched = [], []
    for run in runs:
        if meta(run).get('before'):
            continue
        for item in run['images']:
            if item['name'] not in COMPARISON_SCREENS:
                continue
            match = before.get(match_key(run, item))
            if match:
                left = image_card(*match, title='整合前 · ' + SCREENS[item['name']])
            else:
                unmatched.append(f'<li>{esc(run["label"])} · {esc(SCREENS[item["name"]])}</li>')
                continue
            cards.append(f'<article><h3>{esc(run_title(run))} · {esc(SCREENS[item["name"]])}</h3>'
                         f'<div class="pair"><div class="before">{left}</div>'
                         f'<div class="after">{image_card(run, item, "整合後 · " + SCREENS[item["name"]])}</div></div></article>')
    content = ''.join(cards) or '<div class="missing">沒有同條件的前後擷取；對照尚未執行。</div>'
    if unmatched:
        content += ('<details><summary>未執行同條件的整合前擷取</summary>'
                    '<p>以下畫面只有本輪整合後證據，原圖保留於連續操作與尺寸檢查；不以其他版本、尺寸或舊樣品補圖。</p>'
                    '<ul>' + ''.join(unmatched) + '</ul></details>')
    return content


def coverage_rows(runs):
    after = [run for run in runs if not meta(run).get('before')]

    def tags(run):
        values = meta(run).get('verifiedScenarios', [])
        return set(values if isinstance(values, list) else []) | {meta(run).get('scenario')}

    def has_frames(run, *names):
        return set(names) <= {item['name'] for item in run['images']}

    def native_background(run):
        capture = run['capture']
        if meta(run).get('nativeBackground') is True:
            return True
        actions = capture.get('native_background', [])
        lifecycle = json.dumps(capture.get('observed_lifecycle', []))
        return (bool(actions) and 'paused' in lifecycle and 'resumed' in lifecycle)

    cases = [
        ('真正程序冷重啟（手動）', lambda r: r['status'] == 'manual' and meta(r).get('nativeColdRestart') is True),
        ('原生偏好／資料重啟後仍保存（手動）', lambda r: r['status'] == 'manual' and meta(r).get('nativePreferencesPersistence') is True),
        ('真實 iOS 可及性設定操作（手動）', lambda r: r['status'] == 'manual' and meta(r).get('nativeAccessibilitySettings') is True),
        ('iOS 系統最大字級（App 保留既有上限）', lambda r: r['status'] == 'manual' and meta(r).get('nativeAccessibilitySettings') is True and meta(r).get('nativeContentSize') == 'accessibility-extra-extra-extra-large'),
        ('首次使用 → 真主畫面／既有功能', lambda r: meta(r).get('scenario') == 'first' and not meta(r).get('skipMeeting') and any(i['name'] == '06-real-timer-running' for i in r['images'])),
        ('回訪訪客', lambda r: meta(r).get('scenario') == 'returningGuest'),
        ('回訪已登入（身份模擬）', lambda r: meta(r).get('scenario') == 'returningSignedIn'),
        ('Apple 新旅程（身份模擬）', lambda r: 'appleNew' in tags(r) and has_frames(r, '04-real-home')),
        ('Google 恢復既有旅程（身份／雲端資料模擬）', lambda r: 'googleRestore' in tags(r) and has_frames(r, '02d-restored-cover', '04-real-home')),
        ('取消登入（模擬）', lambda r: bool(tags(r) & {'cancelled', 'canceled', 'cancelLogin'}) or ('authErrors' in tags(r) and has_frames(r, '02b-login-cancelled'))),
        ('登入失敗（模擬）', lambda r: 'authErrors' in tags(r) and has_frames(r, '02c-login-failed')),
        ('離線（模擬）', lambda r: 'offline' in tags(r) or ('authErrors' in tags(r) and has_frames(r, '02d-offline-login'))),
        ('有憑證但雲端未確認 → 重試', lambda r: 'credentialsOffline' in tags(r) and has_frames(r, '02-cloud-unknown', '02b-cloud-empty-confirmed')),
        ('初始化失敗與重試（注入故障）', lambda r: bool(tags(r) & {'initializationFailed', 'initializationFailure'}) or ('initFailure' in tags(r) and has_frames(r, '00-init-error', '01-cover'))),
        ('略過初見', lambda r: meta(r).get('skipMeeting') is True),
        ('原生背景回前景', native_background),
        ('小螢幕（寬度 ≤ 375 pt）', lambda r: any(i['frame'].get('size') and i['frame']['size'][0] <= 375 for i in r['images'])),
        ('大螢幕（寬度 ≥ 430 pt）', lambda r: any(i['frame'].get('size') and i['frame']['size'][0] >= 430 for i in r['images'])),
        ('大字請求（要求 2×，依畫面記錄實際上限）', lambda r: any(isinstance(i['frame'].get('requestedTextScale'), (int, float)) and i['frame']['requestedTextScale'] >= 2 for i in r['images'])),
        ('完整 2× 字級畫面', lambda r: any(isinstance(i['frame'].get('textScale'), (int, float)) and i['frame']['textScale'] >= 2 for i in r['images'])),
        ('Reduce Motion', lambda r: any(i['frame'].get('disableAnimations') is True or i['frame'].get('reduceMotion') is True for i in r['images'])),
    ]
    rows = []
    for title, predicate in cases:
        matched = [run for run in after if predicate(run)]
        passed = [run for run in matched if run['status'] == 'passed']
        manual = [run for run in matched if run['status'] == 'manual']
        if passed:
            status = '有本輪擷取／測試完成紀錄'
            evidence = '、'.join(f'<a href="#run-{esc(run["label"])}">{esc(run["label"])}</a>' for run in passed)
            if manual:
                evidence += '；另有手動：' + '、'.join(f'<a href="#run-{esc(run["label"])}">{esc(run["label"])}</a>' for run in manual)
        elif manual:
            status = '手動操作已核對（非自動測試）'
            evidence = '、'.join(f'<a href="#run-{esc(run["label"])}">{esc(run["label"])}</a>' for run in manual)
        elif matched:
            status = '有擷取，但該批未通過'
            evidence = '、'.join(esc(run['label']) for run in matched)
        else:
            status, evidence = '未執行／未提供可核對證據', '—'
        rows.append(f'<tr><th scope="row">{esc(title)}</th><td>{status}</td><td>{evidence}</td></tr>')
    return ''.join(rows)


def runs_html(runs):
    sections = []
    for run in runs:
        capture = run['capture']
        source = capture.get('source', {})
        status = {'passed': '測試與擷取 manifest 完成', 'manual': '手動操作已核對（非自動測試）', 'failed': '該批未通過', 'missing': '未執行／紀錄未完成'}[run['status']]
        environment = frame_text(run['images'][0]['frame']) if run['images'] else '尚無畫面環境'
        device = capture.get('device', {})
        if not isinstance(device, dict):
            device = {'name': device}
        video = run['video']
        if video:
            decoding = '來源 manifest 記錄已解碼' if video['decoded'] else '尚未提供影片解碼驗證；此頁不把檔案存在當成解碼通過'
            cover = next((item for item in run['images'] if item['name'] == '01-cover'), None)
            poster = f' poster="{esc(cover["path"])}"' if cover else ''
            # Large native recordings should load only when the reviewer plays
            # them, rather than opening fifteen media decoders at page load.
            player = (f'<video controls playsinline preload="none"{poster} src="{esc(video["path"])}"></video>'
                      f'<p class="small">原始連續 MP4，未剪輯。{decoding}。<a href="{esc(video["path"])}">下載原檔</a></p>')
        else:
            player = '<div class="missing">沒有本輪連續錄影。</div>'
        issues = ''.join(f'<li>{esc(issue)}</li>' for issue in run['issues'])
        notes = ''.join(f'<li>{esc(note)}</li>' for note in capture.get('notes', []))
        links = ' · '.join(f'<a href="{esc(item["path"])}">{esc(Path(item["path"]).name)}</a>' for item in run['archives'] if Path(item['path']).suffix in EVIDENCE_SUFFIXES)
        images = ''.join(image_card(run, item) for item in run['images'])
        method = ('正常 lib/main.dart 手動操作；資料隔離方式與錄影起點依本批 metadata／notes，不套用 integration runner 的條件。'
                  if 'manual_review_complete' in capture else 'integration runner 自動操作；執行與資料隔離條件依本批 metadata／notes。')
        sections.append(f'''<article class="run" id="run-{esc(run['label'])}"><div class="eyebrow">{esc(run['label'])} · {status}</div>
<h3>{esc(run_title(run))}</h3><p>{esc(device.get('name', '裝置未記錄'))} · {esc(capture.get('runtime', 'runtime 未記錄'))}<br>{esc(environment)}</p>
<p>{esc(method)}<br>資料條件：{esc(meta(run).get('fixture', '未記錄'))}</p>
<p class="small">來源 {esc(source.get('branch', '未記錄'))} / {esc(source.get('commit', '未記錄'))}<br>工作區差異 SHA-256：{esc(source.get('diff_sha256', '未記錄'))}</p>
{player}<details><summary>逐步原始畫面（{len(run['images'])} 張）</summary><div class="screens">{images}</div></details>
<details><summary>來源、限制與紀錄</summary><p>{links or '沒有紀錄檔。'}</p><ul>{issues}{notes}</ul>
<pre>{esc(json.dumps({'metadata': meta(run), 'source': source, 'native_background': capture.get('native_background', []), 'observed_lifecycle': capture.get('observed_lifecycle', [])}, ensure_ascii=False, indent=2))}</pre></details></article>''')
    return ''.join(sections) or '<div class="missing">本頁尚未輸入任何原生擷取；僅為工具結構檢查。</div>'


def accessibility_html(runs):
    selections = []
    for title, predicate in [
        ('真實 iOS 可及性設定與 APP 接手', lambda f: f.get('nativeAccessibilitySettings') is True),
        ('小螢幕', lambda f: f.get('size') and f['size'][0] <= 375),
        ('大螢幕', lambda f: f.get('size') and f['size'][0] >= 430),
        ('大字（含要求 2×、原生最大字級與既有上限）', lambda f: (isinstance(f.get('textScale'), (int, float)) and f['textScale'] >= 2) or (isinstance(f.get('requestedTextScale'), (int, float)) and f['requestedTextScale'] >= 2) or f.get('nativeContentSize') == 'accessibility-extra-extra-extra-large'),
        ('Reduce Motion', lambda f: f.get('disableAnimations') is True or f.get('reduceMotion') is True),
    ]:
        images = [(run, item) for run in runs if not meta(run).get('before') for item in run['images'] if predicate(item['frame'])]
        # Show each supplied capture, rather than quietly substituting another
        # size/state or limiting to a flattering subset of screenshots.
        content = ''.join(image_card(run, item) for run, item in images)
        if not content:
            content = '<div class="missing">未執行／沒有本輪同條件的原生截圖。</div>'
        selections.append(f'<details><summary>{title}（{len(images)} 張）</summary><div class="screens">{content}</div></details>')
    return ''.join(selections)


STYLE = '''
:root{color-scheme:light;--paper:#fff8ed;--card:#fffdfa;--ink:#594438;--soft:#796657;--line:#ecdccb;--accent:#a55540}
*{box-sizing:border-box}body{margin:0;background:var(--paper);color:var(--ink);font:16px/1.7 -apple-system,BlinkMacSystemFont,"PingFang TC",sans-serif}header,main,footer{max-width:1100px;margin:auto;padding:30px 24px}header{padding-top:54px}h1{font-size:clamp(29px,5vw,48px);line-height:1.2;margin:14px 0}h2{font-size:28px;margin:8px 0 18px}h3{font-size:20px;margin:12px 0}p{color:var(--soft)}a{color:var(--accent);text-underline-offset:4px}nav{display:flex;flex-wrap:wrap;gap:16px}.eyebrow,.small{font-size:12px;overflow-wrap:anywhere}.eyebrow{letter-spacing:.06em;color:var(--accent)}section{margin:12px 0 50px;scroll-margin-top:20px}article{border-top:1px solid var(--line);padding-top:24px;margin:26px 0}.pair{display:grid;grid-template-columns:1fr 1fr;gap:22px;max-width:860px;margin:auto}.screens{display:grid;grid-template-columns:repeat(auto-fit,minmax(210px,1fr));gap:22px;margin-top:22px}figure{margin:0;min-width:0}img{display:block;width:100%;height:auto;background:var(--card);border:1px solid var(--line);border-radius:18px}figcaption{font-size:12px;padding:9px 0}figcaption span{display:block;color:var(--soft)}video{display:block;max-width:440px;width:100%;max-height:76vh;background:#2b241f;border-radius:18px;margin:20px auto}.missing{padding:26px;border:1px dashed #c9aa92;border-radius:18px;background:var(--card);color:var(--soft)}.run{padding:26px;background:var(--card);border:1px solid var(--line);border-radius:22px}.run>h3{margin-top:4px}details{border-top:1px solid var(--line);padding-top:14px;margin-top:16px}summary{cursor:pointer;min-height:44px;font-weight:600}table{border-collapse:collapse;width:100%;font-size:14px}th,td{text-align:left;vertical-align:top;padding:12px 10px;border-bottom:1px solid var(--line)}thead{background:#f8edde}th{font-weight:600}pre{white-space:pre-wrap;overflow-wrap:anywhere;font-size:12px}button{font:inherit;min-height:44px;border:1px solid var(--line);border-radius:30px;padding:8px 18px;background:var(--card);color:var(--ink);cursor:pointer}button[aria-pressed=true]{background:var(--accent);color:white}.modes{display:flex;gap:8px;flex-wrap:wrap;margin-bottom:20px}body[data-compare=after] .before,body[data-compare=before] .after{display:none}body:not([data-compare=both]) .pair{grid-template-columns:1fr;max-width:430px}.table-wrap{overflow-x:auto}:focus-visible{outline:3px solid var(--accent);outline-offset:4px}footer{font-size:12px;color:var(--soft)}@media(max-width:650px){header,main,footer{padding-inline:18px}.pair{gap:12px}.run{padding:18px}.screens{grid-template-columns:repeat(2,minmax(0,1fr));gap:12px}h2{font-size:24px}th,td{padding:10px 6px}}
'''


def build_html(runs):
    passed = sum(run['status'] == 'passed' for run in runs)
    manual = sum(run['status'] == 'manual' for run in runs)
    image_count = sum(len(run['images']) for run in runs)
    video_count = sum(run['video'] is not None for run in runs)
    return f'''<!doctype html><html lang="zh-Hant"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>兔咪 · 真正入口整合驗收</title><style>{STYLE}</style></head><body data-compare="both">
<header><div class="eyebrow">TUMI · ENTRY INTEGRATION · BASELINE a579d10</div><h1>從封面，接回真正的日常。</h1>
<p>基於最新測試版 <strong>codex/experience-redesign / a579d10 / 1.0.1（2026091105）</strong>。本頁只呈現本輪明確輸入的原生擷取，不用舊展示樣品補圖。</p>
<p>正式 RootRestart → MyApp、既有 theme、MainPage、HomePage 與功能路由繼續使用。自動 integration_test 的身份與偏好隔離注入，登入、離線與故障情境是模擬。另有正常 lib/main.dart 的手動操作時，會獨立列明原生資料條件；兩者都不代表真實 OAuth 或雲端備份完成。</p>
<p class="small">輸入 {len(runs)} 批 · {passed} 批有自動測試完成紀錄 · {manual} 批手動操作已核對 · {image_count} 張原始 PNG · {video_count} 段原始 MP4。手動紀錄不增加自動測試通過數；計數由本次來源 manifest 計算，不是產品驗收結論。</p>
<nav><a href="#comparison">整合前後</a><a href="#walkthroughs">連續操作</a><a href="#matrix">情境紀錄</a><a href="#accessibility">尺寸與可及性</a><a href="capture-manifest.json">全部來源與雜湊</a></nav></header>
<main><section id="comparison"><h2>同條件的整合前後</h2><p>只配對相同情境、尺寸、語言、字級與動態偏好。基準的 zh 與本輪的 zh-TW 都使用既有繁中文案，配對視為同語言；每張圖保留實際 locale 紀錄。前後皆為本輪實際執行的 APP 畫面。</p>
<div class="modes" role="group" aria-label="比較方式"><button data-mode="both" aria-pressed="true">並排</button><button data-mode="after" aria-pressed="false">整合後</button><button data-mode="before" aria-pressed="false">整合前</button></div>{comparison_html(runs)}</section>
<section id="walkthroughs"><h2>連續操作與逐步畫面</h2><p>自動錄影從 integration runner handshake 開始，包含真正 app.main 初始化；手動錄影的程序啟動／操作起點另依該批紀錄列示。這些錄影不是 iOS release 冷啟動耗時測量。影片沒有剪接，也未由此工具做解碼或音訊驗證。</p>{runs_html(runs)}</section>
<section id="matrix"><h2>有證據的範圍</h2><div class="table-wrap"><table><thead><tr><th>情境</th><th>本輪紀錄</th><th>來源</th></tr></thead><tbody>{coverage_rows(runs)}</tbody></table></div>
<p class="small">自動測試的大字與 Reduce Motion 依 MediaQuery 數值列示；手動操作依已核對的 iOS 設定列明來源，未量測的 MediaQuery 留為未知。要求 2× 而實際仍是 1.3×、或 iOS 最大字級但 App 保留 1.3× 上限，都不算完整大字支援。原生背景回前景須有 host 操作與 paused／resumed 紀錄，或 metadata.nativeBackground=true 的手動觀察；單獨 widget lifecycle 測試不列入此項。</p></section>
<section id="accessibility"><h2>尺寸、大字與降低動態</h2>{accessibility_html(runs)}</section>
<section><h2>仍需本人判斷</h2><p>請判斷既有 V3 封面與 UI 的遮擋、文字層級、按壓與轉場節奏、真正主場景接手是否自然。模擬器畫面不能代替實機音訊、觸覺、release 啟動耗時或順暢度驗收。</p></section></main>
<footer>此頁為本機驗收附件；未發布或部署。PNG、MP4、log 與來源 JSON 逐位元保存。<a href="capture-manifest.json">開啟證據 manifest</a></footer>
<script>document.querySelectorAll('button[data-mode]').forEach(button=>button.addEventListener('click',()=>{{document.body.dataset.compare=button.dataset.mode;document.querySelectorAll('button[data-mode]').forEach(item=>item.setAttribute('aria-pressed',String(item===button)));}}));</script></body></html>'''


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--capture', action='append', default=[], metavar='LABEL=DIRECTORY')
    parser.add_argument('--output', required=True, type=Path, help='New/empty artifact directory; never overwrites evidence')
    args = parser.parse_args()
    sources, labels = [], set()
    for value in args.capture:
        label, separator, directory = value.partition('=')
        if not separator or not directory or not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9_-]*', label):
            parser.error('--capture must be a unique safe LABEL=DIRECTORY')
        if label in labels:
            parser.error('Duplicate capture label: ' + label)
        labels.add(label)
        sources.append((label, Path(directory).expanduser().resolve()))
    output = args.output.expanduser().resolve()
    if output.exists() and (not output.is_dir() or any(output.iterdir())):
        parser.error('--output must be new or empty; existing evidence is not overwritten')
    if any(output == source for _, source in sources):
        parser.error('--output cannot be an input capture directory')
    output.mkdir(parents=True, exist_ok=True)
    runs = [archive_run(label, source, output) for label, source in sources]
    manifest = {'schema': 1, 'created_at': datetime.now(timezone.utc).isoformat(),
                'baseline': BASELINE, 'basis': 'codex/experience-redesign / 1.0.1 (2026091105)',
                'scope': 'real Flutter app root; integration-only fixtures or manual native state as explicitly recorded per run',
                'gallery_tool_checks': 'byte-preserving copies, SHA-256 and PNG header/dimensions; no native execution or video decoding',
                'runs': runs}
    (output / 'capture-manifest.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    (output / 'index.html').write_text(build_html(runs), encoding='utf-8')
    print(json.dumps({'output': str(output), 'input_runs': len(runs),
                      'completed_manifests': sum(run['status'] == 'passed' for run in runs),
                      'manual_reviews': sum(run['status'] == 'manual' for run in runs),
                      'pngs': sum(len(run['images']) for run in runs),
                      'videos': sum(run['video'] is not None for run in runs)}, ensure_ascii=False))
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
