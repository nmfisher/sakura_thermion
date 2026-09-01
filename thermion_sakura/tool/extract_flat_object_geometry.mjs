#!/usr/bin/env node
import fs from 'node:fs/promises';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import { deflateSync } from 'node:zlib';

const root = process.env.SAKURA_REFERENCE || '/tmp/sakura-ref';
const url = process.env.SAKURA_REFERENCE_URL || 'http://127.0.0.1:5178';
const attributionPath = process.env.ATTRIBUTION;
const prefix = process.env.INCLUDE_PREFIX || '';
let prefixes = prefix.split(',').map((value) => value.trim()).filter(Boolean);
if (attributionPath) {
  const attribution = JSON.parse(await fs.readFile(attributionPath, 'utf8'));
  prefixes.push(...attribution.rankedObjects.map((row) => row.path));
}
const excludedPrefixes = (process.env.EXCLUDE_PREFIX || '')
  .split(',').map((value) => value.trim()).filter(Boolean);
prefixes = [...new Set(prefixes)].filter(
  (value) => !excludedPrefixes.some((excluded) => value.startsWith(excluded)),
);
if (!prefixes.length) throw new Error('INCLUDE_PREFIX or ATTRIBUTION is required');
const bounds = (process.env.BOUNDS || '').split(',').map(Number);
const flatBounds = bounds.length === 4 && bounds.every(Number.isFinite) ? bounds : null;
const output = process.env.OUT || '/tmp/sakura-flat-object.json';
const dartOutput = process.env.DART_OUT;
const dartConst = process.env.DART_CONST || 'sourceGeometryBase64';
const playwright = await import(pathToFileURL(
  path.join(root, 'node_modules/playwright/index.mjs'),
));
const browser = await playwright.chromium.launch({ headless: true });
try {
  const page = await browser.newPage();
  await page.goto(url, { waitUntil: 'domcontentloaded', timeout: 180000 });
  await page.waitForFunction(() => window.__scene?.world, null, { timeout: 180000 });
  const result = await page.evaluate(async ({ prefixes, flatBounds }) => {
    const { flatAt } = await import('/src/world/planet.js');
    const { scene, THREE } = window.__scene;
    scene.updateMatrixWorld(true);
    const root = scene;
    const va = new THREE.Vector3();
    const vb = new THREE.Vector3();
    const vc = new THREE.Vector3();
    function objectPath(object) {
      const segments = [];
      for (let node = object; node && node !== root; node = node.parent) {
        const ordinal = node.parent ? node.parent.children.indexOf(node) : 0;
        const label = (node.name || node.type || 'Object3D').replaceAll('/', '_');
        segments.push(`${label}[${ordinal}]`);
      }
      return segments.reverse().join('/');
    }
    function materialRecord(material) {
      let bands = 3;
      const ramp = material?.gradientMap?.image?.data;
      if (ramp) bands = material.gradientMap.image.width;
      const tint = material?.userData?.shadowTint?.value?.getHex?.() ?? 0;
      return {
        color: material?.color?.getHex?.() ?? 0xffffff,
        tint,
        bands,
        unlit: Boolean(material?.isMeshBasicMaterial),
        mapped: Boolean(material?.map),
      };
    }
    const materials = [];
    const materialIds = new Map();
    const triangles = [];
    function materialId(material) {
      const key = material?.uuid ?? 'none';
      if (materialIds.has(key)) return materialIds.get(key);
      const id = materials.length;
      materials.push(materialRecord(material));
      materialIds.set(key, id);
      return id;
    }
    root.traverse((object) => {
      if (!object.isMesh || object.userData?.isOutline ||
          object.material?.isShaderMaterial || object.visible === false) return;
      const resolved = objectPath(object);
      if (!prefixes.some((prefix) => resolved.startsWith(prefix))) return;
      const geometry = object.geometry;
      if (!geometry?.attributes?.position) return;
      const pos = geometry.attributes.position;
      const index = geometry.index;
      const count = index ? index.count : pos.count;
      const groups = geometry.groups?.length ? geometry.groups : null;
      const materialAt = (offset) => {
        if (!Array.isArray(object.material)) return object.material;
        if (!groups) return object.material[0];
        const group = groups.find((g) => offset >= g.start && offset < g.start + g.count);
        return object.material[group?.materialIndex ?? 0];
      };
      const matrices = [];
      if (object.isInstancedMesh) {
        const local = new THREE.Matrix4();
        for (let i = 0; i < object.count; i++) {
          object.getMatrixAt(i, local);
          matrices.push(new THREE.Matrix4().multiplyMatrices(object.matrixWorld, local));
        }
      } else {
        matrices.push(object.matrixWorld);
      }
      for (const matrix of matrices) {
        for (let i = 0; i < count; i += 3) {
          const ai = index ? index.getX(i) : i;
          const bi = index ? index.getX(i + 1) : i + 1;
          const ci = index ? index.getX(i + 2) : i + 2;
          va.fromBufferAttribute(pos, ai).applyMatrix4(matrix);
          vb.fromBufferAttribute(pos, bi).applyMatrix4(matrix);
          vc.fromBufferAttribute(pos, ci).applyMatrix4(matrix);
          const a = flatAt(va), b = flatAt(vb), c = flatAt(vc);
          if (flatBounds) {
            const [minX, minZ, maxX, maxZ] = flatBounds;
            const cx = (a.x + b.x + c.x) / 3;
            const cz = (a.z + b.z + c.z) / 3;
            if (cx < minX || cx > maxX || cz < minZ || cz > maxZ) continue;
          }
          triangles.push([
            a.x, a.y, a.z, b.x, b.y, b.z, c.x, c.y, c.z,
            materialId(materialAt(i)),
          ]);
        }
      }
    });
    return { prefixes, materials, triangles };
  }, { prefixes, flatBounds });
  await fs.writeFile(output, JSON.stringify(result));
  if (dartOutput) {
    const bytes = Buffer.alloc(
      4 + result.materials.length * 12 + 4 + result.triangles.length * 40,
    );
    let offset = 0;
    bytes.writeUInt32LE(result.materials.length, offset); offset += 4;
    for (const material of result.materials) {
      bytes.writeUInt32LE(material.color >>> 0, offset);
      bytes.writeUInt32LE(material.tint >>> 0, offset + 4);
      bytes.writeUInt8(material.bands, offset + 8);
      bytes.writeUInt8((material.unlit ? 1 : 0) | (material.mapped ? 2 : 0), offset + 9);
      offset += 12;
    }
    bytes.writeUInt32LE(result.triangles.length, offset); offset += 4;
    for (const triangle of result.triangles) {
      for (let i = 0; i < 9; i++) {
        bytes.writeFloatLE(triangle[i], offset); offset += 4;
      }
      bytes.writeUInt16LE(triangle[9], offset); offset += 4;
    }
    const packed = deflateSync(bytes, { level: 9 });
    const encoded = packed.toString('base64');
    const lines = encoded.match(/.{1,76}/g) ?? [];
    const source = `// Generated by tool/extract_flat_object_geometry.mjs.\n` +
      `// Source prefixes: ${prefixes.join(',')}\n` +
      `const ${dartConst} =\n${lines.map((line) => `    '${line}'`).join('\n')};\n`;
    await fs.writeFile(dartOutput, source);
    console.log(`WROTE ${dartOutput} (${packed.length}/${bytes.length} bytes)`);
  }
  console.log(`WROTE ${output} (${result.triangles.length} triangles, ` +
    `${result.materials.length} materials)`);
} finally {
  await browser.close();
}
