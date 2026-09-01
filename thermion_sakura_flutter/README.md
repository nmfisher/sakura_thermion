# Sakura Explorer

Interactive Flutter viewer for the Sakura Crossing **realtime toon** scene. It
loads the reference's own extracted geometry (`ref_geo*.bin`) into a live
Thermion viewport with the per-pixel cel material, painted sky, and per-face
CPU cast shadows — the same scene `thermion_sakura_dart/bin/render_realtime_ref.dart`
renders headless — and lets you fly around it. **Ported** mode loads the Dart
scene used by the fidelity renderer and applies its live depth-ink, anime grade,
vignette, and FXAA finale through the same `sakura_post` material.

## Run

```bash
cd thermion_sakura_flutter
flutter run -d linux      # or macos / windows
```

> Requires a real GPU / DRI render node (`/dev/dri/renderD128` on Linux).
> thermion_flutter's desktop GL path does not fall back to software rendering,
> so the app won't run inside a GPU-less container/CI (it builds fine there;
> the headless `render_realtime_ref.dart` is the path that runs without a GPU).

## Geometry

A gzip-compressed radius-60 subset of the reference geometry
(`assets/ref_geo_r60.bin.gz`, ~28 MB) is **bundled and auto-loaded on startup** —
the scene appears with no setup. To view the full scene instead, point the
top-bar path field at a raw `ref_geo.bin` (or `.bin.gz`) on disk (e.g.
`/tmp/ref_geo.bin`) and press **Load**.

The raw `ref_geo_r60.bin` is ~110 MB (over Git's per-file push limit), which is
why the bundled copy is gzip-compressed (it decompresses at load).

## Controls (Free-Flight)

- **Drag** — look around
- **WASD / arrows** — move
- **Q / E** (or Page Up/Down) — up / down
- **Scroll** — dolly

## How it maps to the code

- `buildSakuraScene(viewer, geoPath)` — ports `render_realtime_ref.dart`'s
  scene setup: `refGeoToPacked` (with the CPU `SunShadowMap`, multi-ramp, canopy
  no-receive-shadow), the `sakura_toon_rt` material, the `sky.dart` dome, the
  linear color grade, and the planet-surface spawn camera.
- The `ViewerWidget` (from `thermion_flutter`) owns the Thermion engine,
  texture binding, and the free-flight gesture manipulator.
