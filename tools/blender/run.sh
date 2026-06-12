#!/usr/bin/env bash
# ===========================================================================
# run.sh — run a Python script inside headless Blender
# ===========================================================================
#   tools/blender/run.sh <script.py> [-- <args for the script>]
#
# Examples:
#   # import a studio export, render an 8-frame turntable, save the .blend
#   tools/blender/run.sh tools/blender/import_voxel_json.py -- \
#       exports/tree_oak.json --render /tmp/oak.png --turntable 8 --save /tmp/oak.blend
#
#   # run any ad-hoc Blender script (e.g. one Claude wrote for a modelling task)
#   tools/blender/run.sh /tmp/scratch_blender_task.py -- arg1 arg2
#
# Set BLENDER=/path/to/blender to point at a specific binary.
set -euo pipefail
BLENDER_BIN="${BLENDER:-blender}"
if ! command -v "$BLENDER_BIN" >/dev/null 2>&1; then
  echo "Blender not found ('$BLENDER_BIN')." >&2
  echo "Install Blender, or set BLENDER=/path/to/blender, then re-run." >&2
  exit 127
fi
if [ $# -lt 1 ]; then
  echo "usage: run.sh <script.py> [-- <args>]" >&2
  exit 2
fi
script="$1"; shift
exec "$BLENDER_BIN" --background --python "$script" "$@"
