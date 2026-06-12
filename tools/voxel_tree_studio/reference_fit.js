// ===========================================================================
// reference_fit.js — heuristic "fit dials to a reference image"
// ===========================================================================
// Analyze a tree photo: find the green canopy + brown trunk, measure their
// proportions, and translate that into a species guess + dial overrides. v1 is
// approximate — it gets you "the right species, in the neighborhood"; you then
// fine-tune. (A v2 iterative optimizer can refine against the silhouette.)
//
// analyzePixels() is pure (takes {data,width,height}) so it can be unit-tested.
// fitFromImage() is the browser wrapper that rasterizes an <img> to a canvas.

export function analyzePixels(imageData) {
  const { data, width: w, height: h } = imageData;
  let fMinX = 1e9, fMinY = 1e9, fMaxX = -1e9, fMaxY = -1e9, fCount = 0, gSum = 0;
  let wMinX = 1e9, wMaxX = -1e9, wCount = 0;
  // per-row wood width, to estimate trunk thickness in the lower image
  const woodRowMin = new Int32Array(h).fill(1e9);
  const woodRowMax = new Int32Array(h).fill(-1e9);

  for (let y = 0; y < h; y++) {
    for (let x = 0; x < w; x++) {
      const i = (y * w + x) * 4;
      const r = data[i], g = data[i+1], b = data[i+2], a = data[i+3];
      if (a < 40) continue;
      const isGreen = g > 55 && g > r * 1.04 && g > b * 1.04;
      const isWood = !isGreen && r > 45 && r < 205 && r >= g && g >= b - 8 && (r - b) > 18;
      if (isGreen) {
        if (x < fMinX) fMinX = x; if (x > fMaxX) fMaxX = x;
        if (y < fMinY) fMinY = y; if (y > fMaxY) fMaxY = y;
        fCount++; gSum += g;
      } else if (isWood) {
        if (x < wMinX) wMinX = x; if (x > wMaxX) wMaxX = x;
        if (x < woodRowMin[y]) woodRowMin[y] = x;
        if (x > woodRowMax[y]) woodRowMax[y] = x;
        wCount++;
      }
    }
  }

  if (fCount < 20) return { species: 'Oak Medium', overrides: {}, debug: { note: 'little foliage found' } };

  const canopyW = Math.max(1, fMaxX - fMinX);
  const canopyH = Math.max(1, fMaxY - fMinY);
  const aspect = canopyH / canopyW;                 // >1 tall/narrow, <1 round/wide
  const density = fCount / (canopyW * canopyH);      // 0..1 fill of canopy box
  const greenBright = (gSum / fCount) / 255;         // 0..1

  // Trunk thickness: median wood-row width in the band just below the canopy.
  const widths = [];
  for (let y = Math.min(h - 1, fMaxY); y < h; y++) {
    if (woodRowMax[y] >= woodRowMin[y]) widths.push(woodRowMax[y] - woodRowMin[y] + 1);
  }
  widths.sort((a, b) => a - b);
  const trunkW = widths.length ? widths[Math.floor(widths.length / 2)] : Math.max(2, canopyW * 0.05);
  const trunkRatio = trunkW / canopyW;

  // Species guess.
  let species, type;
  if (aspect > 1.5) { species = 'Pine Medium'; type = 'Evergreen'; }
  else if (canopyH < h * 0.4 && fMaxY > h * 0.6) { species = 'Bush 1'; type = 'Deciduous'; }
  else { species = aspect > 1.1 ? 'Aspen Medium' : 'Oak Medium'; type = 'Deciduous'; }

  const clamp = (v, lo, hi) => Math.max(lo, Math.min(hi, v));
  const overrides = {
    type,
    levels: species === 'Bush 1' ? 2 : 3,
    leafDensity: +clamp(0.45 + density * 0.6, 0.4, 1).toFixed(2),
    lightGap: +clamp(0.5 - density * 0.45, 0, 0.5).toFixed(2),
    leafLightMix: +clamp(greenBright * 1.25 - 0.2, 0, 1).toFixed(2),
    trunkRadius: +clamp(0.5 + trunkRatio * 9, 0.5, 4).toFixed(2),
    angle1: Math.round(clamp(40 + (1 / aspect) * 45, 30, 115)),
    heightM: +clamp((canopyH / h) * 16 + 4, 3, 18).toFixed(1),
  };
  return { species, overrides, debug: { canopyW, canopyH, aspect: +aspect.toFixed(2), density: +density.toFixed(3), trunkRatio: +trunkRatio.toFixed(3), greenBright: +greenBright.toFixed(2) } };
}

// Browser wrapper: rasterize an <img> (or anything drawable) to a small canvas.
export function fitFromImage(img, maxW = 180) {
  const scale = Math.min(1, maxW / (img.naturalWidth || img.width || maxW));
  const w = Math.max(1, Math.round((img.naturalWidth || img.width) * scale));
  const h = Math.max(1, Math.round((img.naturalHeight || img.height) * scale));
  const cvs = document.createElement('canvas');
  cvs.width = w; cvs.height = h;
  const ctx = cvs.getContext('2d', { willReadFrequently: true });
  ctx.drawImage(img, 0, 0, w, h);
  let imageData;
  try { imageData = ctx.getImageData(0, 0, w, h); }
  catch (e) { return { error: 'Could not read the image (cross-origin). Drag the image onto the view instead.' }; }
  return analyzePixels(imageData);
}
