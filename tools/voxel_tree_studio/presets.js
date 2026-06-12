// ===========================================================================
// VOXEL TREE STUDIO — DESIGN PRESETS
// ===========================================================================
//
// This is the "reference image -> design" memory. Each entry is one tree
// design Claude built from a reference picture you sent.
//
// THE LOOP
//   1. You send Claude a reference image of a voxel tree.
//   2. Claude saves the image under references/ and adds an entry below:
//      its read of the trunk/canopy as slider values, plus the image path.
//   3. You open index.html, pick the preset from the dropdown — the tree
//      loads AND the reference ghosts over the render so you can judge the
//      match. You give feedback, Claude tweaks the numbers here, repeat.
//
// FIELDS
//   label     — what shows in the dropdown.
//   reference — path to the reference image (optional). Used for the overlay.
//   notes     — Claude's reasoning / what to refine.
//   controls  — slider values, keyed EXACTLY by the control ids in index.html:
//                 seed, trunkH, trunkR (1..5), lean, branches, branchLen,
//                 canopyShape ("sphere"|"ellipsoid"|"cone"|"blob"),
//                 canopyR, canopyStretch, density, rough
//
// Two starter presets below show the format. They have no reference image
// yet — real reference-backed presets get added as you send pictures.
// ===========================================================================

window.PRESETS = {

  "oak_broadleaf": {
    label: "Oak — broadleaf (starter)",
    reference: "",   // e.g. "references/oak_ref.png" once you send one
    notes: "Stout short trunk, wide round canopy, dense. Starting point for broadleaf refs.",
    controls: {
      seed: 7, trunkH: 11, trunkR: 3, lean: 18,
      branches: 4, branchLen: 6,
      canopyShape: "sphere", canopyR: 9, canopyStretch: 90, density: 82, rough: 38
    }
  },

  "pine_evergreen": {
    label: "Pine — evergreen (starter)",
    reference: "",
    notes: "Tall thin trunk, narrow conical canopy, looser density. Starting point for conifer refs.",
    controls: {
      seed: 21, trunkH: 22, trunkR: 1, lean: 6,
      branches: 2, branchLen: 4,
      canopyShape: "cone", canopyR: 7, canopyStretch: 180, density: 70, rough: 30
    }
  }

};
