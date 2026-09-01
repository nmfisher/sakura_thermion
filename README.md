# Sakura Thermion

A Dart and Flutter port of Sakura Crossing using Thermion/Filament.

## Packages

- `thermion_sakura_dart`: scene generation, geometry, shaders, post-processing, and fidelity tools.
- `thermion_sakura_dart/bin`: headless native renderer used for fidelity work.
- `thermion_sakura_flutter`: interactive Flutter desktop application.

Thermion dependencies are pinned to commit `d10b1a891df324a17c772e5f73c382e98b3e2a06`.

## Run the Flutter app

Install Flutter and the platform toolchain, then:

```sh
cd thermion_sakura_flutter
flutter pub get
flutter run -d macos   # or linux / windows
```

The bundled radius-60 scene loads automatically.

## Rebuild Sakura materials

Materials are embedded in `thermion_sakura_dart/lib/src/materials_gen.dart`. Compile them with `matc` from the Filament version in `filament.version` (currently v1.75.0).

Download the matching SDK from the [Filament v1.75.0 release](https://github.com/google/filament/releases/tag/v1.75.0), then run:

```sh
cd thermion_sakura_dart
python3 tool/build_materials.py --filament-path /path/to/filament/bin
```

The default `--api all` embeds OpenGL, Vulkan, and Metal variants. For faster local iteration:

```sh
python3 tool/build_materials.py --filament-path /path/to/filament/bin --api metal
python3 tool/build_materials.py --filament-path /path/to/filament/bin --only sakura_toon_rt
```

On ARM64 Linux, the official Linux SDK contains x86-64 tools. The builder automatically uses `qemu-x86_64-static` with `/usr/x86_64-linux-gnu`; install `qemu-user-static`, `libc6-amd64-cross`, and `libstdc++6-amd64-cross` first.

After regeneration:

```sh
dart format thermion_sakura_dart/lib/src/materials_gen.dart
dart analyze thermion_sakura_dart/lib/src/materials_gen.dart
```

## Headless fidelity render

On Linux with Xvfb and an OpenGL software or hardware renderer:

```sh
cd thermion_sakura_dart
dart pub get
python3 tool/render_fidelity_suite.py --only yonchome_hall
```

See `thermion_sakura_dart/README.md` for the full fidelity workflow and implementation notes.

## Validation status

- `thermion_sakura_dart` resolves their pinned Git dependencies and pass scoped Dart analysis.
- `thermion_sakura_flutter` resolves dependencies and completes Flutter analysis with informational lints only.
- A clean Linux Flutter build currently stops in Thermion CMake header discovery when Thermion is consumed as a Git dependency. This is upstream integration behavior, not a Sakura material or Dart compilation error.
