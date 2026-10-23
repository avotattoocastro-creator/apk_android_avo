#!/usr/bin/env bash
# Build AVO BACK V4.0.0-dev for the Heltec Wireless Stick Lite V3 (arduino-cli, arduino-esp32 3.3.x).
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
OUT="${1:-$HERE/firmware_back}"
CLI="${ARDUINO_CLI:-arduino-cli}"
LIBS="$HERE/.build_libs_back"
FQBN="${FQBN:-esp32:esp32:heltec_wireless_stick_lite_V3}"
rm -rf "$LIBS" && mkdir -p "$LIBS" && cp -r "$HERE/lib/avo_core" "$LIBS/"
BP="$HERE/.arduino_build_back"; rm -rf "$BP"
PMAP="-ffile-prefix-map=$HERE=AVO -ffile-prefix-map=$BP=AVOBUILD"
mkdir -p "$OUT"
"$CLI" compile -b "$FQBN" --libraries "$LIBS" --build-path "$BP" --output-dir "$OUT" --warnings default --jobs 0 \
  --build-property "compiler.c.extra_flags=$PMAP" --build-property "compiler.cpp.extra_flags=$PMAP" \
  "$HERE/AVO_BACK_V4_0_0_DEV" 2>&1 | tee "$OUT/build.log"
