#!/usr/bin/env node
import fs from 'node:fs/promises';
import path from 'node:path';
import { pathToFileURL } from 'node:url';

const root = process.env.SAKURA_REFERENCE || '/tmp/sakura-ref';
const url = process.env.SAKURA_REFERENCE_URL || 'http://127.0.0.1:5178';
const playwright = await import(pathToFileURL(
  path.join(root, 'node_modules/playwright/index.mjs'),
));
const browser = await playwright.chromium.launch({headless: true});
try {
  const page = await browser.newPage();
  await page.goto(url, {waitUntil: 'domcontentloaded', timeout: 180000});
  await page.waitForFunction(() => globalThis.__hillPlanting, null,
      {timeout: 180000});
  const planting = await page.evaluate(() => globalThis.__hillPlanting);
  const out = process.env.OUT || '/tmp/sakura-geometry/source-hill-planting.json';
  await fs.writeFile(out, JSON.stringify(planting, null, 2));
  console.log(`WROTE ${out}: ${planting.sakura.length} sakura, ` +
      `${planting.grove.length} grove, ${planting.cedar.length} cedar`);
} finally {
  await browser.close();
}
