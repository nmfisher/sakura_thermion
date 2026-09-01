#!/usr/bin/env python3
"""Render the procedural Thermion port at every representative camera.

Usage:
  python3 tool/render_fidelity_suite.py [--views FILE] [--output-dir DIR]
      [--only NAME[,NAME...]] [--skip-existing]

Run from either the repository root or thermion_sakura_dart. Each native invocation
is isolated because that is the most reliable lifecycle for Filament under
headless X11; existing images can be retained while iterating with
--skip-existing.
"""

import argparse
import json
import os
from pathlib import Path
import subprocess
import sys


TOOL_DIR = Path(__file__).resolve().parent
PACKAGE_DIR = TOOL_DIR.parent
WORKSPACE = PACKAGE_DIR.parent
NATIVE_DIR = PACKAGE_DIR


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--views", type=Path, default=TOOL_DIR / "fidelity_views.json")
    parser.add_argument("--output-dir", type=Path, default=Path("/tmp/sakura-fidelity/thermion"))
    parser.add_argument("--only", help="comma-separated view names")
    parser.add_argument("--skip-existing", action="store_true")
    parser.add_argument(
        "--renderer-arg",
        action="append",
        default=[],
        help="extra argument passed to every native renderer invocation",
    )
    args = parser.parse_args()

    suite = json.loads(args.views.read_text())
    selected = set(args.only.split(",")) if args.only else None
    views = [v for v in suite["views"] if selected is None or v["name"] in selected]
    if selected:
        unknown = selected - {v["name"] for v in views}
        if unknown:
            raise SystemExit(f"unknown views: {', '.join(sorted(unknown))}")
    args.output_dir.mkdir(parents=True, exist_ok=True)

    preload = "/lib/aarch64-linux-gnu/libstdc++.so.6"
    env = os.environ.copy()
    if Path(preload).exists():
        env["LD_PRELOAD"] = preload

    for index, view in enumerate(views, 1):
        png = args.output_dir / f"{view['name']}.png"
        raw = args.output_dir / f"{view['name']}.bin"
        if args.skip_existing and png.exists():
            print(f"[{index}/{len(views)}] {view['name']}: keeping {png}", flush=True)
            continue
        print(f"[{index}/{len(views)}] {view['name']}: rendering", flush=True)
        command = [
            "xvfb-run", "-a", "-s", f"-screen 0 {suite['width']}x{suite['height']}x24",
            "dart", "run", "bin/render_post.dart",
            f"--px={view['px']}", f"--pz={view['pz']}", f"--eye={view['eye']}",
            f"--yaw={view['yaw']}", f"--pitch={view['pitch']}", f"--output={raw}",
            *view.get("renderer_args", []),
            *args.renderer_arg,
        ]
        subprocess.run(command, cwd=NATIVE_DIR, env=env, check=True)
        subprocess.run(
            [sys.executable, TOOL_DIR / "post_to_png.py", raw, png,
             str(suite["width"]), str(suite["height"])],
            check=True,
        )
        raw.unlink()


if __name__ == "__main__":
    main()
