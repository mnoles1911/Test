# tools/devtools — browser self-verification

A headless-Chromium loop so a built page (the voxel studios, any repo HTML, a
rendered artifact) can be **rendered, screenshotted, and checked for console
errors** — closing the dev loop where browser output was previously invisible.

## Setup (one-time)

```bash
cd tools/devtools
npm install playwright          # or link a global install
npx playwright install chromium # downloads the browser (~150 MB)
```
`node_modules/` is git-ignored.

## Use

```bash
# serve the repo locally + screenshot a studio (tests the ACTUAL repo files)
tools/devtools/verify.sh tools/voxel_rock_studio/index.html /tmp/rock.png --wait 5000

# drive it: click a button / set state before the shot
tools/devtools/verify.sh tools/voxel_tree_studio/index.html /tmp/tree.png --click "#randomize"
```

### Regression sweep: `verify_all.sh`

```bash
tools/devtools/verify_all.sh [out_dir]   # default out dir: /tmp/verify_all
```

Serves the repo once and screenshots **every studio in its major modes** (rock:
boulder/angular/cliff/spire/pebbles; tree: oak/pine/space-col/fern/grass/vine +
randomize), printing a `PASS`/`FAIL` line per mode and **exiting nonzero if any
mode logged a console error**. Run it before pushing studio changes (or after a
dependency/CDN bump) to catch a broken studio fast.

`verify.sh` prints a JSON report (`httpStatus`, `errorCount`, `errors[]`) and
exits **1 if the page logged any error** — so it drives a fix-rerun loop. The
PNG is written to the given path (Claude can then *view* it).

### Lower-level: `browse_shot.mjs`

```bash
node tools/devtools/browse_shot.mjs <url> [out.png] \
    [--wait ms] [--full] [--width N] [--height N] \
    [--selector "<sel>"] [--click "<sel>"] [--eval "<js>"]
```
Serving locally is preferred over a CDN/githack URL (avoids cert + cache
flakiness). Launches with SwiftShader WebGL so Three.js renders headlessly.
