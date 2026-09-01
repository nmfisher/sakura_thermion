// SakuraPostProcess — a reusable fullscreen post-process view.
//
// Redirects the main scene view into a render target (RT1: colour + depth),
// then runs a fullscreen triangle with a caller-supplied material that samples
// RT1's textures. The pp view renders to its own render target (RT2).
//
import 'dart:async';

// Material contract: the material must declare
//   sampler2d tDiffuse ; sampler2d tDepth ; float2 texelSize
import 'package:thermion_dart/thermion_dart.dart';
import 'package:thermion_dart/src/filament/src/interface/scene.dart';

class SakuraPostProcess {
  final View view;
  final FilamentApp _app;
  final View _mainView;
  final MaterialInstance _materialInstance;
  final Scene _scene;
  final Skybox _skybox;
  final Camera _camera;
  final ThermionEntity _quadEntity;
  final VertexBuffer _quadVB;
  final IndexBuffer _quadIB;
  final TextureSampler _colorSampler;
  final TextureSampler _depthSampler;
  RenderTarget? _outputRT;

  RenderTarget? _sceneRT;
  RenderTarget? _ppRT;
  Texture? _sceneColor;
  Texture? _sceneDepth;
  Texture? _ppColor;
  Texture? _ppDepth;
  Timer? _outputTargetTimer;
  bool _updatingOutputTarget = false;
  bool _destroyed = false;

  SakuraPostProcess._({
    required this.view,
    required FilamentApp app,
    required View mainView,
    required MaterialInstance materialInstance,
    required Scene scene,
    required Skybox skybox,
    required Camera camera,
    required ThermionEntity quadEntity,
    required VertexBuffer quadVB,
    required IndexBuffer quadIB,
    required TextureSampler colorSampler,
    required TextureSampler depthSampler,
    required RenderTarget? outputRT,
    required RenderTarget? sceneRT,
    required RenderTarget? ppRT,
    required Texture? sceneColor,
    required Texture? sceneDepth,
    required Texture? ppColor,
    required Texture? ppDepth,
  })  : _app = app,
        _mainView = mainView,
        _materialInstance = materialInstance,
        _scene = scene,
        _skybox = skybox,
        _camera = camera,
        _quadEntity = quadEntity,
        _quadVB = quadVB,
        _quadIB = quadIB,
        _colorSampler = colorSampler,
        _depthSampler = depthSampler,
        _outputRT = outputRT,
        _sceneRT = sceneRT,
        _ppRT = ppRT,
        _sceneColor = sceneColor,
        _sceneDepth = sceneDepth,
        _ppColor = ppColor,
        _ppDepth = ppDepth;

