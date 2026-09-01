# Sakura Crossing — 桜踏切

A re-implementation of the
[sakura-crossing](https://github.com/Kenton-GMI/sakura-crossing) scene — an
explorable Japanese suburban railway-crossing street rendered in a cel-shaded
anime style — using **Dart + Thermion (Filament)**.

The goal is visual fidelity with the reference: the same world, the same cel
shading, the same depth-based ink outlines, the same anime colour grade.

## How it works

The reference renders Three.js `MeshToonMaterial` (quantised light bands + cool
violet shadow tint) against a two-light anime setup, then runs a three-pass
post pipeline (`src/core/post.js`): **depth ink → grade → FXAA**. This port
reproduces the same pipeline in linear space for native fidelity renders and
through the `sakura_post` material in the interactive Flutter application.

- **`lib/src/cel.dart`** — the cel shader as a pure function: per-face `dotNL`
  quantisation through the reference's hand-authored ramps (`RAMPS`), the
  violet shadow-tint mix (`celBand * mix(tint, 1, celBand)`), and the
  sun/fill/bounce/hemisphere lights evaluated in **linear** space with a
  `1/π` Lambert gain (matching three.js's `MeshToonMaterial` BRDF). Fog blends
  in linear, like `THREE.Fog`.
- **`lib/src/mesh.dart`** — a face-accumulating builder. Every face is
  flat-shaded (one cel band per face). Box faces are wound CCW-outward so the
  visible walls shade toward the camera. Vertex colours are **linear**. The
  current native and Flutter ported renderers generate a light-space shadow
  texture from visible caster geometry and sample it per pixel; older baked
  shadow helpers remain available for legacy render paths.
- **`lib/src/glb.dart`** — a minimal glTF 2.0 binary encoder. The whole world
  packs into one GLB with a single unlit vertex-colour material and loads via
  `loadGltfFromBuffer`. (The Thermion web build renders nothing for the custom
  `createGeometry` path — gltfio is the only geometry route that works there.)
- **`lib/src/world/`** — faithful ports of the reference's street, railway
  crossing (gates, signals, train), sakura trees (same mulberry32 seeds → the
  same trees), houses, shop, petals, poles/wires and crossing-corner props.
  The sky mixes its palette in linear space, like the reference sky shader.

### The post pipeline (`tool/finale.py`)

A faithful port of the reference `INK_SHADER` + `GRADE_SHADER` + `FXAA_SHADER`,
operating on two float buffers the native renderer dumps:

- **Ink** — second difference of linearised depth (convex strong, concave
  faint), distance fade, sky cutoff. The scene depth cannot be sampled from a
  Thermion custom material (the GL build reads back 0), so the depth is written
  to a float **colour** target by `materials/sakura_depthenc.mat`
  (`gl_FragCoord.z`) and linearised with the reverse-Z formula in Python.
- **Grade** — split-tone (violet darks / warm lights), warmth, shadow lift,
  saturation, vignette, then linear→sRGB.
- **FXAA** — luma-based edge AA.

## Render (native arm64 Linux + OpenGL)

```sh
./render.sh [output.png] [exposure]   # exposure defaults to 0.95
```

This runs `bin/render.dart` under `xvfb-run`
(Xvfb + llvmpipe OpenGL + `LD_PRELOAD=libstdc++.so.6`) to dump the linear scene
(`rt1.bin`) and depth (`depth.bin`) float buffers, then `tool/finale.py` to
produce the final PNG. Camera matches the reference spawn (FOV 46, near 0.25,
far 600, pos (1.85, 1.62, 13.6), yaw 0.20, pitch -0.008).

## Build & run (web)

```sh
dart pub get
dart run thermion_dart:download_web          # fetches the prebuilt WASM runtime
dart compile wasm web/main.dart -o web/main.wasm
dart run tool/serve.dart --port 8080         # COOP/COEP dev server
```

Then open http://localhost:8080 in Chrome (cross-origin isolation is required
for the threaded WASM build).

## Verifying fidelity against the reference

The reference source at
[`Kenton-GMI/sakura-crossing`](https://github.com/Kenton-GMI/sakura-crossing)
is used as ground truth. A
Playwright + SwiftShader capture (`__shot` dev helper) renders the reference
headlessly for pixel-exact comparison targets. The Dart port includes the full
static world: every source district, the railway and crossing, canal, hill
range and trails, both tunnels, lake, lake road, and shore sites. Runtime
interaction metadata and animation are intentionally represented at their
opening-frame state.

`tool/post_to_png.py` converts `render_post.dart`'s float output to a PNG, and
`tool/fidelity.py` reports the repeatable colour/structure/edge score used for
the port. A view passes at 90; the whole-world target additionally requires no
representative view below 85.

The representative cameras live in `tool/fidelity_views.json`. Capture the
Three.js ground truth from a running reference dev server, render the Thermion
suite, and score it with:

```sh
node tool/capture_reference.mjs /tmp/sakura-ref
python3 tool/render_fidelity_suite.py
python3 tool/fidelity_suite.py \
  /tmp/sakura-fidelity/thermion /tmp/sakura-ref/.shots
```

### Frozen reference-scene fixture

For geometry-level comparisons, `tool/extract_geo.js` freezes the reference at
its authored opening frame and exports world-space triangles, source normals,
material ramps, transformed UVs, and the generated canvas textures as an atlas.
The browser is an extraction tool only; rendering remains native Dart/Thermion.

With the reference Vite server running on port 5178:

```sh
RADIUS=22 ATLAS_WIDTH=4096 \
  OUT=/tmp/sakura-crossing.bin \
  ATLAS_OUT=/tmp/sakura-crossing.atlas.png \
  node tool/extract_geo.js

cd ../thermion_sakura_dart
LD_PRELOAD=/lib/aarch64-linux-gnu/libstdc++.so.6 xvfb-run -a \
  dart run bin/render_post.dart \
  --reference-geo=/tmp/sakura-crossing.bin \
  --reference-atlas=/tmp/sakura-crossing.atlas.png \
  --output=/tmp/sakura-crossing.rgba32f
```

Keep atlas dimensions at or below the renderer's texture-size limit. The full
world needs paged atlases; a single crossing fixture fits one 4096-wide page.

## Notes

- The scene is static (baked) rather than animated: the train, petals and gates
  are authored in their opening-frame positions.
- Materials are compiled with the v1.75.0 Filament `matc` and embedded as single-line base64 in
  `lib/src/materials_gen.dart` (Dart's `base64Decode` rejects newlines).
  Rebuild the Sakura materials with
  `python3 tool/build_materials.py --filament-path /path/to/filament/bin`.
  The default `--api all` includes OpenGL, Vulkan, and Metal; use `--api metal`
  for a Metal-only rebuild.
  Use `--only sakura_toon_rt` while iterating on one shader.
