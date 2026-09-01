#!/usr/bin/env python3
"""Build an object-by-object parity ledger for a source-derived Thermion asset.

The reference manifest comes from ``audit_reference_scene.js``. The artifact
coverage manifest comes from ``extract_geo.js`` and records which source mesh
and instance ranges were actually serialized. Matching uses stable hierarchy
paths, never Three.js runtime UUIDs.
"""

import argparse
import json
from pathlib import Path


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("reference", type=Path)
    parser.add_argument("artifact", type=Path)
    parser.add_argument("--json-out", type=Path)
    parser.add_argument("--markdown-out", type=Path)
    parser.add_argument("--limit", type=int, default=100)
    args = parser.parse_args()

    reference = json.loads(args.reference.read_text())
    artifact = json.loads(args.artifact.read_text())
    source_by_path = {row["path"]: row for row in reference["objects"]}
    artifact_by_path = {row["path"]: row for row in artifact["objects"]}

    rows = []
    for path, source in source_by_path.items():
        extracted = artifact_by_path.get(path)
        if extracted is None:
            status = "unmatched"
            included_instances = 0
            included_triangles = 0
        else:
            included_instances = extracted["includedInstances"]
            included_triangles = extracted["includedTriangles"]
            if included_instances == 0:
                status = "excluded"
            elif (
                included_instances == source["instanceCount"]
                and included_triangles == source["triangleCount"]
            ):
                status = "exact"
            else:
                status = "partial"
        rows.append({
            "status": status,
            "path": path,
            "name": source["name"],
            "type": source["type"],
            "sourceInstances": source["instanceCount"],
            "includedInstances": included_instances,
            "sourceTriangles": source["triangleCount"],
            "includedTriangles": included_triangles,
            "bounds": source["bounds"],
            "geometrySignature": source["geometrySignature"],
            "materialSignatures": source["materialSignatures"],
        })

    for path, extracted in artifact_by_path.items():
        if path not in source_by_path:
            rows.append({
                "status": "artifact-only",
                "path": path,
                "name": extracted["name"],
                "type": extracted["type"],
                "sourceInstances": 0,
                "includedInstances": extracted["includedInstances"],
                "sourceTriangles": 0,
                "includedTriangles": extracted["includedTriangles"],
            })

    order = {"unmatched": 0, "partial": 1, "excluded": 2,
             "artifact-only": 3, "exact": 4}
    rows.sort(key=lambda row: (
        order[row["status"]],
        -row["sourceTriangles"],
        row["path"],
    ))
    counts = {}
    for row in rows:
        counts[row["status"]] = counts.get(row["status"], 0) + 1
    report = {
        "format": "sakura-object-parity-report-v1",
        "passing": counts.get("exact", 0) == len(source_by_path),
        "summary": {
            "sourceObjects": len(source_by_path),
            "artifactObjects": len(artifact_by_path),
            **counts,
        },
        "objects": rows,
    }

    if args.json_out:
        args.json_out.parent.mkdir(parents=True, exist_ok=True)
        args.json_out.write_text(json.dumps(report, indent=2) + "\n")

    non_exact = [row for row in rows if row["status"] != "exact"]
    lines = [
        "# Sakura object parity",
        "",
        f"Result: **{'PASS' if report['passing'] else 'NOT PASSING'}**",
        "",
        f"- Source objects: {len(source_by_path)}",
        f"- Exact: {counts.get('exact', 0)}",
        f"- Partial: {counts.get('partial', 0)}",
        f"- Excluded: {counts.get('excluded', 0)}",
        f"- Unmatched: {counts.get('unmatched', 0)}",
        f"- Artifact-only: {counts.get('artifact-only', 0)}",
        "",
        "## Highest-impact non-exact objects",
        "",
        "| Status | Triangles | Instances | Object path |",
        "|---|---:|---:|---|",
    ]
    for row in non_exact[:args.limit]:
        lines.append(
            f"| {row['status']} | {row['sourceTriangles']} | "
            f"{row['includedInstances']}/{row['sourceInstances']} | "
            f"`{row['path']}` |"
        )
    markdown = "\n".join(lines) + "\n"
    if args.markdown_out:
        args.markdown_out.parent.mkdir(parents=True, exist_ok=True)
        args.markdown_out.write_text(markdown)
    print(json.dumps(report["summary"], sort_keys=True))
    if args.markdown_out:
        print(f"WROTE {args.markdown_out}")
    if args.json_out:
        print(f"WROTE {args.json_out}")


if __name__ == "__main__":
    main()