  static Future<SakuraPostProcess> create(
    FilamentApp app, {
    required View mainView,
    required MaterialInstance materialInstance,
    required int width,
    required int height,
    bool redirectMain = true,
  }) async {
    // Preserve a platform-provided output target (for example Flutter's
    // texture). The scene is redirected to RT1 and the post view takes over
    // the original target, so callers do not need a separate compositing path.
    final outputRT = await mainView.getRenderTarget();

    // RT1: the scene renders here (sampleable colour RGBA32F + depth).
    RenderTarget? sceneRT;
    Texture? sceneColor;
    Texture? sceneDepth;
    if (redirectMain) {
      sceneColor = await app.createTexture(
        width,
        height,
        flags: {
          TextureUsage.TEXTURE_USAGE_BLIT_SRC,
          TextureUsage.TEXTURE_USAGE_COLOR_ATTACHMENT,
          TextureUsage.TEXTURE_USAGE_SAMPLEABLE,
        },
        textureFormat: TextureFormat.RGBA32F,
      );
      sceneDepth = await app.createTexture(
        width,
        height,
        flags: {
          TextureUsage.TEXTURE_USAGE_DEPTH_ATTACHMENT,
          TextureUsage.TEXTURE_USAGE_SAMPLEABLE
        },
        textureFormat: TextureFormat.DEPTH32F,
      );
      sceneRT = await app.createRenderTarget(width, height,
          color: sceneColor, depth: sceneDepth);
    }
    if (redirectMain) await mainView.setRenderTarget(sceneRT!);

    // PP view.
    final baseView = await app.createView();
    final scene = await app.createScene();
    final skybox =
        await app.createColoredSkybox(r: 0.0, g: 0.0, b: 0.0, a: 0.0);
    await scene.setSkybox(skybox);
    final camera = await app.createCamera();
    await camera.setProjection(Projection.Orthographic, -1, 1, -1, 1, 0.0, 1.0);

    // Fullscreen triangle. Build this directly instead of going through
    // SceneAsset: this renderable has no glTF transform hierarchy and must
    // remain visible despite its deliberately oversized clip-space bounds.
    // This is the same proven path used by EdgeDetectionView.
    final positions =
        Float32List.fromList([-1, -1, 0.5, 3, -1, 0.5, -1, 3, 0.5]);
    final vbBuilder = app.renderableManager.createVertexBufferBuilder();
    vbBuilder.vertexCount(3);
    vbBuilder.bufferCount(1);
    vbBuilder.attribute(VertexAttribute.POSITION, 0, VertexAttributeType.FLOAT3,
        byteOffset: 0, byteStride: 12);
    final quadVB = await vbBuilder.build();
    await quadVB.setBufferAt(0, positions);

    final indices = Uint16List.fromList([0, 1, 2]);
    final ibBuilder = app.renderableManager.createIndexBufferBuilder();
    ibBuilder.indexCount(3);
    ibBuilder.bufferType(IndexType.USHORT);
    final quadIB = await ibBuilder.build();
    await quadIB.setBuffer(indices);

    final quadEntity = await app.createEntity();
    final renderableBuilder = app.renderableManager.createBuilder(1);
    renderableBuilder
        .boundingBox(Aabb3.minMax(Vector3(-2, -2, 0), Vector3(4, 4, 1)));
    renderableBuilder.geometry(
        0, PrimitiveType.TRIANGLES, quadVB, quadIB, 0, 3);
    renderableBuilder.material(0, materialInstance);
    renderableBuilder.culling(false);
    renderableBuilder.receiveShadows(false);
    renderableBuilder.castShadows(false);
    if (!await renderableBuilder.build(quadEntity) ||
        !app.renderableManager.hasComponent(quadEntity)) {
      throw StateError('Failed to build custom post-process renderable');
    }
    await scene.addEntity(quadEntity);

    // Samplers for the RT textures.
    final colorSampler = await app.createTextureSampler(
      minFilter: TextureMinFilter.NEAREST,
      magFilter: TextureMagFilter.NEAREST,
      wrapS: TextureWrapMode.CLAMP_TO_EDGE,
      wrapT: TextureWrapMode.CLAMP_TO_EDGE,
    );
    final depthSampler = await app.createTextureSampler(
      minFilter: TextureMinFilter.NEAREST,
      magFilter: TextureMagFilter.NEAREST,
      wrapS: TextureWrapMode.CLAMP_TO_EDGE,
      wrapT: TextureWrapMode.CLAMP_TO_EDGE,
    );

    // RT2: the pp view's output target (RGBA32F for HDR post-process).
    RenderTarget? ppRT;
    Texture? ppColor;
    Texture? ppDepth;
    if (outputRT == null) {
      ppColor = await app.createTexture(
        width,
        height,
        flags: {
          TextureUsage.TEXTURE_USAGE_BLIT_SRC,
          TextureUsage.TEXTURE_USAGE_COLOR_ATTACHMENT,
          TextureUsage.TEXTURE_USAGE_SAMPLEABLE,
        },
        textureFormat: TextureFormat.RGBA32F,
      );
      ppDepth = await app.createTexture(
        width,
        height,
        flags: {
          TextureUsage.TEXTURE_USAGE_DEPTH_ATTACHMENT,
          TextureUsage.TEXTURE_USAGE_SAMPLEABLE
        },
        textureFormat: TextureFormat.DEPTH32F,
      );
      ppRT = await app.createRenderTarget(width, height,
          color: ppColor, depth: ppDepth);
    }

    // Linear tone mapper + grading (no double tonemap).
    final linTM = await ToneMapper.linear(app);
    final cgb = await baseView.createColorGradingBuilder();
    cgb.toneMapper(linTM);
    final linCG = await cgb.build();

    final pp = SakuraPostProcess._(
      view: baseView,
      app: app,
      mainView: mainView,
      materialInstance: materialInstance,
      scene: scene,
      skybox: skybox,
      camera: camera,
      quadEntity: quadEntity,
      quadVB: quadVB,
      quadIB: quadIB,
      colorSampler: colorSampler,
      depthSampler: depthSampler,
      outputRT: outputRT,
      sceneRT: sceneRT,
      ppRT: ppRT,
      sceneColor: sceneColor,
      sceneDepth: sceneDepth,
      ppColor: ppColor,
      ppDepth: ppDepth,
    );

    await pp.view.setCamera(camera);
    await pp.view.setScene(scene);
    await pp.view.setRenderTarget(outputRT ?? ppRT);
    await pp.view.setViewport(width, height);
    await pp.view.setColorGrading(linCG);
    await pp.view.setPostProcessing(false);
    await pp.view.setFrustumCullingEnabled(false);
    await pp.view.setBlendMode(BlendMode.transparent);

    // Bind RT1's textures into the material.
    if (sceneRT != null) {
      await materialInstance.setParameterTexture(
          'tDiffuse', sceneColor!, colorSampler);
      await materialInstance.setParameterTexture(
          'tDepth', sceneDepth!, depthSampler);
      await materialInstance.setParameterFloat2(
          'texelSize', 1.0 / width, 1.0 / height);
    }
    return pp;
  }

