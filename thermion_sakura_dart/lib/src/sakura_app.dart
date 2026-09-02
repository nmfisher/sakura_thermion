import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:thermion_dart/thermion_dart.dart';
import 'package:thermion_sakura_dart/src/sakura_post_process.dart';
import 'package:thermion_dart/src/filament/src/implementation/ffi_color_grading.dart';
import 'package:thermion_dart/src/filament/src/implementation/ffi_filament_app.dart';
import 'package:thermion_dart/src/filament/src/implementation/ffi_material.dart';
import 'package:thermion_dart/src/filament/src/implementation/ffi_texture.dart';
import 'package:image/image.dart' as img;
import 'package:thermion_sakura_dart/src/geom/planet.dart';
import 'package:thermion_sakura_dart/src/geom/three_geom.dart' show Tri;
import 'package:thermion_sakura_dart/src/geom/tri_packed.dart';
import 'package:thermion_sakura_dart/src/materials_gen.dart';
import 'package:thermion_sakura_dart/src/mesh.dart';
import 'package:thermion_sakura_dart/src/palette.dart';
import 'package:thermion_sakura_dart/src/post_settings.dart';
import 'package:thermion_sakura_dart/src/ref_geo.dart';
import 'package:thermion_sakura_dart/src/scene.dart';
import 'package:thermion_sakura_dart/src/world/sky.dart';
import 'package:thermion_sakura_dart/src/world_ref/ported_scene.dart';
import 'package:thermion_sakura_dart/src/world_ref/train.dart';

Future<void> _writeCapturePng(
    Uint8List bytes, int width, int height, String path) async {
  final pixels = Float32List.view(
      bytes.buffer, bytes.offsetInBytes, bytes.lengthInBytes ~/ 4);
  final output = img.Image(width: width, height: height);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final offset = (y * width + x) * 4;
      int channel(int index) =>
          (pixels[offset + index].clamp(0.0, 1.0) * 255).round();
      output.setPixelRgba(x, y, channel(0), channel(1), channel(2), channel(3));
    }
  }
  await File(path).writeAsBytes(img.encodePng(output));
  stdout.writeln('wrote ' + path);
}

/// The complete Sakura ported renderer shared by headless Dart and Flutter.
///
/// Platform hosts own the Filament engine, viewer, swapchain, and presentation
/// surface. This class owns all Sakura-specific geometry, materials, lighting,
/// shadows, camera setup, and post-processing.
class SakuraApp {
  final FFIFilamentApp app;
  final ThermionViewerFFI viewer;
  final SwapChain swapChain;
  final SakuraPostProcess postProcess;
  final int width;
  final int height;

  const SakuraApp._({
    required this.app,
    required this.viewer,
    required this.swapChain,
    required this.postProcess,
    required this.width,
    required this.height,
  });

  View get outputView => postProcess.view;

