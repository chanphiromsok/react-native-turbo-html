#!/usr/bin/env bash
# Compiles the platform-independent core (ios/Core, ObjC++) together with the host-side
# tests and runs them on macOS (same Core Text engine as iOS), registering this package's
# bundled test fonts.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
FONTS="${1:-$HERE/fonts}"
OUT="${TMPDIR:-/tmp}/react-native-turbo-html-tests"
clang++ -std=c++20 -fobjc-arc -O2 \
  -framework Foundation -framework CoreText -framework CoreGraphics \
  -o "$OUT" \
  "$HERE/main.mm" "$HERE"/../ios/Core/*.mm
"$OUT" "$FONTS"
