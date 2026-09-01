#!/usr/bin/env python3
"""Faithful port of the reference GRADE_SHADER + FXAA_SHADER.

Reads the linear float32 RGBA .bin dumped by render.dart (RT2 = scene + depth
ink, in linear space) and writes the final sRGB PNG: split-tone grade + warmth
+ lift + saturation + vignette + linear->sRGB, then FXAA.

Usage: python3 grade.py <rt2.bin> <out.png> <w> <h> [--no-fxaa]
"""
import sys
import numpy as np
from PIL import Image


def s2l(c):
    c = np.asarray(c, dtype=np.float64) / 255.0
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def l2s(c):
    c = np.clip(c, 0.0, None)
    return np.where(c <= 0.0031308, c * 12.92, 1.055 * (c ** (1 / 2.4)) - 0.055)


SHADOW = s2l([0xad, 0xa8, 0xd0])  # 0xada8d0  (three.js Color -> linear)
LIGHT = s2l([0xff, 0xf7, 0xe8])  # 0xfff7e8
SAT, LIFT, VIG, WARM = 1.12, 0.032, 0.15, 0.05


def smoothstep(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0.0, 1.0)
    return t * t * (3 - 2 * t)


def grade(rgb):
    """rgb: (h,w,3) linear -> graded linear rgb (port of GRADE_SHADER)."""
    c = rgb.astype(np.float64)
    l = 0.2126 * c[..., 0] + 0.7152 * c[..., 1] + 0.0722 * c[..., 2]
    k = smoothstep(0.02, 0.55, l)[..., None]
    c = c * (SHADOW * (1 - k) + LIGHT * k)
    warm = np.stack([WARM * l, WARM * 0.45 * l, np.zeros_like(l)], axis=-1) * 0.35
    c = c + warm + LIFT * (1 - k)
    c = l[..., None] + (c - l[..., None]) * SAT
    h, w = l.shape
    yy, xx = np.mgrid[0:h, 0:w]
    u = (xx + 0.5) / w
    v = (yy + 0.5) / h
    r = np.sqrt((u - 0.5) ** 2 + (v - 0.5) ** 2) * 1.42
    c = c * (1.0 - VIG * np.clip(r, 0, 1) ** 2.6)[..., None]
    return c


def _sample(a, oy, ox):
    """Bilinear sample of (h,w,3) array at per-pixel offsets (oy,ox)."""
    h, w = a.shape[:2]
    yy, xx = np.mgrid[0:h, 0:w]
    sy = yy + oy
    sx = xx + ox
    y0 = np.floor(sy).astype(int)
    x0 = np.floor(sx).astype(int)
    fy = (sy - y0)[..., None]
    fx = (sx - x0)[..., None]
    y0 = np.clip(y0, 0, h - 1)
    y1 = np.clip(y0 + 1, 0, h - 1)
    x0 = np.clip(x0, 0, w - 1)
    x1 = np.clip(x0 + 1, 0, w - 1)
    top = a[y0, x0] * (1 - fx) + a[y0, x1] * fx
    bot = a[y1, x0] * (1 - fx) + a[y1, x1] * fx
    return top * (1 - fy) + bot * fy


def fxaa(c):
    """c: (h,w,3) sRGB 0..1. Port of FXAA_SHADER (luma-based edge AA)."""
    tex = np.array([1.0 / c.shape[1], 1.0 / c.shape[0]])
    lum = lambda x: 0.299 * x[..., 0] + 0.587 * x[..., 1] + 0.114 * x[..., 2]
    lM = lum(c)
    lNW = lum(_sample(c, -1, -1))
    lNE = lum(_sample(c, -1, 1))
    lSW = lum(_sample(c, 1, -1))
    lSE = lum(_sample(c, 1, 1))
    lMin = np.minimum(np.minimum(lM, lNW), np.minimum(np.minimum(lNE, lSW), lSE))
    lMax = np.maximum(np.maximum(lM, lNW), np.maximum(np.maximum(lNE, lSW), lSE))
    dirx = -((lNW + lNE) - (lSW + lSE))
    diry = (lNW + lSW) - (lNE + lSE)
    reduce_ = np.maximum((lNW + lNE + lSW + lSE) * 0.25 * 0.18, 1.0 / 128.0)
    rcp = 1.0 / (np.minimum(np.abs(dirx), np.abs(diry)) + reduce_)
    dx = np.clip(dirx * rcp, -8, 8) * tex[0]
    dy = np.clip(diry * rcp, -8, 8) * tex[1]
    rgbA = 0.5 * (_sample(c, dy * (1.0 / 3.0 - 0.5), dx * (1.0 / 3.0 - 0.5)) +
                  _sample(c, dy * (2.0 / 3.0 - 0.5), dx * (2.0 / 3.0 - 0.5)))
    rgbB = rgbA * 0.5 + 0.25 * (_sample(c, -dy * 0.5, -dx * 0.5) +
                               _sample(c, dy * 0.5, dx * 0.5))
    lB = lum(rgbB)
    mask = (lB < lMin) | (lB > lMax)
    return np.where(mask[..., None], rgbA, rgbB)


def read_bin(path, w, h):
    a = np.fromfile(path, dtype=np.float32)
    return a.reshape(h, w, 4)[..., :3].astype(np.float64)


def main():
    args = [a for a in sys.argv[1:] if not a.startswith('--')]
    do_fxaa = '--no-fxaa' not in sys.argv
    binf, out, w, h = args[0], args[1], int(args[2]), int(args[3])
    g = grade(read_bin(binf, w, h))
    s = np.clip(l2s(g), 0.0, None)
    final = fxaa(s) if do_fxaa else s
    arr = np.clip(final * 255.0 + 0.5, 0, 255).astype(np.uint8)
    Image.fromarray(arr, 'RGB').save(out)
    print(f'grade{"+fxaa" if do_fxaa else ""} -> {out}  mean={arr.mean():.1f}')


if __name__ == '__main__':
    main()