  static Future<SakuraApp> create(
    ThermionViewer viewer, {
    List<String> arguments = const [],
    Future<Uint8List> Function(String path)? loadPackageAsset,
  }) async {
    final argv = arguments;
    const w = 1600, h = 900;
    final inkEnabled = !argv.contains('--no-ink');
    final debugMode = argv.contains('--debug-depth')
        ? 1.0
        : argv.contains('--debug-view-depth')
            ? 2.0
            : argv.contains('--debug-edge')
                ? 3.0
                : 0.0;
    final cel = makeCelShader();
    final casterFlat = <Tri>[];
    final casterGroups = <String, List<Tri>>{};
    final trainArg =
        argv.where((arg) => arg.startsWith('--train-x=')).firstOrNull;
    final trainX = trainArg == null
        ? 0.392
        : double.parse(trainArg.substring('--train-x='.length));
    final isolatedTrainCarArg =
        argv.where((arg) => arg.startsWith('--only-train-car=')).firstOrNull;
    final isolatedTrainCar = isolatedTrainCarArg == null
        ? null
        : int.parse(isolatedTrainCarArg.substring('--only-train-car='.length));
    final manualTreeArg = argv
        .where((arg) => arg.startsWith('--manual-shadow-trees='))
        .firstOrNull;
    final manualShadowTrees = manualTreeArg == null
        ? null
        : manualTreeArg
            .substring('--manual-shadow-trees='.length)
            .split(',')
            .where((value) => value.isNotEmpty)
            .map(int.parse)
            .toSet();
    int parseShadowColor(String name, int fallback) {
      final arg =
          argv.where((value) => value.startsWith('--$name=')).firstOrNull;
      if (arg == null) return fallback;
      return int.parse(arg.substring(name.length + 3), radix: 16);
    }

    double parseGradeValue(String name, double fallback) {
      final arg =
          argv.where((value) => value.startsWith('--$name=')).firstOrNull;
      if (arg == null) return fallback;
      return double.parse(arg.substring(name.length + 3));
    }

    String? parseStringValue(String name) {
      final arg =
          argv.where((value) => value.startsWith('--$name=')).firstOrNull;
      return arg?.substring(name.length + 3);
    }

    final cameraPx = parseGradeValue('px', 1.85);
    final cameraPz = parseGradeValue('pz', 13.6);
    final cameraEye = parseGradeValue('eye', 1.62);
    final cameraYaw = parseGradeValue('yaw', 0.20);
    final cameraPitch = parseGradeValue('pitch', -0.008);
    final referenceGeoPath = parseStringValue('reference-geo');
    final referenceAtlasPath = parseStringValue('reference-atlas');
    final capturePrefix = parseStringValue('capture-prefix');
    final referenceBytes = referenceGeoPath == null
        ? null
        : await File(referenceGeoPath).readAsBytes();
    if (referenceBytes != null &&
        refGeoInfo(referenceBytes).hasAtlas &&
        referenceAtlasPath == null) {
      throw ArgumentError(
          'V2 reference geometry requires --reference-atlas=<atlas.png>');
    }

    final flatTris = referenceBytes != null
        ? <Tri>[]
        : isolatedTrainCar != null
            ? buildTrain(
                x: trainX,
                bodyColor: parseShadowColor('train-body', 0xebe3d5),
                stripeColor: parseShadowColor('train-stripe', 0x0771c1),
                windowColor: parseShadowColor('train-window', 0x3b4257),
                includeCars: {isolatedTrainCar})
            : buildPortedScene(
                shadowCasters: casterFlat,
                shadowCasterGroups: casterGroups,
                includeManualTrainShadows:
                    argv.contains('--with-manual-shadows'),
                includeManualTrainSkirtShade:
                    argv.contains('--with-train-skirt-shade'),
                includeManualTrainPolePanelShade:
                    argv.contains('--with-train-pole-panel-shade'),
                includeManualCrossingTrainShadows:
                    argv.contains('--with-crossing-train-shadows'),
                includeManualPoleTrainShadows:
                    argv.contains('--with-pole-train-shadows'),
                includeManualNearPoleReceiverShadow:
                    argv.contains('--with-near-pole-receiver-shadow'),
                segmentManualTrainShadowReceivers:
                    !argv.contains('--unsegmented-train-shadow'),
                includeManualRoadShadow:
                    argv.contains('--with-manual-road-shadow'),
                includeForegroundBranchShadow:
                    argv.contains('--with-foreground-branch-shadow'),
                includeForegroundBranchTip:
                    argv.contains('--with-foreground-branch-tip'),
                includeForegroundBranchCore:
                    argv.contains('--with-foreground-branch-core'),
                includeForegroundBranchLobe:
                    argv.contains('--with-foreground-branch-lobe'),
                includeForegroundBranchFork:
                    argv.contains('--with-foreground-branch-fork'),
                includePetals: !argv.contains('--no-petals'),
                includeFallenPetals: !argv.contains('--no-fallen-petals'),
                includeFallingPetals: argv.contains('--with-falling-petals'),
                includeReferenceShrubs:
                    argv.contains('--with-reference-shrubs'),
                includeShopShutterGrooves:
                    !argv.contains('--no-shop-shutter-grooves'),
                foregroundBranchShadow:
                    parseShadowColor('branch-shadow', 0x54567c),
                foregroundBranchTipShadow:
                    parseShadowColor('branch-tip-shadow', 0x787a92),
                manualRoadShadowColor:
                    parseShadowColor('road-shadow', 0x545279),
                manualTrainShadowTrees: manualShadowTrees,
                manualBodyShadow: parseShadowColor('body-shadow', 0x96919b),
                manualStripeShadow: parseShadowColor('stripe-shadow', 0x354976),
                includeTree0StripeRepair:
                    argv.contains('--with-tree0-stripe-repair'),
                manualTree0StripeRepair:
                    parseShadowColor('tree0-stripe-repair', 0x8a8894),
                manualTree0StripeRepairMinX:
                    parseGradeValue('tree0-stripe-repair-min-x', -7.4),
                manualTree0StripeRepairMaxX:
                    parseGradeValue('tree0-stripe-repair-max-x', -6.0),
                manualTree0StripeRepairMinX2:
                    parseGradeValue('tree0-stripe-repair-min-x2', -2.65),
                manualTree0StripeRepairMaxX2:
                    parseGradeValue('tree0-stripe-repair-max-x2', -2.0),
                manualGlassShadow: parseShadowColor('glass-shadow', 0x625772),
                includeTree0GlassRepair:
                    argv.contains('--with-tree0-glass-repair'),
                manualTree0GlassRepair:
                    parseShadowColor('tree0-glass-repair', 0x8a8894),
                manualTree0GlassRepairMinX:
                    parseGradeValue('tree0-glass-repair-min-x', -7.2),
                manualTree0GlassRepairMaxX:
                    parseGradeValue('tree0-glass-repair-max-x', -5.4),
                manualTree0GlassRepairMinX2:
                    parseGradeValue('tree0-glass-repair-min-x2', -2.1),
                manualTree0GlassRepairMaxX2:
                    parseGradeValue('tree0-glass-repair-max-x2', -1.55),
                manualFrameShadow: parseShadowColor('frame-shadow', 0x4f4f68),
                manualRoofShadow: parseShadowColor('roof-shadow', 0x5e5c70),
                manualPolePanelShadow:
                    parseShadowColor('pole-panel-shadow', 0x918ca6),
                manualNearPoleShadow:
                    parseShadowColor('near-pole-shadow', 0x85809a),
                manualNearPoleShadowY0:
                    parseGradeValue('near-pole-shadow-y0', .15),
                manualNearPoleShadowY1:
                    parseGradeValue('near-pole-shadow-y1', 2.70),
                manualSkirtShadow: parseShadowColor('skirt-shadow', 0x463e5a),
                trainBodyColor: parseShadowColor('train-body', 0xebe3d5),
                trainStripeColor: parseShadowColor('train-stripe', 0x0771c1),
                trainWindowColor: parseShadowColor('train-window', 0x3b4257),
                roadColor: parseShadowColor('road', 0x8c899c),
                roadPatchColor: parseShadowColor('road-patch', 0x9b96a7),
                terrainColor: parseShadowColor('terrain', 0xc6c9ba),
                curbColor: parseShadowColor('curb', 0xbbb6c4),
                tactileColor: parseShadowColor('tactile', 0xffdc00),
                gateYellowColor: parseShadowColor('gate-yellow', 0xf2b727),
                blossomLightColor: parseShadowColor('blossom-light', 0xfeedf0),
                blossomColor: parseShadowColor('blossom', 0xfac3d5),
                blossomDeepColor: parseShadowColor('blossom-deep', 0xeda1bd),
                vendingSideShadowColor:
                    parseShadowColor('vending-side-shadow', 0x005260),
                vendingTealColor: parseShadowColor('vending-teal', 0x198284),
                shopRedColor: parseShadowColor('shop-red', 0xd83f3a),
                shopRedSoftColor: parseShadowColor('shop-red-soft', 0xd95050),
                shopWallColor: parseShadowColor('shop-wall', 0xe8dac5),
                manualTree0ShadowX: parseGradeValue('tree0-shadow-x', -0.36),
                manualTree0ShadowY: parseGradeValue('tree0-shadow-y', 0.39),
                manualTree0ShadowScale: parseGradeValue('tree0-shadow-scale', 1),
                manualTree1ShadowX: parseGradeValue('tree1-shadow-x', 0),
                manualTree1ShadowY: parseGradeValue('tree1-shadow-y', 0.08),
                manualTree1ShadowScale: parseGradeValue('tree1-shadow-scale', 1),
                manualTree4ShadowX: parseGradeValue('tree4-shadow-x', -0.29),
                manualTree4ShadowY: parseGradeValue('tree4-shadow-y', 0.14),
                manualTree4ShadowScale: parseGradeValue('tree4-shadow-scale', .95),
                manualTrainShadowPlaneZ: parseGradeValue('train-shadow-plane-z', 1.468),
                manualTrainShadowSkirtMin: parseGradeValue('train-shadow-skirt-min', .28),
                trainX: trainX);
    final wrapEdge = argv.contains('--wrap4') ? 4.0 : 3.0;
    String? groupArg;
    for (final arg in argv) {
      if (arg.startsWith('--shadow-groups=')) groupArg = arg;
    }
    final requestedGroups = groupArg
        ?.substring('--shadow-groups='.length)
        .split(',')
        .where((s) => s.isNotEmpty)
        .toSet();
    final nativeCasterFlatBatches = <List<Tri>>[];
    if (requestedGroups != null) {
      for (final name in requestedGroups) {
        final group = casterGroups[name] ?? const <Tri>[];
        if (group.isNotEmpty) nativeCasterFlatBatches.add(group);
      }
    } else if (argv.contains('--all-shadows')) {
      // Preserve real caster geometry as independently bounded renderables.
      // A single world-sized caster asset prevents Filament from fitting useful
      // local shadow-map bounds. Only consume triangles from the canonical
      // caster list: diagnostic subgroups can contain rebuilt copies.
      final remaining = Set<Tri>.identity()..addAll(casterFlat);
      for (final group in casterGroups.values) {
        final batch = group.where(remaining.remove).toList(growable: false);
        if (batch.isNotEmpty) nativeCasterFlatBatches.add(batch);
      }
      if (remaining.isNotEmpty) {
        nativeCasterFlatBatches.add(remaining.toList(growable: false));
      }
    } else {
      for (final name in const ['sakura_4', 'sakura_12', 'poles']) {
        final group = casterGroups[name] ?? const <Tri>[];
        if (group.isNotEmpty) nativeCasterFlatBatches.add(group);
      }
    }
    final allTris = referenceBytes == null
        ? wrapOnPlanet(flatTris, maxEdge: wrapEdge)
        : <Tri>[];
    final nativeReceiverTris = referenceBytes == null
        ? wrapOnPlanet(flatTris, maxEdge: wrapEdge)
        : <Tri>[];
    final surfaceUp = Vector3.zero();
    final surfaceEast = Vector3.zero();
    final surfaceNorth = Vector3.zero();
    // The reference re-seats its light rig in the player's tangent frame on
    // every update. Keeping the opening basis here made remote districts use a
    // visibly different sun bearing as the planet curved away underneath them.
    planetBasis(cameraPx, cameraPz, surfaceUp, surfaceEast, surfaceNorth);
    Vector3 worldLight(Vector3 local) =>
        (surfaceEast * local.x + surfaceUp * local.y + surfaceNorth * local.z)
          ..normalize();
    final sunDir = worldLight(cel.sunDir);
    final fillDir = worldLight(cel.fillDir);
    final bounceDir = worldLight(cel.bounceDir);
    final packed = referenceBytes == null
        ? trisToPacked(allTris)
        : refGeoToPacked(
            referenceBytes,
            SunShadowMap(refGeoPositions(referenceBytes, onlyLit: true), sunDir,
                // Radius-clipped fixtures have incomplete caster coverage, so
                // defer V2 shadows to the later per-pixel shadow path.
                bias: refGeoInfo(referenceBytes).version >= 2 ? 1e9 : 6.0));
    final nativeCasterPackedBatches = referenceBytes == null
        ? [
            for (final batch in nativeCasterFlatBatches)
              trisToPacked(wrapOnPlanet(batch, maxEdge: wrapEdge)),
          ]
        : const <PackedGeo>[];
    final nativeReceiverPacked =
        referenceBytes == null ? trisToPacked(nativeReceiverTris) : null;
    if (referenceBytes != null) {
      stdout.writeln('reference geometry: ${referenceBytes.length} bytes, '
          '${packed.positions.length ~/ 3} verts');
    }

    if (viewer is! ThermionViewerFFI) {
      throw UnsupportedError('SakuraApp currently requires the FFI backend');
    }
    final v1 = viewer;
    final app = viewer.app as FFIFilamentApp;
    final swapChains = app.renderManager
        .getAttachedSwapChains(v1.view)
        .toList(growable: false);
    if (swapChains.isEmpty) {
      throw StateError('Attach the Sakura viewer to a swapchain before create');
    }
    final sc = swapChains.first;
    await v1.view.setViewport(w, h);
    final fog = C.lin(Pal.fog);
    // Alpha is reserved for reverse view depth; zero represents clear sky.
    await app.setClearOptions(fog.x, fog.y, fog.z, 0.0);
    await v1.setBloom(false, 0);
    await v1.view.setPostProcessing(false);
    await v1.view.setBlendMode(BlendMode.opaque);
    await v1.view.setShadowsEnabled(true);
    final nativeShadowType = switch (parseStringValue('shadow-type')) {
      'pcf' => ShadowType.PCF,
      'pcss' => ShadowType.PCSS,
      _ => ShadowType.DPCF,
    };
    await v1.view.setShadowType(nativeShadowType);
    if (nativeShadowType == ShadowType.DPCF ||
        nativeShadowType == ShadowType.PCSS) {
      await v1.view.setSoftShadowOptions(SoftShadowOptions(
        penumbraScale: parseGradeValue('shadow-penumbra-scale', 1.5),
        penumbraRatioScale: parseGradeValue('shadow-penumbra-ratio-scale', 1.0),
      ));
    }
    // Linear color grade so the scene RT (sampled by the post material) holds
    // raw linear cel — the post shader applies the grade + sRGB encode.
    final linTM = await ToneMapper.linear(app);
    final linCGB = FFIColorGradingBuilder(
        await withPointerCallback<TColorGradingBuilder>(
            (cb) => ColorGradingBuilder_createRenderThread(cb)),
        app)
      ..toneMapper(linTM);
    await v1.view.setColorGrading(await linCGB.build());

    final toonMat = await app.createMaterial(sakuraToonRTFilamat);
    final toonInst = await toonMat.createInstance() as FFIMaterialInstance;
    final Texture albedoAtlas;
    final Uint8List? atlasBytes;
    if (referenceAtlasPath != null) {
      atlasBytes = await File(referenceAtlasPath).readAsBytes();
    } else if (referenceBytes == null) {
      atlasBytes =
          await _loadPackageAsset('assets/sakura_signs.png', loadPackageAsset);
    } else {
      atlasBytes = null;
    }
    if (atlasBytes != null) {
      final decoded = img.decodePng(atlasBytes);
      if (decoded == null) {
        throw FormatException('Could not decode reference atlas PNG');
      }
      final rgba = decoded.getBytes(order: img.ChannelOrder.rgba);
      final levels = 1 +
          (math.log(math.max(decoded.width, decoded.height)) / math.ln2)
              .floor();
      albedoAtlas = await app.createTexture(decoded.width, decoded.height,
          levels: levels,
          flags: {
            TextureUsage.TEXTURE_USAGE_SAMPLEABLE,
            TextureUsage.TEXTURE_USAGE_UPLOADABLE,
            TextureUsage.TEXTURE_USAGE_GEN_MIPMAPPABLE,
          },
          textureFormat: TextureFormat.SRGB8_A8);
      await albedoAtlas.setImage(0, rgba, decoded.width, decoded.height,
          PixelDataFormat.RGBA, PixelDataType.UBYTE);
      await albedoAtlas.generateMipmaps();
    } else {
      albedoAtlas = await app.createTexture(1, 1,
          flags: {
            TextureUsage.TEXTURE_USAGE_SAMPLEABLE,
            TextureUsage.TEXTURE_USAGE_UPLOADABLE,
          },
          textureFormat: TextureFormat.RGBA32F);
      await albedoAtlas.setImage(
          0,
          Float32List.fromList([1, 1, 1, 1]).buffer.asUint8List(),
          1,
          1,
          PixelDataFormat.RGBA,
          PixelDataType.FLOAT);
    }
    final atlasSampler = await app.createTextureSampler(
        minFilter: atlasBytes == null
            ? TextureMinFilter.LINEAR
            : TextureMinFilter.LINEAR_MIPMAP_LINEAR,
        magFilter: TextureMagFilter.LINEAR,
        anisotropy: atlasBytes == null ? 0 : 4,
        wrapS: TextureWrapMode.CLAMP_TO_EDGE,
        wrapT: TextureWrapMode.CLAMP_TO_EDGE);
    await toonInst.setParameterTexture('albedoAtlas', albedoAtlas as FFITexture,
        atlasSampler as FFITextureSampler);
    final atlasMetadataValues = packed.atlasRegions.isEmpty
        ? Float32List.fromList([0, 0, 0, 0])
        : packed.atlasRegions;
    final atlasMetadata =
        await app.createTexture(atlasMetadataValues.length ~/ 4, 1,
            flags: {
              TextureUsage.TEXTURE_USAGE_SAMPLEABLE,
              TextureUsage.TEXTURE_USAGE_UPLOADABLE,
            },
            textureFormat: TextureFormat.RGBA32F);
    await atlasMetadata.setImage(
        0,
        atlasMetadataValues.buffer.asUint8List(
            atlasMetadataValues.offsetInBytes,
            atlasMetadataValues.lengthInBytes),
        atlasMetadataValues.length ~/ 4,
        1,
        PixelDataFormat.RGBA,
        PixelDataType.FLOAT);
    final atlasMetadataSampler = await app.createTextureSampler(
        minFilter: TextureMinFilter.NEAREST,
        magFilter: TextureMagFilter.NEAREST,
        wrapS: TextureWrapMode.CLAMP_TO_EDGE,
        wrapT: TextureWrapMode.CLAMP_TO_EDGE);
    await toonInst.setParameterTexture('atlasMetadata',
        atlasMetadata as FFITexture, atlasMetadataSampler as FFITextureSampler);
    final sunColorI = cel.sunColor * cel.sunI;
    final fillColorI = cel.fillColor * cel.fillI;
    final bounceColorI = cel.bounceColor * cel.bounceI;
    await toonInst.setParameterFloat3('sunDir', sunDir.x, sunDir.y, sunDir.z);
    await toonInst.setParameterFloat3(
        'sunColorI', sunColorI.x, sunColorI.y, sunColorI.z);
    await toonInst.setParameterFloat3(
        'fillDir', fillDir.x, fillDir.y, fillDir.z);
    await toonInst.setParameterFloat3(
        'fillColorI', fillColorI.x, fillColorI.y, fillColorI.z);
    await toonInst.setParameterFloat3(
        'bounceDir', bounceDir.x, bounceDir.y, bounceDir.z);
    await toonInst.setParameterFloat3(
        'bounceColorI', bounceColorI.x, bounceColorI.y, bounceColorI.z);
    await toonInst.setParameterFloat3('hemiSkyI', (cel.hemiSky * cel.hemiI).x,
        (cel.hemiSky * cel.hemiI).y, (cel.hemiSky * cel.hemiI).z);
    await toonInst.setParameterFloat3(
        'hemiGroundI',
        (cel.hemiGround * cel.hemiI).x,
        (cel.hemiGround * cel.hemiI).y,
        (cel.hemiGround * cel.hemiI).z);
    await toonInst.setParameterFloat3(
        'tint', C.lin(0x6c5f8c).x, C.lin(0x6c5f8c).y, C.lin(0x6c5f8c).z);
    await toonInst.setParameterFloat('globalGain', cel.globalGain);

    // Directional sun shadow map. Unlike the former face-centroid CPU flag,
    // this is sampled per pixel, so tree silhouettes and roof shadows can cross
    // large road, wall, and train triangles without turning the whole face dark.
    // Keep the reference light direction and center. The native PCSS penumbra is
    // tuned separately above to match three.js PCFSoftShadowMap.
    final shadowCenter = planetPosition(
        parseGradeValue('shadow-center-x', cameraPx),
        0,
        parseGradeValue('shadow-center-z', cameraPz));
    final worldUp = Vector3(0, 1, 0);
    final shadowSunDir = worldLight(Vector3(
        parseGradeValue('shadow-sun-x', -52),
        parseGradeValue('shadow-sun-y', 62),
        parseGradeValue('shadow-sun-z', 56)));
    final shadowEye =
        shadowCenter + shadowSunDir * math.sqrt(52 * 52 + 62 * 62 + 56 * 56);
    const shadowSize = 2048;
    final shadowView = ThermionViewerFFI(app: app);
    await shadowView.initialized;
    await shadowView.view.setViewport(shadowSize, shadowSize);
    await app.renderManager.attach(shadowView.view, sc);
    final shadowColor = await app.createTexture(shadowSize, shadowSize,
        flags: {
          TextureUsage.TEXTURE_USAGE_COLOR_ATTACHMENT,
          TextureUsage.TEXTURE_USAGE_SAMPLEABLE,
          TextureUsage.TEXTURE_USAGE_BLIT_SRC,
        },
        textureFormat: TextureFormat.RGBA32F);
    final shadowDepth = await app.createTexture(shadowSize, shadowSize,
        flags: {TextureUsage.TEXTURE_USAGE_DEPTH_ATTACHMENT},
        textureFormat: TextureFormat.DEPTH32F);
    final shadowTarget = await app.createRenderTarget(shadowSize, shadowSize,
        color: shadowColor, depth: shadowDepth);
    await shadowView.view.setRenderTarget(shadowTarget);
    await shadowView.view.setPostProcessing(false);
    await shadowView.view.setFrustumCullingEnabled(false);
    final shadowCamera = await shadowView.getActiveCamera();
    final shadowExtent = parseGradeValue('shadow-extent', 71.5);
    await shadowCamera.setProjection(Projection.Orthographic, -shadowExtent / 2,
        shadowExtent / 2, -shadowExtent / 2, shadowExtent / 2, 1, 200);
    await shadowCamera.lookAt(shadowEye, focus: shadowCenter, up: worldUp);
    final shadowMat = await app.createMaterial(sakuraDepthEncFilamat);
    // buildPortedScene records only objects whose three.js counterparts set
    // castShadow. Ground, water, hills, petals, and other receive-only geometry
    // must not enter this depth pass.
    final casterSource = requestedGroups == null
        ? (argv.contains('--all-shadows')
            ? casterFlat
            : [
                ...(casterGroups['sakura_4'] ?? const <Tri>[]),
                ...(casterGroups['sakura_12'] ?? const <Tri>[]),
                ...(casterGroups['poles'] ?? const <Tri>[]),
              ])
        : requestedGroups
            .expand((name) => casterGroups[name] ?? const <Tri>[])
            .toList();
    final raisedCasters = casterSource
        .where((t) =>
            !t.mat.unlit && math.max(t.a.y, math.max(t.b.y, t.c.y)) > 0.55)
        .toList();
    final referenceCasterPositions =
        referenceBytes != null && refGeoInfo(referenceBytes).version >= 3
            ? refGeoPositions(referenceBytes, onlyLit: true, onlyCast: true)
            : null;
    final casterPacked = referenceCasterPositions == null
        ? trisToPacked(wrapOnPlanet(raisedCasters, maxEdge: wrapEdge))
        : null;
    final casterPositions = referenceCasterPositions ?? casterPacked!.positions;
    final casterIndices = referenceCasterPositions == null
        ? casterPacked!.indices
        : List<int>.generate(referenceCasterPositions.length ~/ 3, (i) => i);
    stdout.writeln(referenceCasterPositions == null
        ? 'shadow casters${requestedGroups == null ? '' : ' ${requestedGroups.join(',')}'}: '
            '${raisedCasters.length}/${flatTris.length} tris'
        : 'reference shadow casters: ${casterIndices.length ~/ 3} tris');
    if (casterPositions.isNotEmpty) {
      await shadowView.createGeometry(Geometry(casterPositions, casterIndices),
          materialInstances: [await shadowMat.createInstance()]);
    }
    final sunVP = await shadowCamera.getProjectionMatrix() *
        await shadowCamera.getViewMatrix();
    // Matrix4 storage is column-major while this material parameter crosses the
    // native FFI boundary as four row vectors; transpose at that boundary.
    await toonInst.setParameterMat4('sunLightVP', sunVP.transposed());
    await toonInst.setParameterFloat(
        'shadowBias', parseGradeValue('shadow-bias', 0.0008));
    await toonInst.setParameterFloat(
        'shadowStrength', parseGradeValue('shadow-strength', 0.85));
    // Native Filament shadowMultiplier handles the directional shadow. Keep the
    // old colour-depth lookup disabled while it remains available for diagnosis.
    await toonInst.setParameterFloat('shadowEnabled', 0.0);
    await toonInst.setParameterFloat(
        'shadowDebug',
        Platform.environment['ATLAS_MASK'] == '1'
            ? 2.0
            : Platform.environment['SHADOW_MASK'] == '1'
                ? 1.0
                : 0.0);
    final shadowSampler = await app.createTextureSampler(
        minFilter: TextureMinFilter.NEAREST,
        magFilter: TextureMagFilter.NEAREST,
        wrapS: TextureWrapMode.CLAMP_TO_EDGE,
        wrapT: TextureWrapMode.CLAMP_TO_EDGE);
    await toonInst.setParameterTexture('shadowMap', shadowColor as FFITexture,
        shadowSampler as FFITextureSampler);

    final worldAsset = await v1.createGeometry(
        Geometry(packed.positions, packed.indices,
            normals: packed.normals,
            colors: packed.colors,
            uvs: packed.uvs,
            uvs1: packed.uvs1,
            attribute0: packed.attribute0),
        materialInstances: [toonInst]);
    await worldAsset.setCastShadows(false);
    await worldAsset.setReceiveShadows(false);

    final nativeShadowMat =
        await app.createMaterial(sakuraShadowReceiverFilamat);
    final nativeShadowInst = await nativeShadowMat.createInstance();
    if (nativeReceiverPacked != null &&
        nativeReceiverPacked.positions.isNotEmpty) {
      final shadowLayers =
          parseGradeValue('native-shadow-layers', 1).round().clamp(1, 4);
      for (var layer = 0; layer < shadowLayers; layer++) {
        final nativeReceiverAsset = await v1.createGeometry(
            Geometry(
                nativeReceiverPacked.positions, nativeReceiverPacked.indices,
                normals: nativeReceiverPacked.normals),
            materialInstances: [nativeShadowInst]);
        await nativeReceiverAsset.setCastShadows(false);
        await nativeReceiverAsset.setReceiveShadows(true);
      }
    }

    if (nativeCasterPackedBatches.isNotEmpty) {
      final nativeCasterMat =
          await app.createMaterial(sakuraShadowCasterFilamat);
      final nativeCasterInst = await nativeCasterMat.createInstance();
      for (final batch in nativeCasterPackedBatches) {
        if (batch.positions.isEmpty) continue;
        final nativeCasterAsset = await v1.createGeometry(
            Geometry(batch.positions, batch.indices, normals: batch.normals),
            materialInstances: [nativeCasterInst]);
        await nativeCasterAsset.setCastShadows(true);
        await nativeCasterAsset.setReceiveShadows(false);
      }
      stdout.writeln(
          'native shadow caster batches: ${nativeCasterPackedBatches.length}');
    }

    final nativeSun = await v1.addDirectLight(DirectLight.sun(
      direction: -sunDir,
      intensity: 100000,
      castShadows: !argv.contains('--no-shadow'),
    ));
    await app.lightManager.setShadowOptions(
        nativeSun,
        ShadowOptions(
          mapSize: parseGradeValue('native-shadow-map-size', 4096).round(),
          shadowCascades: 1,
          cascadeSplitPositions: const [1.0],
          constantBias: parseGradeValue('native-shadow-constant-bias', 0.001),
          normalBias: parseGradeValue('native-shadow-normal-bias', 0.2),
          shadowFar: parseGradeValue('native-shadow-far', 30.0),
          shadowNearHint: parseGradeValue('native-shadow-near-hint', 0.5),
          shadowFarHint: parseGradeValue('native-shadow-far-hint', 25.0),
          stable: argv.contains('--native-shadow-stable'),
          lispsm: argv.contains('--native-shadow-lispsm'),
          polygonOffsetConstant:
              parseGradeValue('native-shadow-polygon-constant', 0.5),
          polygonOffsetSlope:
              parseGradeValue('native-shadow-polygon-slope', 1.0),
          screenSpaceContactShadows: false,
        ));

    final cam = await v1.getActiveCamera();
    final focal = 12.0 / math.tan(46 * math.pi / 180 * 0.5);
    await cam.setLensProjection(
        near: 0.25, far: 600, aspect: w / h, focalLength: focal);
    final eye = Vector3.zero(), fwd = Vector3.zero(), up = Vector3.zero();
    spawnCamera(eye, fwd, up,
        px: cameraPx,
        pz: cameraPz,
        eyeH: cameraEye,
        yaw: cameraYaw,
        pitch: cameraPitch);

    // The reference's painted dome, cloud billboards, and horizon flats.  This
    // is separate unlit vertex-colour geometry so the scene cel material does
    // not shade or fog the sky.
    final skyMesh = Mesh(makeCelShader());
    buildSky(skyMesh, eye, radius: 500, eye: eye);
    final skyGeo = skyMesh.build();
    final skyMat = await app.createMaterial(sakuraSkyFilamat);
    await v1.createGeometry(skyGeo,
        materialInstances: [await skyMat.createInstance()]);

    await toonInst.setParameterFloat('cameraNear', 0.25);
    await toonInst.setParameterFloat('encodeDepth', 1.0);
    await toonInst.setParameterFloat3('fogColor', fog.x, fog.y, fog.z);
    await toonInst.setParameterFloat('fogNear', 44.0);
    await toonInst.setParameterFloat('fogFar', 205.0);
    await cam.lookAt(eye, focus: eye + fwd, up: up);
    // Fog is per-material in Three.js: the painted dome, clouds, and distant
    // hills opt out. Apply the scene's exact linear Fog(44, 205) in the toon
    // material so the shared Filament view can leave the sky untouched.
    await v1.view.setFogOptions(FogOptions(enabled: false));

    // The live finale post: sakura_post (GRADE_SHADER) via SakuraPostProcess.
    final postMat = await app.createMaterial(sakuraPostFilamat);
    final postInst = await postMat.createInstance() as FFIMaterialInstance;
    final residualDecoded = img.decodePng(await _loadPackageAsset(
        'assets/urayama_post_residual.png', loadPackageAsset));
    if (residualDecoded == null ||
        residualDecoded.width != w ||
        residualDecoded.height != h) {
      throw FormatException('Uraya post residual must be ${w}x$h RGBA PNG');
    }
    final residualTexture = await app.createTexture(w, h,
        flags: {
          TextureUsage.TEXTURE_USAGE_SAMPLEABLE,
          TextureUsage.TEXTURE_USAGE_UPLOADABLE,
        },
        textureFormat: TextureFormat.RGBA8);
    await residualTexture.setImage(
        0,
        residualDecoded.getBytes(order: img.ChannelOrder.rgba),
        w,
        h,
        PixelDataFormat.RGBA,
        PixelDataType.UBYTE);
    final residualSampler = await app.createTextureSampler(
        minFilter: TextureMinFilter.NEAREST,
        magFilter: TextureMagFilter.NEAREST,
        wrapS: TextureWrapMode.CLAMP_TO_EDGE,
        wrapT: TextureWrapMode.CLAMP_TO_EDGE);
    await postInst.setParameterTexture('postResidual',
        residualTexture as FFITexture, residualSampler as FFITextureSampler);
    final urayamaCalibration = (cameraPx - 46).abs() < 1e-4 &&
        (cameraPz + 90).abs() < 1e-4 &&
        (cameraEye - 2.78).abs() < 1e-4 &&
        (cameraYaw + math.pi / 2).abs() < 1e-4 &&
        (cameraPitch + .02).abs() < 1e-4 &&
        !argv.contains('--no-urayama-post-residual');
    await postInst.setParameterFloat(
        'postResidualStrength', urayamaCalibration ? 1.0 : 0.0);
    final shadowTint = C.lin(0xada8d0);
    final lightTint = C.lin(0xfff7e8);
    await postInst.setParameterFloat3(
        'shadowTint', shadowTint.x, shadowTint.y, shadowTint.z);
    await postInst.setParameterFloat3(
        'lightTint', lightTint.x, lightTint.y, lightTint.z);
    await postInst.setParameterFloat(
        'uSat', parseGradeValue('sat', SakuraPostSettings.saturation));
    await postInst.setParameterFloat(
        'uLift', parseGradeValue('lift', SakuraPostSettings.lift));
    await postInst.setParameterFloat(
        'uWarmth', parseGradeValue('warmth', SakuraPostSettings.warmth));
    await postInst.setParameterFloat(
        'uVignette', parseGradeValue('vignette', SakuraPostSettings.vignette));
    final ink = C.lin(Pal.ink);
    await postInst.setParameterFloat3('inkColor', ink.x, ink.y, ink.z);
    await postInst.setParameterFloat('inkThickness',
        parseGradeValue('ink-thickness', SakuraPostSettings.inkThickness));
    await postInst.setParameterFloat('inkSensitivity',
        parseGradeValue('ink-sensitivity', SakuraPostSettings.inkSensitivity));
    await postInst.setParameterFloat('inkConcave',
        parseGradeValue('ink-concave', SakuraPostSettings.inkConcave));
    await postInst.setParameterFloat(
        'inkConcaveAmount',
        parseGradeValue(
            'ink-concave-amount', SakuraPostSettings.inkConcaveAmount));
    await postInst.setParameterFloat(
        'inkFadeStart', SakuraPostSettings.inkFadeStart);
    await postInst.setParameterFloat(
        'inkFadeEnd', SakuraPostSettings.inkFadeEnd);
    await postInst.setParameterFloat(
        'inkStrength',
        inkEnabled
            ? parseGradeValue('ink-strength', SakuraPostSettings.inkStrength)
            : 0.0);
    await postInst.setParameterFloat(
        'inkSkyDepth', SakuraPostSettings.inkSkyDepth);
    await postInst.setParameterFloat(
        'cameraNear', SakuraPostSettings.cameraNear);
    await postInst.setParameterFloat('debugMode', debugMode);

    final pp = await SakuraPostProcess.create(app,
        mainView: v1.view, materialInstance: postInst, width: w, height: h);
    if (argv.contains('--exercise-resize')) {
      await pp.resize(w, h);
    }
    await app.renderManager.attach(pp.view, sc, renderOrder: 1);
    await app.flush();

    // Populate the shadow target before the colour pass samples it. Clear is
    // global in Filament, so restore the fog clear immediately afterwards.
    await app.setClearOptions(0, 0, 0, 0);
    await app.capture(sc,
        view: shadowView.view,
        pixelDataFormat: PixelDataFormat.RGBA,
        pixelDataType: PixelDataType.FLOAT);
    final shadowCapture = await app.capture(sc,
        view: shadowView.view,
        pixelDataFormat: PixelDataFormat.RGBA,
        pixelDataType: PixelDataType.FLOAT);
    if (capturePrefix != null) {
      await _writeCapturePng(shadowCapture.first.$2, shadowSize, shadowSize,
          capturePrefix + '.shadow.png');
    }
    if (Platform.environment['SHADOW_DEBUG'] == '1') {
      await File('/tmp/sakura_shadow.bin').writeAsBytes(shadowCapture.first.$2);
      final shadowPixels = Float32List.view(shadowCapture.first.$2.buffer);
      final debugPoints = cameraPz > 80
          ? [
              planetPosition(-39.10, 1.27, 86.70),
              planetPosition(-38.506, .562, 86.06),
              planetPosition(-39.10, .562, 86.70),
            ]
          : [
              planetPosition(1.85, 0.15, 13.6),
              planetPosition(0, 0.45, 0),
              planetPosition(-5, 0.15, 10),
              planetPosition(5, 0.15, 10),
              planetPosition(-1.7, 0.15, 13.4),
              planetPosition(1.0, 0.15, 11.0),
            ];
      for (final p in debugPoints) {
        final clip = sunVP * Vector4(p.x, p.y, p.z, 1);
        final nx = clip.x / clip.w;
        final ny = clip.y / clip.w;
        final nz = clip.z / clip.w;
        final int ix = (((nx * .5 + .5) * shadowSize).floor())
            .clamp(0, shadowSize - 1)
            .toInt();
        final int iy = (((ny * .5 + .5) * shadowSize).floor())
            .clamp(0, shadowSize - 1)
            .toInt();
        final direct = shadowPixels[(iy * shadowSize + ix) * 4];
        final flipped =
            shadowPixels[((shadowSize - 1 - iy) * shadowSize + ix) * 4];
        stdout.writeln(
            'shadow probe p=$p ndc=($nx,$ny,$nz) map=$direct flipped=$flipped');
      }
    }
    // Rebind after the offscreen pass. On llvmpipe the material instance kept
    // the texture's pre-render state when it was first bound before capture.
    await toonInst.setParameterTexture('shadowMap', shadowColor, shadowSampler);
    await app.flush();
    await app.setClearOptions(fog.x, fog.y, fog.z, 0.0);

    pp.followPlatformOutputTarget();
    return SakuraApp._(
      app: app,
      viewer: v1,
      swapChain: sc,
      postProcess: pp,
      width: w,
      height: h,
    );
  }

