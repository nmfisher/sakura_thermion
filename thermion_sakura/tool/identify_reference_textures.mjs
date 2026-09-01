#!/usr/bin/env node
/** Map audited CanvasTexture pixel hashes back to textures.js export calls. */

import fs from 'node:fs/promises';
import path from 'node:path';
import { createRequire } from 'node:module';
import { pathToFileURL } from 'node:url';

const referenceRoot = path.resolve(process.env.SAKURA_REFERENCE || '/tmp/sakura-ref');
const referenceUrl = process.env.SAKURA_REFERENCE_URL || 'http://127.0.0.1:5178/';
const manifestPath = path.resolve(process.argv[2] || '/tmp/sakura-object-manifest.json');
const outputPath = path.resolve(process.argv[3] || '/tmp/sakura-texture-identities.json');
const require = createRequire(path.join(referenceRoot, 'package.json'));
const { chromium } = require('playwright');
const manifest = JSON.parse(await fs.readFile(manifestPath, 'utf8'));
const wanted = new Set(manifest.textureTable.map((row) => row.pixelHash).filter(Boolean));
const browser = await chromium.launch({ headless: true });

try {
  const page = await browser.newPage({ viewport: { width: 64, height: 64 } });
  await page.goto(referenceUrl, { waitUntil: 'domcontentloaded', timeout: 180_000 });
  const candidates = await page.evaluate(async () => {
    const textures = await import('/src/core/textures.js');
    const args = [
      [], [false], [true],
      ...Array.from({ length: 24 }, (_, i) => [i]),
    ];
    const rows = [];
    const hashes = new WeakMap();
    async function digest(image) {
      if (hashes.has(image)) return hashes.get(image);
      const pending = (async () => {
      const canvas = document.createElement('canvas');
      canvas.width = image.width;
      canvas.height = image.height;
      canvas.getContext('2d').drawImage(image, 0, 0);
      const pixels = canvas.getContext('2d').getImageData(0, 0, image.width, image.height).data;
      const hash = await crypto.subtle.digest('SHA-256', pixels);
      return [...new Uint8Array(hash)].map((v) => v.toString(16).padStart(2, '0')).join('');
      })();
      hashes.set(image, pending);
      return pending;
    }
    for (const [name, fn] of Object.entries(textures)) {
      if (typeof fn !== 'function') continue;
      for (const callArgs of args) {
        try {
          const texture = fn(...callArgs);
          const image = texture?.image || texture?.source?.data;
          if (!image?.width || !image?.height) continue;
          rows.push({
            call: `${name}(${callArgs.map(String).join(',')})`,
            hash: await digest(image),
            width: image.width,
            height: image.height,
          });
        } catch (_) {
          // Some generators require structured/string arguments; those remain
          // explicitly unidentified instead of receiving a guessed identity.
        }
      }
    }
    return rows;
  });
  const callsByHash = new Map();
  for (const row of candidates) {
    if (!wanted.has(row.hash)) continue;
    const calls = callsByHash.get(row.hash) || new Set();
    calls.add(row.call);
    callsByHash.set(row.hash, calls);
  }
  const textures = manifest.textureTable.map((row) => ({
    ...row,
    candidateCalls: [...(callsByHash.get(row.pixelHash) || [])].sort(),
  }));
  const identified = textures.filter((row) => row.candidateCalls.length).length;
  await fs.writeFile(outputPath, JSON.stringify({
    format: 'sakura-texture-identities-v1',
    identified,
    total: textures.length,
    textures,
  }, null, 2) + '\n');
  console.log(`identified ${identified}/${textures.length}; WROTE ${outputPath}`);
} finally {
  await browser.close();
}
