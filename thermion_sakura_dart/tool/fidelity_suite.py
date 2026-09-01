#!/usr/bin/env python3
"""Score a directory of Thermion renders against reference captures."""

import argparse
import json
from pathlib import Path

from fidelity import measure


TOOL_DIR = Path(__file__).resolve().parent


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("actual_dir", type=Path)
    parser.add_argument("reference_dir", type=Path)
    parser.add_argument("--views", type=Path, default=TOOL_DIR / "fidelity_views.json")
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args()
    suite = json.loads(args.views.read_text())

    results = []
    missing = []
    for view in suite["views"]:
        name = view["name"]
        actual = args.actual_dir / f"{name}.png"
        reference = args.reference_dir / f"{name}.jpg"
        if not actual.exists() or not reference.exists():
            missing.append(name)
            continue
        result = measure(actual, reference)
        results.append({"name": name, **result})

    scores = [row["score"] for row in results]
    summary = {
        "mean": round(sum(scores) / len(scores), 2) if scores else 0.0,
        "minimum": round(min(scores), 2) if scores else 0.0,
        "passing": bool(scores) and not missing and sum(scores) / len(scores) >= 90 and min(scores) >= 85,
        "measured": len(results),
        "expected": len(suite["views"]),
        "missing": missing,
        "views": results,
    }
    if args.json:
        print(json.dumps(summary, indent=2, sort_keys=True))
        return
    for row in results:
        print(
            f"{row['name']:<24} {row['score']:>6.2f}  "
            f"colour {row['colour']:>6.2f}  structure {row['structure_ssim']:>6.2f}  "
            f"edges {row['edge_f1']:>6.2f}"
        )
    if missing:
        print(f"missing: {', '.join(missing)}")
    print(
        f"world fidelity {summary['mean']:.2f}/100; minimum {summary['minimum']:.2f}; "
        f"views {summary['measured']}/{summary['expected']}; "
        f"{'PASS' if summary['passing'] else 'NOT PASSING'}"
    )


if __name__ == "__main__":
    main()
