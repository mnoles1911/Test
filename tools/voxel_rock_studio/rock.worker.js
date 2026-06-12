// Rock voxelization off the main thread (pure JS, no THREE/DOM).
import { voxelizeRock } from './rock_voxelizer.js';
self.onmessage = (e) => {
  const { reqId, params } = e.data;
  try {
    const { positions, materials, stats } = voxelizeRock(params);
    self.postMessage({ reqId, ok: true, positions, materials, stats }, [positions.buffer, materials.buffer]);
  } catch (err) {
    self.postMessage({ reqId, ok: false, error: String(err && err.message || err) });
  }
};
