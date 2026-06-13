// ===========================================================================
// character_builder.js — parametric T-pose voxel biped (humans/goblins/…)
// ===========================================================================
// PURE (no THREE, no DOM) — safe in a Web Worker. Assembles a bilaterally
// symmetric T-POSE humanoid from named body-part volumes (head, neck, torso,
// pelvis, arms, hands, legs, feet) at 18 voxels/metre, so it feeds the existing
// Blender import -> Mixamo auto-rig -> .glb pipeline. Output is the shared
// {positions, materials, stats} shape (via voxel_core), same as the other
// studios.
//
// Strict T-pose: arms straight out along ±X, legs vertical, palms down, feet
// forward (+Z). We build everything for x >= 0 and MIRROR to x < 0, which
// guarantees the symmetry Mixamo's auto-rigger wants.
import { packKey, makeRng, normalizeMapToArrays, connectivityCheck } from '../voxel_studio_common/voxel_core.js';

// Character material ids — preview/vertex-bake only (characters become MESHES,
// not terrain, so these are NOT engine-registered; the export embeds RGBs).
// 40+ avoids terrain (1-15), fluids (16-23), vegetation/rock (24-32).
export const CMAT = {
  SKIN: 40, SKIN_SHADOW: 41, CLOTH: 42, LEATHER: 43, METAL: 44,
  HAIR: 45, EYE: 46, DARK: 47, TOOTH: 48, ACCENT: 49,
};

const DEFAULTS = {
  seed: 1, species: 'Human', heightM: 1.8, build: 1.0,
  headSize: 0.17, headShape: 'round', neckLength: 0.015,
  shoulderWidth: 0.16, torsoDepth: 0.07, hipWidth: 0.11,
  armLength: 0.40, armThickness: 0.045, legThickness: 0.055,
  handSize: 0.05, footSize: 0.09,
  jawWidth: 0.5, browHeight: 0.5, earSize: 0.4, earPoint: 0.0,
  snout: 0.0, tuskSize: 0.0, eyeGlow: 0,
  // feature flags (species presets set these)
  bareChest: 0, loincloth: 0, beard: 0.0, armor: 0, visor: 0, fingers: 5,
};

// ---- fill helpers (operate on a Map<packedKey, materialId>) ----------------
function box(map, x0, x1, y0, y1, z0, z1, mat) {
  for (let x = x0; x <= x1; x++)
    for (let y = y0; y <= y1; y++)
      for (let z = z0; z <= z1; z++) map.set(packKey(x, y, z), mat);
}
// tapered column along Y: half-extents (hx,hz) interpolate y0->y1, centered cx,cz
function colY(map, cx, cz, y0, y1, hx0, hz0, hx1, hz1, mat) {
  const span = Math.max(1, y1 - y0);
  for (let y = y0; y <= y1; y++) {
    const t = (y - y0) / span;
    const hx = Math.round(hx0 + (hx1 - hx0) * t), hz = Math.round(hz0 + (hz1 - hz0) * t);
    box(map, cx - hx, cx + hx, y, y, cz - hz, cz + hz, mat);
  }
}
// horizontal arm along +X from x0..x1 at height cy, depth cz; half-extents in y,z
function armX(map, x0, x1, cy, cz, hy0, hz0, hy1, hz1, mat) {
  const span = Math.max(1, x1 - x0);
  for (let x = x0; x <= x1; x++) {
    const t = (x - x0) / span;
    const hy = Math.round(hy0 + (hy1 - hy0) * t), hz = Math.round(hz0 + (hz1 - hz0) * t);
    box(map, x, x, cy - hy, cy + hy, cz - hz, cz + hz, mat);
  }
}

