#!/usr/bin/env python3
"""產生 iOS 原生啟動畫面的圖，讓它與 Flutter 的 `_StartupSplash` 接得上。

**為什麼需要這個**：原生啟動畫面（LaunchScreen.storyboard）在 Flutter 引擎起來
之前就顯示，它是使用者看到的第一幀。專案原本用的是 Flutter 樣板附的
1×1 空白圖，所以那段時間畫面上什麼都沒有——app 的第一印象是一片白。

**設計對齊**：這張圖複製 `main.dart` 的 `_StartupSplash`：
- 三段垂直漸層 #FFF7EE → #FFE5D3 → #EAF5EF
- 中央 138pt 白圓（82% 不透明）＋ 暖棕陰影，裡面放 tumi_happy
- 圓心在畫面中心**上方 28.3pt**（Flutter 那邊是 SafeArea 置中整個 Column，
  實拍量出來的偏移；改 Column 內容時這個數字要重量）

**刻意不畫標題與進度條**：標題是中文，runtime 走系統 CJK fallback，PIL 湊不出
一模一樣的字，硬做反而會在接手瞬間跳字。留給 Flutter 畫，讀起來像「醒過來」。

用法：python3 scripts/gen_launch_image.py
"""
from PIL import Image, ImageDraw, ImageFilter
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, 'ios/Runner/Assets.xcassets/LaunchImage.imageset')
MASCOT = os.path.join(ROOT, 'assets/mascot/core/tumi_happy.png')

# 邏輯尺寸以 14 Pro Max 為基準（專案的校準機型）。
BASE_W, BASE_H = 430, 932
CIRCLE_PT = 138
CIRCLE_PAD_PT = 18
CIRCLE_DY_PT = -28.3  # 圓心相對畫面中心的位移，實拍量得
GRADIENT = [(0xFF, 0xF7, 0xEE), (0xFF, 0xE5, 0xD3), (0xEA, 0xF5, 0xEF)]
SHADOW_RGB = (0xB9, 0x78, 0x56)


def lerp(a, b, t):
    return tuple(round(x + (y - x) * t) for x, y in zip(a, b))


def build(scale: int) -> Image.Image:
    w, h = BASE_W * scale, BASE_H * scale
    img = Image.new('RGB', (w, h))
    d = ImageDraw.Draw(img)

    # 三段漸層：0 → 0.5 → 1
    for y in range(h):
        t = y / max(h - 1, 1)
        if t < 0.5:
            c = lerp(GRADIENT[0], GRADIENT[1], t / 0.5)
        else:
            c = lerp(GRADIENT[1], GRADIENT[2], (t - 0.5) / 0.5)
        d.line([(0, y), (w, y)], fill=c)

    diameter = CIRCLE_PT * scale
    cx = w / 2
    cy = h / 2 + CIRCLE_DY_PT * scale
    box = [cx - diameter / 2, cy - diameter / 2, cx + diameter / 2, cy + diameter / 2]

    # 暖棕陰影：blur 28、offset (0,16)，與 Flutter 的 BoxShadow 對齊
    shadow = Image.new('RGBA', (w, h), (0, 0, 0, 0))
    sd = ImageDraw.Draw(shadow)
    sd.ellipse(
        [box[0], box[1] + 16 * scale, box[2], box[3] + 16 * scale],
        fill=SHADOW_RGB + (46,),  # 0.18 alpha
    )
    shadow = shadow.filter(ImageFilter.GaussianBlur(28 * scale / 2))
    img = Image.alpha_composite(img.convert('RGBA'), shadow)

    # 白圓 82%
    circle = Image.new('RGBA', (w, h), (0, 0, 0, 0))
    ImageDraw.Draw(circle).ellipse(box, fill=(255, 255, 255, 209))
    img = Image.alpha_composite(img, circle)

    # 兔咪：contain 進扣掉 padding 的方框
    inner = diameter - 2 * CIRCLE_PAD_PT * scale
    m = Image.open(MASCOT).convert('RGBA')
    m.thumbnail((int(inner), int(inner)), Image.LANCZOS)
    img.alpha_composite(m, (int(cx - m.width / 2), int(cy - m.height / 2)))

    return img.convert('RGB')


def main():
    for scale, name in [(1, 'LaunchImage.png'), (2, 'LaunchImage@2x.png'),
                        (3, 'LaunchImage@3x.png')]:
        p = os.path.join(OUT, name)
        build(scale).save(p)
        print(f'{name}  {BASE_W * scale}x{BASE_H * scale}')


if __name__ == '__main__':
    main()
