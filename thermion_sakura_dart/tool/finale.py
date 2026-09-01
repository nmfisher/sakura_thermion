#!/usr/bin/env python3
"""Sakura Crossing final composite: depth-style ink (color second-difference on
the flat cel) + GRADE_SHADER + FXAA, all on the linear float32 RT dumped by
render.dart.

The reference's INK_SHADER is a second difference of *linearised depth*. On a
flat-shaded cel scene a second difference of *luma* is equivalent: coplanar
faces share a cel band (no luma change -> no line), and silhouettes/creases
break the band (luma step -> line). Thermion's GL build does not expose the
scene depth texture to custom materials, so this runs CPU-side.

Usage: python3 finale.py <rt1.bin> <out.png> <w> <h> [ink_thr] [--no-fxaa]
"""
import os
import sys
import numpy as np
from PIL import Image


def s2l(c):
    c = np.asarray(c, dtype=np.float64) / 255.0
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def l2s(c):
    c = np.clip(c, 0.0, None)
    return np.where(c <= 0.0031308, c * 12.92, 1.055 * (c ** (1 / 2.4)) - 0.055)


INK = s2l([0x39, 0x32, 0x4f])           # PAL.ink, linear
SHADOW = s2l([0xad, 0xa8, 0xd0])        # grade shadow tint
LIGHT = s2l([0xff, 0xf7, 0xe8])         # grade light tint
FOG = s2l([0xe6, 0xec, 0xf7])           # PAL.fog (THREE.Fog colour)
SAT, LIFT, VIG, WARM = 1.5, 0.032, 0.15, 0.05
CONTRAST = 1.15  # display-space S-curve punch (darkens darks, lifts lights)

# Ink pass constants — exact port of the reference INK_SHADER uniforms.
NEAR, FAR = 0.25, 600.0
U_THICK, U_SENS = 1.35, 0.0042
U_CONCAVE, U_CONCAVE_AMT = 0.026, 0.42
U_FADE0, U_FADE1, U_SKYDEPTH = 40.0, 98.0, 420.0


def view_z(d):
    """Positive view-space distance from a Filament DEPTH32F value.

    The depth attachment stores LINEAR reverse-Z (d = NEAR/z, 1 at the near
    plane, 0 at infinity), so the true distance is simply NEAR/d. The old
    formula ((NEAR*FAR)/(NEAR + d*(FAR-NEAR))) inverted the wrong convention
    and compressed far distances (the 500m sky read as 258m), so the ink
    pass's sky exclusion (>420) never fired and the fog washed the sky."""
    return NEAR / np.maximum(d, 1e-6)


def smoothstep(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0.0, 1.0)
    return t * t * (3 - 2 * t)


def _sample(a, oy, ox):
    h, w = a.shape[:2]
    yy, xx = np.mgrid[0:h, 0:w]
    sy = yy + oy
    sx = xx + ox
    y0 = np.clip(np.floor(sy).astype(int), 0, h - 1)
    y1 = np.clip(y0 + 1, 0, h - 1)
    x0 = np.clip(np.floor(sx).astype(int), 0, w - 1)
    x1 = np.clip(x0 + 1, 0, w - 1)
    fy = (sy - np.floor(sy))[..., None]
    fx = (sx - np.floor(sx))[..., None]
    top = a[y0, x0] * (1 - fx) + a[y0, x1] * fx
    bot = a[y1, x0] * (1 - fx) + a[y1, x1] * fx
    return top * (1 - fy) + bot * fy


def apply_fog(rgb, depth_raw):
    """Blend toward PAL.fog by view distance (THREE.Fog 44..205). Sky pixels
    (dist > 300) are left alone so the dome keeps its gradient."""
    dist = view_z(depth_raw)[..., None]
    t = np.clip((dist - 44.0) / (205.0 - 44.0), 0.0, 1.0)
    fog = (t * t * (3.0 - 2.0 * t)) * (dist < 300.0)
    return rgb * (1.0 - fog) + FOG * fog


def ink(rgb, depth_raw):
    """Reference INK_SHADER ported exactly: second difference of linearised
    reverse-Z depth, normalised by distance. rgb & depth_raw are (h,w,3)/(h,w)
    arrays in the same resolution. Returns inked linear rgb."""
    c = rgb.astype(np.float64)
    dc = view_z(depth_raw)
    t = U_THICK
    dl = view_z(_sample(depth_raw[..., None], 0, -t)[..., 0])
    dr = view_z(_sample(depth_raw[..., None], 0, t)[..., 0])
    du = view_z(_sample(depth_raw[..., None], t, 0)[..., 0])
    dd = view_z(_sample(depth_raw[..., None], -t, 0)[..., 0])
    sx = (dl + dr - 2 * dc) / np.maximum(dc, 1e-6)
    sy = (du + dd - 2 * dc) / np.maximum(dc, 1e-6)
    convex = np.maximum(0, sx) + np.maximum(0, sy)
    concave = np.maximum(0, -sx) + np.maximum(0, -sy)
    edge = smoothstep(U_SENS * 0.32, U_SENS, convex)
    edge = np.maximum(edge, smoothstep(U_CONCAVE, U_CONCAVE * 3.4, concave) * U_CONCAVE_AMT)
    edge *= 1.0 - smoothstep(U_FADE0, U_FADE1, dc)
    edge = np.where(dc > U_SKYDEPTH, 0.0, edge)
    edge = np.clip(edge, 0, 1)[..., None]
    line = INK * 0.78 + c * 0.42 * 0.22
    return c * (1 - edge) + line * edge


