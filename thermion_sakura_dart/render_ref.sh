#!/bin/bash
# Sakura Crossing — render the EXTRACTED full reference world (every district)
# at a camera, with matching cel + cast shadows + depth ink + grade + FXAA.
#
# Usage: ./render_ref.sh [output.png] [PX] [PZ] [YAW] [PITCH]
#   defaults to the spawn camera (1.85, 13.6, yaw 0.20, pitch -0.008)
set -e
OUT="${1:-output.png}"
PX="${2:-1.85}"; PZ="${3:-13.6}"; YAW="${4:-0.20}"; PITCH="${5:--0.008}"
GEO="${GEO:-/tmp/ref_geo.bin}"
DIR="$(cd "$(dirname "$0")" && pwd)"
NATIVE="$DIR"
PREFIX="/tmp/sakura_out"

if [ ! -f "$GEO" ]; then
  echo "Extracting reference geometry to $GEO (radius 0 = whole world)..."
  ( cd /tmp/cap && RADIUS=0 PLAYWRIGHT_BROWSERS_PATH=/home/agent/.cache/ms-playwright \
      node extract_geo.js ) 2>&1 | tail -2
  cat /tmp/sakura-ref/.shots/geochunk_*.bin.jpg > "$GEO" 2>/dev/null || true
fi

echo "1/2 Rendering extracted scene + depth at PX=$PX PZ=$PZ YAW=$YAW PITCH=$PITCH..."
( cd "$NATIVE" && PX=$PX PZ=$PZ YAW=$YAW PITCH=$PITCH xvfb-run -a -s "-screen 0 1600x900x24" \
  env LD_PRELOAD=/lib/aarch64-linux-gnu/libstdc++.so.6 \
  dart run bin/render_ref.dart "$GEO" "$PREFIX" ) 2>&1 | tail -3

echo "2/2 Depth ink + grade + FXAA -> $OUT"
python3 "$DIR/tool/finale.py" "$PREFIX" "$OUT" 1600 900 0.58
rm -f "$PREFIX.rt1.bin" "$PREFIX.depth.bin"
echo "done -> $OUT"
