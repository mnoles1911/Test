#!/usr/bin/env bash
# ===========================================================================
# verify_all.sh — browser regression across all voxel studios
# ===========================================================================
# Serves the repo once and screenshots each studio in its major modes, watching
# for console errors. Prints a PASS/FAIL summary and exits nonzero if anything
# logged an error — so it works as a pre-push / CI-style check.
#
#   tools/devtools/verify_all.sh [out_dir]      # default out dir: /tmp/verify_all
#
# Requires the one-time devtools setup (see README): npm i playwright +
# npx playwright install chromium.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUTDIR="${1:-/tmp/verify_all}"; mkdir -p "$OUTDIR"
PORT="${PORT:-8099}"

# make the global playwright importable if a local one isn't present
[ -e "$ROOT/tools/devtools/node_modules/playwright" ] || \
  ln -sfn "$(npm root -g)/playwright" "$ROOT/tools/devtools/node_modules/playwright" 2>/dev/null || true

( cd "$ROOT" && exec python3 -m http.server "$PORT" --bind 127.0.0.1 >/tmp/verify_all_httpd.log 2>&1 ) &
SRV=$!
trap 'kill "$SRV" 2>/dev/null || true' EXIT
sleep 1
B="http://127.0.0.1:$PORT"

fail=0; n=0
sel() { echo "var s=document.getElementById('$1');s.value='$2';s.dispatchEvent(new Event('change'))"; }
check() { # label path out [extra browse_shot args...]
  n=$((n + 1)); local label="$1" path="$2" out="$3"; shift 3
  local json ec
  json=$(node "$ROOT/tools/devtools/browse_shot.mjs" "$B/$path" "$OUTDIR/$out" "$@" 2>&1) || true
  ec=$(printf '%s' "$json" | python3 -c "import sys,json
try: print(json.loads(sys.stdin.read())['errorCount'])
except Exception: print('?')" 2>/dev/null)
  if [ "$ec" = "0" ]; then
    printf '  PASS  %s\n' "$label"
  else
    printf '  FAIL  %s  (errors=%s)\n' "$label" "$ec"; fail=$((fail + 1))
    printf '%s\n' "$json" | tail -6
  fi
}

ROCK=tools/voxel_rock_studio/index.html
TREE=tools/voxel_tree_studio/index.html
echo "== Voxel studio regression =="
check "rock · boulder"  "$ROCK" rock_boulder.png  --wait 4000
check "rock · angular"  "$ROCK" rock_angular.png  --eval "$(sel rockType Angular)" --wait 3000
check "rock · cliff"    "$ROCK" rock_cliff.png    --eval "$(sel rockType Cliff)"   --wait 3000
check "rock · spire"    "$ROCK" rock_spire.png    --eval "$(sel rockType Spire)"   --wait 3000
check "rock · pebbles"  "$ROCK" rock_pebbles.png  --eval "$(sel rockType Pebbles)" --wait 3000
check "tree · oak"      "$TREE" tree_oak.png      --wait 4000
check "tree · pine"     "$TREE" tree_pine.png     --eval "$(sel species 'Pine Medium')" --wait 3500
check "tree · space-col" "$TREE" tree_spacecol.png --eval "$(sel plantType 'Tree (space-col)')" --wait 4000
check "tree · fern"     "$TREE" tree_fern.png     --eval "$(sel plantType Fern)" --wait 3000
check "tree · grass"    "$TREE" tree_grass.png    --eval "$(sel plantType 'Grass tuft')" --wait 3000
check "tree · vine"     "$TREE" tree_vine.png     --eval "$(sel plantType Vine)" --wait 3000
check "tree · randomize" "$TREE" tree_random.png  --click '#randomize' --wait 3000

echo
if [ "$fail" -eq 0 ]; then
  echo "ALL $n CHECKS PASSED  (screenshots in $OUTDIR)"
else
  echo "$fail/$n CHECKS FAILED  (screenshots in $OUTDIR)"
fi
exit "$fail"
