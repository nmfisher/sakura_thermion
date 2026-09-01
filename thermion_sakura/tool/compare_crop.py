#!/usr/bin/env python3
"""Single-object comparison: crop the same region from our render and the
three.js reference, show side-by-side + diff heatmap, and report per-crop
stats (both global and per-channel mean abs diff).

Usage:
  python3 tool/compare_crop.py <mine.png> <ref.png> <x0> <y0> <x1> <y1> [--out out.png]
  (crop is in 1600x900 pixels, inclusive-exclusive)
"""
import sys
from PIL import Image, ImageDraw
import numpy as np


def main():
    mine_p, ref_p = sys.argv[1], sys.argv[2]
    x0, y0, x1, y1 = map(int, sys.argv[3:7])
    out_p = sys.argv[sys.argv.index('--out') + 1] if '--out' in sys.argv else '/tmp/compare_crop.png'

    def load(p):
        im = Image.open(p).convert('RGB')
        if im.size != (1600, 900):
            im = im.resize((1600, 900), Image.LANCZOS)
        return np.asarray(im, dtype=np.float32)

    mine, ref = load(mine_p), load(ref_p)
    mc, rc = mine[y0:y1, x0:x1], ref[y0:y1, x0:x1]
    d = np.abs(mc - rc)

    def stats(a):
        mx, mn = a.max(axis=2), a.min(axis=2)
        return (f"mean {a.mean():.1f} std {a.std():.1f} sat {(mx-mn).mean():.1f} "
                f"dark {(a.mean(axis=2)<70).mean()*100:.1f}% hi {(a.mean(axis=2)>200).mean()*100:.1f}%")

    print(f"crop {x0},{y0}-{x1},{y1}  ({x1-x0}x{y1-y0})")
    print("  mine:", stats(mc))
    print("  ref :", stats(rc))
    print(f"  mean abs diff {d.mean():.1f}   max {d.max():.0f}   px>32: {(d.mean(axis=2)>32).mean()*100:.1f}%")
    print("  per-channel mean abs: R %.1f G %.1f B %.1f" % tuple(d.mean(axis=(0, 1))))

    # panel: mine | ref | heatmap
    hm = np.zeros_like(mc, dtype=np.uint8)
    hm[..., 0] = np.clip(d.mean(axis=2) * 4, 0, 255).astype(np.uint8)
    W, H = x1 - x0, y1 - y0
    side = Image.new('RGB', (W * 3 + 40, H + 30), (255, 255, 255))
    dr = ImageDraw.Draw(side)
    side.paste(Image.fromarray(mc.astype(np.uint8)), (0, 30)); dr.text((4, 4), "mine", fill=(0, 0, 0))
    side.paste(Image.fromarray(rc.astype(np.uint8)), (W + 20, 30)); dr.text((W + 24, 4), "ref", fill=(0, 0, 0))
    side.paste(Image.fromarray(hm), (2 * W + 40, 30)); dr.text((2 * W + 44, 4), "|diff| red=far", fill=(0, 0, 0))
    side.save(out_p)
    print(f"saved {out_p}")


if __name__ == '__main__':
    main()
