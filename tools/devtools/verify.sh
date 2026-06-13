#!/usr/bin/env bash
# ===========================================================================
# verify.sh — serve the repo locally and screenshot a page in headless Chromium
# ===========================================================================
# The browser self-verification loop: render a studio (or any repo page) and
# capture console errors. Serving locally avoids CDN/cert flakiness and tests
# the ACTUAL repo files (not a cached deploy).
#
#   tools/devtools/verify.sh <repo-path-url> [out.png] [extra browse_shot args]
#
# e.g.
#   tools/devtools/verify.sh tools/voxel_rock_studio/index.html /tmp/rock.png --wait 5000
#   tools/devtools/verify.sh tools/voxel_tree_studio/index.html /tmp/tree.png --click "#randomize"
#
# Exit code is browse_shot's (1 if the page logged errors). PORT overridable.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PATHURL="${1:?usage: verify.sh <repo-path-url> [out.png] [extra...]}"; shift
OUT="${1:-/tmp/verify.png}"; if [ $# -gt 0 ] && [ "${1:0:2}" != "--" ]; then shift; fi
PORT="${PORT:-8099}"

( cd "$ROOT" && exec python3 -m http.server "$PORT" --bind 127.0.0.1 >/tmp/verify_httpd.log 2>&1 ) &
SRV=$!
trap 'kill "$SRV" 2>/dev/null || true' EXIT
sleep 1

node "$ROOT/tools/devtools/browse_shot.mjs" "http://127.0.0.1:$PORT/$PATHURL" "$OUT" "$@"
