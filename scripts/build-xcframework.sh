#!/usr/bin/env bash
#
# build-xcframework.sh — build a universal sherpa-onnx XCFramework
# from upstream v<VERSION> release tarballs.
#
# Usage:
#   ./scripts/build-xcframework.sh <upstream-version>
#
# Example:
#   ./scripts/build-xcframework.sh 1.13.2
#
# Pipeline:
#   1. Download upstream iOS + macOS XCFramework tarballs
#   2. Combine each iOS sherpa-onnx static lib with its matching ONNX
#      Runtime static lib (libtool) so all iOS slices have ONNX
#      Runtime statically merged in — matches the macOS slice's
#      existing configuration. After this, consumers link only
#      sherpa-onnx.xcframework, never a separate ONNX Runtime.
#   3. Write Headers/module.modulemap exposing the C API as a Clang
#      module called CSherpaOnnx (so Swift can `import CSherpaOnnx`
#      directly — upstream relies on an Xcode bridging header that
#      SPM packages can't use).
#   4. Run `xcodebuild -create-xcframework` to produce the universal
#      sherpa-onnx.xcframework.
#   5. Zip it (SPM .binaryTarget requires .zip, not .tar.bz2) and
#      compute the SHA-256 for Package.swift.
#
# Output: sherpa-onnx.xcframework.zip + the SHA-256 checksum line to
# paste into Package.swift.
#
set -euo pipefail

