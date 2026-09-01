#!/usr/bin/env python3
"""Attribute a render diff to stable Three.js source object paths.

The lossless ID buffer is produced by ``capture_object_ids.mjs``. Pixels over
the selected error threshold are grouped by the visible reference object, so a
side-by-side mismatch becomes an actionable ranked object list.
"""

import argparse
import json
from pathlib import Path

import numpy as np
from PIL import Image


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("actual", type=Path)
    parser.add_argument("reference", type=Path)
    parser.add_argument("id_buffer", type=Path)
    parser.add_argument("id_map", type=Path)
    parser.add_argument("--threshold", type=float, default=32.0)
    parser.add_argument("--crop", help="x0,y0,x1,y1")
    parser.add_argument("--json-out", type=Path)
    parser.add_argument("--markdown-out", type=Path)
    parser.add_argument("--limit", type=int, default=100)
    args = parser.parse_args()

    ref_image = Image.open(args.reference).convert("RGB")
    size = ref_image.size
    actual = np.asarray(Image.open(args.actual).convert("RGB").resize(size),
                        dtype=np.float32)
    reference = np.asarray(ref_image, dtype=np.float32)
    ids_rgb = np.asarray(Image.open(args.id_buffer).convert("RGB").resize(
        size, Image.Resampling.NEAREST), dtype=np.uint32)
    ids = ids_rgb[..., 0] + (ids_rgb[..., 1] << 8) + (ids_rgb[..., 2] << 16)

    x0, y0, x1, y1 = 0, 0, size[0], size[1]
    if args.crop:
        x0, y0, x1, y1 = map(int, args.crop.split(","))
        actual = actual[y0:y1, x0:x1]
        reference = reference[y0:y1, x0:x1]
        ids = ids[y0:y1, x0:x1]

    error = np.abs(actual - reference).mean(axis=2)
    mismatched = error >= args.threshold
    mapping = {
        row["id"]: row for row in json.loads(args.id_map.read_text())["objects"]
    }
    rows = []
    for object_id in np.unique(ids):
        if object_id == 0 or int(object_id) not in mapping:
            continue
        visible = ids == object_id
        bad = visible & mismatched
        visible_pixels = int(visible.sum())
        mismatch_pixels = int(bad.sum())
        if mismatch_pixels == 0:
            continue
        total_error = float(error[bad].sum())
        source = mapping[int(object_id)]
        rows.append({
            **source,
            "visiblePixels": visible_pixels,
            "mismatchPixels": mismatch_pixels,
            "mismatchFraction": round(mismatch_pixels / visible_pixels, 4),
            "meanError": round(total_error / mismatch_pixels, 3),
            "impact": round(total_error, 3),
        })
    rows.sort(key=lambda row: (-row["impact"], -row["mismatchPixels"],
                               row["path"]))
    report = {
        "format": "sakura-object-diff-attribution-v1",
        "actual": str(args.actual),
        "reference": str(args.reference),
        "crop": [x0, y0, x1, y1],
        "threshold": args.threshold,
        "mismatchPixels": int(mismatched.sum()),
        "rankedObjects": rows,
    }
    if args.json_out:
        args.json_out.parent.mkdir(parents=True, exist_ok=True)
        args.json_out.write_text(json.dumps(report, indent=2) + "\n")

    lines = [
        "# Sakura visual diff attribution",
        "",
        f"Crop: `{x0},{y0},{x1},{y1}`; threshold: {args.threshold:.1f}; "
        f"mismatch pixels: {report['mismatchPixels']}",
        "",
        "| Rank | Impact | Bad/visible pixels | Mean error | Source object |",
        "|---:|---:|---:|---:|---|",
    ]
    for rank, row in enumerate(rows[:args.limit], 1):
        lines.append(
            f"| {rank} | {row['impact']:.0f} | {row['mismatchPixels']}/"
            f"{row['visiblePixels']} | {row['meanError']:.1f} | "
            f"`{row['path']}` |"
        )
    markdown = "\n".join(lines) + "\n"
    if args.markdown_out:
        args.markdown_out.parent.mkdir(parents=True, exist_ok=True)
        args.markdown_out.write_text(markdown)
    print(json.dumps({
        "mismatchPixels": report["mismatchPixels"],
        "attributedObjects": len(rows),
    }, sort_keys=True))
    if args.markdown_out:
        print(f"WROTE {args.markdown_out}")
    if args.json_out:
        print(f"WROTE {args.json_out}")


if __name__ == "__main__":
    main()
