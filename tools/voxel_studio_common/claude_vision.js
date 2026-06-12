// ===========================================================================
// voxel_studio_common/claude_vision.js — analyze a reference image with Claude
// ===========================================================================
// Shared by both studios. Browser-side (client) call to the Anthropic Messages
// API: send an uploaded image + a tool whose input schema IS the parameter set,
// force that tool, and get structured params back (strict tool use).
//
// SECURITY: this calls Claude directly from the browser with the user's API key
// (carried in the request). Fine for a local design tool you run yourself; do
// NOT host with a shared/secret key. The `anthropic-dangerous-direct-browser-
// access` header is what permits the call. Keys live only in localStorage.

const API_URL = 'https://api.anthropic.com/v1/messages';
const MODEL = 'claude-opus-4-8';   // all current Claude models are vision-capable

/**
 * @param {string} dataUrl  a data: URL (data:image/...;base64,...)
 * @param {string} apiKey   the user's Anthropic API key
 * @param {object} tool     { name, description, input_schema } — input IS the params
 * @param {string} prompt   instruction text shown alongside the image
 * @returns {Promise<{params?:object, error?:string}>}
 */
export async function analyzeImage(dataUrl, apiKey, tool, prompt) {
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
        tools: [{ ...tool, strict: true }],
        tool_choice: { type: 'tool', name: tool.name },
        messages: [{
          role: 'user',
          content: [
            { type: 'image', source: { type: 'base64', media_type, data } },
            { type: 'text', text: prompt },
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
