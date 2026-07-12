# 燈罩發亮 overlay：photometric local edit（不重畫，只提亮原圖燈罩像素）
# 輸出：與底圖同畫布 1122x1402 的透明 PNG，只有燈罩區域有內容。
from PIL import Image, ImageDraw, ImageFilter
import numpy as np

BG = 'assets/scenes/home/home_bg_glassless.png'
OUT = 'assets/scenes/home/home_lamp_lit.png'

im = Image.open(BG).convert('RGB')
W, H = im.size
arr = np.asarray(im).astype(np.float32)

# ── 幾何遮罩：燈罩梯形（上緣橢圓 / 下緣外凸）＋ 底座上半微光 ──
# 座標由 lamp_region 裁圖實測（原圖 px）：
#   罩頂緣 y≈447 (x 692..770)，罩底緣 y≈575 (x 664..792)
mask_im = Image.new('L', (W, H), 0)
d = ImageDraw.Draw(mask_im)
# 主體梯形（略內縮 1px，邊緣交給羽化）
d.polygon([(693, 452), (769, 452), (791, 572), (665, 572)], fill=255)
# 上緣橢圓（罩口）
d.ellipse((693, 444, 769, 462), fill=255)
# 下緣外凸弧
d.ellipse((665, 560, 791, 586), fill=255)
mask = np.asarray(mask_im.filter(ImageFilter.GaussianBlur(3))).astype(np.float32) / 255.0

# ── 顏色閘門：只留奶油罩（排除綠牆 G>R 與過暗像素）──
r, g, b = arr[..., 0], arr[..., 1], arr[..., 2]
colorgate = ((r >= g - 4) & (r > 150)).astype(np.float32)
colorgate = np.asarray(
    Image.fromarray((colorgate * 255).astype(np.uint8)).filter(
        ImageFilter.GaussianBlur(2)
    )
).astype(np.float32) / 255.0
alpha = mask * colorgate

# ── 發光強度圖：燈泡在罩內中下 (727, 545)，向外衰減 ──
yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
dist2 = ((xx - 727) / 55.0) ** 2 + ((yy - 545) / 75.0) ** 2
k = 0.38 + 0.50 * np.exp(-dist2)  # 邊緣 0.38、燈泡處 0.88

# ── 暖色 screen 提亮：out = 255 - (255-c)*(1 - k*L/255) ──
Lwarm = np.array([255.0, 216.0, 148.0])  # 暖黃光
lit = arr.copy()
for c in range(3):
    f = 1.0 - k * (Lwarm[c] / 255.0) * 0.92
    lit[..., c] = 255.0 - (255.0 - arr[..., c]) * f
# 輕微整體上抬（燈罩透光感）
lit = np.clip(lit * 1.02 + 6, 0, 255)

# ── 底座上半的反光 rim（很淡）──
rim = Image.new('L', (W, H), 0)
dr = ImageDraw.Draw(rim)
dr.ellipse((695, 585, 760, 618), fill=110)  # 珊瑚球頂面
rim = np.asarray(rim.filter(ImageFilter.GaussianBlur(6))).astype(np.float32) / 255.0
alpha = np.clip(alpha + rim * 0.55, 0, 1)
# rim 區域的提亮弱一點
kfull = np.maximum(k * mask, 0.30 * rim)
for c in range(3):
    f = 1.0 - kfull * (Lwarm[c] / 255.0) * 0.92
    lit[..., c] = 255.0 - (255.0 - arr[..., c]) * f
lit = np.clip(lit * 1.02 + 6 * (mask > 0)[..., None], 0, 255)

# 透明區 RGB 歸零：PNG 連 alpha=0 的像素也存 RGB，不歸零檔案會肥 40 倍
lit = lit * (alpha > 0.004)[..., None]

out = np.dstack([lit.astype(np.uint8), (alpha * 255).astype(np.uint8)])
Image.fromarray(out.astype(np.uint8)).save(OUT, optimize=True)

# 邊界檢查：overlay 有內容的 bounding box
ys, xs = np.where(alpha > 0.02)
print('bbox', xs.min(), ys.min(), xs.max(), ys.max(), 'px; canvas', W, H)
print('saved ->', OUT)
