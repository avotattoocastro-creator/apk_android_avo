#!/usr/bin/env bash
# Build AVO BACK V4.0.0 for the AVO BACK V4 board (ESP32-S3-MINI-1U-N8, 8 MB flash, no PSRAM) with arduino-cli.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
OUT="${1:-$HERE/firmware_back}"
CLI="${ARDUINO_CLI:-arduino-cli}"
LIBS="$HERE/.build_libs_back"
FQBN="${FQBN:-esp32:esp32:esp32s3:CDCOnBoot=cdc,USBMode=hwcdc,FlashSize=8M,PartitionScheme=default_8MB,PSRAM=disabled,CPUFreq=160}"
rm -rf "$LIBS" && mkdir -p "$LIBS" && cp -r "$HERE/lib/avo_core" "$LIBS/"
BP="$HERE/.arduino_build_back"; rm -rf "$BP"
PMAP="-ffile-prefix-map=$HERE=AVO -ffile-prefix-map=$BP=AVOBUILD"
mkdir -p "$OUT"
"$CLI" compile -b "$FQBN" --libraries "$LIBS" --build-path "$BP" --output-dir "$OUT" --warnings default --jobs 0 \
  --build-property "compiler.c.extra_flags=$PMAP" --build-property "compiler.cpp.extra_flags=$PMAP" \
  "$HERE/AVO_BACK_V4_0_0" 2>&1 | tee "$OUT/build.log"