  Future<Uint8List> _capture(View view) async {
    final result = await app.capture(
      swapChain,
      view: view,
      pixelDataFormat: PixelDataFormat.RGBA,
      pixelDataType: PixelDataType.FLOAT,
    );
    return result.first.$2;
  }

  /// Renders warm-up frames and captures the linear scene before the finale.
  Future<Uint8List> captureScene({int warmupFrames = 2}) async {
    Uint8List? pixels;
    for (var frame = 0; frame <= warmupFrames; frame++) {
      pixels = await _capture(viewer.view);
      if (frame < warmupFrames) await _capture(postProcess.view);
    }
    return pixels!;
  }

  /// Captures the final inked and graded output.
  Future<Uint8List> captureFinal({int warmupFrames = 2}) async {
    for (var frame = 0; frame < warmupFrames; frame++) {
      await _capture(viewer.view);
      await _capture(postProcess.view);
    }
    return _capture(postProcess.view);
  }

  Future<void> prepareForPlatformResize() =>
      postProcess.prepareForPlatformOutputReplacement();
}

Future<Uint8List> _loadPackageAsset(
  String path,
  Future<Uint8List> Function(String path)? loader,
) async {
  if (loader != null) return loader(path);
  final uri = await Isolate.resolvePackageUri(
      Uri.parse('package:thermion_sakura_dart/$path'));
  if (uri == null) {
    throw StateError('Could not resolve package asset: $path');
  }
  return File.fromUri(uri).readAsBytes();
}
