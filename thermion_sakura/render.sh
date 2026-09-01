#!/bin/bash
# Sakura Crossing — full render pipeline (native arm64 Linux + OpenGL via Xvfb).
#   1. dart: render the linear cel scene (rt1.bin) + a depth pass (depth.bin)
#   2. python: depth second-difference ink + GRADE_SHADER + FXAA -> final PNG
#
# Usage: ./render.sh [output.png] [exposure]
set -e
OUT="${1:-output.png}"
EXP="${2:-0.95}"
DIR="$(cd "$(dirname "$0")" && pwd)"
NATIVE="$DIR/../thermion_sakura_native"
PREFIX="/tmp/sakura_out"

echo "1/2 Rendering scene + depth (OpenGL/Xvfb)..."
( cd "$NATIVE" && xvfb-run -a -s "-screen 0 1600x900x24" \
  env LD_PRELOAD=/lib/aarch64-linux-gnu/libstdc++.so.6 \
  dart run bin/render.dart "$PREFIX" ) 2>&1 | tail -4

echo "2/2 Depth ink + grade + FXAA -> $OUT"
python3 "$DIR/tool/finale.py" "$PREFIX" "$OUT" 1600 900 "$EXP"

rm -f "$PREFIX.rt1.bin" "$PREFIX.depth.bin"
echo "done -> $OUT"
