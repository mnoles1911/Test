// ===========================================================================
// voxel_studio_common/noise.js — shared noise for procedural shapes
// ===========================================================================
// Pure, dependency-free. Used by the rock voxelizer (and available to any
// studio). Provides seedable 3D simplex (smooth lumps), 3D Worley/cellular
// (angular facets / cracks), and an fbm wrapper.

// --- seedable permutation table --------------------------------------------
function buildPerm(seed) {
  const p = new Uint8Array(256);
  for (let i = 0; i < 256; i++) p[i] = i;
  let s = (seed | 0) || 1;
  for (let i = 255; i > 0; i--) {           // Fisher–Yates with a small LCG
    s = (s * 1664525 + 1013904223) & 0x7fffffff;
    const j = s % (i + 1);
    const t = p[i]; p[i] = p[j]; p[j] = t;
  }
  const perm = new Uint8Array(512);
  for (let i = 0; i < 512; i++) perm[i] = p[i & 255];
  return perm;
}

const GRAD3 = [
  [1,1,0],[-1,1,0],[1,-1,0],[-1,-1,0],
  [1,0,1],[-1,0,1],[1,0,-1],[-1,0,-1],
  [0,1,1],[0,-1,1],[0,1,-1],[0,-1,-1],
];

// 3D simplex noise (Gustavson-style), returns roughly [-1, 1].
export function makeSimplex(seed) {
  const perm = buildPerm(seed);
  const F3 = 1 / 3, G3 = 1 / 6;
  return function simplex3(xin, yin, zin) {
    const s = (xin + yin + zin) * F3;
    const i = Math.floor(xin + s), j = Math.floor(yin + s), k = Math.floor(zin + s);
    const t = (i + j + k) * G3;
    const X0 = i - t, Y0 = j - t, Z0 = k - t;
    const x0 = xin - X0, y0 = yin - Y0, z0 = zin - Z0;
    let i1, j1, k1, i2, j2, k2;
    if (x0 >= y0) {
      if (y0 >= z0) { i1=1;j1=0;k1=0; i2=1;j2=1;k2=0; }
      else if (x0 >= z0) { i1=1;j1=0;k1=0; i2=1;j2=0;k2=1; }
      else { i1=0;j1=0;k1=1; i2=1;j2=0;k2=1; }
    } else {
      if (y0 < z0) { i1=0;j1=0;k1=1; i2=0;j2=1;k2=1; }
      else if (x0 < z0) { i1=0;j1=1;k1=0; i2=0;j2=1;k2=1; }
      else { i1=0;j1=1;k1=0; i2=1;j2=1;k2=0; }
    }
    const x1 = x0 - i1 + G3, y1 = y0 - j1 + G3, z1 = z0 - k1 + G3;
    const x2 = x0 - i2 + 2*G3, y2 = y0 - j2 + 2*G3, z2 = z0 - k2 + 2*G3;
    const x3 = x0 - 1 + 3*G3, y3 = y0 - 1 + 3*G3, z3 = z0 - 1 + 3*G3;
    const ii = i & 255, jj = j & 255, kk = k & 255;
    let n0=0, n1=0, n2=0, n3=0;
    const corner = (x,y,z,gi) => {
      let tt = 0.6 - x*x - y*y - z*z;
      if (tt < 0) return 0;
      const g = GRAD3[gi % 12]; tt *= tt;
      return tt * tt * (g[0]*x + g[1]*y + g[2]*z);
    };
    n0 = corner(x0,y0,z0, perm[ii + perm[jj + perm[kk]]]);
    n1 = corner(x1,y1,z1, perm[ii+i1 + perm[jj+j1 + perm[kk+k1]]]);
    n2 = corner(x2,y2,z2, perm[ii+i2 + perm[jj+j2 + perm[kk+k2]]]);
    n3 = corner(x3,y3,z3, perm[ii+1 + perm[jj+1 + perm[kk+1]]]);
    return 32 * (n0 + n1 + n2 + n3);
  };
}

// 3D Worley / cellular noise. Returns F1 (nearest feature distance), ~[0,1+].
export function makeWorley(seed) {
  const perm = buildPerm(seed ^ 0x9e3779b1);
  const hash = (i, j, k) => {
    const h = perm[(i & 255) + perm[(j & 255) + perm[(k & 255)]]];
    return h / 255;
  };
  return function worley3(x, y, z) {
    const xi = Math.floor(x), yi = Math.floor(y), zi = Math.floor(z);
    let f1 = 1e9;
    for (let di = -1; di <= 1; di++)
      for (let dj = -1; dj <= 1; dj++)
        for (let dk = -1; dk <= 1; dk++) {
          const ci = xi + di, cj = yi + dj, ck = zi + dk;
          // one feature point per cell, jittered by a few independent hashes
          const fx = ci + hash(ci, cj, ck);
          const fy = cj + hash(ci + 31, cj + 17, ck + 7);
          const fz = ck + hash(ci + 5, cj + 23, ck + 41);
          const dx = fx - x, dy = fy - y, dz = fz - z;
          const d = dx*dx + dy*dy + dz*dz;
          if (d < f1) f1 = d;
        }
    return Math.sqrt(f1);
  };
}

// Fractal Brownian motion over any 3D noise function. Returns ~[-1,1] for noise
// in [-1,1]. octaves stack detail; lacunarity/gain are the usual fbm knobs.
export function fbm(noise3, x, y, z, octaves = 4, lacunarity = 2.0, gain = 0.5) {
  let amp = 0.5, freq = 1.0, sum = 0, norm = 0;
  for (let o = 0; o < octaves; o++) {
    sum += amp * noise3(x * freq, y * freq, z * freq);
    norm += amp;
    amp *= gain; freq *= lacunarity;
  }
  return sum / (norm || 1);
}
