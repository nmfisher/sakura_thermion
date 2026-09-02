#!/usr/bin/env python3
"""Compile Sakura Filament materials and refresh materials_gen.dart.

The official Linux Filament release is x86_64-only. On an aarch64 host this
script automatically runs matc through qemu-x86_64-static and the Debian cross
sysroot. On x86_64 it invokes matc directly.
"""

import argparse
import base64
import os
from pathlib import Path
import platform
import re
import shutil
import subprocess
import tempfile


PACKAGE = Path(__file__).resolve().parent.parent
MATERIALS = PACKAGE / "materials"
GENERATED = PACKAGE / "lib/src/materials_gen.dart"
VARIABLES = {
    "sakura_depthenc": "sakuraDepthEncFilamat",
    "sakura_ink": "sakuraInkFilamat",
    "sakura_lit": "sakuraLitFilamat",
    "sakura_petals": "sakuraPetalsFilamat",
    "sakura_post": "sakuraPostFilamat",
    "sakura_shadow_caster": "sakuraShadowCasterFilamat",
    "sakura_shadow_receiver": "sakuraShadowReceiverFilamat",
    "sakura_sky": "sakuraSkyFilamat",
    "sakura_toon": "sakuraToonFilamat",
    "sakura_toon_rt": "sakuraToonRTFilamat",
    "sakura_vcolor": "sakuraVcolorFilamat",
}


def matc_command(matc: Path) -> list[str]:
    if platform.machine() in {"x86_64", "amd64"}:
        return [str(matc)]
    qemu = os.environ.get("QEMU_X86_64") or shutil.which("qemu-x86_64-static")
    sysroot = Path(os.environ.get("X86_64_SYSROOT", "/usr/x86_64-linux-gnu"))
    if not qemu or not Path(qemu).is_file() or not sysroot.exists():
        raise SystemExit(
            "aarch64 material builds require qemu-user-static, "
            "libc6-amd64-cross, and libstdc++6-amd64-cross"
        )
    return [qemu, "-L", str(sysroot), str(matc)]


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--filament-path",
        type=Path,
        default=Path(os.environ.get("FILAMENT_PATH", "/opt/filament-v1.69.1/bin")),
        help="directory containing Filament matc",
    )
    parser.add_argument("--only", choices=sorted(VARIABLES))
    parser.add_argument(
        "--api",
        choices=("all", "metal", "opengl", "vulkan"),
        default="all",
        help="shader backends to include in each material package (default: all)",
    )
    args = parser.parse_args()

    matc = args.filament_path / "matc"
    if not matc.is_file():
        raise SystemExit(f"matc not found: {matc}")
    compiler = matc_command(matc)
    selected = [args.only] if args.only else sorted(VARIABLES)
    source = GENERATED.read_text()

    with tempfile.TemporaryDirectory(prefix="sakura-materials-") as tmp:
        for name in selected:
            output = Path(tmp) / f"{name}.filamat"
            command = [
                *compiler,
                "-a",
                args.api,
                "-o",
                str(output),
                str(MATERIALS / f"{name}.mat"),
            ]
            print(f"compiling {name}", flush=True)
            subprocess.run(command, check=True)
            encoded = base64.b64encode(output.read_bytes()).decode("ascii")
            variable = VARIABLES[name]
            pattern = re.compile(
                rf"final Uint8List {variable} = base64Decode\(\n\s*'[^']*',?\s*\);"
            )
            replacement = f"final Uint8List {variable} = base64Decode(\n    '{encoded}');"
            source, count = pattern.subn(replacement, source)
            if count != 1:
                raise SystemExit(f"could not uniquely replace {variable}: {count} matches")

    GENERATED.write_text(source)


if __name__ == "__main__":
    main()
