#!/usr/bin/env python3
"""Measure visual fidelity between a Thermion render and Three.js reference.

The score intentionally combines colour, structure, and line-work instead of
calling a small average RGB error "pixel accurate":

* colour: multi-scale RGB mean absolute error, with 80 levels exhausting the
  colour budget;
* structure: 8x8-block luminance SSIM;
* edges: tolerant F1 over luminance edges (one-pixel registration tolerance).

The aggregate is 40% colour, 35% structure, and 25% edges. A view passes at
90, and a whole-world run passes only when its mean is >= 90 and no view is
below 85. Raw MAE and within-16/32 rates are also reported for diagnosis.

Usage: python3 tool/fidelity.py thermion.png reference.png [--json]
"""

import json
import sys

import numpy as np
from PIL import Image


def _load(path, size=None):
    image = Image.open(path).convert("RGB")
    if size is not None and image.size != size:
        image = image.resize(size, Image.Resampling.LANCZOS)
    return np.asarray(image, dtype=np.float32)


def _luma(rgb):
    return rgb[..., 0] * 0.2126 + rgb[..., 1] * 0.7152 + rgb[..., 2] * 0.0722


def _block_ssim(a, b, block=8):
    h = min(a.shape[0], b.shape[0]) // block * block
    w = min(a.shape[1], b.shape[1]) // block * block
    a = a[:h, :w].reshape(h // block, block, w // block, block)
    b = b[:h, :w].reshape(h // block, block, w // block, block)
    axes = (1, 3)
    ma, mb = a.mean(axis=axes), b.mean(axis=axes)
    va, vb = a.var(axis=axes), b.var(axis=axes)
    cov = ((a - ma[:, None, :, None]) * (b - mb[:, None, :, None])).mean(
        axis=axes
    )
    c1 = (0.01 * 255) ** 2
    c2 = (0.03 * 255) ** 2
    score = ((2 * ma * mb + c1) * (2 * cov + c2)) / (
        (ma * ma + mb * mb + c1) * (va + vb + c2)
    )
    return float(np.clip(score.mean(), 0.0, 1.0))


def _edges(luma):
    gx = np.zeros_like(luma)
    gy = np.zeros_like(luma)
    gx[:, 1:-1] = luma[:, 2:] - luma[:, :-2]
    gy[1:-1, :] = luma[2:, :] - luma[:-2, :]
    return np.hypot(gx, gy) >= 34.0


def _dilate(mask):
    out = mask.copy()
    for dy in (-1, 0, 1):
        for dx in (-1, 0, 1):
            out |= np.roll(np.roll(mask, dy, axis=0), dx, axis=1)
    return out


def _edge_f1(a, b):
    ea, eb = _edges(a), _edges(b)
    matched_a = np.count_nonzero(ea & _dilate(eb))
    matched_b = np.count_nonzero(eb & _dilate(ea))
    precision = matched_a / max(1, np.count_nonzero(ea))
    recall = matched_b / max(1, np.count_nonzero(eb))
    return float(2 * precision * recall / max(1e-9, precision + recall))


def measure(actual_path, reference_path):
    reference_image = Image.open(reference_path).convert("RGB")
    actual = _load(actual_path, reference_image.size)
    reference = np.asarray(reference_image, dtype=np.float32)
    delta = np.abs(actual - reference)

    scale_mae = []
    for divisor in (1, 2, 4, 8):
        size = (
            max(1, reference_image.width // divisor),
            max(1, reference_image.height // divisor),
        )
        a = np.asarray(
            Image.fromarray(actual.astype(np.uint8)).resize(
                size, Image.Resampling.BILINEAR
            ),
            dtype=np.float32,
        )
        b = np.asarray(
            reference_image.resize(size, Image.Resampling.BILINEAR),
            dtype=np.float32,
        )
        scale_mae.append(float(np.abs(a - b).mean()))

    multiscale_mae = float(np.mean(scale_mae))
    colour = max(0.0, 1.0 - multiscale_mae / 80.0)
    structure = _block_ssim(_luma(actual), _luma(reference))
    edges = _edge_f1(_luma(actual), _luma(reference))
    score = 100.0 * (0.40 * colour + 0.35 * structure + 0.25 * edges)
    return {
        "score": round(score, 2),
        "colour": round(100 * colour, 2),
        "structure_ssim": round(100 * structure, 2),
        "edge_f1": round(100 * edges, 2),
        "rgb_mae": round(float(delta.mean()), 3),
        "multiscale_mae": round(multiscale_mae, 3),
        "pixels_within_16": round(
            100 * float(np.mean(np.max(delta, axis=2) <= 16)), 2
        ),
        "pixels_within_32": round(
            100 * float(np.mean(np.max(delta, axis=2) <= 32)), 2
        ),
    }


def main():
    args = [arg for arg in sys.argv[1:] if arg != "--json"]
    if len(args) != 2:
        raise SystemExit("usage: fidelity.py thermion.png reference.png [--json]")
    result = measure(args[0], args[1])
    if "--json" in sys.argv:
        print(json.dumps(result, sort_keys=True))
        return
    print(f"fidelity {result['score']:.2f}/100")
    print(
        "  colour {colour:.2f}  structure {structure_ssim:.2f}  "
        "edges {edge_f1:.2f}".format(**result)
    )
    print(
        "  RGB MAE {rgb_mae:.3f}  multiscale MAE {multiscale_mae:.3f}  "
        "within16 {pixels_within_16:.2f}%  within32 {pixels_within_32:.2f}%".format(
            **result
        )
    )


if __name__ == "__main__":
    main()
