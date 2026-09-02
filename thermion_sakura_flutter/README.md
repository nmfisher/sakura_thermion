# Thermion Sakura Flutter

Interactive Flutter viewer for Sakura Crossing. In the default **Ported** mode,
Flutter creates the platform Thermion viewer and passes it directly to
`SakuraApp.create(viewer)`. This is the same application entry point used by
the maximum-fidelity Dart renderer: geometry, camera, lighting, native Filament
shadow pass, depth ink, anime grade, vignette, and FXAA are shared rather than
reimplemented by the Flutter wrapper.

The Flutter host enables Sakura's shared runtime mode: the train circles the
planet at the reference speed, the crossing booms close and reopen from the
train's approach distance, falling blossom drifts in independently phased
groups, and the walking camera is constrained to the planet terrain. The
reference start/pause card is shown at launch and returns with Escape.

The optional reference-geometry mode loads extracted `ref_geo*.bin` geometry
into a live Thermion viewport. It remains a separate diagnostic path and uses
the legacy CPU `SunShadowMap`.

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

## Controls

- **Drag** — look around
- **WASD / arrows** — move
- **Scroll** — dolly
- **Escape** — pause / resume menu

## How it maps to the code

- `buildSakuraScene(viewer, geo)` — loads extracted reference geometry with the
  legacy CPU `SunShadowMap`, multi-ramp cel shading, canopy no-receive-shadow,
  the `sky.dart` dome, linear color grade, and planet-surface spawn camera.
- `SakuraApp.create(viewer)` — constructs the complete Dart-authored fidelity
  renderer. `bin/render_post.dart` and this Flutter app invoke this same API.
- The `ViewerWidget` (from `thermion_flutter`) owns the Thermion engine,
  texture binding, and the free-flight gesture manipulator.
