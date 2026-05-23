// swift-tools-version: 6.0
//
// Swift Package wrapper for sherpa-onnx — exposes the upstream
// k2-fsa/sherpa-onnx XCFramework + Swift API wrapper as a single
// SPM-installable product for iOS and macOS consumers.
//
// Architecture:
//
//   ┌──────────────────────────────────────────────────────┐
//   │ Consumer app (e.g. ArticleQ)                         │
//   │   import SherpaOnnx                                  │
//   └──────────────────────────────────────────────────────┘
//                          ↓ depends on
//   ┌──────────────────────────────────────────────────────┐
//   │ Product: SherpaOnnx                                  │
//   │   .target SherpaOnnx                                 │
//   │     Sources/SherpaOnnx/SherpaOnnx.swift              │
//   │       — Swift wrapper from upstream                  │
//   │       swift-api-examples/SherpaOnnx.swift            │
//   │     depends on → CSherpaOnnx (Clang module)          │
//   └──────────────────────────────────────────────────────┘
//                          ↓ depends on
//   ┌──────────────────────────────────────────────────────┐
//   │ .binaryTarget CSherpaOnnx                            │
//   │   sherpa-onnx.xcframework — universal static lib     │
//   │     ios-arm64 (device)                               │
//   │     ios-arm64_x86_64-simulator                       │
//   │     macos-arm64_x86_64                               │
//   │   ONNX Runtime is statically merged into all slices, │
//   │   so consumers only need to link THIS XCFramework.   │
//   └──────────────────────────────────────────────────────┘
//
// Upstream version: sherpa-onnx v1.13.2
// Upstream ONNX Runtime: 1.17.1 (statically merged)
// Build script: see scripts/build-xcframework.sh
//

import PackageDescription

let package = Package(
    name: "sherpa-onnx-spm",
    platforms: [
        // iOS 14 / macOS 11 are sherpa-onnx's documented minimums.
        // Bumped to iOS 16 / macOS 13 here to match the typical
        // floor of apps consuming this in 2026 — older floors are
        // available by forking and pinning the platform requirement.
        .iOS(.v16),
        .macOS(.v13),
    ],
    products: [
        .library(
            name: "SherpaOnnx",
            targets: ["SherpaOnnx"]
        ),
    ],
    targets: [
        // Swift wrapper. The source file is a minimally-modified
        // copy of upstream's `swift-api-examples/SherpaOnnx.swift`
        // — only an `import CSherpaOnnx` was added at the top
        // (upstream relies on an Xcode bridging header which
        // doesn't work in SPM packages; the import achieves the
        // same effect via the Clang module exposed by
        // `CSherpaOnnx`'s module.modulemap). See NOTICE for
        // attribution.
        .target(
            name: "SherpaOnnx",
            dependencies: ["CSherpaOnnx"],
            path: "Sources/SherpaOnnx"
        ),

        // Binary XCFramework — sherpa-onnx static library with
        // ONNX Runtime merged in, exposing the C API via a
        // module.modulemap-defined Clang module called CSherpaOnnx.
        //
        // The url + checksum point at the matching GitHub Release
        // of THIS repo (not the upstream sherpa-onnx repo, since
        // upstream ships TWO platform-specific tarballs that aren't
        // SPM-consumable directly — see scripts/build-xcframework.sh
        // for the merge process).
        .binaryTarget(
            name: "CSherpaOnnx",
            url: "https://github.com/genericgroup/sherpa-onnx-spm/releases/download/v1.13.2/sherpa-onnx.xcframework.zip",
            checksum: "f537df7329312dabdcb69f5c49a7b1cc73199763b13b6e41ef676ea5a1d930ac"
        ),
    ]
)
