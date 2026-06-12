// Rock-specific wrapper around the shared Claude-vision call. The tool's input
// schema IS the rock parameter set; strict tool use guarantees the shape.
import { analyzeImage } from '../voxel_studio_common/claude_vision.js';

const ROCK_TOOL = {
  name: 'set_rock_parameters',
  description: 'Set the procedural voxel-rock parameters that best reproduce the rock in the image.',
  input_schema: {
    type: 'object',
    additionalProperties: false,
    properties: {
      rockType:   { type: 'string', enum: ['Boulder','Angular','Cliff','Spire','Pebbles','Pile'], description: 'Closest overall form.' },
      boxiness:   { type: 'number', description: 'Superquadric exponent 2 (rounded) to 8 (blocky/cubic).' },
      noiseAmp:   { type: 'number', description: 'Surface roughness 0 (smooth) to 0.5 (very rough).' },
      faceting:   { type: 'number', description: 'Angular flat-facet amount 0 (none) to 0.8 (very faceted).' },
      flatBottom: { type: 'number', description: 'How flat the base sits 0 (round) to 0.8 (flat).' },
      erosion:    { type: 'number', description: 'Weathered smoothing 0 (sharp) to 0.8 (smooth).' },
      topTaper:   { type: 'number', description: 'Pointed top 0 (none) to 0.9 (sharp spire).' },
      strata:     { type: 'number', description: 'Horizontal sedimentary layering 0 to 0.8.' },
      marbleVeins:{ type: 'number', description: 'Light mineral veining 0 to 0.6.' },
      mossAmount: { type: 'number', description: 'Moss coverage on top 0 to 0.8.' },
      darkMix:    { type: 'number', description: 'Darkness of the stone 0 (light) to 0.9 (dark).' },
      aspectTall: { type: 'number', description: 'Height vs width: 0.3 (flat/wide) to 3 (tall/thin).' },
    },
    required: ['rockType','boxiness','noiseAmp','faceting','flatBottom','erosion','topTaper','strata','marbleVeins','mossAmount','darkMix','aspectTall'],
  },
};

const PROMPT =
  'Analyze this reference image of a rock to recreate it as a chunky voxel rock. ' +
  'Judge its overall form (rounded boulder, angular/faceted, tall cliff or spire, ' +
  'pebble scatter, or a pile), surface roughness, how flat it sits on the ground, ' +
  'any horizontal layering/strata, light mineral veins, moss on top, darkness, and ' +
  'its height-to-width proportion. Call set_rock_parameters with values in the ' +
  'stated ranges that best reproduce this rock. Be decisive.';

export function analyzeRockImage(dataUrl, apiKey) {
  return analyzeImage(dataUrl, apiKey, ROCK_TOOL, PROMPT);
}
