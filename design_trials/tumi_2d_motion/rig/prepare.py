"""Reproducible trial-only layer extraction; originals are never overwritten.

The user explicitly authorized programmatic cutouts/alignment on 2026-09-08.
Hidden pixels come from image_gen clean plates, not stretched adjacent fur.
Run with the bundled Python (Pillow + NumPy). Outputs stay in this trial folder.
"""
from pathlib import Path
import hashlib
import json

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
SIZE = 1024
BASE = ROOT / 'assets/mascot/core/tumi_neutral_front.png'


def path_mask(start, curves, feather=0):
    points = [start]
    p0 = np.array(start, dtype=float)
    for a, b, end in curves:
        a, b, end = map(lambda p: np.array(p, dtype=float), (a, b, end))
        for t in np.linspace(0, 1, 40)[1:]:
            p = (1-t)**3*p0 + 3*(1-t)**2*t*a + 3*(1-t)*t*t*b + t**3*end
            points.append(tuple(p))
        p0 = end
    mask = Image.new('L', (SIZE*4, SIZE*4))
    ImageDraw.Draw(mask).polygon([(round(x*4), round(y*4)) for x,y in points], fill=255)
    mask = mask.resize((SIZE, SIZE), Image.Resampling.LANCZOS)
    return mask.filter(ImageFilter.GaussianBlur(feather)) if feather else mask


def normalized(path):
    return Image.open(path).convert('RGBA').resize((SIZE, SIZE), Image.Resampling.LANCZOS)


def main():
    out = HERE / 'layers'
    out.mkdir(exist_ok=True)
    base = normalized(BASE)
    assert hashlib.sha256(BASE.read_bytes()).hexdigest() == '95b81df9721ddf54712a1d8c822e772d8a7e25036ae9ea8b15235d6987aa0f96'
    arm_mask = path_mask((383,538), [
        ((361,546),(320,611),(304,652)),
        ((295,674),(289,708),(309,722)),
        ((329,740),(359,725),(372,689)),
        ((382,661),(390,593),(407,553)),
        ((402,543),(393,537),(383,538)),
    ], .65)
    arm = np.array(base)
    arm[:,:,3] = np.rint(arm[:,:,3].astype(float)*np.array(arm_mask)/255).astype('uint8')
    Image.fromarray(arm).save(out / 'arm.png')

    # The clean plate is used ONLY around the removed arm, preserving the
    # approved head, ears, opposite arm and feet byte-for-byte outside this mask.
    patch_mask = path_mask((381,533), [
        ((351,542),(300,611),(289,662)),
        ((282,703),(295,744),(330,746)),
        ((361,750),(411,749),(433,738)),
        ((435,675),(434,598),(418,554)),
        ((407,544),(397,538),(381,533)),
    ], 2)
    clean = np.array(normalized(HERE / 'sources/body-clean-plate.png'))
    # White is only classified within the small gray-fur/empty-background ROI;
    # no global threshold is applied to the original cream fur or eye highlights.
    darkness = clean[:,:,:3].min(axis=2).astype(float)
    clean[:,:,3] = np.rint(np.clip((248-darkness)/10, 0, 1)*255).astype('uint8')
    original = np.array(base)
    w = np.array(patch_mask).astype(float)[:,:,None]/255
    body = np.rint(original*(1-w)+clean*w).astype('uint8')
    Image.fromarray(body).save(out / 'body.png')
    patch_mask.save(out / 'repair-mask.png')

    vest_path = HERE / 'sources/vest-clean-plate.png'
    if vest_path.exists():
        vest = np.array(normalized(vest_path))
        vest_mask = path_mask((379,535), [
            ((416,538),(456,569),(512,588)),
            ((548,569),(606,549),(644,535)),
            ((654,538),(658,543),(655,550)),
            ((637,587),(640,654),(657,695)),
            ((662,711),(670,721),(683,726)),
            ((686,733),(684,739),(679,744)),
            ((633,765),(555,773),(514,772)),
            ((456,772),(378,759),(341,745)),
            ((334,741),(334,736),(338,728)),
            ((343,663),(357,599),(373,550)),
            ((372,543),(376,538),(379,535)),
        ], .5)
        # The generated checkerboard is neutral gray, whereas the vest's sage
        # cloth and ivory trim both have a warm/green chroma. Apply this only
        # inside the traced garment mask, never as whole-character keying.
        rgb = vest[:,:,:3].astype(float)
        chroma = np.minimum(rgb[:,:,0]-rgb[:,:,2], rgb[:,:,1]-rgb[:,:,2])
        vest[:,:,3] = np.rint(np.array(vest_mask)*np.clip((chroma-5)/5, 0, 1)).astype('uint8')
        Image.fromarray(vest).save(out / 'vest.png')

    manifest = {}
    for name in ['body','arm','vest']:
        file = out / f'{name}.png'
        if file.exists():
            manifest[name] = file.name
    report = {
        'base_sha256': hashlib.sha256(BASE.read_bytes()).hexdigest(),
        'outside_repair_mask_changed_pixels': int(np.count_nonzero(np.any(body != original, axis=2) & (np.array(patch_mask) == 0))),
        'layers': {name: {'size': list(Image.open(out/f'{name}.png').size), 'alpha_extrema': list(Image.open(out/f'{name}.png').getchannel('A').getextrema())} for name in manifest},
    }
    (HERE / 'asset-check.json').write_text(json.dumps(report, indent=2)+'\n')
    print(json.dumps(report, indent=2))
    print('Serve these trial-only layers on localhost:8766:', out)


if __name__ == '__main__':
    main()
