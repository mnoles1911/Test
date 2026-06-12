// ===========================================================================
// voxel_studio_common/scale_figure.js — a 1.8 m human for scale reference
// ===========================================================================
// A simple blocky humanoid ~18 voxels tall (1.8 m at 10 cm/voxel), to stand
// next to a generated asset so the designer can read its real-world size.
// THREE is passed in so this stays a plain shared module (no import map needed).

export function makeHumanFigure(THREE) {
  const g = new THREE.Group();
  g.name = 'ScaleHuman';
  const mat = new THREE.MeshLambertMaterial({ color: 0x6f93bf, transparent: true, opacity: 0.85 });
  const add = (w, h, d, x, y, z) => {
    const m = new THREE.Mesh(new THREE.BoxGeometry(w, h, d), mat);
    m.position.set(x, y, z); g.add(m);
  };
  // base of feet at y=0, total height ~18 (1.8 m)
  add(1.6, 8, 1.6, -1.2, 4, 0);   // left leg
  add(1.6, 8, 1.6,  1.2, 4, 0);   // right leg
  add(5.0, 6, 2.4,  0,  11, 0);   // torso
  add(1.4, 6, 1.4, -3.2, 11, 0);  // left arm
  add(1.4, 6, 1.4,  3.2, 11, 0);  // right arm
  add(3.0, 3, 3.0,  0,  16.5, 0); // head
  return g;
}

// Stand the figure just to the +X side of an asset of the given voxel size,
// with a ~0.8 m gap. asset base and figure base both sit at y=0.
export function placeFigureBeside(figure, sizeVox) {
  figure.position.set((sizeVox[0] / 2) + 8, 0, 0);
}
