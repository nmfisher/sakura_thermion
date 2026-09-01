#!/usr/bin/env python3
"""Rank source meshes with Canvas textures by visible coverage pixels.

Consumes the reference scene manifest from ``audit_reference_scene.js`` and
lossless ID buffers from ``capture_object_ids.mjs``. The result identifies the
mapped source objects that actually contribute pixels to coverage cameras,
which is the authoritative queue for removing visible placeholder artwork.
"""

import argparse
from collections import Counter, defaultdict
import json
from pathlib import Path

from PIL import Image


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("manifest", type=Path)
    parser.add_argument("id_dir", type=Path)
    parser.add_argument("--json-out", type=Path)
    parser.add_argument("--markdown-out", type=Path)
    parser.add_argument("--limit", type=int, default=200)
    args = parser.parse_args()

    manifest = json.loads(args.manifest.read_text())
    materials = {row["id"]: row for row in manifest["materialTable"]}
    textures = {row["id"]: row for row in manifest["textureTable"]}
    source = {row["path"]: row for row in manifest["objects"]}
    totals: Counter[str] = Counter()
    by_view: dict[str, Counter[str]] = defaultdict(Counter)

    for mapping_path in sorted(args.id_dir.glob("*.objects.json")):
        view = mapping_path.name.removesuffix(".objects.json")
        png_path = mapping_path.with_name(f"{view}.png")
        if not png_path.exists():
            continue
        mapping = json.loads(mapping_path.read_text())
        paths = {row["id"]: row["path"] for row in mapping["objects"]}
        pixels = Counter()
        for r, g, b, *_ in Image.open(png_path).convert("RGB").getdata():
            object_id = r | (g << 8) | (b << 16)
            if object_id:
                pixels[object_id] += 1
        for object_id, count in pixels.items():
            path = paths.get(object_id)
            if path is None:
                continue
            totals[path] += count
            by_view[path][view] += count

    rows = []
    for path, visible_pixels in totals.items():
        obj = source.get(path)
        if obj is None:
            continue
        mapped = [
            materials[mid]
            for mid in obj["materials"]
            if materials[mid].get("hasMap") or materials[mid].get("hasAlphaMap")
        ]
        if not mapped:
            continue
        rows.append({
            "path": path,
            "visiblePixels": visible_pixels,
            "views": dict(by_view[path].most_common()),
            "triangleCount": obj["triangleCount"],
            "instanceCount": obj["instanceCount"],
            "bounds": obj["bounds"],
            "textures": sorted({
                texture
                for material in mapped
                for texture in [material.get("mapTexture"), material.get("alphaMapTexture")]
                if texture
            }),
            "textureNames": sorted({
                textures[texture].get("name") or texture
                for material in mapped
                for texture in [material.get("mapTexture"), material.get("alphaMapTexture")]
                if texture
            }),
        })
    rows.sort(key=lambda row: (-row["visiblePixels"], row["path"]))
    report = {
        "format": "sakura-visible-mapped-objects-v1",
        "coverageViews": sorted({view for views in by_view.values() for view in views}),
        "visibleMappedObjects": len(rows),
        "objects": rows,
    }

    if args.json_out:
        args.json_out.parent.mkdir(parents=True, exist_ok=True)
        args.json_out.write_text(json.dumps(report, indent=2) + "\n")
    lines = [
        "# Visible mapped source objects",
        "",
        f"Mapped objects contributing coverage pixels: **{len(rows)}**",
        "",
        "| Visible pixels | Views | Triangles | Source object | Textures |",
        "|---:|---:|---:|---|---|",
    ]
    for row in rows[: args.limit]:
        lines.append(
            f"| {row['visiblePixels']} | {len(row['views'])} | {row['triangleCount']} | "
            f"`{row['path']}` | {', '.join(row['textureNames'])} |"
        )
    markdown = "\n".join(lines) + "\n"
    if args.markdown_out:
        args.markdown_out.parent.mkdir(parents=True, exist_ok=True)
        args.markdown_out.write_text(markdown)
    print(json.dumps({"visibleMappedObjects": len(rows), "views": len(report["coverageViews"])}))


if __name__ == "__main__":
    main()
