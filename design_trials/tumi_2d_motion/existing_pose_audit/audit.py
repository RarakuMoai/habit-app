"""Read approved endpoint PNGs; produce diagnostic comparisons, never new poses.

Requires Pillow and NumPy. Does not overwrite or normalize source images.
GIF panels show image replacement/crossfade, NOT generated motion inbetweens.
"""
from pathlib import Path
import hashlib
import json

import numpy as np
from PIL import Image, ImageDraw, ImageFont, ImageSequence

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
SOURCE = ROOT / 'assets/mascot/core'
PAIRS = [('neutral_front', 'neutral_front_blink'), ('expect', 'happy'),
         ('neutral_front', 'invite'), ('happy', 'pop_happy')]
FONT = ImageFont.truetype(str(ROOT / 'assets/fonts/Nunito-Regular.ttf'), 18)
BG = '#39464b'


def load(name):
    return Image.open(SOURCE / f'tumi_{name}.png').convert('RGBA')


def flat(im, size):
    bg = Image.new('RGBA', im.size, BG)
    bg.alpha_composite(im)
    return bg.convert('RGB').resize((size, size), Image.Resampling.LANCZOS)


def main():
    before = {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in SOURCE.glob('*.png')}
    report = {'method': 'Original 1024 canvases, no per-image alignment or warp. Alpha bounds use explicit thresholds; IoU is not a naturalness score.', 'assets': {}, 'pairs': []}
    images = {}
    board = Image.new('RGB', (1400, 930), '#fffdf9')
    pen = ImageDraw.Draw(board)
    for i, p in enumerate(sorted(SOURCE.glob('*.png'))):
        name = p.stem.removeprefix('tumi_')
        im = load(name)
        assert im.size == (1024, 1024)
        images[name] = im
        alpha = im.getchannel('A')
        report['assets'][name] = {'sha256': before[p.name], 'bounds': {str(t): alpha.point(lambda value: 255 if value >= t else 0).getbbox() for t in [1, 16, 64, 128]}}
        x, y = i % 5 * 280, i // 5 * 310
        board.paste(flat(im, 280), (x, y))
        pen.text((x+8, y+282), name, font=FONT, fill='#453229')
    board.save(HERE / 'approved-poses.png')

    midpoint = Image.new('RGB', (960, len(PAIRS)*370), '#fffdf9')
    draw = ImageDraw.Draw(midpoint)
    for row, (a, b) in enumerate(PAIRS):
        x, y = np.array(images[a]).astype(float), np.array(images[b]).astype(float)
        p, q = x[:,:,3]>=64, y[:,:,3]>=64
        lower = p & q
        lower[:540] = False
        report['pairs'].append({'from': a, 'to': b, 'alpha64_iou': round(float((p&q).sum()/(p|q).sum()), 4),
            'lower_rgb_mae': round(float(np.abs(x[:,:,:3]-y[:,:,:3])[lower].mean()), 2),
            'lower_rgb_over15_fraction': round(float((np.abs(x[:,:,:3]-y[:,:,:3]).max(axis=2)[lower]>15).mean()), 3)})
        frames = [flat(images[a], 320), flat(images[b], 320)]
        for col, (im, label) in enumerate([(frames[0], a), (Image.blend(*frames, .5), '50% dissolve (NOT motion)'), (frames[1], b)]):
            midpoint.paste(im, (col*320, row*370))
            draw.text((col*320+8, row*370+324), label, font=FONT, fill='#453229')

        endpoints = [flat(images[a], 260), flat(images[b], 260)]
        palette_source = Image.new('RGB', (780, 320), '#fffdf9')
        for col, im in enumerate([*endpoints, Image.blend(*endpoints, .5)]):
            palette_source.paste(im, (col*260, 50))
        palette = palette_source.quantize(colors=256)
        gif_frames = []
        for ms in range(0, 2760, 40):
            if ms < 840: t = 0
            elif ms < 1200: t = (ms-840)/360
            elif ms < 2040: t = 1
            elif ms < 2400: t = 1-(ms-2040)/360
            else: t = 0
            frame = Image.new('RGB', (520, 350), '#fffdf9')
            d = ImageDraw.Draw(frame)
            d.text((12, 7), f'{a} -> {b}', font=FONT, fill='#453229')
            d.text((12, 35), 'Cut (pose switch)', font=FONT, fill='#453229')
            d.text((272, 35), 'Dissolve (360 ms)', font=FONT, fill='#453229')
            frame.paste(endpoints[int(t >= .5)], (0, 66))
            frame.paste(Image.blend(*endpoints, t), (260, 66))
            d.text((12, 328), 'Endpoint diagnostic / no inbetween drawing', font=FONT, fill='#453229')
            gif_frames.append(frame.quantize(palette=palette, dither=Image.Dither.NONE))
        output = HERE / f'{a}-to-{b}.gif'
        gif_frames[0].save(output, save_all=True, append_images=gif_frames[1:], duration=40, loop=0, disposal=2, optimize=False)
        with Image.open(output) as gif:
            assert gif.size == (520, 350)
            assert sum(f.info.get('duration',0) for f in ImageSequence.Iterator(gif)) == 2760
        print('Saved and checked:', output.name)

    midpoint.save(HERE / 'endpoint-midpoints.png')
    assert before == {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in SOURCE.glob('*.png')}
    report['source_unchanged'] = True
    (HERE / 'measurements.json').write_text(json.dumps(report, ensure_ascii=False, indent=2)+'\n')
    print('All 13 approved source files unchanged.')


if __name__ == '__main__':
    main()
