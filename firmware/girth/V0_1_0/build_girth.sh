#!/usr/bin/env bash
# Build AVO GIRTH V0.1.0 for an ESP32-C6 board in XIAO format (arduino-cli, arduino-esp32 3.3.x).
# The protocol library is the back's (single source): firmware/back/V3_8_0/lib/avo_core.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
OUT="${1:-$HERE/firmware_girth}"
CLI="${ARDUINO_CLI:-arduino-cli}"
LIBS="$HERE/.build_libs_girth"
FQBN="${FQBN:-esp32:esp32:XIAO_ESP32C6}"
rm -rf "$LIBS" && mkdir -p "$LIBS" && cp -r "$HERE/../../back/V3_8_0/lib/avo_core" "$LIBS/"
BP="$HERE/.arduino_build_girth"; rm -rf "$BP"
PMAP="-ffile-prefix-map=$HERE=AVO -ffile-prefix-map=$BP=AVOBUILD"
mkdir -p "$OUT"
"$CLI" compile -b "$FQBN" --libraries "$LIBS" --build-path "$BP" --output-dir "$OUT" --warnings default --jobs 0 \
  --build-property "compiler.c.extra_flags=$PMAP" --build-property "compiler.cpp.extra_flags=$PMAP" \
  "$HERE/AVO_GIRTH_V0_1_0" 2>&1 | tee "$OUT/build.log"
