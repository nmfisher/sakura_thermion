// Extract reference scene geometry (post planet-bake, world-space) + materials
// into a binary, posted to the vite /__shot endpoint in base64 chunks and
// reassembled by the driver. Optional RADIUS filter around (CX,CZ).
//
// Format v3:
//   u32 magic ('SAK3'), u32 atlasWidth, u32 atlasHeight, u32 numMaterials
//   per material: u32 colorHex, u32 tintHex, u8 rampLen, u8[rampLen] ramp, u8 flags
//      flags: bit0 = unlit, bit1 = smooth normals, bit2 = has color map
//   u32 numMeshes
//   per mesh: u32 matIdx, u32 numVerts, u32 flags,
//             f32[numVerts*12]
//               (px,py,pz,nx,ny,nz,mapU,mapV,atlasX,atlasY,sizePack,mapFlags)
// mapU/mapV have the Three texture matrix applied but retain their unwrapped
// range. atlasX/Y are the texture region's normalized top-left. sizePack is
// width + height*4096. mapFlags packs wrapS + 4*wrapT + 16*flipY, where wrap
// is 0=clamp, 1=repeat, 2=mirrored. Mesh flags are bit0=castShadow and
// bit1=receiveShadow. The shader applies wrapping per fragment;
// wrapping only triangle vertices destroys repeated textures.
// The atlas is emitted as a separate PNG. Both artifacts are deterministic for
// a frozen scene and are consumed only by the native Dart renderer.
const path = require('node:path');
const fs = require('node:fs');
const { createRequire } = require('node:module');

const REFERENCE_ROOT = path.resolve(process.env.SAKURA_REFERENCE || '/tmp/sakura-ref');
const REFERENCE_URL = process.env.SAKURA_REFERENCE_URL || 'http://127.0.0.1:5178/';
const OUTPUT_PATH = path.resolve(process.env.OUT || '/tmp/ref_geo.bin');
const ATLAS_PATH = path.resolve(
  process.env.ATLAS_OUT || OUTPUT_PATH.replace(/\.[^.]+$/, '') + '.atlas.png',
);
const MANIFEST_PATH = path.resolve(
  process.env.MANIFEST_OUT || OUTPUT_PATH.replace(/\.[^.]+$/, '') + '.manifest.json',
);
// Playwright belongs to the reference checkout rather than this Dart package.
// Resolve it there so the extractor works from any current working directory.
const referenceRequire = createRequire(path.join(REFERENCE_ROOT, 'package.json'));
const { chromium } = referenceRequire('playwright');

const URL = REFERENCE_URL;
const RADIUS = parseFloat(process.env.RADIUS || '0');
const CX = parseFloat(process.env.CX || '1.85');
const CZ = parseFloat(process.env.CZ || '13.6');
const ATLAS_WIDTH = parseInt(process.env.ATLAS_WIDTH || '8192', 10);
const CAMERA_FILTER = process.env.CAMERA_FILTER === '1';
const INCLUDE_PREFIXES = (process.env.INCLUDE_PREFIXES || '').split(',').filter(Boolean);
const INCLUDE_PATHS = process.env.INCLUDE_PATHS
  ? (() => {
      const data = JSON.parse(fs.readFileSync(path.resolve(process.env.INCLUDE_PATHS), 'utf8'));
      if (Array.isArray(data)) return data;
      const rows = data.objects ?? data.rankedObjects;
      return rows.map((row) => row.path);
    })()
  : null;

function chunkPath(prefix, i) {
  // The existing Vite frame-grabber appends .jpg to every non-JPEG name.
  return path.join(
    REFERENCE_ROOT,
    '.shots',
    `${prefix}_${String(i).padStart(5, '0')}.bin.jpg`,
  );
}

