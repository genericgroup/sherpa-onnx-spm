#!/usr/bin/env bash
#
# build-xcframework.sh — build a universal sherpa-onnx XCFramework
# from upstream v<VERSION> release tarballs PLUS a matched-version
# ONNX Runtime from `csukuangfj/onnxruntime-libs`.
#
# Usage:
#   ./scripts/build-xcframework.sh <sherpa-version> <ort-version> [<custom-macos-libsherpa-onnx-a>]
#
# Example (use upstream macOS prebuilt, NO CoreML):
#   ./scripts/build-xcframework.sh 1.13.2 1.24.4
#
# Example (use a locally-built CoreML-enabled macOS slice — see v1.0.5):
#   ./scripts/build-xcframework.sh 1.13.2 1.24.4 \
#       /path/to/locally/built/install/lib/libsherpa-onnx.a
#
# Why the custom-macos-lib slot exists: upstream's
# `sherpa-onnx-v1.13.2-macos-xcframework-static.tar.bz2` is built
# with `-DSHERPA_ONNX_DISABLE_COREML` (see
# cmake/onnxruntime-osx-{arm64,universal,x86_64}-static.cmake in
# the upstream source — the static-ORT path explicitly opts out of
# CoreML, presumably because Apple's static CoreML framework
# linkage requires manual setup). If you want CoreML acceleration
# on macOS, rebuild sherpa-onnx from source with those
# `add_definitions(-DSHERPA_ONNX_DISABLE_COREML)` lines removed AND
# `target_link_libraries(sherpa-onnx-core "-framework Foundation"
# "-framework CoreML" "-framework Accelerate")` patched in, then
# pass the resulting libsherpa-onnx.a as the third arg here. iOS is
# unaffected — upstream's iOS prebuilt already has CoreML enabled.
#
# Why a separate ORT version arg:
#
# sherpa-onnx v1.13.2's `-ios.tar.bz2` ships sherpa-onnx binaries
# compiled against ORT API 24 (= ORT 1.20+) but bundles an ORT
# 1.17.1 binary. Linking that mismatched bundle at runtime gives:
#
#   "The requested API version [24] is not available, only API
#    versions [1, 17] are supported in this build. Current ORT
#    Version is: 1.17.1."
#
# Fix: ignore the ORT bundled in upstream's iOS tar and fetch a
# matching ORT (1.24.4 carries API 24) from
# `csukuangfj/onnxruntime-libs`, which publishes the same ORT
# XCFrameworks sherpa-onnx itself consumes.
#
# Pipeline:
#   1. Download upstream sherpa-onnx iOS + macOS XCFramework tarballs
#   2. Download matched ORT iOS XCFramework + macOS universal static
#      lib from csukuangfj/onnxruntime-libs
#   3. Combine each sherpa-onnx static lib with its matching ORT
#      static lib (libtool merge) per-arch. macOS needs extra
#      handling because its ORT ships as three split .a files
#      (libonnxruntime + libonnxruntime_mlas_arm64 +
#       libonnxruntime_mlas_x86_64) — we merge per-arch then lipo
#      them universal.
#   4. Write Headers/module.modulemap exposing the C API as a Clang
#      module called CSherpaOnnx.
#   5. Run `xcodebuild -create-xcframework` to produce the universal
#      sherpa-onnx.xcframework.
#   6. Zip it (SPM .binaryTarget requires .zip) and compute the
#      SHA-256 for Package.swift.
#
# Output: sherpa-onnx.xcframework.zip + the SHA-256 checksum line to
# paste into Package.swift.
#
set -euo pipefail

