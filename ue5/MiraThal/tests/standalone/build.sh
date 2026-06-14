#!/usr/bin/env bash
# build.sh — compile + run the engine-agnostic Core parity harness with clang.
#
# This is the headless verification loop that runs in CI and the dev container
# (no Unreal needed). It compiles the pure-C++17 Core against the standalone
# test harness and runs the selectors. Exit 0 = green.
#
# Usage:
#   ./build.sh                 # build, then run every selector
#   ./build.sh scale codec     # build, then run only the named selectors
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Core headers live under the MiraThalVoxel module's Public/ dir.
INCLUDE="$HERE/../../Source/MiraThalVoxel/Public"
OUT="$HERE/run_tests"

CXX="${CXX:-clang++}"

echo "== building Core parity harness =="
"$CXX" -std=c++17 -O2 -Wall -Wextra -Wshadow \
    -I "$INCLUDE" \
    "$HERE/test_main.cpp" \
    -o "$OUT"

echo "== running selectors =="
"$OUT" "$@"
