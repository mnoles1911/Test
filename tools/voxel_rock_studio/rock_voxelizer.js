// ===========================================================================
// rock_voxelizer.js — procedural ROCKS as solid voxels (SDF sampling)
// ===========================================================================
// Unlike trees (skeleton rasterization), rocks are SOLID volumes. We sample an
// implicit "rock field" at every grid cell: a superquadric base + FBM surface
// roughness + Worley/Voronoi faceting + random scrape planes + a flat bottom,
// then assign stone materials by noise/strata and grow moss on up-facing tops.
// Output is the same {positions, materials, stats} the renderer/export expect.
//
// Algorithm sources (see plan): gl-rock (scrape + noise), Blender Rock Generator
// (Voronoi + noise displacement), Iñigo Quílez SDF primitives.
import { ROCK_MAT, packKey, unpackKey, FACES, makeRng, normalizeMapToArrays, connectivityCheck } from '../voxel_studio_common/voxel_core.js';
import { makeSimplex, makeWorley, fbm } from '../voxel_studio_common/noise.js';

const DEFAULTS = {
  rockType: 'Boulder',
  seed: 1,
  sizeX: 24, sizeY: 18, sizeZ: 24,   // bounding box in voxels (10cm each)
  boxiness: 2.6,                       // superquadric exponent (2=ellipsoid, 8=cube)
  noiseScale: 1.8, noiseOctaves: 4, noiseAmp: 0.28,
  faceting: 0.0, facetScale: 2.4,      // Worley angular facets
  scrapeCount: 0, scrapeDepth: 0.75,   // flat cut planes
  flatBottom: 0.45,                    // sit flat on the ground
  erosion: 0.2,                        // smooth/round
  topTaper: 0.0,                       // point the top (spires)
  clusters: 1, clusterSpread: 0.0,     // scatter (pebbles/piles)
  // materials
  darkMix: 0.35, marbleVeins: 0.0, gravelBase: 0.0, oreAmount: 0.0,
  strata: 0.0, strataBands: 6,
  mossAmount: 0.0,
};

export function voxelizeRock(params = {}) {
  const o = { ...DEFAULTS, ...params };
  const rng = makeRng((o.seed | 0) || 1);
  const simplex = makeSimplex((o.seed | 0) || 1);
  const worley = makeWorley((o.seed | 0) || 1);
  const voxels = new Map();

  const clusters = Math.max(1, o.clusters | 0);
  for (let c = 0; c < clusters; c++) {
    // per-cluster placement + size jitter
    let ox = 0, oy = 0, oz = 0, scale = 1;
    if (clusters > 1) {
      const a = rng()*6.2832, r = Math.sqrt(rng()) * o.clusterSpread;
      ox = Math.cos(a) * r * o.sizeX; oz = Math.sin(a) * r * o.sizeZ;
      scale = 0.55 + rng() * 0.7;
    }
    stampRock(voxels, o, rng, simplex, worley, ox, oy, oz, scale, c);
  }

  // Remove floating noise specks. A single rock keeps only its largest body
  // (so it's provably connected); a scatter (pebbles/piles) keeps every chunk
  // above a small minimum.
  pruneComponents(voxels, clusters === 1, 6);

  // Moss on up-facing surfaces (after the solid is built).
  if (o.mossAmount > 0) growMoss(voxels, o, simplex);

  const { positions, materials, sizeVox } = normalizeMapToArrays(voxels);
  const disconnected = connectivityCheck(positions, materials);
  // histogram
  let mossN = 0; for (const m of materials) if (m === ROCK_MAT.MOSS) mossN++;
  const stats = { total: materials.length, sizeVox, disconnected, moss: mossN };
  return { positions, materials, stats };
}

