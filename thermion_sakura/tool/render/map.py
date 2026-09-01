#!/usr/bin/env python3
"""Classify a screenshot PNG into a letter map + save a small preview.

Usage: python3 map.py <png> [cols] [out_preview.png]
Classes: . sky/fog  w white  R red  y yellow  b blue  p pink  g green
         r mid-gray(road)  k dark
"""
import sys
from PIL import Image

def cls(r, g, b):
    if r > 225 and g > 225 and b > 240: return '.'
    if r > 240 and g > 240 and b > 240: return 'w'
    if r > 160 and g < 130 and b < 130: return 'R'
    if r > 180 and g > 150 and b < 130: return 'y'
    if r < 110 and g < 110 and b > 130: return 'b'
    if r > 200 and 140 < g < 205 and 150 < b < 215 and (r - b) > 12: return 'p'
    if g > r * 1.12 and g > b * 1.12: return 'g'
    if r > 140 and g > 140 and b > 140: return 'w'
    if r > 90 and g > 90 and b > 90: return 'r'
    return 'k'

def main():
    src = sys.argv[1]
    cols = int(sys.argv[2]) if len(sys.argv) > 2 else 100
    preview = sys.argv[3] if len(sys.argv) > 3 else None
    im = Image.open(src).convert('RGB')
    W, H = im.size
    rows = max(1, round(cols * H / W / 2.1))
    small = im.resize((cols, rows), Image.BILINEAR)
    px = small.load()
    for y in range(rows):
        print(''.join(cls(*px[x, y]) for x in range(cols)))
    if preview:
        small.save(preview)
        print(f'preview -> {preview}')

main()
