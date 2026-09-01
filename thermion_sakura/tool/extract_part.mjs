// Validation oracle: instantiate a reference geometry factory (makePole) in
// Node + three.js, and dump its world-space triangles (centroid, face normal,
// material colour) plus the mulberry32 rng sequence. The Dart port
// (`thermion_sakura/lib/src/world_ref/make_pole.dart`) produces the same and
// the two are diffed — proving the substrate (box/cyl/trs/bake/rng) + the
// mechanical translation reproduce three.js's geometry exactly.
//
//   node tool/extract_part.mjs <out_tris.txt> <out_rng.txt>
//
// Requires the reference project at /tmp/sakura-ref (the sakura-crossing app).
// makePole pulls in textures.js, which builds canvas textures at import time;
// it never USES them in makePole, so a no-op DOM stub lets the module load.
import * as THREE from '/tmp/sakura-ref/node_modules/three/build/three.module.js';
import { writeFileSync } from 'fs';

// Minimal DOM stub so textures.js's top-level canvas creation doesn't throw.
const _noopCtx = new Proxy({}, { get: () => () => _noopCtx });
const _fakeCanvas = { width: 0, height: 0, getContext: () => _noopCtx, addEventListener() {} };
globalThis.document = { createElement: (t) => (t === 'canvas' ? _fakeCanvas : {}) };
globalThis.window = globalThis;
const _warn = console.warn;
console.warn = () => {}; // silence the harmless flatShading-on-ToonMaterial notes
const { makePole } = await import('/tmp/sakura-ref/src/world/props.js');
const { buildSakura } = await import('/tmp/sakura-ref/src/world/trees.js');
const { makeHouse } = await import('/tmp/sakura-ref/src/world/buildings.js');
const { buildRailway } = await import('/tmp/sakura-ref/src/world/railway.js');
const { buildTrain } = await import('/tmp/sakura-ref/src/world/train.js');
const { buildShop } = await import('/tmp/sakura-ref/src/world/shop.js');
const { buildPetals } = await import('/tmp/sakura-ref/src/world/petals.js');
const { mulberry32 } = await import('/tmp/sakura-ref/src/core/util.js');
console.warn = _warn;

// Dump world-space triangles (centroid, face normal, material colour) of a root
// object graph into [outFile]. Handles InstancedMesh (one geometry per instance).
function dumpScene(root, outFile) {
  const scene = new THREE.Scene();
  scene.add(root);
  scene.updateMatrixWorld(true);
  const tris = [];
  const _v = [new THREE.Vector3(), new THREE.Vector3(), new THREE.Vector3()];
  const _n = new THREE.Vector3();
  const _m4 = new THREE.Matrix4();
  const emit = (geometry, mw, col) => {
    const pos = geometry.getAttribute('position');
    const nor = geometry.getAttribute('normal');
    const idx = geometry.index;
    const nm = new THREE.Matrix3().getNormalMatrix(mw);
    const push = (a, b, c) => {
      _v[0].fromBufferAttribute(pos, a).applyMatrix4(mw);
      _v[1].fromBufferAttribute(pos, b).applyMatrix4(mw);
      _v[2].fromBufferAttribute(pos, c).applyMatrix4(mw);
      const cx = (_v[0].x + _v[1].x + _v[2].x) / 3;
      const cy = (_v[0].y + _v[1].y + _v[2].y) / 3;
      const cz = (_v[0].z + _v[1].z + _v[2].z) / 3;
      _n.fromBufferAttribute(nor, a).applyMatrix3(nm).normalize();
      tris.push([cx, cy, cz, _n.x, _n.y, _n.z, col]);
    };
    if (idx) for (let i = 0; i < idx.count; i += 3) push(idx.getX(i), idx.getX(i + 1), idx.getX(i + 2));
    else for (let i = 0; i < pos.count; i += 3) push(i, i + 1, i + 2);
  };
  root.traverse((obj) => {
    if (!obj.isMesh || !obj.geometry) return;
    const mat = obj.material;
    const col = mat && !Array.isArray(mat) && mat.color ? mat.color.getHexString() : null;
    if (!col) return;
    if (obj.isInstancedMesh) {
      const im = new THREE.Matrix4();
      for (let i = 0; i < obj.count; i++) {
        obj.getMatrixAt(i, im);
        _m4.multiplyMatrices(obj.matrixWorld, im);
        emit(obj.geometry, _m4, parseInt(col, 16));
      }
    } else {
      emit(obj.geometry, obj.matrixWorld, parseInt(col, 16));
    }
  });
  tris.sort((a, b) => a[0] - b[0] || a[1] - b[1] || a[2] - b[2]);
  writeFileSync(outFile, tris.map((t) => t.map((x) => (+Number(x).toFixed(6))).join(' ')).join('\n'));
  return tris.length;
}

