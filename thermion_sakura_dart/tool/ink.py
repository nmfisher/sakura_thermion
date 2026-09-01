#!/usr/bin/env python3
"""CPU-side depth-ink post-process for the Sakura Crossing scene.

For flat-shaded cel, color-based Sobel edge detection is equivalent to the
reference's depth second-difference: coplanar faces share a cel band (no color
edge = no line), and creases/silhouettes break the band (edge = line).

Usage: python3 ink.py <input.png> <output.png> [threshold] [sens]
"""
import sys, math
from PIL import Image

def main():
    src = sys.argv[1]
    dst = sys.argv[2]
    threshold = float(sys.argv[3]) if len(sys.argv) > 3 else 18.0
    sens = float(sys.argv[4]) if len(sys.argv) > 4 else 0.0042

    im = Image.open(src).convert('RGB')
    W, H = im.size
    px = im.load()

    # ink color (PAL.ink = 0x39324f)
    ir, ig, ib = 57, 50, 79

    # luma buffer
    lm = [[int(0.299*px[x,y][0]+0.587*px[x,y][1]+0.114*px[x,y][2]) for x in range(W)] for y in range(H)]

    # Sobel + threshold
    edge = [[0.0]*W for _ in range(H)]
    for y in range(2, H-2):
        for x in range(2, W-2):
            gx = -lm[y-1][x-1]-2*lm[y][x-1]-lm[y+1][x-1]+lm[y-1][x+1]+2*lm[y][x+1]+lm[y+1][x+1]
            gy = -lm[y-1][x-1]-2*lm[y-1][x]-lm[y-1][x+1]+lm[y+1][x-1]+2*lm[y+1][x]+lm[y+1][x+1]
            mag = math.sqrt(gx*gx+gy*gy)
            if mag > threshold:
                # smoothstep the edge
                t = min(1.0, (mag - threshold) / (threshold * 2.5))
                # distance fade: fade ink in the haze (high-luma = distant/fog)
                l = lm[y][x]
                fade = 1.0
                if l > 200: fade = max(0.0, 1.0 - (l - 200) / 40.0)
                edge[y][x] = t * fade

    # Dilate edges by 1px for slightly thicker, cleaner lines
    dilated = [[0.0]*W for _ in range(H)]
    for y in range(1, H-1):
        for x in range(1, W-1):
            m = max(edge[y-1][x-1],edge[y-1][x],edge[y-1][x+1],
                    edge[y][x-1],edge[y][x],edge[y][x+1],
                    edge[y+1][x-1],edge[y+1][x],edge[y+1][x+1])
            dilated[y][x] = m * 0.85  # slightly softer after dilation

    # composite
    result = Image.new('RGB', (W, H))
    rpx = result.load()
    for y in range(H):
        for x in range(W):
            e = dilated[y][x]
            if e > 0.02:
                r, g, b = px[x, y]
                lr = ir*0.78 + r*0.42*0.22
                lg = ig*0.78 + g*0.42*0.22
                lb = ib*0.78 + b*0.42*0.22
                rpx[x, y] = (int(r*(1-e)+lr*e), int(g*(1-e)+lg*e), int(b*(1-e)+lb*e))
            else:
                rpx[x, y] = px[x, y]

    result.save(dst)
    ink_px = sum(1 for y in range(H) for x in range(W) if dilated[y][x] > 0.02)
    print(f"Ink: {100*ink_px/(W*H):.1f}% | threshold={threshold}")

if __name__ == '__main__':
    main()
