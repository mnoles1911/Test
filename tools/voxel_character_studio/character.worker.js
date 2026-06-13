// Character voxelization off the main thread (pure JS, no THREE/DOM).
import { buildCharacter } from './character_builder.js';
self.onmessage = (e) => {
  const { reqId, params } = e.data;
  try {
    const { positions, materials, stats } = buildCharacter(params);
    self.postMessage({ reqId, ok: true, positions, materials, stats }, [positions.buffer, materials.buffer]);
  } catch (err) {
    self.postMessage({ reqId, ok: false, error: String(err && err.message || err) });
  }
};
