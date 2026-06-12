#!/usr/bin/env python3
"""自動描圖：把扁平風參考圖轉成向量色塊 + 線稿，生成 Dart 資料檔。

用法：python3 scripts/trace_tumi.py
輸入：assets/mascot/ref/tumi_neutral_front.JPG
輸出：lib/dev/tumi/tumi_traced_data.dart（1024 設計網格座標）
"""
from PIL import Image, ImageFilter
from collections import deque
import math, sys, os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, 'assets/mascot/ref/tumi_neutral_front.JPG')
DST = os.path.join(ROOT, 'lib/dev/tumi/tumi_traced_data.dart')

img = Image.open(SRC).convert('RGB').filter(ImageFilter.MedianFilter(3))
W, H = img.size
px = img.load()
SCALE = 1024.0 / W

# ---- 調色盤（實測） ----
PALETTE = {
    'grey':    (203, 197, 197),
    'white':   (250, 243, 241),
    'pink':    (252, 186, 187),
    'blush':   (251, 190, 206),
    'eye':     (38, 36, 42),
    'nose':    (208, 140, 151),
    'outline': (107, 107, 109),
}
COLOR_OUT = {  # 輸出用 ARGB
    'grey': 0xFFCBC5C5, 'white': 0xFFFDF5F3, 'pink': 0xFFFCBABB,
    'blush': 0xFFFBBECE, 'eye': 0xFF26242A, 'nose': 0xFFD08C97,
}
FILL_CLASSES = list(COLOR_OUT)

def classify(p):
    best, bd = None, 1e9
    for name, c in PALETTE.items():
        d = (p[0]-c[0])**2 + (p[1]-c[1])**2 + (p[2]-c[2])**2
        if d < bd: bd, best = d, name
    return best

# ---- 1. 背景：從邊框 flood fill 近白像素 ----
is_bg = bytearray(W*H)
dq = deque()
for x in range(W):
    for y in (0, H-1): dq.append((x, y))
for y in range(H):
    for x in (0, W-1): dq.append((x, y))
while dq:
    x, y = dq.popleft()
    i = y*W + x
    if is_bg[i]: continue
    p = px[x, y]
    if min(p) < 240: continue
    is_bg[i] = 1
    if x > 0: dq.append((x-1, y))
    if x < W-1: dq.append((x+1, y))
    if y > 0: dq.append((x, y-1))
    if y < H-1: dq.append((x, y+1))

# ---- 2. 分類 ----
cls = [None]*(W*H)
for y in range(H):
    base = y*W
    for x in range(W):
        i = base + x
        cls[i] = 'bg' if is_bg[i] else classify(px[x, y])

# ---- 3. 連通元件（4-連通，按類別） ----
comp_id = [-1]*(W*H)
comps = []  # (class, [pixels])
for y in range(H):
    for x in range(W):
        i = y*W + x
        if comp_id[i] != -1 or cls[i] in ('bg', 'outline'): continue
        c = cls[i]
        pix = []
        comp_id[i] = len(comps)
        q = deque([(x, y)])
        while q:
            cx, cy = q.popleft()
            pix.append((cx, cy))
            for nx, ny in ((cx-1,cy),(cx+1,cy),(cx,cy-1),(cx,cy+1)):
                if 0 <= nx < W and 0 <= ny < H:
                    j = ny*W + nx
                    if comp_id[j] == -1 and cls[j] == c:
                        comp_id[j] = len(comps)
                        q.append((nx, ny))
        comps.append((c, pix))

comps = [(c, p) for c, p in comps if len(p) >= 80]
comps.sort(key=lambda cp: -len(cp[1]))
print('components:', [(c, len(p)) for c, p in comps[:24]])

# ---- 4. 外輪廓追蹤（Moore boundary tracing） ----
# 8 鄰域順時針序（從正西開始）
_MOORE = [(-1,0),(-1,-1),(0,-1),(1,-1),(1,0),(1,1),(0,1),(-1,1)]

def outer_boundary(pixset):
    start = min(pixset, key=lambda p: (p[1], p[0]))  # 最上最左
    path = [start]
    cur = start
    back = 0  # 進入方向索引（從西進入）
    max_steps = len(pixset) * 4 + 100
    for _ in range(max_steps):
        found = False
        for k in range(8):
            idx = (back + k) % 8
            dx, dy = _MOORE[idx]
            nxt = (cur[0]+dx, cur[1]+dy)
            if nxt in pixset:
                cur = nxt
                # 新的 backtrack：從剛才那個空格反向開始掃
                back = (idx + 5) % 8
                found = True
                break
        if not found: break  # 孤立點
        if cur == start and len(path) > 2: break
        path.append(cur)
    return path

