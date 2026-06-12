// ===========================================================================
// voxel_studio_common/voxel_core.js — shared voxel primitives
// ===========================================================================
// Pure, dependency-free. Shared by the rock studio (and adoptable by the tree
// studio). Holds the integer-cell packing, 6-connected flood-fill connectivity
// check (mirrors the engine's SeverFollowLib), seeded RNG, and the map→typed-
// array normalization stage that every voxelizer ends with.

// Rock/stone material ids map to EXISTING engine materials (deployable as-is),
// plus moss (32, new). 16–23 are native fluid models; 24–31 are tree/vegetation.
export const ROCK_MAT = {
  STONE: 1,
  GRAVEL: 7,
  MARBLE: 9,
  COPPER: 12,
  STONE_DARK: 14,
  IRON: 15,
  MOSS: 32,
};

const OFFSET = 4096, SPAN = 8192;
export const packKey = (x, y, z) => (x + OFFSET) * SPAN * SPAN + (y + OFFSET) * SPAN + (z + OFFSET);
export const unpackKey = (k) => [Math.floor(k / (SPAN*SPAN)) - OFFSET, Math.floor((k / SPAN) % SPAN) - OFFSET, (k % SPAN) - OFFSET];
export const FACES = [[1,0,0],[-1,0,0],[0,1,0],[0,-1,0],[0,0,1],[0,0,-1]];

export function makeRng(seed) {
  let a = seed >>> 0;
  return () => { a |= 0; a = (a + 0x6d2b79f5) | 0; let t = Math.imul(a ^ (a >>> 15), 1 | a); t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t; return ((t ^ (t >>> 14)) >>> 0) / 4294967296; };
}

// Normalize a Map<packedKey, materialId> → flat typed arrays. Trunk/rock base
// at y=0, centered on x/z. Returns positions (Int16 ×3), materials (Uint8),
// and sizeVox.
export function normalizeMapToArrays(voxels) {
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
  const positions = new Int16Array(n*3), materials = new Uint8Array(n);
  let i = 0;
  for (const [k, mat] of voxels) {
    const x = Math.floor(k / (SPAN*SPAN)) - OFFSET;
    const y = Math.floor((k / SPAN) % SPAN) - OFFSET;
    const z = (k % SPAN) - OFFSET;
    positions[i*3] = x - cx; positions[i*3+1] = y - minY; positions[i*3+2] = z - cz;
    materials[i] = mat; i++;
  }
  return { positions, materials, sizeVox: [maxX-minX+1, maxY-minY+1, maxZ-minZ+1] };
}

// 6-connected flood-fill from the lowest voxel over ALL voxels — mirrors the
// engine's connectivity rule. Returns the count NOT reachable (0 = one body).
export function connectivityCheck(positions, materials) {
  const n = materials.length;
  if (n === 0) return 0;
  const index = new Map();
  let seed = 0, seedY = Infinity;
  for (let i = 0; i < n; i++) {
    const x = positions[i*3], y = positions[i*3+1], z = positions[i*3+2];
    index.set(packKey(x, y, z), i);
    if (y < seedY) { seedY = y; seed = i; }
  }
  const visited = new Uint8Array(n); const stack = [seed]; visited[seed] = 1; let reached = 1;
  while (stack.length) {
    const i = stack.pop();
    const x = positions[i*3], y = positions[i*3+1], z = positions[i*3+2];
    for (const [a,b,c] of FACES) { const j = index.get(packKey(x+a, y+b, z+c)); if (j !== undefined && !visited[j]) { visited[j]=1; reached++; stack.push(j); } }
  }
  return n - reached;
}
