# 黃昏長影 overlay：床/床頭櫃/五斗櫃 往右下的柔軟長影（多層淡出＋重模糊）
# 輸出同畫布透明 PNG；app 端用 dusk 權重控制 opacity。
from PIL import Image, ImageDraw, ImageFilter
import numpy as np

BG = 'assets/scenes/home/home_bg_glassless.png'
OUT = 'assets/scenes/home/home_shadow_dusk.png'
W, H = 1122, 1402

SHADOW = (86, 60, 84)  # 暖紫棕（黃昏影子的冷邊）

def soft_wedge(draw_layers, base_quad, tip_quad, steps=4):
    """base(靠家具、深) → tip(遠端、淡) 的分層楔形，之後整體重模糊。"""
    b = np.array(base_quad, dtype=float)
    t = np.array(tip_quad, dtype=float)
    for i in range(steps):
        f0 = i / steps
        q = b * (1 - f0) + t * f0
        alpha = int(185 * (1 - f0) ** 1.6)
        draw_layers.polygon([tuple(p) for p in q], fill=alpha)

mask = Image.new('L', (W, H), 0)
d = ImageDraw.Draw(mask)

# 1. 床：右側底邊 (90,1040)-(560,860) 往右下延伸
soft_wedge(
    d,
    base_quad=[(95, 1045), (555, 865), (585, 880), (130, 1075)],
    tip_quad=[(230, 1130), (700, 950), (760, 985), (300, 1180)],
)
# 2. 床頭櫃：腳底 (600,800)-(780,824) 往右
soft_wedge(
    d,
    base_quad=[(625, 806), (778, 822), (782, 836), (630, 822)],
    tip_quad=[(700, 846), (880, 872), (888, 894), (712, 872)],
    steps=3,
)
# 3. 五斗櫃：底邊 (810,910)-(1110,950) 往右下（大多出畫）
soft_wedge(
    d,
    base_quad=[(825, 918), (1108, 952), (1110, 972), (830, 940)],
    tip_quad=[(900, 985), (1122, 1030), (1122, 1075), (930, 1040)],
    steps=3,
)

mask = mask.filter(ImageFilter.GaussianBlur(26))
alpha = np.asarray(mask).astype(np.float32) / 255.0
# 全域上限：最深處 ~0.5（app 端 dusk 權重再乘一次，實效 ~0.2 以下）
alpha = np.clip(alpha, 0, 0.5)

rgb = np.zeros((H, W, 3), dtype=np.uint8)
rgb[..., 0] = SHADOW[0]
rgb[..., 1] = SHADOW[1]
rgb[..., 2] = SHADOW[2]
out = np.dstack([rgb, (alpha * 255).astype(np.uint8)])
Image.fromarray(out).save(OUT)
print('saved ->', OUT)