/** @returns {{positions:Int16Array, materials:Uint8Array, stats:object}} */
export function buildCharacter(params = {}) {
  const p = { ...DEFAULTS, ...params };
  const rng = makeRng((p.seed | 0) || 1);
  const map = new Map();

  const H = Math.max(10, Math.round(p.heightM * 18));
  const b = p.build;
  const fr = (f) => Math.round(f * H);

  // vertical landmarks
  const yAnkle = fr(0.04), yKnee = fr(0.28), yHip = fr(0.50), yShoulder = fr(0.80);
  const headHt = Math.max(3, fr(p.headSize));
  const yHeadBot = yShoulder + Math.max(1, fr(p.neckLength));
  const yHeadTop = Math.min(H - 1, yHeadBot + headHt);
  const headCY = Math.round((yHeadBot + yHeadTop) / 2);

  // half-extents (voxels)
  const shoulderHalf = Math.max(2, fr(p.shoulderWidth) * b | 0) || 2;
  const hipHalf = Math.max(2, Math.round(fr(p.hipWidth) * b));
  const torsoDepth = Math.max(1, Math.round(fr(p.torsoDepth) * b));
  const armT = Math.max(1, Math.round(fr(p.armThickness) * b));
  const legT = Math.max(1, Math.round(fr(p.legThickness) * b));
  const headHalf = Math.max(2, Math.round(headHt * (p.headShape === 'long' ? 0.42 : p.headShape === 'square' ? 0.55 : 0.5)));
  const headDepth = Math.max(2, Math.round(headHt * (p.snout > 0 ? 0.62 : 0.5)));
  const armLen = Math.max(4, fr(p.armLength));
  const handR = Math.max(1, fr(p.handSize));
  const footLen = Math.max(2, fr(p.footSize));

  const torsoMat = p.armor ? CMAT.METAL : (p.bareChest ? CMAT.SKIN : CMAT.CLOTH);
  const limbMat = p.armor ? CMAT.METAL : CMAT.SKIN;
  const legMat = p.armor ? CMAT.METAL : (p.loincloth ? CMAT.SKIN : CMAT.CLOTH);

  // --- TORSO (pelvis -> shoulders), shoulders wider than hips -------------
  colY(map, 0, 0, yHip, yShoulder, hipHalf, torsoDepth, shoulderHalf, torsoDepth, torsoMat);
  // --- PELVIS / hips ------------------------------------------------------
  box(map, 0, hipHalf, yAnkle + Math.round((yHip - yAnkle) * 0.0), yHip, -torsoDepth, torsoDepth, p.armor ? CMAT.METAL : (p.loincloth ? CMAT.DARK : CMAT.CLOTH));
  // loincloth skirt for goblins
  if (p.loincloth) box(map, 0, hipHalf + 1, yHip - Math.round(0.10 * H), yHip + 1, -torsoDepth - 1, torsoDepth + 1, CMAT.DARK);
  // --- NECK ---------------------------------------------------------------
  box(map, 0, Math.max(1, headHalf - 2), yShoulder, yHeadBot, -Math.max(1, headDepth - 2), Math.max(1, headDepth - 2), limbMat);

  // --- HEAD ---------------------------------------------------------------
  box(map, 0, headHalf, yHeadBot, yHeadTop, -headDepth, headDepth, p.visor ? CMAT.METAL : CMAT.SKIN);
  if (!p.visor) {
    // eyes on the front (+Z), at x = ±eyeX
    const eyeY = headCY + Math.round(headHt * (0.10 + 0.2 * p.browHeight) - headHt * 0.1);
    const eyeX = Math.max(1, Math.round(headHalf * 0.5));
    const eyeMat = p.eyeGlow ? CMAT.EYE : CMAT.DARK;
    box(map, eyeX - 1, eyeX + 1, eyeY, eyeY + 1, headDepth - 1, headDepth, eyeMat);
    // brow ridge
    box(map, 0, headHalf, eyeY + 2, eyeY + 2 + Math.round(p.browHeight * 2), headDepth - 1, headDepth, CMAT.SKIN_SHADOW);
    // snout / muzzle (goblin/beast) forward
    if (p.snout > 0) box(map, 0, Math.max(1, Math.round(headHalf * 0.5)), headCY - 1, headCY + 1, headDepth, headDepth + Math.round(p.snout * headHt * 0.6), CMAT.SKIN);
    // tusks
    if (p.tuskSize > 0) { const tx = Math.max(1, Math.round(headHalf * 0.4)); box(map, tx, tx, headCY - 2 - Math.round(p.tuskSize * 2), headCY - 1, headDepth, headDepth + 1, CMAT.TOOTH); }
    // ears on the sides (±X), pointed if earPoint
    if (p.earSize > 0) {
      const ey = headCY, ez = 0, eo = headHalf + 1, el = Math.max(1, Math.round(p.earSize * headHt * 0.7));
      for (let i = 0; i < el; i++) box(map, eo + i, eo + i, ey - 1 + (p.earPoint > 0.5 ? i : 0), ey + 1 - (p.earPoint > 0.5 ? i : 0), ez - 1, ez + 1, CMAT.SKIN);
    }
    // hair cap + beard
    if (p.beard < 0.5) box(map, 0, headHalf, yHeadTop, yHeadTop, -headDepth, headDepth, CMAT.HAIR);
    if (p.beard > 0) box(map, 0, Math.max(1, headHalf - 1), yHeadBot, headCY - 1, headDepth - 1, headDepth + Math.round(p.beard * 2), CMAT.HAIR);
  }

  // --- ARM (right, +X) : shoulder -> wrist, then hand ---------------------
  const ax0 = shoulderHalf, ax1 = shoulderHalf + armLen;
  armX(map, ax0, ax1, yShoulder, 0, armT, armT, Math.max(1, armT - 1), Math.max(1, armT - 1), p.armor ? CMAT.METAL : CMAT.SKIN);
  // hand (palm down — flat in Y, wider in Z); claw/mitten silhouette
  box(map, ax1, ax1 + handR, yShoulder - 1, yShoulder, -handR, handR, CMAT.SKIN);
  if (p.fingers <= 3) { for (let f = -1; f <= 1; f++) box(map, ax1 + handR, ax1 + handR + 1, yShoulder, yShoulder, f * 2, f * 2, CMAT.SKIN); }

  // --- LEG (right, +X) : hip -> ankle, then foot -------------------------
  const lx = hipHalf - Math.max(1, legT);
  colY(map, lx, 0, yAnkle, yHip, legT, legT, legT, legT, legMat);
  box(map, lx - legT, lx + legT, yAnkle, yAnkle, -legT, legT, legMat); // skin lower leg if clothed? keep
  // foot forward (+Z)
  box(map, lx - legT, lx + legT, yAnkle - Math.max(1, Math.round(0.03 * H)), yAnkle, -legT, legT + footLen, p.armor ? CMAT.METAL : CMAT.LEATHER);

  // --- MIRROR x>0 -> x<0 (perfect bilateral symmetry) --------------------
  for (const [k, mat] of [...map]) {
    const x = Math.floor(k / (8192 * 8192)) - 4096;
    const y = Math.floor((k / 8192) % 8192) - 4096;
    const z = (k % 8192) - 4096;
    if (x > 0) { const mk = packKey(-x, y, z); if (!map.has(mk)) map.set(mk, mat); }
  }

  const { positions, materials, sizeVox } = normalizeMapToArrays(map);
  const disconnected = connectivityCheck(positions, materials);
  const hist = {}; for (const m of materials) hist[m] = (hist[m] || 0) + 1;
  return { positions, materials, stats: { total: materials.length, sizeVox, disconnected, hist } };
}
