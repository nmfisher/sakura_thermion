#!/usr/bin/env node
/** Capture lossless object-ID buffers for the representative reference views.
 *
 * Each visible source mesh gets a stable 24-bit colour derived from hierarchy
 * traversal order. The companion JSON maps pixels back to object paths. This
 * turns a visual diff into a ranked list of source objects instead of a manual
 * hunt through thousands of unnamed Three.js groups.
 */

import fs from 'node:fs/promises';
import path from 'node:path';
import { pathToFileURL } from 'node:url';

const referenceRoot = path.resolve(process.env.SAKURA_REFERENCE || '/tmp/sakura-ref');
const viewsPath = path.resolve(
  process.env.VIEWS || new URL('./fidelity_views.json', import.meta.url).pathname,
);
const serverUrl = process.env.SAKURA_REFERENCE_URL || 'http://127.0.0.1:5178';
const outputDir = path.resolve(process.env.OUT || '/tmp/sakura-object-ids');
const selected = process.env.ONLY ? new Set(process.env.ONLY.split(',')) : null;
const playwrightUrl = pathToFileURL(
  path.join(referenceRoot, 'node_modules/playwright/index.mjs'),
);
const { chromium } = await import(playwrightUrl.href);
const suite = JSON.parse(await fs.readFile(viewsPath, 'utf8'));
await fs.mkdir(outputDir, { recursive: true });

const browser = await chromium.launch({ headless: true });
try {
  const page = await browser.newPage({
    viewport: { width: suite.width, height: suite.height },
  });
  await page.goto(serverUrl, { waitUntil: 'domcontentloaded', timeout: 180_000 });
  await page.waitForFunction(() => window.__scene?.world, null, {
    timeout: 180_000,
  });
  await page.evaluate(() => {
    const world = window.__scene.world;
    world.update = () => {};
    world.train.x = 0.392;
    world.train.update(0);
    for (const mesh of world.petals.meshes) mesh.visible = false;
  });

  for (const view of suite.views.filter((row) => !selected || selected.has(row.name))) {
    const capture = await page.evaluate(({ view, width, height }) => {
      const { scene, camera, renderer, player, world, THREE } = window.__scene;
      world.train.x = view.train_x ?? 0.392;
      world.train.update(0);
      if (view.only_train_car !== undefined) {
        const car = world.train.cars[view.only_train_car];
        scene.traverse((object) => {
          if (!object.isMesh) return;
          let node = object;
          while (node && node !== car) node = node.parent;
          if (node !== car) object.visible = false;
        });
      }
      player.pos.set(view.px, world.heightAt(view.px, view.pz), view.pz);
      player.yaw = view.yaw;
      player.pitch = view.pitch;
      player.bob = 0;
      player.applyCamera(0);
      camera.aspect = width / height;
      camera.updateProjectionMatrix();
      renderer.setSize(width, height, false);
      renderer.setPixelRatio(1);
      renderer.outputColorSpace = THREE.LinearSRGBColorSpace;
      renderer.toneMapping = THREE.NoToneMapping;
      renderer.setClearColor(0x000000, 1);

      const rows = [];
      function objectPath(object) {
        const segments = [];
        for (let node = object; node && node !== scene; node = node.parent) {
          const ordinal = node.parent ? node.parent.children.indexOf(node) : 0;
          const label = (node.name || node.type || 'Object3D').replaceAll('/', '_');
          segments.push(`${label}[${ordinal}]`);
        }
        return segments.reverse().join('/');
      }
      let sourceIndex = 0;
      scene.traverse((object) => {
        if (!object.isMesh || object.visible === false || !object.geometry ||
            object.userData?.isOutline || object.material?.isShaderMaterial) {
          if (object.userData?.isOutline || object.material?.isShaderMaterial) {
            object.visible = false;
          }
          return;
        }
        const id = sourceIndex + 1;
        const r = id & 255;
        const g = (id >> 8) & 255;
        const b = (id >> 16) & 255;
        const originals = Array.isArray(object.material)
          ? object.material : [object.material];
        const original = originals.find(Boolean);
        const cutout = original &&
          (original.transparent || original.alphaTest > 0) &&
          (original.alphaMap || original.map);
        object.material = new THREE.MeshBasicMaterial({
          color: new THREE.Color(r / 255, g / 255, b / 255),
          side: original?.side ?? THREE.FrontSide,
          alphaMap: cutout ? (original.alphaMap || original.map) : null,
          alphaTest: cutout ? 0.01 : 0,
          depthWrite: true,
          depthTest: true,
          fog: false,
          toneMapped: false,
        });
        rows.push({ id, sourceIndex, path: objectPath(object),
          name: object.name || '', type: object.type });
        sourceIndex++;
      });
      scene.updateMatrixWorld(true);
      renderer.render(scene, camera);
      return {
        dataUrl: renderer.domElement.toDataURL('image/png'),
        objects: rows,
      };
    }, { view, width: suite.width, height: suite.height });
    const png = Buffer.from(capture.dataUrl.split(',', 2)[1], 'base64');
    await fs.writeFile(path.join(outputDir, `${view.name}.png`), png);
    await fs.writeFile(
      path.join(outputDir, `${view.name}.objects.json`),
      JSON.stringify({
        format: 'sakura-object-id-buffer-v1',
        width: suite.width,
        height: suite.height,
        objects: capture.objects,
      }, null, 2),
    );
    console.log(`WROTE ${path.join(outputDir, `${view.name}.png`)}`);
  }
} finally {
  await browser.close();
}