function assembleChunks(stats, outputPath, prefix) {
  fs.mkdirSync(path.dirname(outputPath), { recursive: true });
  const output = fs.openSync(outputPath, 'w');
  let assembled = 0;
  try {
    for (let i = 0; i < stats.nchunks; i++) {
      const data = fs.readFileSync(chunkPath(prefix, i));
      fs.writeSync(output, data);
      assembled += data.length;
    }
  } finally {
    fs.closeSync(output);
  }
  if (assembled !== stats.bytes) {
    throw new Error(`assembled ${assembled} bytes, expected ${stats.bytes}`);
  }
  for (let i = 0; i < stats.nchunks; i++) {
    fs.unlinkSync(chunkPath(prefix, i));
  }
  console.log('WROTE', outputPath, assembled);
}

if (process.env.ASSEMBLE_ONLY) {
  assembleChunks({
    nchunks: Number(process.env.CHUNKS),
    bytes: Number(process.env.BYTES),
  }, OUTPUT_PATH, process.env.PREFIX || 'geochunk');
  process.exit(0);
}

(async () => {
  const browser = await chromium.launch({ headless: true, args: [
    '--enable-webgl', '--use-gl=angle', '--use-angle=swiftshader',
    '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist', '--no-sandbox'] });
  const page = await (await browser.newContext({ viewport: { width: 64, height: 64 } })).newPage();
  page.on('pageerror', (e) => console.error('PAGEEX:', e.message));
  await page.goto(URL, { waitUntil: 'load', timeout: 60000 });
  await page.waitForFunction(() => !!(window.__scene && window.__scene.scene), { timeout: 60000 });
  await page.waitForTimeout(2000);

  const stats = await page.evaluate(async (env) => {
    const THREE = window.__scene.THREE;
    const root = window.__scene.scene;
    const R = env.RADIUS, cx = env.CX, cz = env.CZ;
    const includePaths = env.INCLUDE_PATHS ? new Set(env.INCLUDE_PATHS) : null;
    const includePrefixes = env.INCLUDE_PREFIXES;

    // Freeze the authored opening frame exactly like capture_reference.mjs.
    // Geometry extraction must not depend on how long Chromium took to load.
    const world = window.__scene.world;
    world.update = () => {};
    world.train.x = 0.392;
    world.train.update(0);
    for (const mesh of world.petals.meshes) mesh.visible = false;
    const camera = window.__scene.camera;
    if (env.CAMERA_FILTER) {
      const player = window.__scene.player;
      player.pos.set(cx, world.heightAt(cx, cz), cz);
      player.yaw = -Math.PI / 2;
      player.pitch = -0.02;
      player.bob = 0;
      player.applyCamera(0);
      camera.aspect = 1600 / 900;
      camera.updateProjectionMatrix();
      camera.updateMatrixWorld(true);
    }
    root.updateMatrixWorld(true);

    const matList = []; const matIdx = new Map();
    function matId(m) {
      if (matIdx.has(m.uuid)) return matIdx.get(m.uuid);
      const unlit = m.isMeshBasicMaterial ? 1 : 0;
      const flatOff = (m.flatShading === false) ? 2 : 0;
      const mapped = m.map && m.map.image ? 4 : 0;
      let rampLen = 3, ramp = [92, 178, 255];
      try {
        const g = m.gradientMap;
        if (g && g.image && g.image.data) {
          rampLen = g.image.width;
          ramp = [];
          for (let i = 0; i < rampLen; i++) ramp.push(g.image.data[i * 4]);
        }
      } catch (e) {}
      const tint = (m.userData && m.userData.shadowTint && m.userData.shadowTint.value) || null;
      const id = matList.length;
      matList.push({
        color: m.color ? parseInt(m.color.getHexString(), 16) : 0xffffff,
        tint: tint ? parseInt(tint.getHexString(), 16) : 0,
        rampLen, ramp, flags: unlit | flatOff | mapped, map: m.map || null,
      });
      matIdx.set(m.uuid, id);
      return id;
    }

    const meshes = [];
    const objects = [];
    let verts = 0;
    const _v = new THREE.Vector3(), _n = new THREE.Vector3();
    function objectPath(object) {
      const segments = [];
      for (let node = object; node && node !== root; node = node.parent) {
        const ordinal = node.parent ? node.parent.children.indexOf(node) : 0;
        const label = (node.name || node.type || 'Object3D').replaceAll('/', '_');
        segments.push(`${label}[${ordinal}]`);
      }
      return segments.reverse().join('/');
    }
    root.traverse((o) => {
      if (!o.isMesh) return;
      if ((o.userData && o.userData.isOutline) ||
          (!Array.isArray(o.material) && o.material && o.material.isShaderMaterial)) return;
      // Direct hullOutline() calls predate the isOutline tag and leave their
      // custom ShaderMaterial shells unmarked. They are screen-space ink, not
      // source surface geometry; importing them as ordinary meshes turns them
      // into solid white occluders.
      if (o.visible === false) return;
      const raw = o.geometry;
      if (!raw || !raw.attributes.position) return;
      const resolvedPath = objectPath(o);
      if (includePaths && !includePaths.has(resolvedPath) &&
          !includePrefixes.some((prefix) => resolvedPath.startsWith(prefix))) return;
      const objectRecord = {
        sourceIndex: objects.length,
        path: resolvedPath,
        name: o.name || '',
        type: o.type,
        sourceInstances: o.isInstancedMesh ? o.count : 1,
        includedInstances: 0,
        sourceTriangles: 0,
        includedTriangles: 0,
      };
      objects.push(objectRecord);
      const geo = raw.index ? raw.toNonIndexed() : raw;   // triangle list: every 3 verts
      const pos = geo.attributes.position;
      const nor = geo.attributes.normal;
      o.updateMatrixWorld(true);
      // resolve per-range materials (meshes can carry a material array + groups)
      const isArr = Array.isArray(o.material);
      const groups = (geo.groups && geo.groups.length) ? geo.groups : null;
      const ranges = [];
      if (isArr && groups) {
        for (const g of groups) ranges.push({ mat: o.material[g.materialIndex ?? 0], s: g.start, n: g.count });
      } else if (isArr) {
        ranges.push({ mat: o.material[0], s: 0, n: pos.count });
      } else {
        ranges.push({ mat: o.material, s: 0, n: pos.count });
      }
      const matrices = [];
      if (o.isInstancedMesh) {
        const tmp = new THREE.Matrix4();
        for (let i = 0; i < o.count; i++) {
          o.getMatrixAt(i, tmp);
          matrices.push(new THREE.Matrix4().multiplyMatrices(o.matrixWorld, tmp));
        }
      } else matrices.push(o.matrixWorld);
      objectRecord.sourceTriangles = (pos.count / 3) * matrices.length;
      for (const M of matrices) {
        const n3 = new THREE.Matrix3().getNormalMatrix(M);
        const uv = geo.attributes.uv;
        const full = new Float32Array(pos.count * 12);
        let sx = 0, sy = 0, sz = 0;
        for (let i = 0; i < pos.count; i++) {
          _v.fromBufferAttribute(pos, i).applyMatrix4(M);
          full[i * 12] = _v.x; full[i * 12 + 1] = _v.y; full[i * 12 + 2] = _v.z;
          sx += _v.x; sy += _v.y; sz += _v.z;
          if (nor) {
            _n.fromBufferAttribute(nor, i).applyMatrix3(n3).normalize();
            full[i * 12 + 3] = _n.x; full[i * 12 + 4] = _n.y; full[i * 12 + 5] = _n.z;
          }
          full[i * 12 + 6] = uv ? uv.getX(i) : 0;
          full[i * 12 + 7] = uv ? uv.getY(i) : 0;
        }
        const c = pos.count || 1;
        if (env.CAMERA_FILTER && o.isInstancedMesh) {
          _v.set(sx / c, sy / c, sz / c).project(camera);
          if (_v.z < -1 || _v.z > 1 || _v.x < -1.3 || _v.x > 1.3 ||
              _v.y < -1.3 || _v.y > 1.3) continue;
        }
        if (R > 0) {
          const dx = sx / c - cx, dz = sz / c - cz;
          if (dx * dx + dz * dz > R * R) continue;
        }
        objectRecord.includedInstances++;
        for (const rg of ranges) {
          const arr = full.slice(rg.s * 12, (rg.s + rg.n) * 12);
          meshes.push({
            mid: matId(rg.mat), count: rg.n, arr,
            sourceIndex: objectRecord.sourceIndex,
            flags: (o.castShadow ? 1 : 0) | (o.receiveShadow ? 2 : 0),
          });
          verts += rg.n;
          objectRecord.includedTriangles += rg.n / 3;
        }
      }
    });

    // Pack only maps referenced by geometry that survived the spatial filter.
    // This keeps representative fixtures small while preserving one stable
    // format for a later full-world export.
    const padding = 2;
    const atlasWidth = env.ATLAS_WIDTH;
    const textureMap = new Map();
    for (const m of matList) {
      const tex = m.map;
      if (!tex || !tex.image || textureMap.has(tex.uuid)) continue;
      textureMap.set(tex.uuid, {
        tex,
        image: tex.image,
        width: Number(tex.image.width || 0),
        height: Number(tex.image.height || 0),
      });
    }
    const textures = [...textureMap.values()].filter((t) => t.width && t.height)
      .sort((a, b) => b.height - a.height || b.width - a.width ||
        a.tex.uuid.localeCompare(b.tex.uuid));
    let ax = padding, ay = padding, rowHeight = 0;
    for (const t of textures) {
      if (ax + t.width + padding > atlasWidth) {
        ax = padding;
        ay += rowHeight + padding * 2;
        rowHeight = 0;
      }
      t.x = ax; t.y = ay;
      ax += t.width + padding * 2;
      rowHeight = Math.max(rowHeight, t.height);
    }
    const atlasHeight = Math.max(1, ay + rowHeight + padding);
    const atlas = document.createElement('canvas');
    atlas.width = atlasWidth;
    atlas.height = atlasHeight;
    const actx = atlas.getContext('2d');
    actx.clearRect(0, 0, atlasWidth, atlasHeight);
    for (const t of textures) {
      // The enlarged under-draw duplicates edge colors into the padding. The
      // exact-size over-draw leaves every authored texel untouched.
      actx.drawImage(t.image, t.x - padding, t.y - padding,
        t.width + padding * 2, t.height + padding * 2);
      actx.drawImage(t.image, t.x, t.y, t.width, t.height);
      t.tex.updateMatrix();
    }

    // Apply only Three.js's affine UV matrix here. Wrapping and flipY must be
    // performed per fragment after interpolation, just like the source GPU.
    const _uv = new THREE.Vector2();
    const wrapCode = (wrap) => wrap === THREE.RepeatWrapping ? 1
      : wrap === THREE.MirroredRepeatWrapping ? 2 : 0;
    for (const me of meshes) {
      const map = matList[me.mid].map;
      if (!map || !textureMap.has(map.uuid)) continue;
      const t = textureMap.get(map.uuid);
      const flags = wrapCode(map.wrapS) + 4 * wrapCode(map.wrapT) +
        (map.flipY ? 16 : 0);
      const sizePack = t.width + t.height * 4096;
      for (let i = 0; i < me.count; i++) {
        _uv.set(me.arr[i * 12 + 6], me.arr[i * 12 + 7]);
        _uv.applyMatrix3(map.matrix);
        me.arr[i * 12 + 6] = _uv.x;
        me.arr[i * 12 + 7] = _uv.y;
        me.arr[i * 12 + 8] = t.x / atlasWidth;
        me.arr[i * 12 + 9] = t.y / atlasHeight;
        me.arr[i * 12 + 10] = sizePack;
        me.arr[i * 12 + 11] = flags;
      }
    }

    // serialise into one typed buffer (align mesh section to 4 bytes)
    let matBytes = 16;
    for (const m of matList) matBytes += 4 + 4 + 1 + m.rampLen + 1;
    let meshStart = matBytes + 4;            // after numMeshes
    meshStart = (meshStart + 3) & ~3;        // align to 4
    let total = meshStart + meshes.length * 12 + verts * 48;
    total = (total + 3) & ~3;                // whole buffer 4-aligned (Float32 view)
    const buf = new ArrayBuffer(total);
    const u8 = new Uint8Array(buf);
    const dv = new DataView(buf);
    let p = 0;
    dv.setUint32(p, 0x53414b33, true); p += 4;
    dv.setUint32(p, atlasWidth, true); p += 4;
    dv.setUint32(p, atlasHeight, true); p += 4;
    dv.setUint32(p, matList.length, true); p += 4;
    for (const m of matList) {
      dv.setUint32(p, m.color, true); p += 4;
      dv.setUint32(p, m.tint, true); p += 4;
      u8[p++] = m.rampLen & 0xff;
      for (const r of m.ramp) u8[p++] = r & 0xff;
      u8[p++] = m.flags & 0xff;
    }
    dv.setUint32(p, meshes.length, true); p += 4;
    p = meshStart;                            // aligned start of mesh data
    const f32 = new Float32Array(buf);
    for (const me of meshes) {
      dv.setUint32(p, me.mid, true); p += 4;
      dv.setUint32(p, me.count, true); p += 4;
      dv.setUint32(p, me.flags, true); p += 4;
      f32.set(me.arr, p >> 2);
      p += me.count * 48;
    }

    const CSIZE = 3 * 1024 * 1024;
    async function postChunks(prefix, data) {
      const nchunks = Math.ceil(data.length / CSIZE);
      for (let c = 0; c < nchunks; c++) {
        const s = c * CSIZE, e = Math.min(data.length, s + CSIZE);
        const sub = data.subarray(s, e);
        let b64 = '';
        for (let i = 0; i < sub.length; i += 49152)
          b64 += btoa(String.fromCharCode.apply(null, sub.subarray(i, Math.min(sub.length, i + 49152))));
        await fetch('/__shot', {
          method: 'POST', headers: { 'content-type': 'application/json' },
          body: JSON.stringify({ name: prefix + '_' + String(c).padStart(5, '0') + '.bin',
            data: 'data:image/jpeg;base64,' + b64 })
        });
      }
      return { nchunks, bytes: data.length };
    }
    const geometry = await postChunks('geochunk', u8);
    const atlasBlob = await new Promise((resolve, reject) =>
      atlas.toBlob((blob) => blob ? resolve(blob) : reject(new Error('atlas PNG encode failed')), 'image/png'));
    const atlasBytes = new Uint8Array(await atlasBlob.arrayBuffer());
    const atlasResult = await postChunks('atlaschunk', atlasBytes);
    return { mats: matList.length, meshes: meshes.length, verts,
      textures: textures.length, atlasWidth, atlasHeight,
      objects, geometry, atlas: atlasResult };
  }, { RADIUS, CX, CZ, ATLAS_WIDTH, INCLUDE_PATHS, CAMERA_FILTER, INCLUDE_PREFIXES });

  const manifest = {
    format: 'sakura-extracted-object-coverage-v1',
    source: REFERENCE_URL,
    radius: RADIUS,
    center: [CX, CZ],
    objects: stats.objects,
    summary: {
      sourceObjects: stats.objects.length,
      exactObjects: stats.objects.filter((o) =>
        o.includedInstances === o.sourceInstances).length,
      partialObjects: stats.objects.filter((o) =>
        o.includedInstances > 0 && o.includedInstances < o.sourceInstances).length,
      excludedObjects: stats.objects.filter((o) => o.includedInstances === 0).length,
      materials: stats.mats,
      meshes: stats.meshes,
      vertices: stats.verts,
      textures: stats.textures,
      atlas: `${stats.atlasWidth}x${stats.atlasHeight}`,
    },
  };
  fs.mkdirSync(path.dirname(MANIFEST_PATH), { recursive: true });
  fs.writeFileSync(MANIFEST_PATH, JSON.stringify(manifest, null, 2));
  console.log('EXTRACT', JSON.stringify(manifest.summary));
  console.log('WROTE', MANIFEST_PATH);
  await browser.close();

  // The Vite helper accepts bounded request bodies, so the page posts chunks.
  // Reassemble them here and discard the intermediates after a verified write.
  assembleChunks(stats.geometry, OUTPUT_PATH, 'geochunk');
  assembleChunks(stats.atlas, ATLAS_PATH, 'atlaschunk');
})().catch((e) => { console.error('FATAL', e); process.exit(1); });
