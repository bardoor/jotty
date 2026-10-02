#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
WORK="$ROOT/.build"
UPSTREAM="$WORK/webrtc-audio-processing"
REVISION=846fe90a289f58b7c9303a635142aa2c7caa93e5
ABSEIL_ARCHIVE=abseil-cpp-20240722.0.tar.gz
ABSEIL_PATCH=abseil-cpp_20240722.0-3_patch.zip

mkdir -p "$WORK"

if [ ! -d "$UPSTREAM/.git" ]; then
  git clone --branch v2.1 --depth 1 \
    https://gitlab.freedesktop.org/pulseaudio/webrtc-audio-processing.git \
    "$UPSTREAM"
fi

actual_revision=$(git -C "$UPSTREAM" rev-parse HEAD)
if [ "$actual_revision" != "$REVISION" ]; then
  printf 'unexpected upstream revision: %s\n' "$actual_revision" >&2
  exit 1
fi

if [ ! -x "$WORK/venv/bin/meson" ]; then
  python3 -m venv "$WORK/venv"
  "$WORK/venv/bin/pip" install meson==1.12.1
fi

mkdir -p "$UPSTREAM/subprojects/packagecache"
if [ ! -f "$UPSTREAM/subprojects/packagecache/$ABSEIL_ARCHIVE" ]; then
  curl -fL \
    "https://github.com/abseil/abseil-cpp/releases/download/20240722.0/$ABSEIL_ARCHIVE" \
    -o "$UPSTREAM/subprojects/packagecache/$ABSEIL_ARCHIVE"
fi
if [ ! -f "$UPSTREAM/subprojects/packagecache/$ABSEIL_PATCH" ]; then
  curl -fL \
    "https://wrapdb.mesonbuild.com/v2/abseil-cpp_20240722.0-3/get_patch" \
    -o "$UPSTREAM/subprojects/packagecache/$ABSEIL_PATCH"
fi

(
  cd "$UPSTREAM/subprojects/packagecache"
  printf '%s  %s\n' \
    f50e5ac311a81382da7fa75b97310e4b9006474f9560ac46f54a9967f07d4ae3 \
    "$ABSEIL_ARCHIVE" | shasum -a 256 -c
  printf '%s  %s\n' \
    12dd8df1488a314c53e3751abd2750cf233b830651d168b6a9f15e7d0cf71f7b \
    "$ABSEIL_PATCH" | shasum -a 256 -c
)

rm -rf "$UPSTREAM/build-static" "$UPSTREAM/install-static"
"$WORK/venv/bin/meson" setup "$UPSTREAM/build-static" "$UPSTREAM" \
  --prefix "$UPSTREAM/install-static" \
  -Dbuildtype=release \
  -Ddefault_library=static \
  --force-fallback-for=absl_base,absl_flags,absl_strings,absl_numeric,absl_synchronization,absl_bad_optional_access
ninja -C "$UPSTREAM/build-static"
ninja -C "$UPSTREAM/build-static" install

INCLUDE_DIR="$UPSTREAM/install-static/include/webrtc-audio-processing-2"

clang++ -std=c++17 -Wall -Wextra -Werror -dynamiclib \
  "$ROOT/AecBridge.cpp" \
  -I"$ROOT" \
  -isystem "$UPSTREAM/install-static/include" \
  -isystem "$INCLUDE_DIR" \
  -DWEBRTC_LIBRARY_IMPL \
  -DWEBRTC_POSIX \
  "$UPSTREAM/install-static/lib/libwebrtc-audio-processing-2.a" \
  -framework Foundation \
  -framework CoreFoundation \
  -install_name @rpath/libJottyAEC.dylib \
  -o "$WORK/libJottyAEC.dylib"

swiftc \
  -warnings-as-errors \
  "$ROOT/smoke.swift" \
  -I "$ROOT" \
  -L "$WORK" \
  -lJottyAEC \
  -Xlinker -rpath \
  -Xlinker "$WORK" \
  -o "$WORK/aec-smoke"

"$WORK/aec-smoke"
file "$WORK/libJottyAEC.dylib" "$WORK/aec-smoke"
otool -L "$WORK/libJottyAEC.dylib"
