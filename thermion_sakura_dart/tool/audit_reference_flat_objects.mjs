#!/usr/bin/env node
import fs from 'node:fs/promises';
import path from 'node:path';
import { pathToFileURL } from 'node:url';

const root = process.env.SAKURA_REFERENCE || '/tmp/sakura-ref';
const url = process.env.SAKURA_REFERENCE_URL || 'http://127.0.0.1:5178';
const output = process.env.OUT || '/tmp/sakura-object-parity/reference-flat-objects.json';
const playwright = await import(pathToFileURL(
  path.join(root, 'node_modules/playwright/index.mjs'),
));
const browser = await playwright.chromium.launch({ headless: true });
try {
  const page = await browser.newPage();
  await page.goto(url, { waitUntil: 'domcontentloaded', timeout: 180000 });
  await page.waitForFunction(() => window.__scene?.world, null, {
    timeout: 180000,
  });
  const rows = await page.evaluate(async () => {
    const { flatAt } = await import('/src/world/planet.js');
    const { scene, THREE } = window.__scene;
    scene.updateMatrixWorld(true);
    function objectPath(object) {
      const segments = [];
      for (let node = object; node && node !== scene; node = node.parent) {
        const ordinal = node.parent ? node.parent.children.indexOf(node) : 0;
        const label = (node.name || node.type || 'Object3D').replaceAll('/', '_');
        segments.push(`${label}[${ordinal}]`);
      }
      return segments.reverse().join('/');
    }
    const worldPoint = new THREE.Vector3();
    const out = [];
    scene.traverse((object) => {
      if (!object.isMesh || object.isInstancedMesh || !object.geometry?.attributes?.position) return;
      const attr = object.geometry.attributes.position;
      const min = { x: Infinity, y: Infinity, z: Infinity };
      const max = { x: -Infinity, y: -Infinity, z: -Infinity };
      for (let i = 0; i < attr.count; i++) {
        worldPoint.fromBufferAttribute(attr, i).applyMatrix4(object.matrixWorld);
        const flat = flatAt(worldPoint);
        min.x = Math.min(min.x, flat.x); min.y = Math.min(min.y, flat.y); min.z = Math.min(min.z, flat.z);
        max.x = Math.max(max.x, flat.x); max.y = Math.max(max.y, flat.y); max.z = Math.max(max.z, flat.z);
      }
      if (max.x < -28.5 || min.x > -23.5 || max.z < 46.4 || min.z > 48.2 ||
          max.y < 3.1 || min.y > 4.8) return;
      const materials = (Array.isArray(object.material) ? object.material : [object.material])
        .filter(Boolean).map((m) => m.color?.getHexString?.() || '');
      out.push({ path: objectPath(object), vertices: attr.count, materials, min, max });
    });
    return out;
  });
  await fs.writeFile(output, JSON.stringify(rows, null, 2));
  console.log(`WROTE ${output} (${rows.length} objects)`);
} finally {
  await browser.close();
}