// Fixed params — must match the Dart ports exactly.
const pole = makePole({ seed: 11, h: 9.2, x: 5, y: 0, z: -3, lamp: true, transformer: true, armDir: 1 });
console.log('JS pole tris:', dumpScene(pole, process.argv[2] || '/tmp/pole_js.txt'));

// A cherry tree: buildSakura(ctx, spots). ctx only needs add/collide here.
const ctx = { add(o) { return o; }, collide() {} };
const { wood, canopies } = buildSakura(ctx, [{ x: 0, z: 0, scale: 1, seed: 42 }]);
const treeRoot = new THREE.Group();
treeRoot.add(wood);
for (const c of canopies) treeRoot.add(c);
console.log('JS sakura tris:', dumpScene(treeRoot, process.argv[3] || '/tmp/sakura_js.txt'));

const r = mulberry32(42);
const rng = Array.from({ length: 20 }, () => r());
writeFileSync(process.argv[4] || '/tmp/rng_js.txt', rng.map((x) => (+x.toFixed(10))).join('\n'));
console.log('JS rng:', rng.length);

// A house: makeHouse(o) returns a Group. Fixed params — match the Dart port.
const house = makeHouse({ x: 0, z: 0, w: 7.0, d: 7.0, floors: 2, face: 'x+', seed: 21, wall: 0, roof: 1, roofKind: 'gable' });
console.log('JS house tris:', dumpScene(house, process.argv[5] || '/tmp/house_js.txt'));

// Railway/train/shop/petals: build*(ctx) add to ctx. Collect and dump.
function collectCtx() {
  const root = new THREE.Group();
  const ctx = {
    scene: { add() {} }, root,
    add(o) { root.add(o); return o; },
    collide() {}, platform() {}, cut() {}, interact() {}, update() {},
    groundAt: () => 0, heightAt: () => 0,
  };
  return { root, ctx };
}
let c = collectCtx(); buildRailway(c.ctx);
console.log('JS railway tris:', dumpScene(c.root, process.argv[6] || '/tmp/railway_js.txt'));
c = collectCtx(); buildTrain(c.ctx);
console.log('JS train tris:', dumpScene(c.root, process.argv[7] || '/tmp/train_js.txt'));
c = collectCtx(); buildShop(c.ctx);
console.log('JS shop tris:', dumpScene(c.root, process.argv[8] || '/tmp/shop_js.txt'));
const { buildShrubs, buildCedar } = await import('/tmp/sakura-ref/src/world/trees.js');
c = collectCtx(); buildShrubs(c.ctx, [{ x: 0, z: 0, seed: 65 }]);
console.log('JS shrubs tris:', dumpScene(c.root, process.argv[9] || '/tmp/shrubs_js.txt'));
c = collectCtx(); buildCedar(c.ctx, [{ x: 0, z: 0, scale: 1.1, seed: 61 }]);
console.log('JS cedar tris:', dumpScene(c.root, process.argv[10] || '/tmp/cedar_js.txt'));
