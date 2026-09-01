// Audit the fully-built Three.js scene so the frozen-frame interchange format
// can be sized from facts: geometry reuse, material count, and generated maps.
//
//   node tool/audit_reference_scene.js
//
// Environment: SAKURA_REFERENCE, SAKURA_REFERENCE_URL.
const path = require('node:path');
const fs = require('node:fs');
const { createRequire } = require('node:module');

const referenceRoot = path.resolve(
  process.env.SAKURA_REFERENCE || '/tmp/sakura-ref',
);
const referenceUrl =
  process.env.SAKURA_REFERENCE_URL || 'http://127.0.0.1:5178/';
const referenceRequire = createRequire(path.join(referenceRoot, 'package.json'));
const { chromium } = referenceRequire('playwright');

(async () => {
  const browser = await chromium.launch({
    headless: true,
    args: [
      '--enable-webgl',
      '--use-gl=angle',
      '--use-angle=swiftshader',
      '--enable-unsafe-swiftshader',
      '--ignore-gpu-blocklist',
      '--no-sandbox',
    ],
  });
  try {
    const page = await (
      await browser.newContext({ viewport: { width: 64, height: 64 } })
    ).newPage();
    await page.goto(referenceUrl, { waitUntil: 'load', timeout: 60_000 });
    await page.waitForFunction(() => window.__scene?.world, null, {
      timeout: 60_000,
    });
    await page.waitForTimeout(2_000);
    const report = await page.evaluate(async () => {
      const THREE = window.__scene.THREE;
      const scene = window.__scene.scene;
      const world = window.__scene.world;
      world.update = () => {};
      world.train.x = 0.392;
      world.train.update(0);
      for (const mesh of world.petals.meshes) mesh.visible = false;
      scene.updateMatrixWorld(true);

      const geometries = new Map();
      const materials = new Map();
      const textures = new Map();
      const objects = [];
      let meshes = 0;
      let instances = 0;
      let triangles = 0;

      function hashBytes(view) {
        if (!view) return '';
        const bytes = new Uint8Array(view.buffer, view.byteOffset, view.byteLength);
        let hash = 0x811c9dc5;
        for (let i = 0; i < bytes.length; i++) {
          hash ^= bytes[i];
          hash = Math.imul(hash, 0x01000193);
        }
        return (hash >>> 0).toString(16).padStart(8, '0');
      }

      function hashText(text) {
        return hashBytes(new TextEncoder().encode(text));
      }

      function objectPath(object) {
        const segments = [];
        for (let node = object; node && node !== scene; node = node.parent) {
          const ordinal = node.parent ? node.parent.children.indexOf(node) : 0;
          const label = (node.name || node.type || 'Object3D')
            .replaceAll('/', '_');
          segments.push(`${label}[${ordinal}]`);
        }
        return segments.reverse().join('/');
      }

      function matrixValues(matrix) {
        return matrix.elements.map((value) => Number(value.toFixed(7)));
      }

      function materialRecord(material) {
        if (!material) return null;
        function textureTransform(texture) {
          if (!texture) return null;
          const image = texture.image || texture.source?.data;
          return {
            width: Number(image?.width || 0),
            height: Number(image?.height || 0),
            wrapS: texture.wrapS,
            wrapT: texture.wrapT,
            flipY: texture.flipY,
            repeat: [texture.repeat.x, texture.repeat.y],
            offset: [texture.offset.x, texture.offset.y],
            center: [texture.center.x, texture.center.y],
            rotation: texture.rotation,
            colorSpace: texture.colorSpace || '',
          };
        }
        const record = {
          type: material.type,
          name: material.name || '',
          color: material.color?.getHexString() || '',
          emissive: material.emissive?.getHexString() || '',
          roughness: material.roughness ?? null,
          metalness: material.metalness ?? null,
          opacity: material.opacity,
          alphaTest: material.alphaTest,
          transparent: material.transparent,
          side: material.side,
          depthWrite: material.depthWrite,
          depthTest: material.depthTest,
          vertexColors: material.vertexColors,
          flatShading: material.flatShading,
          map: textureTransform(material.map),
          alphaMap: textureTransform(material.alphaMap),
        };
        return {
          ...record,
          _mapSourceId: material.map?.uuid || null,
          _alphaMapSourceId: material.alphaMap?.uuid || null,
          signature: hashText(JSON.stringify(record)),
        };
      }

      function geometryRecord(geometry) {
        const attributes = {};
        for (const [name, attribute] of Object.entries(geometry.attributes)) {
          attributes[name] = {
            count: attribute.count,
            itemSize: attribute.itemSize,
            normalized: attribute.normalized,
            hash: hashBytes(attribute.array),
          };
        }
        const record = {
          vertices: geometry.attributes.position?.count || 0,
          indices: geometry.index?.count || 0,
          indexHash: geometry.index ? hashBytes(geometry.index.array) : '',
          attributes,
          groups: geometry.groups.map((group) => ({
            start: group.start,
            count: group.count,
            materialIndex: group.materialIndex,
          })),
          drawRange: { ...geometry.drawRange },
        };
        return {
          ...record,
          signature: hashText(JSON.stringify(record)),
        };
      }

      function worldBounds(object) {
        const geometry = object.geometry;
        if (!geometry.boundingBox) geometry.computeBoundingBox();
        const bounds = new THREE.Box3();
        if (object.isInstancedMesh) {
          const instance = new THREE.Matrix4();
          const world = new THREE.Matrix4();
          for (let i = 0; i < object.count; i++) {
            object.getMatrixAt(i, instance);
            world.multiplyMatrices(object.matrixWorld, instance);
            bounds.union(geometry.boundingBox.clone().applyMatrix4(world));
          }
        } else {
          bounds.copy(geometry.boundingBox).applyMatrix4(object.matrixWorld);
        }
        const round = (value) => Number(value.toFixed(6));
        return {
          min: [round(bounds.min.x), round(bounds.min.y), round(bounds.min.z)],
          max: [round(bounds.max.x), round(bounds.max.y), round(bounds.max.z)],
        };
      }

      function recordTexture(texture) {
        if (!texture || textures.has(texture.uuid)) return;
        const image = texture.image || texture.source?.data;
        const width = Number(image?.width || 0);
        const height = Number(image?.height || 0);
        textures.set(texture.uuid, {
          name: texture.name || '',
          width,
          height,
          texels: width * height,
          type: image?.constructor?.name || typeof image,
          wrapS: texture.wrapS,
          wrapT: texture.wrapT,
          flipY: texture.flipY,
          colorSpace: texture.colorSpace || '',
          image,
        });
      }

      scene.traverse((object) => {
        if (!object.isMesh || object.visible === false || !object.geometry) {
          return;
        }
        if (object.userData?.isOutline) return;
        meshes++;
        const count = object.isInstancedMesh ? object.count : 1;
        instances += count;
        const geometry = object.geometry;
        const triCount = geometry.index
          ? geometry.index.count / 3
          : geometry.attributes.position.count / 3;
        triangles += triCount * count;
        if (!geometries.has(geometry.uuid)) {
          geometries.set(geometry.uuid, geometryRecord(geometry));
        }
        const objectMaterials = Array.isArray(object.material)
          ? object.material
          : [object.material];
        for (const material of objectMaterials) {
          if (!material) continue;
          if (!materials.has(material.uuid)) {
            materials.set(material.uuid, {
              ...materialRecord(material),
              hasMap: Boolean(material.map),
              hasAlphaMap: Boolean(material.alphaMap),
            });
          }
          recordTexture(material.map);
          recordTexture(material.alphaMap);
        }

        const materialArray = Array.isArray(object.material)
          ? object.material
          : [object.material];
        objects.push({
          sourceIndex: objects.length,
          path: objectPath(object),
          name: object.name || '',
          type: object.type,
          instanceCount: count,
          triangleCount: triCount * count,
          geometry: geometry.uuid,
          geometrySignature: geometries.get(geometry.uuid).signature,
          materials: materialArray.filter(Boolean).map((material) => material.uuid),
          materialSignatures: materialArray.filter(Boolean)
            .map((material) => materials.get(material.uuid).signature),
          matrixWorld: matrixValues(object.matrixWorld),
          instanceMatrixHash: object.isInstancedMesh
            ? hashBytes(object.instanceMatrix.array)
            : '',
          bounds: worldBounds(object),
          castShadow: object.castShadow,
          receiveShadow: object.receiveShadow,
          renderOrder: object.renderOrder,
          noOutline: Boolean(object.userData?.noOutline),
          noShadow: Boolean(object.userData?.noShadow),
        });
      });

      // Hash the authored pixels. UUIDs alone are intentionally not used as a
      // parity key: Three.js generates them randomly on every scene build.
      for (const texture of textures.values()) {
        const image = texture.image;
        if (image && texture.width && texture.height) {
          const canvas = document.createElement('canvas');
          canvas.width = texture.width;
          canvas.height = texture.height;
          const context = canvas.getContext('2d', { willReadFrequently: true });
          context.drawImage(image, 0, 0);
          const pixels = context.getImageData(
            0, 0, texture.width, texture.height,
          ).data;
          const digest = await crypto.subtle.digest('SHA-256', pixels);
          texture.pixelHash = [...new Uint8Array(digest)]
            .map((byte) => byte.toString(16).padStart(2, '0')).join('');
        } else {
          texture.pixelHash = '';
        }
        delete texture.image;
      }

      // Convert all runtime UUID links to deterministic table ordinals. Three
      // creates UUIDs randomly, while insertion order and hierarchy order are
      // stable for this seeded scene.
      const geometryIds = new Map([...geometries.keys()].map(
        (uuid, index) => [uuid, `g${String(index).padStart(5, '0')}`],
      ));
      const materialIds = new Map([...materials.keys()].map(
        (uuid, index) => [uuid, `m${String(index).padStart(4, '0')}`],
      ));
      const textureIds = new Map([...textures.keys()].map(
        (uuid, index) => [uuid, `t${String(index).padStart(3, '0')}`],
      ));
      for (const object of objects) {
        object.geometry = geometryIds.get(object.geometry);
        object.materials = object.materials.map((uuid) => materialIds.get(uuid));
        object.materialSignatures = object.materials.map((id) => {
          const index = Number(id.substring(1));
          return [...materials.values()][index].signature;
        });
      }
      const geometryTable = [...geometries.entries()].map(([uuid, value]) => ({
        id: geometryIds.get(uuid), ...value,
      }));
      const materialTable = [...materials.entries()].map(([uuid, value]) => {
        const record = { ...value };
        record.id = materialIds.get(uuid);
        record.mapTexture = record._mapSourceId
          ? textureIds.get(record._mapSourceId) : null;
        record.alphaMapTexture = record._alphaMapSourceId
          ? textureIds.get(record._alphaMapSourceId) : null;
        delete record._mapSourceId;
        delete record._alphaMapSourceId;
        return record;
      });
      const textureTable = [...textures.entries()].map(([uuid, value]) => ({
        id: textureIds.get(uuid), ...value,
      }));

      const textureList = [...textures.values()];
      const materialList = [...materials.values()];
      const bySize = {};
      for (const texture of textureList) {
        const key = `${texture.width}x${texture.height}`;
        bySize[key] = (bySize[key] || 0) + 1;
      }
      // Deterministic shelf layout used by the exporter: tallest first, two
      // pixels of padding on every edge to prevent filtered atlas bleed.
      const atlasWidth = 8192;
      const padding = 2;
      let atlasX = padding;
      let atlasY = padding;
      let rowHeight = 0;
      for (const texture of [...textureList].sort(
        (a, b) => b.height - a.height || b.width - a.width,
      )) {
        if (atlasX + texture.width + padding > atlasWidth) {
          atlasX = padding;
          atlasY += rowHeight + padding * 2;
          rowHeight = 0;
        }
        atlasX += texture.width + padding * 2;
        rowHeight = Math.max(rowHeight, texture.height);
      }
      const packedAtlasHeight = atlasY + rowHeight + padding;
      return {
        format: 'sakura-object-manifest-v1',
        referenceUrl: location.href,
        objects,
        geometryTable,
        materialTable,
        textureTable,
        summary: {
        meshes,
        instances,
        triangles,
        uniqueGeometries: geometries.size,
        materials: materials.size,
        mappedMaterials: materialList.filter((m) => m.hasMap).length,
        alphaMappedMaterials: materialList.filter((m) => m.hasAlphaMap).length,
        transparentMaterials: materialList.filter((m) => m.transparent).length,
        textures: textureList.length,
        totalTexels: textureList.reduce((sum, t) => sum + t.texels, 0),
        packedAtlas: `${atlasWidth}x${packedAtlasHeight}`,
        textureSizes: Object.fromEntries(
          Object.entries(bySize).sort((a, b) => b[1] - a[1]),
        ),
        textureTypes: [...new Set(textureList.map((t) => t.type))],
        },
      };
    });
    const json = JSON.stringify(report, null, 2);
    if (process.env.OUT) {
      fs.mkdirSync(path.dirname(path.resolve(process.env.OUT)), {
        recursive: true,
      });
      fs.writeFileSync(path.resolve(process.env.OUT), json);
      console.log(`WROTE ${path.resolve(process.env.OUT)}`);
      console.log(JSON.stringify(report.summary, null, 2));
    } else {
      console.log(json);
    }
  } finally {
    await browser.close();
  }
})().catch((error) => {
  console.error(error);
  process.exit(1);
});
