#!/usr/bin/env node
/** Capture every fidelity view from a running sakura-crossing dev server.
 *
 * Usage:
 *   node tool/capture_reference.mjs /path/to/sakura-crossing [views.json] [url]
 *
 * Playwright is loaded from the reference checkout, so it need not be a
 * dependency of this Dart package. The reference's Vite dev server must
 * already be running; its __shot helper writes JPEGs to <reference>/.shots.
 */

import fs from 'node:fs/promises';
import path from 'node:path';
import { pathToFileURL } from 'node:url';

const referenceRoot = path.resolve(process.argv[2] ?? '/tmp/sakura-ref');
const viewsPath = path.resolve(
  process.argv[3] ?? new URL('./fidelity_views.json', import.meta.url).pathname,
);
const serverUrl = process.argv[4] ?? 'http://127.0.0.1:5178';
const playwrightUrl = pathToFileURL(
  path.join(referenceRoot, 'node_modules/playwright/index.mjs'),
);
const { chromium } = await import(playwrightUrl.href);
const suite = JSON.parse(await fs.readFile(viewsPath, 'utf8'));
const selected = process.env.ONLY ? new Set(process.env.ONLY.split(',')) : null;
const disableShadows = process.env.NO_SHADOWS === '1';
const shotSuffix = process.env.SHOT_SUFFIX ?? '';
const browser = await chromium.launch({ headless: true });

try {
  const page = await browser.newPage({
    viewport: { width: suite.width, height: suite.height },
  });
  page.on('console', (message) => {
    if (message.type() === 'error') console.error(`browser: ${message.text()}`);
  });
  await page.goto(serverUrl, { waitUntil: 'domcontentloaded', timeout: 180_000 });
  await page.waitForFunction(() => typeof window.__shot === 'function', null, {
    timeout: 180_000,
  });
  await page.evaluate(() => {
    const world = window.__scene.world;
    // The fidelity target is a static authored frame. Freeze the simulation,
    // put the train at the Dart port's default opening position, and hide the
    // continuously falling field (fallen petals remain part of the scene).
    world.update = () => {};
    world.train.x = 0.392;
    world.train.update(0);
    for (const mesh of world.petals.meshes) mesh.visible = false;
  });

  for (const view of suite.views.filter((item) => !selected || selected.has(item.name))) {
    const result = await page.evaluate(async ({ view, width, height, disableShadows, shotSuffix }) => {
      const { world, scene, renderer } = window.__scene;
      if (disableShadows) renderer.shadowMap.enabled = false;
      world.train.x = view.train_x ?? 0.392;
      world.train.update(0);
      const isolated = [];
      if (view.only_train_car !== undefined) {
        const car = world.train.cars[view.only_train_car];
        scene.traverse((object) => {
          if (!object.isMesh) return;
          let node = object;
          while (node && node !== car) node = node.parent;
          if (node !== car) {
            isolated.push([object, object.visible]);
            object.visible = false;
          }
        });
      }
      const ground = world.heightAt(view.px, view.pz);
      const shot = await window.__shot(view.name + shotSuffix, width, height, {
        pos: [view.px, 0, view.pz],
        yaw: view.yaw,
        pitch: view.pitch,
        quality: 1,
        scale: 1,
      });
      for (const [object, visible] of isolated) object.visible = visible;
      return { shot, ground, expectedEye: ground + 1.62 };
    }, { view, width: suite.width, height: suite.height, disableShadows, shotSuffix });
    const eyeDelta = view.eye - result.expectedEye;
    console.log(
      `${view.name}: ground=${result.ground.toFixed(3)} ` +
      `eye=${result.expectedEye.toFixed(3)} ` +
      `declared-eye-delta=${eyeDelta.toFixed(3)}`,
    );
  }
} finally {
  await browser.close();
}