function stampRock(voxels, o, rng, simplex, worley, ox, oy, oz, scale, ci) {
  const rx = (o.sizeX * scale) / 2, ry = (o.sizeY * scale) / 2, rz = (o.sizeZ * scale) / 2;
  const e = o.boxiness, inv_e = 1 / e;
  const bottomLevel = -1 + o.flatBottom * 0.7;
  // precompute scrape planes
  const planes = [];
  for (let s = 0; s < (o.scrapeCount | 0); s++) {
    const t = rng()*6.2832, ph = (rng()-0.5)*Math.PI;
    planes.push({ n: [Math.cos(ph)*Math.cos(t), Math.sin(ph), Math.cos(ph)*Math.sin(t)], off: o.scrapeDepth + rng()*0.15 });
  }
  // per-cluster phase so clusters look different
  const ph = ci * 13.7;

  const X0 = Math.floor(ox - rx) - 1, X1 = Math.ceil(ox + rx) + 1;
  const Y0 = Math.floor(oy - ry) - 1, Y1 = Math.ceil(oy + ry) + 1;
  const Z0 = Math.floor(oz - rz) - 1, Z1 = Math.ceil(oz + rz) + 1;

  for (let x = X0; x <= X1; x++)
    for (let y = Y0; y <= Y1; y++)
      for (let z = Z0; z <= Z1; z++) {
        // normalized position within the rock's box
        let nx = (x - ox) / rx, ny = (y - oy) / ry, nz = (z - oz) / rz;
        if (ny < bottomLevel) continue;                 // flat bottom
        // taper top (spires): shrink horizontal radius toward the top
        if (o.topTaper > 0) {
          const t = Math.max(0, (ny + 1) / 2);          // 0 bottom .. 1 top
          const k = 1 - o.topTaper * t;
          if (k <= 0.05) continue;
          nx /= k; nz /= k;
        }
        // superquadric base distance
        let d = Math.pow(Math.pow(Math.abs(nx), e) + Math.pow(Math.abs(ny), e) + Math.pow(Math.abs(nz), e), inv_e);
        // FBM surface roughness (eroded down)
        const nd = fbm(simplex, nx*o.noiseScale+ph, ny*o.noiseScale, nz*o.noiseScale, o.noiseOctaves) * o.noiseAmp * (1 - o.erosion);
        d += nd;
        // Worley faceting (angular breaks)
        if (o.faceting > 0) {
          const w = worley(nx*o.facetScale+ph, ny*o.facetScale, nz*o.facetScale);
          d += o.faceting * (w - 0.45);
        }
        if (d > 1) continue;
        // scrape planes (flat cleaves)
        let cut = false;
        for (const pl of planes) { if (nx*pl.n[0] + ny*pl.n[1] + nz*pl.n[2] > pl.off) { cut = true; break; } }
        if (cut) continue;
        // material
        const mat = pickMaterial(x, y, z, ny, rng, simplex, worley, o);
        const key = packKey(x, y, z);
        if (!voxels.has(key)) voxels.set(key, mat);
      }
}

function pickMaterial(x, y, z, ny, rng, simplex, worley, o) {
  // ore pockets
  if (o.oreAmount > 0) {
    const ore = fbm(simplex, x*0.12+50, y*0.12, z*0.12+50, 3);
    if (ore > 1 - o.oreAmount * 0.6) return rng() < 0.5 ? ROCK_MAT.COPPER : ROCK_MAT.IRON;
  }
  // marble veins (thin Worley boundaries)
  if (o.marbleVeins > 0) {
    const v = worley(x*0.22, y*0.22, z*0.22);
    if (v < o.marbleVeins * 0.28) return ROCK_MAT.MARBLE;
  }
  // sedimentary strata bands by height
  if (o.strata > 0) {
    const band = Math.floor((ny * 0.5 + 0.5) * o.strataBands);
    if ((band & 1) === 0 && rng() < o.strata) return ROCK_MAT.STONE_DARK;
  }
  // gravel near the base
  if (o.gravelBase > 0 && ny < -0.4 && rng() < o.gravelBase) return ROCK_MAT.GRAVEL;
  // base dark/light mix
  const n = simplex(x*0.13, y*0.13, z*0.13);
  if (n < (o.darkMix - 0.5) * 1.2) return ROCK_MAT.STONE_DARK;
  return ROCK_MAT.STONE;
}

// Keep the largest 6-connected component (single rock) or drop tiny detached
// specks below minSize (scatter), so noise doesn't leave floating bits.
function pruneComponents(voxels, keepLargestOnly, minSize) {
  const visited = new Set(); const comps = [];
  for (const start of voxels.keys()) {
    if (visited.has(start)) continue;
    const comp = [start]; visited.add(start); const stack = [start];
    while (stack.length) {
      const k = stack.pop(); const [x, y, z] = unpackKey(k);
      for (const [a, b, c] of FACES) { const nk = packKey(x+a, y+b, z+c); if (voxels.has(nk) && !visited.has(nk)) { visited.add(nk); comp.push(nk); stack.push(nk); } }
    }
    comps.push(comp);
  }
  if (comps.length <= 1) return;
  comps.sort((a, b) => b.length - a.length);
  const keep = new Set();
  if (keepLargestOnly) { for (const k of comps[0]) keep.add(k); }
  else { for (const c of comps) if (c.length >= minSize) for (const k of c) keep.add(k); }
  for (const k of [...voxels.keys()]) if (!keep.has(k)) voxels.delete(k);
}

// Moss on up-facing surface cells (cell directly above is empty).
function growMoss(voxels, o, simplex) {
  const entries = [...voxels.keys()];
  for (const k of entries) {
    const x = Math.floor(k / (8192*8192)) - 4096;
    const y = Math.floor((k / 8192) % 8192) - 4096;
    const z = (k % 8192) - 4096;
    if (voxels.has(packKey(x, y+1, z))) continue;          // not a top surface
    const n = simplex(x*0.25, y*0.25, z*0.25) * 0.5 + 0.5; // 0..1
    if (n < o.mossAmount) voxels.set(k, ROCK_MAT.MOSS);
  }
}
