#!/usr/bin/env python3
"""Combined grade + ink post-process for Sakura Crossing (CPU-side).

Ports the reference's GRADE_SHADER (split-tone, warmth, lift, saturation) and
INK_SHADER (Sobel edge detection on luma) for flat-shaded cel.

Usage: python3 grade_ink.py <input.png> <output.png> [ink_threshold]
"""
import sys, math
from PIL import Image

def s2l(c):  # sRGB 0..255 → linear 0..1
    c = c / 255.0
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4

def l2s(c):  # linear 0..1 → sRGB 0..255
    return int(255 * (c * 12.92 if c <= 0.0031308 else 1.055 * (c ** (1/2.4)) - 0.055))

def ss(e0, e1, x):
    t = max(0, min(1, (x - e0) / (e1 - e0)))
    return t * t * (3 - 2 * t)

def main():
    src, dst = sys.argv[1], sys.argv[2]
    thr = float(sys.argv[3]) if len(sys.argv) > 3 else 24.0

    im = Image.open(src).convert('RGB')
    W, H = im.size
    px = im.load()

    # ---- GRADE (linear space) ----
    shadow = [s2l(0xad), s2l(0xa8), s2l(0xd0)]  # 0xada8d0
    light  = [s2l(0xff), s2l(0xf7), s2l(0xe8)]  # 0xfff7e8
    ink    = [s2l(57), s2l(50), s2l(79)]         # PAL.ink linear

    graded = Image.new('RGB', (W, H))
    gpx = graded.load()
    luma_lin = [[0.0]*W for _ in range(H)]

    for y in range(H):
        for x in range(W):
            r, g, b = px[x, y]
            lr, lg, lb = s2l(r), s2l(g), s2l(b)
            l = 0.2126*lr + 0.7152*lg + 0.0722*lb
            luma_lin[y][x] = l
            k = ss(0.02, 0.55, l)
            # split-tone
            lr *= shadow[0]*(1-k) + light[0]*k
            lg *= shadow[1]*(1-k) + light[1]*k
            lb *= shadow[2]*(1-k) + light[2]*k
            # warmth
            lr += 0.05 * l * 0.35
            lg += 0.05 * 0.45 * l * 0.35
            # lift
            lift = 0.032 * (1 - k)
            lr += lift; lg += lift; lb += lift
            # saturation 1.12
            lr = l + (lr - l) * 1.12
            lg = l + (lg - l) * 1.12
            lb = l + (lb - l) * 1.12
            gpx[x, y] = (max(0,min(255,l2s(lr))), max(0,min(255,l2s(lg))), max(0,min(255,l2s(lb))))

    # ---- INK (Sobel on graded luma) ----
    # compute luma of graded image
    glm = [[0.299*gpx[x,y][0]+0.587*gpx[x,y][1]+0.114*gpx[x,y][2] for x in range(W)] for y in range(H)]

    result = Image.new('RGB', (W, H))
    rpx = result.load()
    ink_count = 0
    for y in range(H):
        for x in range(W):
            edge = 0.0
            if 1 < x < W-1 and 1 < y < H-1:
                gx = -glm[y-1][x-1]-2*glm[y][x-1]-glm[y+1][x-1]+glm[y-1][x+1]+2*glm[y][x+1]+glm[y+1][x+1]
                gy = -glm[y-1][x-1]-2*glm[y-1][x]-glm[y-1][x+1]+glm[y+1][x-1]+2*glm[y+1][x]+glm[y+1][x+1]
                mag = math.sqrt(gx*gx+gy*gy)
                if mag > thr:
                    t = min(1.0, (mag - thr) / (thr * 2.0))
                    # distance fade
                    l = glm[y][x]
                    fade = 1.0 if l < 195 else max(0.0, 1.0 - (l - 195) / 45.0)
                    edge = t * fade

            if edge > 0.03:
                ink_count += 1
                r, g, b = gpx[x, y]
                # ink keeps whisper of underlying hue
                lr = ink[0]*0.78 + s2l(r)*0.42*0.22
                lg = ink[1]*0.78 + s2l(g)*0.42*0.22
                lb = ink[2]*0.78 + s2l(b)*0.42*0.22
                rpx[x, y] = (max(0,min(255,l2s(s2l(r)*(1-edge)+lr*edge))),
                             max(0,min(255,l2s(s2l(g)*(1-edge)+lg*edge))),
                             max(0,min(255,l2s(s2l(b)*(1-edge)+lb*edge))))
            else:
                rpx[x, y] = gpx[x, y]

    result.save(dst)
    print(f"Grade+Ink done: {100*ink_count/(W*H):.1f}% ink, threshold={thr}")

if __name__ == '__main__':
    main()
