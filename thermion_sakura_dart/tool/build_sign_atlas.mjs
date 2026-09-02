#!/usr/bin/env node
// Build the deterministic sign atlas used by the native Thermion port.
//
// The source scene owns the artwork: its Canvas2D texture functions are
// evaluated in Chromium so the pixels, font fallback, sizing, and spacing are
// exactly the same as the Three.js reference. The checked-in PNG is then a
// normal package asset; rendering never depends on a browser.

import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const packageRoot = path.resolve(here, '..');
const referenceRoot = path.resolve(
  process.env.SAKURA_REFERENCE || '/tmp/sakura-ref',
);
const referenceUrl = process.env.SAKURA_REFERENCE_URL || 'http://127.0.0.1:5178/';
const output = path.resolve(
  process.env.OUT || path.join(packageRoot, 'lib/assets/sakura_signs.png'),
);
const referenceRequire = createRequire(path.join(referenceRoot, 'package.json'));
const { chromium } = referenceRequire('playwright');

const browser = await chromium.launch({
  headless: true,
  args: [
    '--enable-webgl', '--use-gl=angle', '--use-angle=swiftshader',
    '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist', '--no-sandbox',
  ],
});

try {
  const page = await (await browser.newContext({ viewport: { width: 64, height: 64 } })).newPage();
  await page.goto(referenceUrl, { waitUntil: 'load', timeout: 60000 });
  const dataUrl = await page.evaluate(async () => {
    const textures = await import('/src/core/textures.js');
    const atlas = document.createElement('canvas');
    atlas.width = 4096;
    atlas.height = 4096;
    const c = atlas.getContext('2d');
    c.clearRect(0, 0, atlas.width, atlas.height);

    // Bake the source's repeating chain-link map at the refuse gate's exact
    // physical repeat (1.54/.11 by .82/.11). Keeping this as one atlas region
    // avoids sampling outside a sub-rectangle when the shared atlas itself is
    // clamp-to-edge.
    const chainSource = textures.chainLinkTex().image;
    const chainPanel = document.createElement('canvas');
    chainPanel.width = 770;
    chainPanel.height = 410;
    const chainContext = chainPanel.getContext('2d');
    const pattern = chainContext.createPattern(chainSource, 'repeat');
    const cellPixels = chainPanel.width / (1.54 / .11);
    pattern.setTransform(new DOMMatrix().scale(
      cellPixels / chainSource.width,
      cellPixels / chainSource.height,
    ));
    chainContext.fillStyle = pattern;
    chainContext.fillRect(0, 0, chainPanel.width, chainPanel.height);

    const schoolChainPanel = document.createElement('canvas');
    schoolChainPanel.width = 1600;
    schoolChainPanel.height = 40;
    const schoolChainContext = schoolChainPanel.getContext('2d');
    const schoolPattern = schoolChainContext.createPattern(chainSource, 'repeat');
    const schoolCellPixels = schoolChainPanel.width / (32 / .30);
    schoolPattern.setTransform(new DOMMatrix().scale(
      schoolCellPixels / chainSource.width,
      schoolCellPixels / chainSource.height,
    ));
    schoolChainContext.fillStyle = schoolPattern;
    schoolChainContext.fillRect(0, 0,
      schoolChainPanel.width, schoolChainPanel.height);

    // Thermion's compact hand-authored material path has no transparent
    // second surface for these shop windows. Pre-compose the source's 42%
    // blue glass over the exact Canvas2D interior so its authored labels and
    // stock remain intact with the same glazing colour contribution.
    const glazedInterior = (variant) => {
      const source = textures.superInterior(variant).image;
      const panel = document.createElement('canvas');
      panel.width = source.width;
      panel.height = source.height;
      const pc = panel.getContext('2d');
      pc.drawImage(source, 0, 0);
      pc.fillStyle = 'rgba(157, 192, 212, 0.42)';
      pc.fillRect(0, 0, panel.width, panel.height);
      return panel;
    };

    const glazedTatami = (variant) => {
      const source = textures.tatamiRoom(variant).image;
      const panel = document.createElement('canvas');
      panel.width = source.width;
      panel.height = source.height;
      const pc = panel.getContext('2d');
      pc.drawImage(source, 0, 0);
      pc.fillStyle = 'rgba(157, 192, 212, 0.50)';
      pc.fillRect(0, 0, panel.width, panel.height);
      return panel;
    };

    const entries = [
      { image: textures.hallPlate().image, x: 2, y: 2 },
      { image: textures.hallNotice(0).image, x: 518, y: 2 },
      { image: textures.gomiPlate(0).image, x: 780, y: 2 },
      { image: chainPanel, x: 1170, y: 2 },
      { image: textures.platePlate().image, x: 2, y: 420 },
      { image: textures.crossingSign().image, x: 262, y: 420 },
      { image: textures.stationSign().image, x: 778, y: 420 },
      { image: textures.warningPlate(1).image, x: 1548, y: 420 },
      { image: textures.trainDest().image, x: 2, y: 680 },
      { image: textures.trainNumber().image, x: 518, y: 680 },
      { image: textures.superFascia().image, x: 2046, y: 2 },
      { image: glazedInterior(2), x: 2046, y: 262 },
      { image: glazedInterior(1), x: 2562, y: 262 },
      { image: textures.superBanner(0).image, x: 3070, y: 262 },
      { image: textures.superBanner(1).image, x: 3070, y: 458 },
      { image: textures.superBanner(2).image, x: 3070, y: 654 },
      { image: textures.onsenFascia('yunoya').image, x: 2, y: 1026 },
      { image: textures.onsenFascia('hourai').image, x: 1030, y: 1026 },
      { image: textures.onsenFascia('sakuraan').image, x: 2058, y: 1026 },
      { image: textures.onsenFascia('yunoka').image, x: 3070, y: 1026 },
      { image: textures.onsenFascia('kokeshi').image, x: 2, y: 1250 },
      { image: textures.onsenBlade('yunoya').image, x: 1030, y: 1250 },
      { image: textures.onsenBlade('hourai').image, x: 1226, y: 1250 },
      { image: textures.onsenBlade('sakuraan').image, x: 1422, y: 1250 },
      { image: textures.onsenBlade('yunoka').image, x: 1618, y: 1250 },
      { image: textures.onsenBlade('kokeshi').image, x: 1814, y: 1250 },
      { image: textures.onsenNoren('yunoya').image, x: 2010, y: 1250 },
      { image: textures.onsenNoren('kanmi').image, x: 2526, y: 1250 },
      { image: textures.onsenNoren('kissa').image, x: 3042, y: 1250 },
      { image: textures.tatamiRoom(0).image, x: 2010, y: 1510 },
      { image: textures.tatamiRoom(1).image, x: 2526, y: 1510 },
      { image: textures.shopFascia('bento').image, x: 2010, y: 1834 },
      { image: textures.shopFascia('zakka').image, x: 3070, y: 1834 },
      { image: textures.shopFascia('bungu').image, x: 2, y: 2022 },
      { image: textures.onsenLanternTex(0).image, x: 1030, y: 2022 },
      { image: textures.onsenLanternTex(1).image, x: 1290, y: 2022 },
      { image: textures.onsenLanternTex(2).image, x: 1550, y: 2022 },
      { image: glazedTatami(0), x: 1810, y: 2022 },
      { image: glazedTatami(1), x: 2326, y: 2022 },
      { image: textures.poster(2).image, x: 2842, y: 2022 },
      { image: textures.houraiFuji().image, x: 2, y: 2498 },
      { image: textures.onsenNoren('male').image, x: 1030, y: 2498 },
      { image: textures.onsenNoren('female').image, x: 1546, y: 2498 },
      { image: textures.ashiyuPlate().image, x: 2062, y: 2498 },
      { image: schoolChainPanel, x: 2450, y: 2498 },
      { image: textures.roadPaint('arrow').image, x: 2, y: 3014 },
      { image: textures.superHours().image, x: 518, y: 3014 },
      { image: textures.superPoster(0).image, x: 906, y: 3014 },
      { image: textures.superPoster(1).image, x: 1272, y: 3014 },
      { image: textures.superPoster(2).image, x: 1638, y: 3014 },
      { image: textures.superPoster(3).image, x: 2004, y: 3014 },
      { image: textures.superDeal().image, x: 2370, y: 3014 },
      { image: textures.warningPlate(3).image, x: 2760, y: 3014 },
      { image: textures.noParking().image, x: 3020, y: 3014 },
      { image: textures.vendHeader(0).image, x: 2, y: 3530 },
      { image: textures.vendHeader(1).image, x: 518, y: 3530 },
      { image: textures.vendHeader(2).image, x: 1034, y: 3530 },
      { image: textures.vendPrice().image, x: 1550, y: 3530 },
      { image: textures.vendCold(false).image, x: 2066, y: 3530 },
      { image: textures.vendCold(true).image, x: 2326, y: 3530 },
      { image: textures.vendSlot().image, x: 2586, y: 3530 },
      { image: textures.norenTex('bento').image, x: 2850, y: 3530 },
      { image: textures.flagTex(0).image, x: 3366, y: 3530 },
      { image: textures.flagTex(1).image, x: 3626, y: 3530 },
    ];
    const padding = 2;
    for (const entry of entries) {
      const { image, x, y } = entry;
      // Bleed edge colours into the gutter before restoring every authored
      // texel. This prevents mip/filter samples from picking up transparency.
      c.drawImage(image, x - padding, y - padding,
        image.width + padding * 2, image.height + padding * 2);
      c.drawImage(image, x, y, image.width, image.height);
    }
    return atlas.toDataURL('image/png');
  });

  fs.mkdirSync(path.dirname(output), { recursive: true });
  fs.writeFileSync(output, Buffer.from(dataUrl.split(',', 2)[1], 'base64'));
  console.log(`WROTE ${output}`);
} finally {
  await browser.close();
}
