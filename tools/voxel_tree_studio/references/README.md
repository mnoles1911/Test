# references/

Reference images of voxel trees go here — the pictures that drive a design.

When you send Claude a reference image, Claude:

1. Saves it here (e.g. `references/oak_gnarled.png`).
2. Adds a matching entry to `../presets.js` (estimated slider values + this
   image path).

Then in the studio you pick that preset from the dropdown: it loads the tree
**and** ghosts the reference over the 3D render (Overlay opacity slider) so
you can see how close the match is and ask for tweaks.

Pixel-art / small PNGs render crisply (the overlay uses pixelated scaling).