if [[ $# -ne 1 ]]; then
    echo "Usage: $0 <upstream-version>" >&2
    echo "Example: $0 1.13.2" >&2
    exit 2
fi

VERSION="$1"
WORK="$(mktemp -d -t sherpa-build-XXXXXX)"
echo "→ Working directory: $WORK"
cd "$WORK"

# ----------------------------------------------------------------------
# 1. Download upstream tarballs.
# ----------------------------------------------------------------------

UPSTREAM="https://github.com/k2-fsa/sherpa-onnx/releases/download/v${VERSION}"
echo "→ Downloading from $UPSTREAM ..."
curl -fLO "${UPSTREAM}/sherpa-onnx-v${VERSION}-ios.tar.bz2"
curl -fLO "${UPSTREAM}/sherpa-onnx-v${VERSION}-macos-xcframework-static.tar.bz2"

echo "→ Extracting tarballs ..."
mkdir -p ios-extracted macos-extracted
tar -xjf "sherpa-onnx-v${VERSION}-ios.tar.bz2" -C ios-extracted
tar -xjf "sherpa-onnx-v${VERSION}-macos-xcframework-static.tar.bz2" -C macos-extracted

# Pin to expected paths inside each tarball (may need adjustment if
# upstream changes layout — verify with `find ios-extracted -name '*.a'`).
SHERPA_IOS_DEV="ios-extracted/build-ios/sherpa-onnx.xcframework/ios-arm64/libsherpa-onnx.a"
SHERPA_IOS_SIM="ios-extracted/build-ios/sherpa-onnx.xcframework/ios-arm64_x86_64-simulator/libsherpa-onnx.a"
SHERPA_MAC="macos-extracted/sherpa-onnx-v${VERSION}-macos-xcframework-static/sherpa-onnx.xcframework/macos-arm64_x86_64/libsherpa-onnx.a"
HDRS_SRC="ios-extracted/build-ios/sherpa-onnx.xcframework/ios-arm64/Headers"

# Locate the ONNX Runtime version directory dynamically (upstream
# bumps it across releases — e.g. 1.17.1 in v1.13.2 but may change).
ONNX_DIR_ROOT="ios-extracted/build-ios/ios-onnxruntime"
ONNX_VER_DIR="$(ls "$ONNX_DIR_ROOT" | head -1)"
ONNX_IOS_DEV="${ONNX_DIR_ROOT}/${ONNX_VER_DIR}/onnxruntime.xcframework/ios-arm64/onnxruntime.a"
ONNX_IOS_SIM="${ONNX_DIR_ROOT}/${ONNX_VER_DIR}/onnxruntime.xcframework/ios-arm64_x86_64-simulator/onnxruntime.a"

# Sanity-check that all six input files exist.
for f in "$SHERPA_IOS_DEV" "$SHERPA_IOS_SIM" "$SHERPA_MAC" \
         "$ONNX_IOS_DEV" "$ONNX_IOS_SIM" "$HDRS_SRC"; do
    if [[ ! -e "$f" ]]; then
        echo "Error: expected input missing: $f" >&2
        exit 1
    fi
done

# ----------------------------------------------------------------------
# 2. Combine iOS sherpa-onnx + ONNX Runtime into single static libs per slice.
# ----------------------------------------------------------------------

mkdir -p combined/ios-arm64 combined/ios-sim combined/macos combined/headers

echo "→ Combining iOS device slice (sherpa-onnx + ONNX Runtime) ..."
libtool -static -o combined/ios-arm64/libsherpa-onnx.a \
    "$SHERPA_IOS_DEV" "$ONNX_IOS_DEV" 2>&1 | grep -v "no symbols" | grep -v "same member name" || true

echo "→ Combining iOS simulator slice (sherpa-onnx + ONNX Runtime) ..."
libtool -static -o combined/ios-sim/libsherpa-onnx.a \
    "$SHERPA_IOS_SIM" "$ONNX_IOS_SIM" 2>&1 | grep -v "no symbols" | grep -v "same member name" || true

echo "→ Using macOS slice as-is (ONNX Runtime already statically merged) ..."
cp "$SHERPA_MAC" combined/macos/libsherpa-onnx.a

# ----------------------------------------------------------------------
# 3. Stage headers + module.modulemap.
# ----------------------------------------------------------------------

cp -R "$HDRS_SRC"/. combined/headers/
cat > combined/headers/module.modulemap <<'MODMAP'
module CSherpaOnnx {
    header "sherpa-onnx/c-api/c-api.h"
    export *
}
MODMAP

# ----------------------------------------------------------------------
# 4. Build universal XCFramework.
# ----------------------------------------------------------------------

echo "→ Creating universal sherpa-onnx.xcframework ..."
xcodebuild -create-xcframework \
    -library combined/ios-arm64/libsherpa-onnx.a -headers combined/headers \
    -library combined/ios-sim/libsherpa-onnx.a -headers combined/headers \
    -library combined/macos/libsherpa-onnx.a -headers combined/headers \
    -output sherpa-onnx.xcframework

# ----------------------------------------------------------------------
# 5. Zip + checksum.
# ----------------------------------------------------------------------

echo "→ Zipping XCFramework ..."
# SPM `.binaryTarget(url:checksum:)` expects a ZIP archive that
# contains the .xcframework at its root.
zip -qr sherpa-onnx.xcframework.zip sherpa-onnx.xcframework

# Apple expects the checksum to be computed by `swift package
# compute-checksum`. shasum produces a different format; SPM uses
# its own. We invoke `swift package compute-checksum` if available.
echo "→ Computing checksum ..."
if command -v swift >/dev/null 2>&1; then
    CHECKSUM=$(swift package compute-checksum sherpa-onnx.xcframework.zip 2>&1 | tail -1)
else
    # Fallback: SPM accepts the hex digest of SHA-256.
    CHECKSUM=$(shasum -a 256 sherpa-onnx.xcframework.zip | awk '{print $1}')
fi

ZIP_SIZE=$(stat -f%z sherpa-onnx.xcframework.zip 2>/dev/null || stat -c%s sherpa-onnx.xcframework.zip)
ZIP_MB=$(( ZIP_SIZE / 1048576 ))

# ----------------------------------------------------------------------
# Output.
# ----------------------------------------------------------------------

OUTPUT_DIR="$(pwd)"

cat <<EOF

═══════════════════════════════════════════════════════════════════
✓ Built sherpa-onnx.xcframework.zip for upstream v${VERSION}

Output:
  $OUTPUT_DIR/sherpa-onnx.xcframework.zip  (${ZIP_MB} MB)

Update Package.swift with:

  .binaryTarget(
      name: "CSherpaOnnx",
      url: "https://github.com/genericgroup/sherpa-onnx-spm/releases/download/v${VERSION}/sherpa-onnx.xcframework.zip",
      checksum: "${CHECKSUM}"
  )

Then publish the release:

  gh release create v${VERSION} \\
      "$OUTPUT_DIR/sherpa-onnx.xcframework.zip" \\
      --title "v${VERSION}" \\
      --notes "Wraps upstream sherpa-onnx v${VERSION}. See NOTICE for attribution."

═══════════════════════════════════════════════════════════════════
EOF
