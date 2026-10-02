#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
OUTPUT_DIRECTORY=${1:-}
AEC_BUILD="$ROOT/spikes/001-aec-build-api/.build"
AEC_LIBRARY="$AEC_BUILD/libJottyAEC.dylib"
RECORDER="$ROOT/native/recorder/.build/release/jotty-recorder"

if [ -z "$OUTPUT_DIRECTORY" ]; then
  printf 'Usage: %s OUTPUT_DIRECTORY\n' "$0" >&2
  exit 64
fi

mkdir -p "$OUTPUT_DIRECTORY"

if [ ! -f "$AEC_LIBRARY" ] || \
  [ "$ROOT/spikes/001-aec-build-api/AecBridge.cpp" -nt "$AEC_LIBRARY" ] || \
  [ "$ROOT/spikes/001-aec-build-api/AecBridge.h" -nt "$AEC_LIBRARY" ]; then
  "$ROOT/spikes/001-aec-build-api/build.sh"
fi

swift build -c release --package-path "$ROOT/native/recorder"

printf 'Recording AEC quality sample. Press Ctrl-C to stop.\n' >&2
JOTTY_AEC_LIBRARY_PATH="$AEC_LIBRARY" \
  "$RECORDER" --aec-spike "$OUTPUT_DIRECTORY" >/dev/null
