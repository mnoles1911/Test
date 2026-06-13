// Character-specific wrapper around the shared Claude-vision call. The tool's
// input schema IS the character parameter set; strict tool use guarantees shape.
import { analyzeImage } from '../voxel_studio_common/claude_vision.js';

const CHARACTER_TOOL = {
  name: 'set_character_parameters',
  description: 'Set the procedural T-pose voxel-character parameters that best reproduce the biped in the image.',
  input_schema: {
    type: 'object', additionalProperties: false,
    properties: {
      species:       { type: 'string', enum: ['Human','Goblin','Dwarf','Ashfallen'], description: 'Closest creature type.' },
      heightM:       { type: 'number', description: 'Height in meters, 1.2 to 2.1.' },
      build:         { type: 'number', description: 'Body bulk: 0.7 (lean) to 1.4 (heavy/broad).' },
      headSize:      { type: 'number', description: 'Head size as fraction of height, 0.13 to 0.22.' },
      shoulderWidth: { type: 'number', description: 'Shoulder half-width fraction, 0.10 (narrow) to 0.22 (broad).' },
      earSize:       { type: 'number', description: 'Ear size 0 to 1.' },
      earPoint:      { type: 'number', description: 'Ear pointedness 0 (round) to 1 (pointed/elf/goblin).' },
      snout:         { type: 'number', description: 'Muzzle/snout protrusion 0 to 1.' },
      tuskSize:      { type: 'number', description: 'Tusks 0 to 1.' },
      beard:         { type: 'number', description: 'Beard amount 0 to 1.' },
      eyeGlow:       { type: 'number', description: 'Glowing eyes 0 (no) or 1 (yes).' },
      bareChest:     { type: 'number', description: 'Bare chest 0 (clothed) or 1 (bare).' },
      armor:         { type: 'number', description: 'Plate armor covering 0 (none) or 1 (armored).' },
    },
    required: ['species','heightM','build','headSize','shoulderWidth','earSize','earPoint','snout','tuskSize','beard','eyeGlow','bareChest','armor'],
  },
};

const PROMPT =
  'Analyze this reference image of a bipedal character/creature to recreate it as ' +
  'a chunky T-pose voxel character. Judge its species (human, goblin, dwarf, or ' +
  'armored knight), height, how lean vs heavy/broad it is, head size, shoulder ' +
  'width, ear size and pointedness, any snout or tusks, beard, whether the eyes ' +
  'glow, whether the chest is bare, and whether it wears plate armor. Call ' +
  'set_character_parameters with values in the stated ranges. Be decisive.';

export function analyzeCharacterImage(dataUrl, apiKey) {
  return analyzeImage(dataUrl, apiKey, CHARACTER_TOOL, PROMPT);
}