def rdp(pts, eps):
    if len(pts) < 3: return pts
    def d(p, a, b):
        ax, ay = a; bx, by = b; pxx, pyy = p
        dx, dy = bx-ax, by-ay
        if dx == dy == 0: return math.hypot(pxx-ax, pyy-ay)
        t = max(0, min(1, ((pxx-ax)*dx + (pyy-ay)*dy) / (dx*dx + dy*dy)))
        return math.hypot(pxx-(ax+t*dx), pyy-(ay+t*dy))
    dmax, idx = 0, 0
    for i in range(1, len(pts)-1):
        dd = d(pts[i], pts[0], pts[-1])
        if dd > dmax: dmax, idx = dd, i
    if dmax > eps:
        l = rdp(pts[:idx+1], eps); r = rdp(pts[idx:], eps)
        return l[:-1] + r
    return [pts[0], pts[-1]]

sys.setrecursionlimit(10000)

# outline 像素集合（描邊判定用）
outline_set = {(i % W, i // W) for i in range(W*H) if cls[i] == 'outline'}

def near_outline(x, y, r=3):
    for dy in range(-r, r+1):
        for dx in range(-r, r+1):
            if (x+dx, y+dy) in outline_set: return True
    return False

shapes = []   # (argb, [scaled pts], area)
stroke_polys = []  # 區域邊界中有描邊的分段
for c, pixlist in comps:
    pixset = set(pixlist)
    path = outer_boundary(pixset)
    simp = rdp(path, 1.4)
    if len(simp) < 3: continue
    pts = [(round(x*SCALE, 1), round(y*SCALE, 1)) for x, y in simp]
    shapes.append((COLOR_OUT[c], pts, len(pixlist)))
    # 邊界描邊分段（沿簡化前 path 取樣）
    seg = []
    step = max(1, len(path)//400)
    for i in range(0, len(path), step):
        x, y = path[i]
        if near_outline(x, y):
            seg.append((round(x*SCALE, 1), round(y*SCALE, 1)))
        else:
            if len(seg) >= 6: stroke_polys.append(rdp(seg, 1.4))
            seg = []
    if len(seg) >= 6: stroke_polys.append(rdp(seg, 1.4))

# ---- 5. 內部線（嘴/人中/腳趾縫/手臂內線）：周圍同類的 outline 像素 ----
def interior_line_pixels():
    out = []
    for (x, y) in outline_set:
        seen = set()
        for dy in range(-4, 5):
            for dx in range(-4, 5):
                nx, ny = x+dx, y+dy
                if 0 <= nx < W and 0 <= ny < H:
                    cc = cls[ny*W + nx]
                    if cc not in ('outline',): seen.add(cc)
        if 'bg' in seen: continue
        if len(seen - {'outline'}) <= 1:
            out.append((x, y))
    return out

ipix = interior_line_pixels()
# 聚類 + 貪婪走訪成折線
iset = set(ipix)
lines = []
while iset:
    seed = next(iter(iset))
    blob = []
    q = deque([seed]); iset.discard(seed)
    while q:
        cx, cy = q.popleft(); blob.append((cx, cy))
        for dy in range(-2, 3):
            for dx in range(-2, 3):
                p = (cx+dx, cy+dy)
                if p in iset: iset.discard(p); q.append(p)
    if len(blob) < 25: continue
    # 從極端點開始貪婪走訪取中軸近似
    start = max(blob, key=lambda p: max(math.hypot(p[0]-q2[0], p[1]-q2[1]) for q2 in blob[::7] or blob))
    remain = set(blob); cur = start; poly = [cur]; remain.discard(cur)
    while remain:
        nxt = min(remain, key=lambda p: (p[0]-cur[0])**2 + (p[1]-cur[1])**2)
        if (nxt[0]-cur[0])**2 + (nxt[1]-cur[1])**2 > 36: break
        poly.append(nxt); remain.discard(nxt); cur = nxt
    simp = rdp(poly, 1.6)
    if len(simp) >= 2:
        lines.append([(round(x*SCALE, 1), round(y*SCALE, 1)) for x, y in simp])
print('interior lines:', len(lines))

# ---- 6. 生成 Dart ----
def fmt(pts):
    return ', '.join(f'{x}, {y}' for x, y in pts)

with open(DST, 'w') as f:
    f.write('// GENERATED by scripts/trace_tumi.py — 請勿手改。\n')
    f.write('// 來源：assets/mascot/ref/tumi_neutral_front.JPG（1024 網格）\n\n')
    f.write('class TracedShape {\n  final int color;\n  final List<double> pts;\n'
            '  const TracedShape(this.color, this.pts);\n}\n\n')
    f.write('const List<TracedShape> tumiTracedShapes = [\n')
    for argb, pts, area in shapes:
        f.write(f'  TracedShape(0x{argb:08X}, [{fmt(pts)}]), // area {area}\n')
    f.write('];\n\n')
    f.write('const List<List<double>> tumiTracedStrokes = [\n')
    for poly in stroke_polys:
        spts = [(round(x*SCALE,1), round(y*SCALE,1)) for x, y in poly] \
            if poly and isinstance(poly[0][0], int) else poly
        f.write(f'  [{fmt(spts)}],\n')
    for poly in lines:
        f.write(f'  [{fmt(poly)}],\n')
    f.write('];\n')
print('shapes:', len(shapes), 'stroke polys:', len(stroke_polys))
print('wrote', DST)
