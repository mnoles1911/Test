// ===========================================================================
// tree_voxelizer.js — turn an ez-tree skeleton into 6-connected cubic voxels
// ===========================================================================
//
// PURE module: no THREE, no DOM. Safe to import on the main thread OR inside a
// Web Worker. Input is the skeleton our forked ez-tree captures
// (vendor/ez-tree/tree.js): a list of branch centerline polylines + radii, plus
// leaf anchor points. Output is flat typed arrays of voxel positions + material
// ids, ready for an InstancedMesh and for the game export.
//
// WHY 6-connected matters: the game's tree-felling (`SeverFollowLib.gd`) floods
// a chopped tree through FACE neighbors only. If any wood voxel were merely
// diagonally touching, the tree would break into pieces when chopped. So we
// rasterize branch centerlines with strictly orthogonal steps, and we GROW
// leaves outward from wood (never place floating canopy blobs).
//
// Material ids (rich palette; see DESIGNER_TODO). 16–23 are taken by native
// fluid models, so the tree palette starts at 24.
export const MAT = {
  BARK: 24,
  HEARTWOOD: 25,
  DEADWOOD: 26,
  LEAF_DARK: 27,
  LEAF_LIGHT: 28,
  GRASS: 29,
  GRASS_DRY: 30,
  FERN: 31,
};
export const WOOD_IDS = [MAT.BARK, MAT.HEARTWOOD, MAT.DEADWOOD];
export const LEAF_IDS = [MAT.LEAF_DARK, MAT.LEAF_LIGHT, MAT.GRASS, MAT.GRASS_DRY, MAT.FERN];
// Collapse map for the deployable export (wood→10 log, foliage→11 leaves).
export const COLLAPSE = {
  [MAT.BARK]: 10, [MAT.HEARTWOOD]: 10, [MAT.DEADWOOD]: 10,
  [MAT.LEAF_DARK]: 11, [MAT.LEAF_LIGHT]: 11,
  [MAT.GRASS]: 11, [MAT.GRASS_DRY]: 11, [MAT.FERN]: 11,
};

// Integer cell packing. Coordinates are kept within ±OFFSET voxels (a 200 m
// tree at 10 cm/vox = 2000 vox, well inside the range). One Map keyed by a
// single number is far faster than string keys for 100k–500k voxels.
const OFFSET = 4096;
const SPAN = 8192;
const packKey = (x, y, z) => (x + OFFSET) * SPAN * SPAN + (y + OFFSET) * SPAN + (z + OFFSET);

