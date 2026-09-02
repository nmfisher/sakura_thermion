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
import 'package:thermion_sakura_dart/src/world_ref/hills.dart';
import 'package:thermion_sakura_dart/src/world_ref/petals.dart';
import 'package:thermion_sakura_dart/src/world_ref/ported_scene.dart';
import 'package:thermion_sakura_dart/src/world_ref/railway.dart';
import 'package:thermion_sakura_dart/src/world_ref/street.dart';
import 'package:thermion_sakura_dart/src/world_ref/train.dart';

/// Groups the flat authored world before planet wrapping so every resulting
/// Filament renderable has a local bounding box. A single map-sized renderable
/// prevents view-frustum culling even when only one street is visible.
List<List<Tri>> _spatialChunks(List<Tri> tris, {double size = 48.0}) {
  final chunks = <(int, int), List<Tri>>{};
  for (final tri in tris) {
    final center = tri.centroid;
    final key = ((center.x / size).floor(), (center.z / size).floor());
    (chunks[key] ??= <Tri>[]).add(tri);
  }
  return chunks.values.toList(growable: false);
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
  final _SakuraRuntime? _runtime;

  SakuraApp._({
    required this.app,
    required this.viewer,
    required this.swapChain,
    required this.postProcess,
    required this.width,
    required this.height,
    required _SakuraRuntime? runtime,
  }) : _runtime = runtime;

  View get outputView => postProcess.view;

  static Future<SakuraApp> create(
    ThermionViewer viewer, {
    List<String> arguments = const [],
    Future<Uint8List> Function(String path)? loadPackageAsset,
    bool runtimeAnimations = false,
    bool groundedCamera = false,
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
                includeTrain: !runtimeAnimations,
                includeCrossingBooms: !runtimeAnimations,
                includeActiveCrossingLamps: !runtimeAnimations,
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
                tactileColor: parseShadowColor('tactile', 0xf2c53d),
                gateYellowColor: parseShadowColor('gate-yellow', 0xf4c033),
                blossomLightColor: parseShadowColor('blossom-light', 0xfeedf0),
                blossomColor: parseShadowColor('blossom', 0xfac3d5),
                blossomDeepColor: parseShadowColor('blossom-deep', 0xeda1bd),
                vendingSideShadowColor:
                    parseShadowColor('vending-side-shadow', 0x075b6c),
                vendingTealColor: parseShadowColor('vending-teal', 0x2e9a98),
                shopRedColor: parseShadowColor('shop-red', 0xe0453f),
                shopRedSoftColor: parseShadowColor('shop-red-soft', 0xef6a60),
                shopWallColor: parseShadowColor('shop-wall', 0xf2e7d3),
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
    final flatWorldChunks = referenceBytes == null
        ? argv.contains('--no-spatial-chunks')
            ? <List<Tri>>[flatTris]
            : _spatialChunks(flatTris)
        : const <List<Tri>>[];
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
    final worldPackedChunks = referenceBytes == null
        ? [
            for (final chunk in flatWorldChunks)
              trisToPacked(wrapOnPlanet(chunk, maxEdge: wrapEdge)),
          ]
        : [
            refGeoToPacked(
                referenceBytes,
                SunShadowMap(
                    refGeoPositions(referenceBytes, onlyLit: true), sunDir,
                    // Radius-clipped fixtures have incomplete caster coverage,
                    // so defer V2 shadows to the later per-pixel shadow path.
                    bias: refGeoInfo(referenceBytes).version >= 2 ? 1e9 : 6.0)),
          ];
    final nativeCasterPackedBatches = referenceBytes == null
        ? [
            for (final batch in nativeCasterFlatBatches)
              trisToPacked(wrapOnPlanet(batch, maxEdge: wrapEdge)),
          ]
        : const <PackedGeo>[];
    final nativeReceiverPackedChunks =
        referenceBytes == null ? worldPackedChunks : const <PackedGeo>[];
    if (referenceBytes != null) {
      stdout.writeln('reference geometry: ${referenceBytes.length} bytes, '
          '${worldPackedChunks.single.positions.length ~/ 3} verts');
    } else {
      final vertices = worldPackedChunks.fold<int>(
          0, (total, chunk) => total + chunk.positions.length ~/ 3);
      stdout.writeln(
          'world geometry: ${worldPackedChunks.length} spatial chunks, $vertices verts');
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
    final atlasRegions = worldPackedChunks.first.atlasRegions;
    final atlasMetadataValues = atlasRegions.isEmpty
        ? Float32List.fromList([0, 0, 0, 0])
        : atlasRegions;
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

    // Native Filament shadowMultiplier handles the directional shadow. Keep the
    // legacy colour-depth lookup disabled. Its sampler must still be bound
    // because it remains declared in the compiled material.
    await toonInst.setParameterFloat('shadowEnabled', 0.0);
    await toonInst.setParameterFloat(
        'shadowDebug',
        Platform.environment['ATLAS_MASK'] == '1'
            ? 2.0
            : Platform.environment['SHADOW_MASK'] == '1'
                ? 1.0
                : 0.0);
    final unusedShadow = await app.createTexture(1, 1,
        flags: {TextureUsage.TEXTURE_USAGE_SAMPLEABLE},
        textureFormat: TextureFormat.RGBA8);
    final unusedShadowSampler = await app.createTextureSampler(
        minFilter: TextureMinFilter.NEAREST,
        magFilter: TextureMagFilter.NEAREST,
        wrapS: TextureWrapMode.CLAMP_TO_EDGE,
        wrapT: TextureWrapMode.CLAMP_TO_EDGE);
    await toonInst.setParameterTexture('shadowMap', unusedShadow as FFITexture,
        unusedShadowSampler as FFITextureSampler);

    for (final packed in worldPackedChunks) {
      if (packed.positions.isEmpty) continue;
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
    }

    final nativeShadowMat =
        await app.createMaterial(sakuraShadowReceiverFilamat);
    final nativeShadowInst = await nativeShadowMat.createInstance();
    if (nativeReceiverPackedChunks.isNotEmpty) {
      final shadowLayers =
          parseGradeValue('native-shadow-layers', 1).round().clamp(1, 4);
      for (var layer = 0; layer < shadowLayers; layer++) {
        for (final packed in nativeReceiverPackedChunks) {
          if (packed.positions.isEmpty) continue;
          final nativeReceiverAsset = await v1.createGeometry(
              Geometry(packed.positions, packed.indices,
                  normals: packed.normals),
              materialInstances: [nativeShadowInst]);
          await nativeReceiverAsset.setCastShadows(false);
          await nativeReceiverAsset.setReceiveShadows(true);
        }
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

    final runtime = runtimeAnimations && referenceBytes == null
        ? await _SakuraRuntime.create(v1, toonInst,
            groundedCamera: groundedCamera,
            animateTrain: !argv.contains('--no-runtime-train'),
            animateBooms: !argv.contains('--no-runtime-booms'),
            animatePetals: !argv.contains('--no-runtime-petals'),
            instancePetals: !argv.contains('--cpu-runtime-petals'),
            freezeWorld: argv.contains('--freeze-runtime'))
        : groundedCamera
            ? await _SakuraRuntime.create(v1, toonInst,
                groundedCamera: true, animateWorld: false)
            : null;

    pp.followPlatformOutputTarget();
    return SakuraApp._(
      app: app,
      viewer: v1,
      swapChain: sc,
      postProcess: pp,
      width: w,
      height: h,
      runtime: runtime,
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

  Future<void> prepareForPlatformResize() async {
    // The host pauses its frame scheduler before entering here. Drain any hook
    // that was already accepted and flush Filament before changing a view's
    // render target; otherwise a resize can invalidate a handle used by the
    // in-flight frame.
    await app.drainRequestFrameHooks();
    await app.flush();
    await postProcess.prepareForPlatformOutputReplacement();
    await app.flush();
  }

  /// Rebinds the final post-process view after Flutter replaces its surface.
  Future<void> completePlatformResize() async {
    await postProcess.completePlatformOutputReplacement();
    // Finish all target rebind/destroy commands before the host resumes its
    // frame scheduler. Otherwise the next frame can overtake resize cleanup on
    // Filament's backend thread and dereference a retired handle.
    await app.flush();
  }

  /// Pauses or resumes train, crossing, and petal animation.
  void setPaused(bool paused) => _runtime?.paused = paused;

  /// Returns the walking camera to the authored opening view.
  Future<void> resetCamera() async => _runtime?.resetCamera();

  /// Applies first-person camera input. Translation is in camera-local metres;
  /// look deltas are radians. Grounded runtimes immediately restore eye height.
  Future<void> controlCamera({
    double right = 0,
    double forward = 0,
    double yaw = 0,
    double pitch = 0,
  }) async =>
      _runtime?.controlCamera(
          right: right, forward: forward, yaw: yaw, pitch: pitch);

  /// Detaches frame callbacks owned by the optional realtime runtime.
  Future<void> dispose() async => _runtime?.dispose();
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

Uint8List _floatBytes(Float32List values) =>
    values.buffer.asUint8List(values.offsetInBytes, values.lengthInBytes);

Future<void> _uploadPetalInstances(
        Texture texture, FallingPetalSimulation petals) =>
    texture.setImage(0, _floatBytes(petals.instanceData()), 3,
        petals.instanceCount, PixelDataFormat.RGBA, PixelDataType.FLOAT);

/// Builds one true instanced draw for all animated petals. The tiny silhouette
/// buffers remain static; only three RGBA32F texels per instance are uploaded
/// as the simulation advances.
Future<Texture> _createInstancedPetals(
    ThermionViewerFFI viewer, FallingPetalSimulation petals) async {
  final app = viewer.app;
  final geometry = petals.geometry;
  final vertexBuffer = await (app.renderableManager.createVertexBufferBuilder()
        ..bufferCount(1)
        ..vertexCount(geometry.vertexCount)
        ..attribute(VertexAttribute.POSITION, 0, VertexAttributeType.FLOAT3,
            byteStride: 12))
      .build();
  await vertexBuffer.setBufferAt(0, geometry.positions);

  final indexBuffer = await (app.renderableManager.createIndexBufferBuilder()
        ..indexCount(geometry.indices.length)
        ..bufferType(IndexType.USHORT))
      .build();
  await indexBuffer.setBuffer(Uint16List.fromList(geometry.indices));

  final instanceTexture = await app.createTexture(3, petals.instanceCount,
      flags: {
        TextureUsage.TEXTURE_USAGE_SAMPLEABLE,
        TextureUsage.TEXTURE_USAGE_UPLOADABLE,
      },
      textureFormat: TextureFormat.RGBA32F);
  await _uploadPetalInstances(instanceTexture, petals);
  final sampler = await app.createTextureSampler(
      minFilter: TextureMinFilter.NEAREST,
      magFilter: TextureMagFilter.NEAREST,
      wrapS: TextureWrapMode.CLAMP_TO_EDGE,
      wrapT: TextureWrapMode.CLAMP_TO_EDGE);
  final material = await app.createMaterial(sakuraPetalsFilamat);
  final materialInstance = await material.createInstance();
  await materialInstance.setParameterTexture(
      'instanceData', instanceTexture, sampler);
  await materialInstance.setParameterFloat('cameraNear', .25);
  final fog = C.lin(Pal.fog);
  await materialInstance.setParameterFloat3('fogColor', fog.x, fog.y, fog.z);
  await materialInstance.setParameterFloat('fogNear', 44);
  await materialInstance.setParameterFloat('fogFar', 205);

  final entity = await app.createEntity();
  final builder = app.renderableManager.createBuilder(1)
    ..boundingBox(Aabb3.minMax(Vector3(-20, -10, -38), Vector3(20, 12, 40)))
    ..geometry(0, PrimitiveType.TRIANGLES, vertexBuffer, indexBuffer, 0,
        geometry.indices.length)
    ..material(0, materialInstance)
    ..instances(petals.instanceCount)
    ..castShadows(false)
    ..receiveShadows(false);
  if (!await builder.build(entity)) {
    throw StateError('Failed to build instanced falling petals');
  }
  final scene = await viewer.view.getScene();
  await scene.addEntity(entity);
  stdout.writeln(
      'falling petals: ${petals.instanceCount} instances, ${geometry.vertexCount} shared verts');
  return instanceTexture;
}

class _SakuraRuntime {
  _SakuraRuntime._(
      this.viewer,
      this.camera,
      this.train,
      this.booms,
      this.lamps,
      this.petals,
      this.petalBuffer,
      this.petalInstanceTexture,
      this.groundedCamera);

  final ThermionViewerFFI viewer;
  final Camera camera;
  final ThermionAsset? train;
  final List<ThermionAsset> booms;
  final List<_CrossingLamp> lamps;
  final FallingPetalSimulation? petals;
  final VertexBuffer? petalBuffer;
  final Texture? petalInstanceTexture;
  final bool groundedCamera;
  final Stopwatch _clock = Stopwatch();
  double _trainX = .392;
  double _armT = 0;
  double _time = 0;
  double _gust = 0;
  double _lastSeconds = 0;
  bool paused = false;
  bool _updating = false;
  late final Matrix4 _spawnCamera;

  static Future<_SakuraRuntime> create(
    ThermionViewerFFI viewer,
    MaterialInstance material, {
    required bool groundedCamera,
    bool animateWorld = true,
    bool animateTrain = true,
    bool animateBooms = true,
    bool animatePetals = true,
    bool instancePetals = true,
    bool freezeWorld = false,
  }) async {
    ThermionAsset? train;
    final booms = <ThermionAsset>[];
    final lamps = <_CrossingLamp>[];
    FallingPetalSimulation? petals;
    VertexBuffer? petalBuffer;
    Texture? petalInstanceTexture;

    Future<ThermionAsset> add(List<Tri> tris, {bool casts = false}) async {
      final packed = trisToPacked(tris);
      final asset = await viewer.createGeometry(
          Geometry(packed.positions, packed.indices,
              normals: packed.normals,
              colors: packed.colors,
              uvs: packed.uvs,
              uvs1: packed.uvs1,
              attribute0: packed.attribute0),
          materialInstances: [material]);
      await asset.setCastShadows(casts);
      await asset.setReceiveShadows(false);
      return asset;
    }

    if (animateWorld) {
      if (animateTrain) {
        // The source bends the full train onto the equator once, then advances
        // it by rotating that curved mesh about the planet's Z axis.
        train = await add(
            wrapOnPlanet(
                buildTrain(
                    x: 0,
                    bodyColor: 0xebe3d5,
                    stripeColor: 0x0771c1,
                    windowColor: 0x3b4257),
                maxEdge: 4),
            casts: true);
      }
      if (animateBooms) {
        final boom = buildCrossingBoom(gateYellowColor: 0xf4c033);
        booms
          ..add(await add(boom, casts: true))
          ..add(await add(boom, casts: true));
        final lampGeometry = buildCrossingLamp();
        final cx = centerX(0);
        for (final corner in const [
          (-1, 1, true),
          (1, -1, true),
          (1, 1, false),
          (-1, -1, false),
        ]) {
          final sx = corner.$1, sz = corner.$2;
          final rootX = cx + sx * (roadHalf + .42);
          final mastX = corner.$3 ? sx * .44 : 0.0;
          final yaw = sz > 0 ? 0.0 : math.pi;
          for (var lens = 0; lens < 2; lens++) {
            final lx = lens == 0 ? -.28 : .28;
            final worldX = rootX + mastX + (sz > 0 ? lx : -lx);
            final worldZ = sz * 2.95 + sz * (.02 + .145);
            lamps.add(_CrossingLamp(await add(lampGeometry), lens,
                _planetFrame(worldX, 2.55, worldZ, yaw: yaw)));
          }
        }
      }
      if (animatePetals) {
        petals = FallingPetalSimulation();
        if (instancePetals) {
          petalInstanceTexture = await _createInstancedPetals(viewer, petals);
        } else {
          final asset = await add(wrapOnPlanet(petals.triangles(), maxEdge: 1),
              casts: false);
          petalBuffer = asset.getVertexBuffer();
          if (petalBuffer == null) {
            throw StateError('Runtime petal geometry has no writable buffer');
          }
        }
      }
    }

    final runtime = _SakuraRuntime._(
        viewer,
        await viewer.getActiveCamera(),
        train,
        booms,
        lamps,
        petals,
        petalBuffer,
        petalInstanceTexture,
        groundedCamera);
    runtime._spawnCamera = await runtime.camera.getModelMatrix();
    runtime.paused = freezeWorld;
    runtime._clock.start();
    viewer.app.registerRequestFrameHook(runtime._onFrame);
    await runtime._onFrame();
    return runtime;
  }

  Future<void> resetCamera() => camera.setModelMatrix(_spawnCamera.clone());

  Future<void> controlCamera({
    double right = 0,
    double forward = 0,
    double yaw = 0,
    double pitch = 0,
  }) async {
    if (paused) return;
    final current = await camera.getModelMatrix();
    final rotation = Quaternion.axisAngle(Vector3(0, 1, 0), yaw) *
        Quaternion.axisAngle(Vector3(1, 0, 0), pitch);
    final updated = current *
        Matrix4.compose(Vector3(right, 0, -forward), rotation, Vector3.all(1));
    await camera.setModelMatrix(updated);
    if (groundedCamera) await _groundCamera();
  }

  Future<void> dispose() async {
    _clock.stop();
    await viewer.app.unregisterRequestFrameHook(_onFrame);
  }

  Future<void> _onFrame() async {
    if (_updating) return;
    _updating = true;
    try {
      final seconds = _clock.elapsedMicroseconds / 1000000;
      final dt = math.min(.05, math.max(0.0, seconds - _lastSeconds));
      _lastSeconds = seconds;
      if (!paused) {
        _time += dt;
        await _animate(dt);
      }
      if (groundedCamera) await _groundCamera();
    } catch (error, stackTrace) {
      stderr.writeln('Sakura runtime update failed: $error');
      stderr.writeln(stackTrace);
    } finally {
      _updating = false;
    }
  }

  Future<void> _animate(double dt) async {
    const circumference = math.pi * 2 * planetRadius;
    _trainX = ((_trainX + 23.5 * dt + circumference / 2) % circumference) -
        circumference / 2;
    if (train != null) {
      await train!.setTransform(_trainPlanetTransform(_trainX));
    }

    final ahead = -_trainX;
    final closing = ahead < 165 && ahead > -62;
    _armT = (_armT + dt / (closing ? 3.4 : -3.0)).clamp(0.0, 1.0);
    final eased =
        _armT < .5 ? 2 * _armT * _armT : 1 - math.pow(-2 * _armT + 2, 2) / 2;
    final angle = (1 - eased) * (math.pi / 2) * .99 + .004;
    if (booms.length == 2) {
      const gateZ = 2.95;
      const hingeY = .2 + .92 + .12;
      final cx = centerX(0);
      await booms[0].setTransform(_planetFrame(
          cx - roadHalf - .42, hingeY, gateZ,
          yaw: 0, roll: angle));
      await booms[1].setTransform(_planetFrame(
          cx + roadHalf + .42, hingeY, -gateZ,
          yaw: math.pi, roll: angle));
    }

    final warningActive = closing || _armT > .02;
    final blinkPhase = (_time * 1.6) % 1;
    for (final lamp in lamps) {
      final visible = warningActive &&
          (lamp.phase == 0 ? blinkPhase < .5 : blinkPhase >= .5);
      await lamp.asset.setTransform(lamp.transform *
          Matrix4.diagonal3Values(
              visible ? 1 : .001, visible ? 1 : .001, visible ? 1 : .001));
    }

    if (petals != null &&
        (petalInstanceTexture != null || petalBuffer != null)) {
      final near = math.max(0.0, 1 - _trainX.abs() / 46);
      _gust = math.max(_gust * math.exp(-dt * 1.4), near * near);
      petals!.update(dt, _gust, 1);
      if (petalInstanceTexture != null) {
        await _uploadPetalInstances(petalInstanceTexture!, petals!);
      } else {
        final packed =
            trisToPacked(wrapOnPlanet(petals!.triangles(), maxEdge: 1));
        await petalBuffer!.setBufferAt(0, packed.positions);
      }
    }
  }

  Future<void> _groundCamera() async {
    final matrix = await camera.getModelMatrix();
    final position = matrix.getTranslation();
    final radial = position - Vector3(0, -planetRadius, 0);
    if (radial.length2 < 1) return;
    radial.normalize();
    final z = math.asin(radial.z.clamp(-1.0, 1.0)) * planetRadius;
    final x = math.atan2(radial.x, radial.y) * planetRadius;
    final ground = math.max(groundY(z), hillSurfaceY(x, z));
    final desired = planetPosition(x, ground + 1.62, z);
    matrix.setTranslation(desired);
    await camera.setModelMatrix(matrix);
  }
}

class _CrossingLamp {
  const _CrossingLamp(this.asset, this.phase, this.transform);
  final ThermionAsset asset;
  final int phase;
  final Matrix4 transform;
}

Matrix4 _planetFrame(double x, double y, double z,
    {double yaw = 0, double roll = 0}) {
  final up = Vector3.zero(), east = Vector3.zero(), north = Vector3.zero();
  planetBasis(x, z, up, east, north);
  final frame = Matrix4.identity();
  frame.setColumn(0, Vector4(east.x, east.y, east.z, 0));
  frame.setColumn(1, Vector4(up.x, up.y, up.z, 0));
  frame.setColumn(2, Vector4(north.x, north.y, north.z, 0));
  frame.setTranslation(planetPosition(x, y, z));
  return frame * Matrix4.rotationY(yaw) * Matrix4.rotationZ(roll);
}

Matrix4 _trainPlanetTransform(double x) =>
    Matrix4.translationValues(0, -planetRadius, 0) *
    Matrix4.rotationZ(-x / planetRadius) *
    Matrix4.translationValues(0, planetRadius, 0);
