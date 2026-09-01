#!/bin/bash
# Sakura Crossing — REALTIME TOON on the EXTRACTED reference geometry.
#   1. dart: ref_geo.bin -> per-pixel realtime cel + realtime sun shadow map
#      -> linear RT (+ depth RT for ink). Geometry/camera/world are the
#      reference's own (identical by construction); no baked cel, no CPU shadows.
#   2. python: depth-ink + GRADE_SHADER + FXAA -> final PNG
#
# Usage: ./render_realtime_ref.sh [output.png] [geo.bin]
# Env:   PX/PZ/EYE/YAW/PITCH  spawn camera override
#        GRADE="exp SAT CONTRAST"  finale grade (default: reference 1.0 1.12 1.0)
set -e
OUT="${1:-output_rref.png}"
GEO="${2:-/tmp/ref_geo_r60.bin}"
DIR="$(cd "$(dirname "$0")" && pwd)"
NATIVE="$DIR/../thermion_sakura_native"
PREFIX="/tmp/sakura_rref"
GRADE="${GRADE:-1.0 1.12 1.0}"   # reference grade: no exposure boost, SAT 1.12, no contrast S-curve

echo "1/2 Realtime toon cel + sun shadow map on extracted geometry ($GEO)..."
( cd "$NATIVE" && xvfb-run -a -s "-screen 0 1600x900x24" \
  env LD_PRELOAD=/lib/aarch64-linux-gnu/libstdc++.so.6 \
  dart run bin/render_realtime_ref.dart "$GEO" "$PREFIX" ) 2>&1 | tail -6

echo "2/2 Depth ink + fog + grade + FXAA -> $OUT  (grade: $GRADE)"
# shellcheck disable=SC2086
python3 "$DIR/tool/finale.py" "$PREFIX" "$OUT" 1600 900 $GRADE --fog

rm -f "$PREFIX.rt1.bin" "$PREFIX.depth.bin"
echo "done -> $OUT"