// Tiny seeded RNG (mulberry32) so foliage is reproducible per seed.
function makeRng(seed) {
  let a = seed >>> 0;
  return () => {
    a |= 0; a = (a + 0x6d2b79f5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

// Cheap value-noise for light gaps in the canopy (deterministic).
function valueNoise(x, y, z) {
  const s = Math.sin(x * 12.9898 + y * 78.233 + z * 37.719) * 43758.5453;
  return s - Math.floor(s);
}

// 6-connected line walk (Amanatides–Woo with orthogonal-only steps). Calls
// emit(x,y,z,t) for every cell from A to B; consecutive cells share a FACE.
function line6(a, b, emit) {
  let x = a[0], y = a[1], z = a[2];
  const dx = Math.abs(b[0] - a[0]), dy = Math.abs(b[1] - a[1]), dz = Math.abs(b[2] - a[2]);
  const sx = Math.sign(b[0] - a[0]), sy = Math.sign(b[1] - a[1]), sz = Math.sign(b[2] - a[2]);
  const n = dx + dy + dz;
  emit(x, y, z, 0);
  if (n === 0) return;
  const tdx = dx === 0 ? Infinity : 1 / dx;
  const tdy = dy === 0 ? Infinity : 1 / dy;
  const tdz = dz === 0 ? Infinity : 1 / dz;
  let tx = tdx, ty = tdy, tz = tdz;
  for (let i = 1; i <= n; i++) {
    if (tx <= ty && tx <= tz) { x += sx; tx += tdx; }
    else if (ty <= tz) { y += sy; ty += tdy; }
    else { z += sz; tz += tdz; }
    emit(x, y, z, i / n);
  }
}

const FACES = [[1,0,0],[-1,0,0],[0,1,0],[0,-1,0],[0,0,1],[0,0,-1]];

/**
 * @param {{level:number, points:number[][], radii:number[]}[]} skeleton
 * @param {number[][]} leafAnchors
 * @param {object} opts
 * @returns {{positions:Int16Array, materials:Uint8Array, stats:object}}
 */
export function voxelize(skeleton, leafAnchors, opts = {}) {
  const o = {
    voxelScale: 4.0,        // voxels per ez-tree unit (caller sets from target height)
    barkThickness: 1.0,     // outer shell thickness in voxels
    deadwoodFraction: 0.0,  // chance a high-order branch is deadwood
    deadwoodMinLevel: 2,
    leafClusterSize: 4,     // radius (vox) of each leaf clump
    leafDensity: 0.7,       // keep-probability inside a clump
    lightGap: 0.25,         // fraction carved out as gaps
    leafLightMix: 0.5,      // share of light-green leaves
    leaves: true,
    seed: 1,
    ...opts,
  };
  const S = o.voxelScale;
  const rng = makeRng(o.seed);
  const voxels = new Map(); // packedKey -> material id

  // -- helpers -------------------------------------------------------------
  const setWood = (x, y, z, mat) => {
    const k = packKey(x, y, z);
    const cur = voxels.get(k);
    // wood always wins; among wood, don't overwrite bark with heartwood
    if (cur === undefined) voxels.set(k, mat);
    else if (LEAF_IDS.includes(cur)) voxels.set(k, mat);
    else if (cur === MAT.HEARTWOOD && mat === MAT.BARK) voxels.set(k, mat);
  };
  const stampBall = (cx, cy, cz, r, deadwood, flatMat) => {
    if (r < 1) { setWood(cx, cy, cz, flatMat != null ? flatMat : (deadwood ? MAT.DEADWOOD : MAT.BARK)); return; }
    const ri = Math.ceil(r);
    const r2 = r * r;
    const inner2 = Math.max(0, r - o.barkThickness) * Math.max(0, r - o.barkThickness);
    for (let dx = -ri; dx <= ri; dx++)
      for (let dy = -ri; dy <= ri; dy++)
        for (let dz = -ri; dz <= ri; dz++) {
          const d2 = dx*dx + dy*dy + dz*dz;
          if (d2 > r2) continue;
          let mat;
          if (flatMat != null) mat = flatMat;                  // grass/fern green stems
          else if (deadwood) mat = MAT.DEADWOOD;
          else mat = d2 >= inner2 ? MAT.BARK : MAT.HEARTWOOD;
          setWood(cx + dx, cy + dy, cz + dz, mat);
        }
  };

  // -- 1. WOOD: rasterize every branch centerline as a 6-connected capsule --
  for (const br of skeleton) {
    const deadwood = o.deadwoodFraction > 0 && br.level >= o.deadwoodMinLevel
      && rng() < o.deadwoodFraction;
    const pts = br.points, radii = br.radii, flatMat = br.mat;
    for (let i = 0; i < pts.length - 1; i++) {
      const a = [Math.round(pts[i][0]*S), Math.round(pts[i][1]*S), Math.round(pts[i][2]*S)];
      const b = [Math.round(pts[i+1][0]*S), Math.round(pts[i+1][1]*S), Math.round(pts[i+1][2]*S)];
      const r0 = radii[i] * S, r1 = radii[i+1] * S;
      line6(a, b, (x, y, z, t) => stampBall(x, y, z, r0 + (r1 - r0) * t, deadwood, flatMat));
    }
  }

  // Optional ground mat (ground cover) — a thin disc at y=0 that ties scattered
  // tufts into one connected body.
  if (o.groundDisc) {
    const R = Math.round(o.groundDisc.radius * S), gm = o.groundDisc.mat;
    for (let dx = -R; dx <= R; dx++)
      for (let dz = -R; dz <= R; dz++)
        if (dx*dx + dz*dz <= R*R) { const k = packKey(dx, 0, dz); if (!voxels.has(k)) voxels.set(k, gm); }
  }

  // Wood is placed. Snapshot which cells are wood for the leaf-adjacency test.
  const isWood = (k) => { const v = voxels.get(k); return v !== undefined && WOOD_IDS.includes(v); };

  // -- 2. FOLIAGE: grow leaf clumps OUTWARD from wood, never floating -------
  let leafCount = 0;
  if (o.leaves && leafAnchors.length) {
    const R = o.leafClusterSize;
    const R2 = R * R;
    for (const anc of leafAnchors) {
      const ax = Math.round(anc[0]*S), ay = Math.round(anc[1]*S), az = Math.round(anc[2]*S);
      // BFS frontier seeded from the anchor cell; accept only cells that are
      // 6-adjacent to wood or to an already-accepted leaf → provably connected.
      const stack = [[ax, ay, az]];
      const seen = new Set([packKey(ax, ay, az)]);
      while (stack.length) {
        const [x, y, z] = stack.pop();
        for (const [fx, fy, fz] of FACES) {
          const nx = x+fx, ny = y+fy, nz = z+fz;
          const k = packKey(nx, ny, nz);
          if (seen.has(k)) continue;
          seen.add(k);
          const dx = nx-ax, dy = ny-ay, dz = nz-az;
          if (dx*dx + dy*dy + dz*dz > R2) continue;          // envelope
          if (voxels.has(k)) continue;                        // occupied (wood/leaf)
          // adjacency: must touch wood or an accepted leaf
          let touches = false;
          for (const [gx, gy, gz] of FACES) {
            const v = voxels.get(packKey(nx+gx, ny+gy, nz+gz));
            if (v !== undefined) { touches = true; break; }
          }
          if (!touches) continue;
          // acceptance masks
          if (rng() > o.leafDensity) { continue; }
          if (valueNoise(nx*0.7, ny*0.7, nz*0.7) < o.lightGap) { continue; }
          const mat = rng() < o.leafLightMix ? MAT.LEAF_LIGHT : MAT.LEAF_DARK;
          voxels.set(k, mat);
          leafCount++;
          stack.push([nx, ny, nz]);
        }
      }
    }
  }

  // -- 3. Normalize coords: trunk base at y=0, x/z centered ---------------
  let minX=1e9,minY=1e9,minZ=1e9,maxX=-1e9,maxY=-1e9,maxZ=-1e9;
  for (const k of voxels.keys()) {
    const x = Math.floor(k / (SPAN*SPAN)) - OFFSET;
    const y = Math.floor((k / SPAN) % SPAN) - OFFSET;
    const z = (k % SPAN) - OFFSET;
    if (x<minX)minX=x; if (x>maxX)maxX=x;
    if (y<minY)minY=y; if (y>maxY)maxY=y;
    if (z<minZ)minZ=z; if (z>maxZ)maxZ=z;
  }
  const cx = Math.round((minX+maxX)/2), cz = Math.round((minZ+maxZ)/2);
  const n = voxels.size;
  const positions = new Int16Array(n * 3);
  const materials = new Uint8Array(n);
  let woodN = 0, leafN = 0, i = 0;
  for (const [k, mat] of voxels) {
    const x = Math.floor(k / (SPAN*SPAN)) - OFFSET;
    const y = Math.floor((k / SPAN) % SPAN) - OFFSET;
    const z = (k % SPAN) - OFFSET;
    positions[i*3] = x - cx;
    positions[i*3+1] = y - minY;
    positions[i*3+2] = z - cz;
    materials[i] = mat;
    if (WOOD_IDS.includes(mat)) woodN++; else leafN++;
    i++;
  }

  const stats = {
    total: n, wood: woodN, leaves: leafN,
    sizeVox: [maxX-minX+1, maxY-minY+1, maxZ-minZ+1],
    disconnected: connectivityCheck(positions, materials),
  };
  return { positions, materials, stats };
}

/**
 * 6-connected flood-fill from the lowest wood voxel over ALL voxels — mirrors
 * the engine's SeverFollowLib. Returns the count of voxels NOT reachable
 * (should be 0 for a choppable tree).
 */
export function connectivityCheck(positions, materials) {
  const n = materials.length;
  if (n === 0) return 0;
  const index = new Map();
  let seedIdx = 0, seedY = Infinity;
  for (let i = 0; i < n; i++) {
    const x = positions[i*3], y = positions[i*3+1], z = positions[i*3+2];
    index.set(packKey(x, y, z), i);
    if (WOOD_IDS.includes(materials[i]) && y < seedY) { seedY = y; seedIdx = i; }
  }
  const visited = new Uint8Array(n);
  const stack = [seedIdx];
  visited[seedIdx] = 1;
  let reached = 1;
  while (stack.length) {
    const i = stack.pop();
    const x = positions[i*3], y = positions[i*3+1], z = positions[i*3+2];
    for (const [fx, fy, fz] of FACES) {
      const j = index.get(packKey(x+fx, y+fy, z+fz));
      if (j !== undefined && !visited[j]) { visited[j] = 1; reached++; stack.push(j); }
    }
  }
  return n - reached;
}
