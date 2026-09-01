#!/usr/bin/env node
import fs from 'node:fs/promises';
import path from 'node:path';
import {pathToFileURL} from 'node:url';

const root = process.env.SAKURA_REFERENCE || '/tmp/sakura-ref';
const url = process.env.SAKURA_REFERENCE_URL || 'http://127.0.0.1:5178';
const playwright = await import(pathToFileURL(
  path.join(root, 'node_modules/playwright/index.mjs')));
const names = [
  'hillSun', 'hillTurf', 'hillDeep', 'hillBracken', 'hillEarth',
  'hillLitter', 'lakeBed', 'lakeShore',
];
const browser = await playwright.chromium.launch({headless: true});
try {
  const page = await browser.newPage();
  await page.goto(url, {waitUntil: 'domcontentloaded', timeout: 180000});
  await page.waitForFunction(() => window.__scene?.world, null,
      {timeout: 180000});
  const rows = await page.evaluate(async (names) => {
    const {flatAt} = await import('/src/world/planet.js');
    const {scene, THREE} = window.__scene;
    scene.updateMatrixWorld(true);
    const result = Object.fromEntries(names.map((name) => [name, []]));
    const p = new THREE.Vector3();
    scene.traverse((object) => {
      if (!object.isMesh || !names.includes(object.name) ||
          object.isInstancedMesh || object.renderOrder < 0) return;
      const position = object.geometry?.attributes?.position;
      if (!position) return;
      const index = object.geometry.index;
      const count = index ? index.count : position.count;
      const out = result[object.name];
      for (let i = 0; i < count; i++) {
        const vi = index ? index.getX(i) : i;
        p.fromBufferAttribute(position, vi).applyMatrix4(object.matrixWorld);
        const f = flatAt(p);
        out.push(f.x, f.y, f.z);
      }
    });
    return result;
  }, names);
  const chunks = [];
  for (const name of names) {
    const values = rows[name];
    const b = Buffer.allocUnsafe(4 + values.length / 3 * 6);
    b.writeUInt32LE(values.length / 3, 0);
    let o = 4;
    for (let i = 0; i < values.length; i += 3) {
      b.writeUInt16LE(Math.max(0, Math.min(65535,
        Math.round((values[i] + 200) * 100))), o); o += 2;
      b.writeUInt16LE(Math.max(0, Math.min(65535,
        Math.round((values[i + 1] + 10) * 1000))), o); o += 2;
      b.writeUInt16LE(Math.max(0, Math.min(65535,
        Math.round((values[i + 2] + 200) * 100))), o); o += 2;
    }
    chunks.push(b);
    console.log(`${name}: ${values.length / 9} triangles`);
  }
  const output = process.env.OUT || '/tmp/sakura-geometry/hill-surface.u16';
  await fs.writeFile(output, Buffer.concat(chunks));
  console.log(`WROTE ${output}`);
} finally {
  await browser.close();
}
