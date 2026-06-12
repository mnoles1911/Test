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
//   3. You open the studio, pick the preset from the dropdown — the tree
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
// SCALE: 10 cm per voxel. A trunkH of 64 = 6.4 m.
// ===========================================================================

window.PRESETS = {

  // -------------------------------------------------------------------------
  // SET: "Mira broadleaf oak" — inspired by the Steam fantasy-voxel scene
  // (app 2776090). Thick dark trunks, big full rounded/billowing green
  // canopies. Four variations: one grand hero oak + rounded mid-ground oaks
  // + a young understory oak, so a forest reads with variety.
  // -------------------------------------------------------------------------

  "oak_grand": {
    label: "Oak — grand spreading (ref)",
    reference: "references/steam_2776090_scene.png",
    notes: "Hero foreground oak: thick trunk, wide billowing lumpy canopy. ~9m tall. Heavy voxel count — that's expected for a hero tree.",
    controls: {
      seed: 41, trunkH: 64, trunkR: 3, lean: 28,
      branches: 6, branchLen: 14,
      canopyShape: "blob", canopyR: 32, canopyStretch: 92, density: 84, rough: 48
    }
  },

  "oak_round_a": {
    label: "Oak — rounded mid (ref)",
    reference: "references/steam_2776090_scene.png",
    notes: "Mid-ground lollipop oak: full round canopy, medium trunk. ~7m tall.",
    controls: {
      seed: 12, trunkH: 46, trunkR: 2, lean: 16,
      branches: 4, branchLen: 8,
      canopyShape: "sphere", canopyR: 24, canopyStretch: 100, density: 84, rough: 32
    }
  },

  "oak_round_b": {
    label: "Oak — rounded mid, var. B (ref)",
    reference: "references/steam_2776090_scene.png",
    notes: "Sibling of round_a — different seed, a touch taller and narrower for forest variety. ~7.5m tall.",
    controls: {
      seed: 88, trunkH: 52, trunkR: 2, lean: 20,
      branches: 4, branchLen: 9,
      canopyShape: "sphere", canopyR: 22, canopyStretch: 112, density: 82, rough: 36
    }
  },

  "oak_young": {
    label: "Oak — young understory (ref)",
    reference: "references/steam_2776090_scene.png",
    notes: "Smaller filler oak for the forest floor / mid distance. ~4.5m tall.",
    controls: {
      seed: 5, trunkH: 34, trunkR: 2, lean: 22,
      branches: 2, branchLen: 6,
      canopyShape: "sphere", canopyR: 16, canopyStretch: 100, density: 80, rough: 40
    }
  },

  // -------------------------------------------------------------------------
  // Starter presets (no reference) — kept as format examples.
  // -------------------------------------------------------------------------

  "pine_evergreen": {
    label: "Pine — evergreen (starter)",
    reference: "",
    notes: "Tall thin trunk, narrow conical canopy, looser density. Starting point for conifer refs.",
    controls: {
      seed: 21, trunkH: 64, trunkR: 1, lean: 6,
      branches: 2, branchLen: 4,
      canopyShape: "cone", canopyR: 16, canopyStretch: 180, density: 70, rough: 30
    }
  }

};
