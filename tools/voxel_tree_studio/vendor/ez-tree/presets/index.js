// VENDOR MODIFICATION (Voxel Tree Studio):
// Upstream ez-tree imports each preset as a JSON module (`import x from './a.json'`),
// which Vite resolves at build time. Browsers can't bare-import JSON without an
// import-assertion + bundler, so we load the presets from `data.js` (generated
// from the original JSONs, which are kept alongside for provenance). Behavior is
// identical to upstream's TreePreset map + loadPreset.
import TreeOptions from '../options.js';
import { TreePresetData } from './data.js';

export const TreePreset = TreePresetData;

/**
 * @param {string} name The name of the preset to load
 * @returns {TreeOptions}
 */
export function loadPreset(name) {
  const preset = TreePreset[name];
  return preset ? structuredClone(preset) : new TreeOptions();
}
