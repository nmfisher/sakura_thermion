# Thermion Sakura Flutter

Interactive Flutter viewer for the Sakura Crossing **realtime toon** scene. It
loads the reference's extracted geometry (`ref_geo*.bin`) into a live Thermion
viewport with the per-pixel cel material and painted sky — the same scene
`thermion_sakura_dart/bin/render_realtime_ref.dart` renders headless — and lets
you fly around it. This reference-geometry mode currently uses the legacy CPU
`SunShadowMap`. **Ported** mode assembles the Dart scene used by the fidelity
renderer, renders visible caster geometry into a light-space shadow texture,
samples that texture per pixel, and applies live depth ink, anime grade,
vignette, and FXAA through the `sakura_post` material.

## Run

```bash
cd thermion_sakura_flutter
flutter run -d linux      # or macos / windows
```

> Requires a real GPU / DRI render node (`/dev/dri/renderD128` on Linux).
> thermion_flutter's desktop GL path does not fall back to software rendering,
> so the app will not run inside a GPU-less container/CI. A clean Linux build
> from the pinned Git dependency currently stops during Thermion's CMake header
> discovery. The headless Dart renderer remains the supported CI render path.

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

- `buildSakuraScene(viewer, geo)` — loads extracted reference geometry with the
  legacy CPU `SunShadowMap`, multi-ramp cel shading, canopy no-receive-shadow,
  the `sky.dart` dome, linear color grade, and planet-surface spawn camera.
- `buildPortedFilamentScene(viewer)` — assembles the Dart-authored world and
  drives its per-pixel light-space shadow map and `sakura_post` finale.
- The `ViewerWidget` (from `thermion_flutter`) owns the Thermion engine,
  texture binding, and the free-flight gesture manipulator.
