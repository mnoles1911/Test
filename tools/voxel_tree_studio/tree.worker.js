// ===========================================================================
// tree.worker.js — offload voxelization so the UI stays responsive
// ===========================================================================
// The ez-tree skeleton is built on the main thread (it needs THREE math), then
// the plain skeleton arrays are posted here. Voxelization (the heavy 100k–500k
// cell loop) runs off-thread and the result transfers back as typed arrays.
import { voxelize } from './tree_voxelizer.js';

self.onmessage = (e) => {
  const { reqId, skeleton, leafAnchors, opts } = e.data;
  try {
    const { positions, materials, stats } = voxelize(skeleton, leafAnchors, opts);
    self.postMessage(
      { reqId, ok: true, positions, materials, stats },
      [positions.buffer, materials.buffer],
    );
  } catch (err) {
    self.postMessage({ reqId, ok: false, error: String(err && err.message || err) });
  }
};
