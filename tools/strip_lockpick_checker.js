// strip_lockpick_checker.js
//
// Converts the AI-generated lockpick + resonance_glow JPGs into PNGs with
// proper alpha. The image generators baked a grey/white checkerboard pattern
// into the JPG output (rendering "what transparency looks like" instead of
// emitting a real alpha channel). This script recovers true alpha by:
//
//   1. Detecting checker pixels via low chroma + checker-range brightness.
//   2. (Glow only) Computing alpha from chroma/luma against the gold body,
//      then unmixing the underlying checker out of the RGB. The RGB is also
//      sourced from a heavy-blurred copy of the input so the periodic
//      checker pattern dissolves into the smooth gold gradient.
//   3. Writing PNG with real alpha next to each source JPG.
//
// USAGE:
//   1. Install once (one-time, in any temp folder):
//        npm install sharp
//   2. Run from the repo root, pointing NODE_PATH at the install:
//        NODE_PATH=/path/to/temp/node_modules node tools/strip_lockpick_checker.js
//   OR copy this file alongside a node_modules/sharp install and run directly.
//
// Rerun after regenerating any of the source JPGs.

const sharp = require('sharp');
const path = require('path');

const ART_DIR = path.resolve(__dirname, '..', 'assets', 'lockpick');

async function processImage(inputName, outputName, mode) {
  const inPath  = path.join(ART_DIR, inputName);
  const outPath = path.join(ART_DIR, outputName);

  const origImg = sharp(inPath).ensureAlpha();
  const { data, info } = await origImg.raw().toBuffer({ resolveWithObject: true });
  const { width, height, channels } = info;

  let rgbData = data;
  if (mode === 'glow') {
    // Heavy blur dissolves the AI's high-frequency checker pattern while
    // preserving the smooth radial gold gradient.
    const blurred = await sharp(inPath).blur(30).ensureAlpha().raw().toBuffer();
    rgbData = blurred;
  }

  const out = Buffer.alloc(width * height * 4);

  for (let i = 0, j = 0; i < data.length; i += channels, j += 4) {
    // Glow uses blurred for alpha source (smooth falloff). Lockpick uses
    // original (sharp tool edges).
    const r = (mode === 'glow' ? rgbData[i]   : data[i]);
    const g = (mode === 'glow' ? rgbData[i+1] : data[i+1]);
    const b = (mode === 'glow' ? rgbData[i+2] : data[i+2]);

    out[j]   = rgbData[i];
    out[j+1] = rgbData[i+1];
    out[j+2] = rgbData[i+2];

    const max = Math.max(r, g, b);
    const min = Math.min(r, g, b);
    const chroma = max - min;
    const luma   = (r * 0.299 + g * 0.587 + b * 0.114);

    let alpha = 255;

    if (mode === 'lockpick') {
      // Lockpick: object has metal (low chroma) + brown handle (mid chroma).
      // Checker is very-low-chroma AND very bright. Soft-key the band edge.
      if (chroma <= 14 && luma >= 188) {
        const checkerStrength = Math.min(1, (luma - 188) / 30 + (14 - chroma) / 14);
        alpha = Math.round(255 * (1 - checkerStrength));
      } else if (chroma <= 22 && luma >= 175) {
        const edgeMix = ((22 - chroma) / 22) * Math.max(0, (luma - 175) / 60);
        alpha = Math.round(255 * (1 - edgeMix * 0.7));
      }
    } else if (mode === 'glow') {
      // chroma <= 8, luma <  240 → checker, alpha = 0
      // chroma <= 8, luma >= 240 → white-hot core, alpha by brightness
      // chroma  > 8             → alpha rises with chroma (sat near chroma~70)
      let alphaF = 0;
      if (chroma <= 8) {
        if (luma >= 240) alphaF = Math.min(1, (luma - 240) / 15);
      } else {
        alphaF = Math.min(1, (chroma - 8) / 62);
      }
      alpha = Math.round(alphaF * 255);

      // Unmix the blurred RGB against checker baseline to recover pure gold.
      if (alphaF > 0.04 && alphaF < 0.99) {
        const checkerBase = 225;
        const inv = 1 - alphaF;
        const ur = (rgbData[i]   - inv * checkerBase) / alphaF;
        const ug = (rgbData[i+1] - inv * checkerBase) / alphaF;
        const ub = (rgbData[i+2] - inv * checkerBase) / alphaF;
        out[j]   = Math.max(0, Math.min(255, Math.round(ur)));
        out[j+1] = Math.max(0, Math.min(255, Math.round(ug)));
        out[j+2] = Math.max(0, Math.min(255, Math.round(ub)));
      }
    }

    out[j+3] = alpha;
  }

  await sharp(out, { raw: { width, height, channels: 4 } })
    .png({ compressionLevel: 9 })
    .toFile(outPath);

  console.log(`${inputName} -> ${outputName} (${width}x${height})`);
}

(async () => {
  await processImage('lockpick.jpg',       'lockpick.png',       'lockpick');
  await processImage('resonance_glow.jpg', 'resonance_glow.png', 'glow');
  console.log('Done.');
})().catch(e => { console.error(e); process.exit(1); });