if [[ $# -lt 2 || $# -gt 3 ]]; then
    echo "Usage: $0 <sherpa-version> <ort-version> [<custom-macos-libsherpa-onnx-a>]" >&2
    echo "Example: $0 1.13.2 1.24.4" >&2
    echo "Example: $0 1.13.2 1.24.4 /tmp/sherpa-src/build-swift-macos/install/lib/libsherpa-onnx.a" >&2
    exit 2
fi

VERSION="$1"
ORT_VERSION="$2"
CUSTOM_MAC_LIB="${3:-}"
WORK="$(mktemp -d -t sherpa-build-XXXXXX)"
echo "→ Working directory: $WORK"
cd "$WORK"

# ----------------------------------------------------------------------
# 1. Download upstream sherpa-onnx tarballs.
# ----------------------------------------------------------------------

UPSTREAM="https://github.com/k2-fsa/sherpa-onnx/releases/download/v${VERSION}"
echo "→ Downloading sherpa-onnx v${VERSION} ..."
curl -fLO "${UPSTREAM}/sherpa-onnx-v${VERSION}-ios.tar.bz2"
curl -fLO "${UPSTREAM}/sherpa-onnx-v${VERSION}-macos-xcframework-static.tar.bz2"

echo "→ Extracting sherpa-onnx tarballs ..."
mkdir -p ios-extracted macos-extracted
tar -xjf "sherpa-onnx-v${VERSION}-ios.tar.bz2" -C ios-extracted
tar -xjf "sherpa-onnx-v${VERSION}-macos-xcframework-static.tar.bz2" -C macos-extracted

# ----------------------------------------------------------------------
# 2. Download matched-version ORT prebuilts.
# ----------------------------------------------------------------------

ORT_UPSTREAM="https://github.com/csukuangfj/onnxruntime-libs/releases/download/v${ORT_VERSION}"
echo "→ Downloading ORT v${ORT_VERSION} ..."
curl -fLO "${ORT_UPSTREAM}/onnxruntime-ios-static-xcframework-${ORT_VERSION}.zip"
curl -fLO "${ORT_UPSTREAM}/onnxruntime-osx-universal2-static_lib-${ORT_VERSION}.zip"

echo "→ Extracting ORT zips ..."
unzip -q "onnxruntime-ios-static-xcframework-${ORT_VERSION}.zip"
unzip -q "onnxruntime-osx-universal2-static_lib-${ORT_VERSION}.zip"

# Resolve all input paths.
SHERPA_IOS_DEV="ios-extracted/build-ios/sherpa-onnx.xcframework/ios-arm64/libsherpa-onnx.a"
SHERPA_IOS_SIM="ios-extracted/build-ios/sherpa-onnx.xcframework/ios-arm64_x86_64-simulator/libsherpa-onnx.a"
HDRS_SRC="ios-extracted/build-ios/sherpa-onnx.xcframework/ios-arm64/Headers"

# macOS slice: prefer a caller-supplied custom .a (CoreML-enabled
# build done out-of-band), fall back to upstream's prebuilt
# otherwise. Upstream's prebuilt has CoreML disabled — see header
# comment.
if [[ -n "$CUSTOM_MAC_LIB" ]]; then
    if [[ ! -e "$CUSTOM_MAC_LIB" ]]; then
        echo "Error: custom macOS lib not found at: $CUSTOM_MAC_LIB" >&2
        exit 1
    fi
    SHERPA_MAC="$CUSTOM_MAC_LIB"
    echo "→ Using CUSTOM macOS sherpa-onnx slice: $SHERPA_MAC"
else
    SHERPA_MAC="macos-extracted/sherpa-onnx-v${VERSION}-macos-xcframework-static/sherpa-onnx.xcframework/macos-arm64_x86_64/libsherpa-onnx.a"
    echo "→ Using UPSTREAM macOS sherpa-onnx slice (CoreML disabled): $SHERPA_MAC"
fi

# ORT iOS XCFramework: ships the static archive inside an
# onnxruntime.framework bundle. The binary file (named
# `onnxruntime`, with no .a extension) is still a Mach-O ar
# archive — usable as a static lib by libtool.
ORT_IOS_DEV="onnxruntime-ios-static-xcframework-${ORT_VERSION}/onnxruntime.xcframework/ios-arm64/onnxruntime.framework/onnxruntime"
ORT_IOS_SIM="onnxruntime-ios-static-xcframework-${ORT_VERSION}/onnxruntime.xcframework/ios-arm64_x86_64-simulator/onnxruntime.framework/onnxruntime"

# ORT macOS: ships as 3 split static libs.
#   - libonnxruntime.a              (universal arm64+x86_64; the bulk)
#   - libonnxruntime_mlas_arm64.a   (arm64-only matrix-multiply backend)
#   - libonnxruntime_mlas_x86_64.a  (x86_64-only matrix-multiply backend)
# All three are required for a complete link. We merge per-arch
# then lipo into a universal sherpa-onnx.a.
ORT_MAC_LIB_DIR="onnxruntime-osx-universal2-static_lib-${ORT_VERSION}/lib"
ORT_MAC_UNIVERSAL="${ORT_MAC_LIB_DIR}/libonnxruntime.a"
ORT_MAC_MLAS_ARM64="${ORT_MAC_LIB_DIR}/libonnxruntime_mlas_arm64.a"
ORT_MAC_MLAS_X86_64="${ORT_MAC_LIB_DIR}/libonnxruntime_mlas_x86_64.a"

# Sanity-check every input.
for f in "$SHERPA_IOS_DEV" "$SHERPA_IOS_SIM" "$SHERPA_MAC" \
         "$ORT_IOS_DEV" "$ORT_IOS_SIM" \
         "$ORT_MAC_UNIVERSAL" "$ORT_MAC_MLAS_ARM64" "$ORT_MAC_MLAS_X86_64" \
         "$HDRS_SRC"; do
    if [[ ! -e "$f" ]]; then
        echo "Error: expected input missing: $f" >&2
        exit 1
    fi
done

# ----------------------------------------------------------------------
# 3. Combine sherpa-onnx + ONNX Runtime per slice.
# ----------------------------------------------------------------------

mkdir -p combined/ios-arm64 combined/ios-sim combined/macos combined/headers

echo "→ Combining iOS device slice (sherpa-onnx + ORT ${ORT_VERSION}) ..."
libtool -static -o combined/ios-arm64/libsherpa-onnx.a \
    "$SHERPA_IOS_DEV" "$ORT_IOS_DEV" 2>&1 | grep -v "no symbols" | grep -v "same member name" || true

echo "→ Combining iOS simulator slice (sherpa-onnx + ORT ${ORT_VERSION}) ..."
libtool -static -o combined/ios-sim/libsherpa-onnx.a \
    "$SHERPA_IOS_SIM" "$ORT_IOS_SIM" 2>&1 | grep -v "no symbols" | grep -v "same member name" || true

# macOS: need to merge per-arch because the mlas backends ship as
# arch-specific archives. Slice each universal input by arch, then
# libtool-merge per-arch, then lipo-create the final universal.
echo "→ Slicing sherpa-onnx macOS (arm64 + x86_64) ..."
lipo -thin arm64  "$SHERPA_MAC"          -output mac-arm64-sherpa.a
lipo -thin x86_64 "$SHERPA_MAC"          -output mac-x86_64-sherpa.a

echo "→ Slicing ORT macOS libonnxruntime.a (arm64 + x86_64) ..."
lipo -thin arm64  "$ORT_MAC_UNIVERSAL"   -output mac-arm64-ort.a
lipo -thin x86_64 "$ORT_MAC_UNIVERSAL"   -output mac-x86_64-ort.a

echo "→ Merging macOS arm64 slice (sherpa + ort + mlas_arm64) ..."
libtool -static -o mac-arm64-merged.a \
    mac-arm64-sherpa.a mac-arm64-ort.a "$ORT_MAC_MLAS_ARM64" \
    2>&1 | grep -v "no symbols" | grep -v "same member name" || true

echo "→ Merging macOS x86_64 slice (sherpa + ort + mlas_x86_64) ..."
libtool -static -o mac-x86_64-merged.a \
    mac-x86_64-sherpa.a mac-x86_64-ort.a "$ORT_MAC_MLAS_X86_64" \
    2>&1 | grep -v "no symbols" | grep -v "same member name" || true

echo "→ Lipo-creating universal macOS libsherpa-onnx.a ..."
lipo -create mac-arm64-merged.a mac-x86_64-merged.a \
    -output combined/macos/libsherpa-onnx.a

# ----------------------------------------------------------------------
# 4. Stage headers + module.modulemap.
# ----------------------------------------------------------------------

cp -R "$HDRS_SRC"/. combined/headers/
cat > combined/headers/module.modulemap <<'MODMAP'
module CSherpaOnnx {
    header "sherpa-onnx/c-api/c-api.h"
    export *
}
MODMAP

# ----------------------------------------------------------------------
# 5. Build universal XCFramework.
# ----------------------------------------------------------------------

echo "→ Creating universal sherpa-onnx.xcframework ..."
xcodebuild -create-xcframework \
    -library combined/ios-arm64/libsherpa-onnx.a -headers combined/headers \
    -library combined/ios-sim/libsherpa-onnx.a -headers combined/headers \
    -library combined/macos/libsherpa-onnx.a -headers combined/headers \
    -output sherpa-onnx.xcframework

# ----------------------------------------------------------------------
# 6. Zip + checksum.
# ----------------------------------------------------------------------

echo "→ Zipping XCFramework ..."
zip -qr sherpa-onnx.xcframework.zip sherpa-onnx.xcframework

echo "→ Computing checksum ..."
if command -v swift >/dev/null 2>&1; then
    CHECKSUM=$(swift package compute-checksum sherpa-onnx.xcframework.zip 2>&1 | tail -1)
else
    CHECKSUM=$(shasum -a 256 sherpa-onnx.xcframework.zip | awk '{print $1}')
fi

ZIP_SIZE=$(stat -f%z sherpa-onnx.xcframework.zip 2>/dev/null || stat -c%s sherpa-onnx.xcframework.zip)
ZIP_MB=$(( ZIP_SIZE / 1048576 ))

OUTPUT_DIR="$(pwd)"

cat <<EOF

═══════════════════════════════════════════════════════════════════
✓ Built sherpa-onnx.xcframework.zip for sherpa v${VERSION} + ORT v${ORT_VERSION}

Output:
  ${OUTPUT_DIR}/sherpa-onnx.xcframework.zip   (${ZIP_MB} MB)

SPM Package.swift binaryTarget snippet:

  .binaryTarget(
      name: "CSherpaOnnx",
      url: "https://github.com/genericgroup/sherpa-onnx-spm/releases/download/<RELEASE>/sherpa-onnx.xcframework.zip",
      checksum: "${CHECKSUM}"
  )

═══════════════════════════════════════════════════════════════════
EOF
