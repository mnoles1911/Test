// ===========================================================================
// space_colonization.js — Runions et al. (2007) growth as an alternate mode
// ===========================================================================
// Branches GROW TOWARD attractor points seeded in a crown envelope, competing
// for space. This yields very organic forking + natural leaf clustering. Output
// is the SAME skeleton shape the voxelizer eats:
//   { skeleton: [{level, points:[[x,y,z]...], radii:[...]}], leafAnchors:[[x,y,z]] }
// Coordinates are in arbitrary "ez units"; the caller scales to a target height.

function makeRng(seed) {
  let a = seed >>> 0;
  return () => { a |= 0; a = (a + 0x6d2b79f5) | 0; let t = Math.imul(a ^ (a >>> 15), 1 | a); t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t; return ((t ^ (t >>> 14)) >>> 0) / 4294967296; };
}
const sub = (a, b) => [a[0]-b[0], a[1]-b[1], a[2]-b[2]];
const add = (a, b) => [a[0]+b[0], a[1]+b[1], a[2]+b[2]];
const len = (a) => Math.hypot(a[0], a[1], a[2]);
const norm = (a) => { const l = len(a) || 1; return [a[0]/l, a[1]/l, a[2]/l]; };

export function growSpaceColonization(p) {
  const rng = makeRng((p.seed | 0) || 1);
  const trunkH = p.scTrunkHeight, crownR = p.scCrownRadius, crownH = p.scCrownHeight;
  const influence = p.scInfluence, kill = p.scKill, step = p.scStep;
  const crownCY = trunkH + crownH * 0.4;

  // 1. Seed attractors in an ellipsoidal crown (rejection-sample a unit ball).
  const attractors = [];
  let guard = p.scAttractors * 40;
  while (attractors.length < p.scAttractors && guard-- > 0) {
    const x = rng()*2-1, y = rng()*2-1, z = rng()*2-1;
    if (x*x + y*y + z*z > 1) continue;
    attractors.push({ pos: [x*crownR, crownCY + y*crownH*0.5, z*crownR], dead: false });
  }

  // 2. Nodes. Root at origin; grow a straight trunk up until attractors are in
  //    reach, then let competition take over.
  const nodes = [{ pos: [0,0,0], parent: -1, children: [] }];
  const nearestActiveDist = (pos) => {
    let best = Infinity;
    for (const at of attractors) if (!at.dead) { const d = len(sub(at.pos, pos)); if (d < best) best = d; }
    return best;
  };
  let topIdx = 0, trunkGuard = 1000;
  while (nearestActiveDist(nodes[topIdx].pos) > influence && trunkGuard-- > 0 && nodes[topIdx].pos[1] < crownCY) {
    const np = add(nodes[topIdx].pos, [0, step, 0]);
    nodes.push({ pos: np, parent: topIdx, children: [] });
    nodes[topIdx].children.push(nodes.length - 1);
    topIdx = nodes.length - 1;
  }

  // 3. Space-colonization growth loop.
  const MAX_NODES = 6000;
  let iter = 600;
  while (iter-- > 0 && nodes.length < MAX_NODES) {
    // Each attractor pulls on its nearest node.
    const pull = new Map(); // nodeIdx -> summed direction
    let anyActive = false;
    for (const at of attractors) {
      if (at.dead) continue;
      anyActive = true;
      let best = -1, bestD = influence;
      for (let i = 0; i < nodes.length; i++) {
        const d = len(sub(at.pos, nodes[i].pos));
        if (d < bestD) { bestD = d; best = i; }
      }
      if (best >= 0) {
        const dir = norm(sub(at.pos, nodes[best].pos));
        const cur = pull.get(best);
        pull.set(best, cur ? add(cur, dir) : dir);
      }
    }
    if (!anyActive) break;
    if (pull.size === 0) break;
    // Spawn one child per pulled node, in the averaged+jittered direction.
    let grew = false;
    for (const [idx, dir] of pull) {
      let d = norm(dir);
      d = norm([d[0] + (rng()-0.5)*0.25, d[1] + (rng()-0.5)*0.25, d[2] + (rng()-0.5)*0.25]);
      const np = add(nodes[idx].pos, [d[0]*step, d[1]*step, d[2]*step]);
      nodes.push({ pos: np, parent: idx, children: [] });
      nodes[idx].children.push(nodes.length - 1);
      grew = true;
    }
    if (!grew) break;
    // Kill attractors reached by any node.
    for (const at of attractors) {
      if (at.dead) continue;
      for (let i = 0; i < nodes.length; i++) { if (len(sub(at.pos, nodes[i].pos)) < kill) { at.dead = true; break; } }
    }
  }

  // 4. Pipe-model radii: post-order accumulate from tips.
  const rMin = 0.08, e = 2.2;
  const radius = new Float64Array(nodes.length);
  const order = [...nodes.keys()].sort((a, b) => nodes[b].pos[1] - nodes[a].pos[1]); // high y first ≈ tips first
  for (const i of order) {
    if (nodes[i].children.length === 0) radius[i] = rMin;
    else {
      let s = 0; for (const c of nodes[i].children) s += Math.pow(radius[c], e);
      radius[i] = Math.max(rMin, Math.pow(s, 1 / e));
    }
  }

  // 5. Depth (for level buckets) + emit skeleton + leaf anchors.
  const depth = new Int32Array(nodes.length);
  let maxDepth = 1;
  for (let i = 0; i < nodes.length; i++) { if (nodes[i].parent >= 0) { depth[i] = depth[nodes[i].parent] + 1; if (depth[i] > maxDepth) maxDepth = depth[i]; } }
  const skeleton = [];
  const leafAnchors = [];
  for (let i = 0; i < nodes.length; i++) {
    const par = nodes[i].parent;
    if (par >= 0) {
      const level = Math.min(3, Math.floor((depth[i] / maxDepth) * 3.999));
      skeleton.push({ level, points: [nodes[par].pos, nodes[i].pos], radii: [radius[par], radius[i]] });
    }
    if (nodes[i].children.length === 0) leafAnchors.push(nodes[i].pos);
  }
  return { skeleton, leafAnchors };
}
