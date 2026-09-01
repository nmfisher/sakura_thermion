#!/usr/bin/env node
import fs from 'node:fs/promises';
import path from 'node:path';
import { pathToFileURL } from 'node:url';

const root = process.env.SAKURA_REFERENCE || '/tmp/sakura-ref';
const url = process.env.SAKURA_REFERENCE_URL || 'http://127.0.0.1:5178';
const meshPrefix = process.env.MESH_PREFIX || 'groveCanopy';
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
  const rows = await page.evaluate(async (meshPrefix) => {
    const { flatAt, basisAt } = await import('/src/world/planet.js');
    const { scene, camera, player, world, THREE } = window.__scene;
    player.pos.set(-22.5, world.heightAt(-22.5, 48.8), 48.8);
    player.yaw = Math.PI / 2;
    player.pitch = -0.015;
    player.bob = 0;
    player.applyCamera(0);
    camera.aspect = 1600 / 900;
    camera.updateProjectionMatrix();
    camera.updateMatrixWorld(true);
    scene.updateMatrixWorld(true);
    const matrix = new THREE.Matrix4();
    const position = new THREE.Vector3();
    const rotation = new THREE.Quaternion();
    const flatRotation = new THREE.Quaternion();
    const frameRotation = new THREE.Quaternion();
    const basisMatrix = new THREE.Matrix4();
    const scale = new THREE.Vector3();
    const out = [];
    scene.traverse((object) => {
      if (!object.isInstancedMesh || !object.name.startsWith(meshPrefix)) return;
      for (let i = 0; i < object.count; i++) {
        object.getMatrixAt(i, matrix);
        matrix.premultiply(object.matrixWorld).decompose(position, rotation, scale);
        const flat = flatAt(position);
        if (flat.x < -54 || flat.x > -12 || flat.z < 40 || flat.z > 66) continue;
        const basis = basisAt(flat.x, flat.z);
        basisMatrix.makeBasis(basis.east, basis.up, basis.north);
        frameRotation.setFromRotationMatrix(basisMatrix).invert();
        flatRotation.copy(frameRotation).multiply(rotation);
        out.push({
          tone: Number(object.name.slice(meshPrefix.length)),
          x: flat.x, y: flat.y, z: flat.z,
          sx: scale.x, sy: scale.y, sz: scale.z,
          qx: flatRotation.x, qy: flatRotation.y,
          qz: flatRotation.z, qw: flatRotation.w,
          screenX: (position.clone().project(camera).x * .5 + .5) * 1600,
          screenY: (-position.clone().project(camera).y * .5 + .5) * 900,
        });
      }
    });
    return out;
  }, meshPrefix);
  const output = process.env.OUT || '/tmp/sakura-object-parity/source-onsen-grove.json';
  await fs.writeFile(output, JSON.stringify(rows, null, 2));
  console.log(`WROTE ${output} (${rows.length} instances)`);
} finally {
  await browser.close();
}
