#!/usr/bin/env python3
"""Sweep finale grade params (exposure, saturation, contrast) against the
three.js reference, scoring the blossom-tree crop, the train crop, and the
full frame. Uses the raw bins produced by render_ref.dart (prefix arg).

Usage: python3 tool/sweep_grade.py /tmp/sweep
"""
import subprocess, sys
from PIL import Image
import numpy as np

PREFIX = sys.argv[1] if len(sys.argv) > 1 else '/tmp/sweep'
REF = '/tmp/sakura-ref/.shots/ref_spawn.jpg'
W, H = 1600, 900

# crops: tree (0,0-150,330), train (350,270-860,590), sky band, full frame
CROPS = [('tree', 0, 0, 150, 330), ('train', 350, 270, 860, 590),
         ('sky', 300, 0, 1300, 260), ('full', 0, 0, 1600, 900)]


def load(p):
    im = Image.open(p).convert('RGB')
    if im.size != (W, H):
        im = im.resize((W, H), Image.LANCZOS)
    return np.asarray(im, dtype=np.float32)


def sat(a):
    mx, mn = a.max(axis=2), a.min(axis=2)
    return (mx - mn).mean()


ref = load(REF)

PARAMSETS = [
    ('current (0.58/1.5/1.15)', [0.58, 1.5, 1.15]),
    ('ref-like (1.0/1.12/1.0)', [1.0, 1.12, 1.0]),
    ('mid (0.80/1.3/1.08)', [0.80, 1.3, 1.08]),
    ('exp1.0 sat1.12 cont1.15', [1.0, 1.12, 1.15]),
    ('exp0.70 sat1.10 cont1.0', [0.70, 1.10, 1.0]),
]

header = f"{'params':<26}" + "".join(f"{n:>14}" for n, *_ in CROPS) + f"{'':>6}sat  "
print(header)
# ref scores per crop: mean, sat
refs = {}
for name, x0, y0, x1, y1 in CROPS:
    c = ref[y0:y1, x0:x1]
    refs[name] = (c.mean(), sat(c))
print(f"{'REF':<26}" + "".join(f"{'m%.0f/s%.0f' % refs[n]:>14}" for n, *_ in CROPS))

for label, (exp, s, cont) in PARAMSETS:
    out = f'/tmp/grade_{label.split()[0]}.png'
    subprocess.run([sys.executable, '/workspace/thermion_sakura/tool/finale.py',
                    PREFIX, out, str(W), str(H), str(exp), str(s), str(cont)],
                   capture_output=True)
    mine = load(out)
    row = f"{label:<26}"
    for name, x0, y0, x1, y1 in CROPS:
        c = mine[y0:y1, x0:x1]
        d = np.abs(c - ref[y0:y1, x0:x1])
        row += f"{'d%.1f' % d.mean():>14}"
    row += f"  m{mine.mean():.0f}"
    print(row)