def grade(rgb):
    c = rgb.astype(np.float64)
    l = 0.2126 * c[..., 0] + 0.7152 * c[..., 1] + 0.0722 * c[..., 2]
    k = smoothstep(0.02, 0.55, l)[..., None]
    c = c * (SHADOW * (1 - k) + LIGHT * k)
    c = c + np.stack([WARM * l, WARM * 0.45 * l, np.zeros_like(l)], axis=-1) * 0.35
    c = c + LIFT * (1 - k)
    c = l[..., None] + (c - l[..., None]) * SAT
    h, w = l.shape
    yy, xx = np.mgrid[0:h, 0:w]
    u = (xx + 0.5) / w
    v = (yy + 0.5) / h
    r = np.sqrt((u - 0.5) ** 2 + (v - 0.5) ** 2) * 1.42
    c = c * (1.0 - VIG * np.clip(r, 0, 1) ** 2.6)[..., None]
    return c


def fxaa(c):
    tex = np.array([1.0 / c.shape[1], 1.0 / c.shape[0]])
    lum = lambda x: 0.299 * x[..., 0] + 0.587 * x[..., 1] + 0.114 * x[..., 2]
    lM = lum(c)
    lNW = lum(_sample(c, -1, -1)); lNE = lum(_sample(c, -1, 1))
    lSW = lum(_sample(c, 1, -1)); lSE = lum(_sample(c, 1, 1))
    lMin = np.minimum(np.minimum(lM, lNW), np.minimum(np.minimum(lNE, lSW), lSE))
    lMax = np.maximum(np.maximum(lM, lNW), np.maximum(np.maximum(lNE, lSW), lSE))
    dirx = -((lNW + lNE) - (lSW + lSE))
    diry = (lNW + lSW) - (lNE + lSE)
    reduce_ = np.maximum((lNW + lNE + lSW + lSE) * 0.25 * 0.18, 1.0 / 128.0)
    rcp = 1.0 / (np.minimum(np.abs(dirx), np.abs(diry)) + reduce_)
    dx = np.clip(dirx * rcp, -8, 8) * tex[0]
    dy = np.clip(diry * rcp, -8, 8) * tex[1]
    rgbA = 0.5 * (_sample(c, dy * (1 / 3 - 0.5), dx * (1 / 3 - 0.5)) +
                  _sample(c, dy * (2 / 3 - 0.5), dx * (2 / 3 - 0.5)))
    rgbB = rgbA * 0.5 + 0.25 * (_sample(c, -dy * 0.5, -dx * 0.5) + _sample(c, dy * 0.5, dx * 0.5))
    mask = (lum(rgbB) < lMin) | (lum(rgbB) > lMax)
    return np.where(mask[..., None], rgbA, rgbB)


def read_bin(path, w, h):
    a = np.fromfile(path, dtype=np.float32)
    return a.reshape(h, w, 4)[..., :3].astype(np.float64)


def read_depth(path, w, h):
    a = np.fromfile(path, dtype=np.float32).reshape(h, w, 4)
    return a[..., 0].astype(np.float64)


def main():
    args = [a for a in sys.argv[1:] if not a.startswith('--')]
    do_fxaa = '--no-fxaa' not in sys.argv
    do_fog = '--fog' in sys.argv
    prefix, out, w, h = args[0], args[1], int(args[2]), int(args[3])
    exposure = float(args[4]) if len(args) > 4 else 0.58
    if len(args) > 5:
        global SAT
        SAT = float(args[5])
    if len(args) > 6:
        global CONTRAST
        CONTRAST = float(args[6])
    rgb_raw = read_bin(f'{prefix}.rt1.bin', w, h)
    # Composite the isolated sky (rendered on its own pass) where the scene RT
    # is the sentinel (<0 = no world geometry). The toon material corrupts the
    # sky when sharing its view, so the sky is rendered separately.
    sky_path = f'{prefix}.sky.bin'
    if os.path.exists(sky_path):
        sky = read_bin(sky_path, w, h)
        mask = (rgb_raw[..., 0] < -0.5)[..., None]
        rgb_raw = np.where(mask, sky, rgb_raw)
    rgb = rgb_raw * exposure
    depth = read_depth(f'{prefix}.depth.bin', w, h)
    # The baked GLB path (refGeoToGlb) already applies THREE.Fog per-face, so
    # it must NOT re-fog here. The realtime path has no baked fog, so its
    # wrapper passes --fog: apply the reference's THREE.Fog(44..205) from the
    # depth RT before inking. Sky pixels (no geometry in the depth RT -> huge
    # view-z) are excluded so the dome keeps its gradient.
    if do_fog:
        rgb = apply_fog(rgb, depth)
    inked = ink(rgb, depth)
    frac = np.mean(np.any(np.abs(inked - rgb) > 0.002, axis=-1))
    g = grade(inked)
    s = np.clip(l2s(g), 0.0, None)
    if CONTRAST != 1.0:
        s = (s - 0.5) * CONTRAST + 0.5
    final = fxaa(s) if do_fxaa else s
    arr = np.clip(final * 255.0 + 0.5, 0, 255).astype(np.uint8)
    Image.fromarray(arr, 'RGB').save(out)
    print(f'finale exp={exposure} ink={frac*100:.1f}% fxaa={do_fxaa} -> {out} mean={arr.mean():.1f}')


if __name__ == '__main__':
    main()