  Future<void> resize(int width, int height,
      {RenderTarget? outputRenderTarget}) async {
    if (outputRenderTarget != null) {
      _outputRT = outputRenderTarget;
    }
    final sceneColor = await _app.createTexture(
      width,
      height,
      flags: {
        TextureUsage.TEXTURE_USAGE_BLIT_SRC,
        TextureUsage.TEXTURE_USAGE_COLOR_ATTACHMENT,
        TextureUsage.TEXTURE_USAGE_SAMPLEABLE,
      },
      textureFormat: TextureFormat.RGBA32F,
    );
    final sceneDepth = await _app.createTexture(
      width,
      height,
      flags: {
        TextureUsage.TEXTURE_USAGE_DEPTH_ATTACHMENT,
        TextureUsage.TEXTURE_USAGE_SAMPLEABLE
      },
      textureFormat: TextureFormat.DEPTH32F,
    );
    final sceneRT = await _app.createRenderTarget(width, height,
        color: sceneColor, depth: sceneDepth);
    await _materialInstance.setParameterTexture(
        'tDiffuse', sceneColor, _colorSampler);
    await _materialInstance.setParameterTexture(
        'tDepth', sceneDepth, _depthSampler);
    await _materialInstance.setParameterFloat2(
        'texelSize', 1.0 / width, 1.0 / height);
    await _mainView.setRenderTarget(sceneRT);
    await _mainView.setViewport(width, height);
    await _sceneRT?.destroy();
    await _sceneColor?.destroy();
    await _sceneDepth?.destroy();
    _sceneRT = sceneRT;
    _sceneColor = sceneColor;
    _sceneDepth = sceneDepth;

    if (_outputRT == null) {
      final ppColor = await _app.createTexture(
        width,
        height,
        flags: {
          TextureUsage.TEXTURE_USAGE_BLIT_SRC,
          TextureUsage.TEXTURE_USAGE_COLOR_ATTACHMENT,
          TextureUsage.TEXTURE_USAGE_SAMPLEABLE,
        },
        textureFormat: TextureFormat.RGBA32F,
      );
      final ppDepth = await _app.createTexture(
        width,
        height,
        flags: {
          TextureUsage.TEXTURE_USAGE_DEPTH_ATTACHMENT,
          TextureUsage.TEXTURE_USAGE_SAMPLEABLE
        },
        textureFormat: TextureFormat.DEPTH32F,
      );
      final ppRT = await _app.createRenderTarget(width, height,
          color: ppColor, depth: ppDepth);
      await view.setRenderTarget(ppRT);
      await _ppRT?.destroy();
      await _ppColor?.destroy();
      await _ppDepth?.destroy();
      _ppRT = ppRT;
      _ppColor = ppColor;
      _ppDepth = ppDepth;
    } else {
      await view.setRenderTarget(_outputRT);
      await _ppRT?.destroy();
      await _ppColor?.destroy();
      await _ppDepth?.destroy();
      _ppRT = null;
      _ppColor = null;
      _ppDepth = null;
    }
    await view.setViewport(width, height);
  }

  /// Keeps the post-process connected when Flutter creates or replaces its
  /// platform render target. The main view normally points at [_sceneRT]; any
  /// other non-null target was assigned by the Flutter surface lifecycle and
  /// must become the post view's output.
  void followPlatformOutputTarget({
    Duration interval = const Duration(milliseconds: 50),
  }) {
    _outputTargetTimer ??= Timer.periodic(interval, (_) {
      unawaited(_adoptPlatformOutputTarget());
    });
    unawaited(_adoptPlatformOutputTarget());
  }

  Future<void> _adoptPlatformOutputTarget() async {
    if (_destroyed || _updatingOutputTarget) return;
    _updatingOutputTarget = true;
    try {
      final candidate = await _mainView.getRenderTarget();
      if (candidate == null || identical(candidate, _sceneRT)) return;

      final viewport = await _mainView.getViewport();
      if (viewport.width <= 0 || viewport.height <= 0) return;

      await resize(
        viewport.width,
        viewport.height,
        outputRenderTarget: candidate,
      );
    } finally {
      _updatingOutputTarget = false;
    }
  }

  Future<void> destroy() async {
    _destroyed = true;
    _outputTargetTimer?.cancel();
    while (_updatingOutputTarget) {
      await Future<void>.delayed(Duration.zero);
    }
    await view.setRenderTarget(null);
    await _mainView.setRenderTarget(_outputRT);
    await view.setCamera(null);
    await _scene.removeEntity(_quadEntity);
    await _app.destroyEntity(_quadEntity);
    await _quadVB.destroy();
    await _quadIB.destroy();
    await _scene.setSkybox(null);
    await _skybox.destroy();
    await _app.destroyScene(_scene);
    await _camera.destroy();
    await _sceneRT?.destroy();
    await _ppRT?.destroy();
    await _sceneColor?.destroy();
    await _sceneDepth?.destroy();
    await _ppColor?.destroy();
    await _ppDepth?.destroy();
    await _app.destroyView(view);
  }
}
