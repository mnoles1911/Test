// ===========================================================================
// claude_vision.js — analyze a reference image with Claude, get rock params
// ===========================================================================
// Browser-side (client) call to the Anthropic Messages API. You paste your own
// API key (stored in localStorage). The model looks at the uploaded rock image
// and returns structured parameters via STRICT TOOL USE, which we apply to the
// dials.
//
// SECURITY: this calls Claude directly from the browser using YOUR key — the
// key is visible in this page's network traffic. That's fine for a local design
// tool you run yourself; do NOT deploy this with a shared/secret key. The
// `anthropic-dangerous-direct-browser-access` header is what permits the call.

const API_URL = 'https://api.anthropic.com/v1/messages';
const MODEL = 'claude-opus-4-8';   // all current Claude models are vision-capable

// The tool whose `input` schema IS the rock parameter set. strict:true + a
// forced tool_choice guarantees Claude returns exactly this JSON shape.
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

/**
 * @param {string} dataUrl  a data: URL (data:image/png;base64,...) or any image
 * @param {string} apiKey   the user's Anthropic API key
 * @returns {Promise<{params?:object, error?:string}>}
 */
export async function analyzeRockImage(dataUrl, apiKey) {
  if (!apiKey) return { error: 'Enter your Anthropic API key first.' };
  const m = /^data:(image\/[a-zA-Z+]+);base64,(.+)$/.exec(dataUrl || '');
  if (!m) return { error: 'Image must be a base64 data URL — drag/drop or load a file (not a remote URL).' };
  const media_type = m[1], data = m[2];

  let resp;
  try {
    resp = await fetch(API_URL, {
      method: 'POST',
      headers: {
        'content-type': 'application/json',
        'x-api-key': apiKey,
        'anthropic-version': '2023-06-01',
        'anthropic-dangerous-direct-browser-access': 'true',
      },
      body: JSON.stringify({
        model: MODEL,
        max_tokens: 1024,
        tools: [{ ...ROCK_TOOL, strict: true }],
        tool_choice: { type: 'tool', name: ROCK_TOOL.name },
        messages: [{
          role: 'user',
          content: [
            { type: 'image', source: { type: 'base64', media_type, data } },
            { type: 'text', text: PROMPT },
          ],
        }],
      }),
    });
  } catch (e) {
    return { error: 'Network error calling Claude (check connection / key). ' + (e && e.message || e) };
  }
  if (!resp.ok) {
    let detail = resp.status + '';
    try { const j = await resp.json(); detail = j.error?.message || JSON.stringify(j); } catch {}
    return { error: 'Claude API error: ' + detail };
  }
  const json = await resp.json();
  const tu = (json.content || []).find(b => b.type === 'tool_use');
  if (!tu) return { error: 'Claude did not return parameters (no tool_use block).' };
  return { params: tu.input };
}
