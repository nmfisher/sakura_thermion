#!/bin/bash
# Sakura Crossing — REALTIME render pipeline (native arm64 Linux + OpenGL/Xvfb).
#   1. dart: world geometry (raw albedo) lit by real Filament sun + IBL with
#      native shadow maps -> linear float RT (rt1.bin)
#   2. python: luma second-difference ink + GRADE_SHADER + FXAA -> final PNG
#
# Usage: ./render_realtime.sh [output.png] [exposure]
# Env:   SUN_I FILL_I BOUNCE_I IBL_I  NO_SHADOW=1  SHADOW=0  NO_IBL=1
set -e
OUT="${1:-output_realtime.png}"
EXP="${2:-1.0}"
DIR="$(cd "$(dirname "$0")" && pwd)"
NATIVE="$DIR/../thermion_sakura_native"
PREFIX="/tmp/sakura_rt"

echo "1/2 Realtime lit render + shadow map (OpenGL/Xvfb)..."
( cd "$NATIVE" && xvfb-run -a -s "-screen 0 1600x900x24" \
  env LD_PRELOAD=/lib/aarch64-linux-gnu/libstdc++.so.6 \
  dart run bin/render_realtime.dart "$PREFIX" ) 2>&1 | tail -6

echo "2/2 Depth ink + grade + FXAA -> $OUT"
python3 "$DIR/tool/finale.py" "$PREFIX" "$OUT" 1600 900 "$EXP"

rm -f "$PREFIX.rt1.bin"
echo "done -> $OUT"
