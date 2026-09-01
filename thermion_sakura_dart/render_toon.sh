#!/bin/bash
# Sakura Crossing — REALTIME TOON pipeline (native arm64 + OpenGL/Xvfb).
#   1. dart: world geometry (raw albedo + flat normals) cel-shaded per pixel by
#      a custom toon material under a realtime sun shadow map -> linear RT
#   2. python: depth-ink + GRADE_SHADER + FXAA -> final PNG
# No baked vertex colours, no baked/CPU shadows — all lighting + shadows are
# computed per pixel every frame. (Manual shadow map: Filament's lit-model
# shadow factor isn't exposed to custom unlit materials, so the sun shadow map
# is rendered into a sampleable depth texture and the toon material samples it.)
#
# Usage: ./render_toon.sh [output.png]
# Env:   SHADOW_DEBUG=1  dump the sun shadow map (.shadowmap.bin)
set -e
OUT="${1:-output_toon.png}"
DIR="$(cd "$(dirname "$0")" && pwd)"
NATIVE="$DIR"
PREFIX="/tmp/sakura_rt"

echo "1/2 Realtime toon cel + sun shadow map (OpenGL/Xvfb)..."
( cd "$NATIVE" && xvfb-run -a -s "-screen 0 1600x900x24" \
  env LD_PRELOAD=/lib/aarch64-linux-gnu/libstdc++.so.6 \
  dart run bin/render_toon.dart "$PREFIX" ) 2>&1 | tail -5

echo "2/2 Depth ink + grade + FXAA -> $OUT"
python3 "$DIR/tool/finale.py" "$PREFIX" "$OUT" 1600 900 1.35 1.7 1.3

rm -f "$PREFIX.rt1.bin" "$PREFIX.depth.bin"
echo "done -> $OUT"
