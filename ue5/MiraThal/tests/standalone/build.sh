#!/usr/bin/env bash
# build.sh — compile + run the engine-agnostic Core parity harness with clang.
#
# This is the headless verification loop that runs in CI and the dev container
# (no Unreal needed). Each test_*.cpp is a self-contained program (its own main)
# covering one ported Core system; it is compiled against all Core sources and
# run. Exit 0 = every harness green.
#
# Usage:
#   ./build.sh                 # build + run every test_*.cpp
#   ./build.sh water gravity   # build + run only test_water / test_gravity
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INCLUDE="$HERE/../../Source/MiraThalVoxel/Public"
CORE_SRC_DIR="$HERE/../../Source/MiraThalVoxel/Private/Core"
CXX="${CXX:-clang++}"
FLAGS=(-std=c++17 -O2 -Wall -Wextra -Wshadow -I "$INCLUDE")

# Every Core .cpp (water sim, gravity, generator, ...). Each test links all of
# them; Core sources contain no main(), so there are no symbol clashes.
CORE_SRCS=()
if [ -d "$CORE_SRC_DIR" ]; then
    while IFS= read -r -d '' f; do CORE_SRCS+=("$f"); done \
        < <(find "$CORE_SRC_DIR" -name '*.cpp' -print0 | sort -z)
fi

# Which harnesses to run: all test_*.cpp, or just the named ones.
declare -a TESTS
if [ "$#" -eq 0 ]; then
    while IFS= read -r -d '' f; do TESTS+=("$f"); done \
        < <(find "$HERE" -maxdepth 1 -name 'test_*.cpp' -print0 | sort -z)
else
    for name in "$@"; do
        f="$HERE/test_${name}.cpp"
        [ -f "$f" ] || { echo "no harness: test_${name}.cpp"; exit 2; }
        TESTS+=("$f")
    done
fi

fails=0
for t in "${TESTS[@]}"; do
    base="$(basename "$t" .cpp)"
    out="$HERE/$base.run"
    echo "== building $base =="
    "$CXX" "${FLAGS[@]}" "$t" "${CORE_SRCS[@]}" -o "$out"
    "$out" || fails=$((fails + 1))
done

echo "===================="
if [ "$fails" -eq 0 ]; then
    echo "ALL HARNESSES GREEN"
else
    echo "$fails HARNESS(ES) FAILED"
fi
exit "$fails"
