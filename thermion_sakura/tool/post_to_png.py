#!/usr/bin/env python3
"""Convert render_post.dart's float RGBA output into an RGB PNG.

Usage: python3 tool/post_to_png.py input.bin output.png [width height]
"""

import sys

import numpy as np
from PIL import Image


def main():
    if len(sys.argv) not in (3, 5):
        raise SystemExit(
            "usage: post_to_png.py input.bin output.png [width height]"
        )
    source, output = sys.argv[1:3]
    width = int(sys.argv[3]) if len(sys.argv) == 5 else 1600
    height = int(sys.argv[4]) if len(sys.argv) == 5 else 900
    rgba = np.fromfile(source, dtype=np.float32)
    expected = width * height * 4
    if rgba.size != expected:
        raise SystemExit(
            f"{source}: expected {expected} float32 values, found {rgba.size}"
        )
    rgb = np.clip(rgba.reshape(height, width, 4)[..., :3], 0.0, 1.0)
    Image.fromarray((rgb * 255.0 + 0.5).astype(np.uint8), "RGB").save(output)
    print(f"wrote {output} ({width}x{height})")


if __name__ == "__main__":
    main()
