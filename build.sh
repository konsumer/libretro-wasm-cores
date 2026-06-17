#!/usr/bin/env bash
# build.sh — build one libretro core as a wasm SIDE_MODULE.
#
# Usage: ./build.sh <core_name>
#
# Reads cores.json for build parameters. Requires emcc + emmake in PATH.
# Output: dist/<core_name>_libretro.wasm
#
# Environment overrides:
#   SRC_DIR    where to clone/reuse sources   (default: ./src)
#   DIST_DIR   where to write .wasm output    (default: ./dist)
#   JOBS       make parallelism               (default: nproc)

set -euo pipefail

CORE="${1:?Usage: $0 <core_name>}"
SRC_DIR="${SRC_DIR:-./src}"
DIST_DIR="${DIST_DIR:-./dist}"
JOBS="${JOBS:-$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4)}"

command -v emcc   >/dev/null || { echo "emcc not found"; exit 1; }
command -v emmake >/dev/null || { echo "emmake not found"; exit 1; }
command -v jq     >/dev/null || { echo "jq not found"; exit 1; }

MANIFEST="$(dirname "$0")/cores.json"
CORE_JSON="$(jq -r ".cores[] | select(.name == \"$CORE\")" "$MANIFEST")"
[ -n "$CORE_JSON" ] || { echo "Unknown core: $CORE"; exit 1; }

REPO="$(echo "$CORE_JSON"       | jq -r '.repo')"
MAKEFILE="$(echo "$CORE_JSON"   | jq -r '.makefile')"
SUBDIR="$(echo "$CORE_JSON"     | jq -r '.subdir // ""')"
EXTRA_CFLAGS="$(echo "$CORE_JSON" | jq -r '.emcc_cflags // ""')"
MAKE_FLAGS="$(echo "$CORE_JSON" | jq -r '.make_flags // ""')"
# src_name: which repo to clone into (for HW variants sharing a repo with SW)
SRC_NAME="$(echo "$CORE_JSON"   | jq -r '.src_name // .name')"

EXPORTS_CSV="$(jq -r '[.libretro_exports[]] | join(",")' "$MANIFEST")"

CORE_SRC="$SRC_DIR/$SRC_NAME"
BUILD_DIR="$CORE_SRC${SUBDIR:+/$SUBDIR}"
BC_FILE="$BUILD_DIR/${CORE}_libretro_emscripten.bc"
OUT_WASM="$DIST_DIR/${CORE}_libretro.wasm"

mkdir -p "$SRC_DIR" "$DIST_DIR"

# ── Clone ────────────────────────────────────────────────────────────────────
if [ ! -d "$CORE_SRC/.git" ]; then
    echo "==> Cloning $CORE from $REPO"
    git clone --depth 1 --recurse-submodules --shallow-submodules "$REPO" "$CORE_SRC"

    # Patch Makefile.common: force STATIC_LINKING gate to always-true so the
    # core includes libretro-common in the side module (no frontend to provide it).
    MK_COMMON="$CORE_SRC/Makefile.common"
    if [ -f "$MK_COMMON" ]; then
        if grep -q 'ifneq (\$(STATIC_LINKING), 1)' "$MK_COMMON"; then
            echo "==> Patching $CORE/Makefile.common (STATIC_LINKING gate)"
            sed -i.bak 's/ifneq (\$(STATIC_LINKING), 1)/ifeq (1, 1)/g' "$MK_COMMON"
        fi
    fi

    # mgba: drop -DHAVE_CRC32 so the core uses its internal crc32, not zlib's.
    MGBA_MK="$CORE_SRC/libretro-build/Makefile.common"
    if [ -f "$MGBA_MK" ]; then
        if grep -q 'RETRODEFS += -DHAVE_CRC32' "$MGBA_MK"; then
            echo "==> Patching $CORE libretro-build/Makefile.common (drop -DHAVE_CRC32)"
            sed -i.bak 's/RETRODEFS += -DHAVE_CRC32/# patched: use internal crc32/' "$MGBA_MK"
        fi
    fi
fi

# ── Build ────────────────────────────────────────────────────────────────────
echo "==> Building $CORE (emmake, -j$JOBS)"
(
    cd "$BUILD_DIR"
    EMCC_CFLAGS="-O3${EXTRA_CFLAGS:+ $EXTRA_CFLAGS}" \
        emmake make -f "$MAKEFILE" platform=emscripten fpic=-fPIC -j"$JOBS" \
        ${MAKE_FLAGS}
)

# The make step produces a .bc (bitcode archive); copy it to .a for emcc.
A_FILE="${BC_FILE%.bc}.a"
cp "$BC_FILE" "$A_FILE"

# ── Link as SIDE_MODULE ───────────────────────────────────────────────────────
echo "==> Linking $CORE as SIDE_MODULE=2 -> $OUT_WASM"
emcc -O3 -sSIDE_MODULE=2 \
    "-sEXPORTED_FUNCTIONS=$EXPORTS_CSV" \
    -Wl,--whole-archive "$A_FILE" -Wl,--no-whole-archive \
    -o "$OUT_WASM"

echo "==> Done: $OUT_WASM ($(du -h "$OUT_WASM" | cut -f1))"
