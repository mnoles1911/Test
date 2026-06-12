// ===========================================================================
// plants.js — non-tree plant generators (bush handled via ez-tree bias)
// ===========================================================================
// Each builder returns the same neutral format the voxelizer eats:
//   { skeleton: [{level, points:[[x,y,z]...], radii:[...], mat?}], leafAnchors, groundDisc? }
// `mat` (optional) flat-colors a branch (e.g. green grass/fern stems) instead
// of the bark/heartwood logic. Coordinates are arbitrary "ez units"; the caller
// scales the whole thing to a target height. Everything is rooted so the voxels
// stay 6-connected (one body) where that makes sense.
//
// Material ids reused from the tree palette: 24 bark, 27 leaf_dark, 28 leaf_light.

function makeRng(seed) {
  let a = seed >>> 0;
  return () => { a |= 0; a = (a + 0x6d2b79f5) | 0; let t = Math.imul(a ^ (a >>> 15), 1 | a); t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t; return ((t ^ (t >>> 14)) >>> 0) / 4294967296; };
}
const norm = (a) => { const l = Math.hypot(a[0], a[1], a[2]) || 1; return [a[0]/l, a[1]/l, a[2]/l]; };
const cross = (a, b) => [a[1]*b[2]-a[2]*b[1], a[2]*b[0]-a[0]*b[2], a[0]*b[1]-a[1]*b[0]];

// --- GRASS TUFT / GROUND COVER ---------------------------------------------
// A tuft of arching blades from a shared base. Ground cover scatters many
// tufts over a disc and lays a thin connecting mat so it's one body.
export function buildGrass(p, { scatter = false } = {}) {
  const rng = makeRng((p.seed | 0) || 1);
  const skeleton = [];
  const green = [27, 28];
  const clumps = scatter ? Math.max(1, p.gcClumps | 0) : 1;
  const patchR = scatter ? p.gcPatchRadius : 0;

  for (let c = 0; c < clumps; c++) {
    let bx = 0, bz = 0;
    if (scatter && clumps > 1) { const a = rng()*6.2832, r = Math.sqrt(rng())*patchR; bx = Math.cos(a)*r; bz = Math.sin(a)*r; }
    const blades = scatter ? Math.max(2, Math.round(p.gcBlades / Math.max(1, clumps/3))) : p.gcBlades;
    for (let b = 0; b < blades; b++) {
      const ang = rng()*6.2832;
      let d = norm([Math.cos(ang)*p.gcSpread, 1, Math.sin(ang)*p.gcSpread]);
      const segs = 6, step = 0.6 + rng()*0.3;
      let pos = [bx, 0, bz]; const pts = [], radii = [];
      for (let s = 0; s <= segs; s++) {
        pts.push([pos[0], pos[1], pos[2]]); radii.push(0.12 * (1 - s/segs*0.7));
        pos = [pos[0]+d[0]*step, pos[1]+d[1]*step, pos[2]+d[2]*step];
        d = norm([d[0] + (rng()-0.5)*0.12, d[1] - p.gcCurl*0.28, d[2] + (rng()-0.5)*0.12]); // arch over
      }
      skeleton.push({ level: 3, points: pts, radii, mat: green[(b + c) % 2] });
    }
  }
  const out = { skeleton, leafAnchors: [] };
  if (scatter && clumps > 1) out.groundDisc = { radius: patchR, mat: 27 };
  return out;
}

// --- FERN ------------------------------------------------------------------
// Several arching fronds from a base; each rachis carries pinnate leaflets on
// both sides, shrinking toward the tip.
export function buildFern(p) {
  const rng = makeRng((p.seed | 0) || 1);
  const skeleton = [];
  const fronds = p.fernFronds | 0;
  for (let f = 0; f < fronds; f++) {
    const ang = (f / fronds) * 6.2832 + rng()*0.5;
    const ox = Math.cos(ang), oz = Math.sin(ang);
    const segs = 12, step = 0.7;
    let d = norm([ox*0.4, 1, oz*0.4]);
    let pos = [0, 0, 0]; const pts = [], radii = [], rachis = [];
    for (let s = 0; s <= segs; s++) {
      pts.push([pos[0], pos[1], pos[2]]); radii.push(0.14 * (1 - s/segs*0.7));
      rachis.push({ pos: [pos[0], pos[1], pos[2]], dir: [d[0], d[1], d[2]], t: s/segs });
      pos = [pos[0]+d[0]*step, pos[1]+d[1]*step, pos[2]+d[2]*step];
      d = norm([d[0] + ox*p.fernArch*0.06, d[1] - p.fernArch*0.13, d[2] + oz*p.fernArch*0.06]); // arch up then droop
    }
    skeleton.push({ level: 2, points: pts, radii, mat: 27 }); // rachis dark green
    const pairs = p.fernLeaflets | 0;
    for (let i = 1; i <= pairs; i++) {
      const t = i / (pairs + 1), idx = Math.min(segs, Math.floor(t * segs));
      const rp = rachis[idx], len = p.fernLeafletLen * (1 - t*0.7);
      const perp = norm(cross(rp.dir, [0, 1, 0]));
      for (const sgn of [1, -1]) {
        const tip = [rp.pos[0] + perp[0]*sgn*len + rp.dir[0]*0.3,
                     rp.pos[1] + 0.2,
                     rp.pos[2] + perp[2]*sgn*len + rp.dir[2]*0.3];
        skeleton.push({ level: 3, points: [rp.pos, tip], radii: [0.1, 0.04], mat: 28 }); // leaflet light green
      }
    }
  }
  return { skeleton, leafAnchors: [] };
}

// --- VINE ------------------------------------------------------------------
// A meandering woody stem that climbs (+Y) or hangs (−Y), with leaf clumps
// grown along it (via leafAnchors). Single connected strand.
export function buildVine(p) {
  const rng = makeRng((p.seed | 0) || 1);
  const skeleton = [], leafAnchors = [];
  const climb = p.vineMode === 'Climb';
  const primary = climb ? 1 : -1;
  const segs = p.vineLength | 0, step = 0.8;
  const ang = rng()*6.2832;
  let d = norm([Math.cos(ang)*0.3, primary, Math.sin(ang)*0.3]);
  let pos = [0, 0, 0]; const pts = [], radii = [];
  for (let s = 0; s <= segs; s++) {
    pts.push([pos[0], pos[1], pos[2]]); radii.push(0.16 * (1 - s/segs*0.5));
    if (s > 0 && s % Math.max(1, p.vineLeafEvery | 0) === 0) leafAnchors.push([pos[0], pos[1], pos[2]]);
    pos = [pos[0]+d[0]*step, pos[1]+d[1]*step, pos[2]+d[2]*step];
    d = norm([d[0] + (rng()-0.5)*p.vineWander*0.5, d[1]*0.6 + primary*0.4, d[2] + (rng()-0.5)*p.vineWander*0.5]);
  }
  skeleton.push({ level: 1, points: pts, radii, mat: 24 }); // woody (bark) stem
  return { skeleton, leafAnchors };
}
