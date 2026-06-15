#!/usr/bin/env bash
# build.sh — compile + run the engine-agnostic Core parity harness with clang.
#
# This is the headless verification loop that runs in CI and the dev container
# (no Unreal needed). Each test_*.cpp is a self-contained program (its own main)
# covering one ported Core system; it is compiled against ALL Core sources from
# EVERY module (MiraThalVoxel, MiraThalCore, ...) and run. Exit 0 = every green.
#
# Adding a module's pure-logic Core is automatic: drop headers in
# <Module>/Public/Core and sources in <Module>/Private/Core, add a test_*.cpp,
# and this script finds them.
#
# Usage:
#   ./build.sh                 # build + run every test_*.cpp
#   ./build.sh water combat    # build + run only test_water / test_combat
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_ROOT="$HERE/../../Source"
CXX="${CXX:-clang++}"

# Include path: every module's Public dir (so "Core/Foo.h" resolves regardless
# of which module owns it).
INCLUDES=()
while IFS= read -r -d '' d; do INCLUDES+=(-I "$d"); done \
    < <(find "$SOURCE_ROOT" -type d -name Public -print0 | sort -z)

FLAGS=(-std=c++17 -O2 -Wall -Wextra -Wshadow "${INCLUDES[@]}")

# Every Core .cpp across all modules. Core sources contain no main(), so a test
# can link the whole set with no symbol clashes.
CORE_SRCS=()
while IFS= read -r -d '' f; do CORE_SRCS+=("$f"); done \
    < <(find "$SOURCE_ROOT" -type d -name Core -path '*/Private/*' \
            -exec find {} -name '*.cpp' -print0 \; | sort -z)

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
