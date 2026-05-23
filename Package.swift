// swift-tools-version: 6.0
//
// Swift Package wrapper for sherpa-onnx — exposes the upstream
// k2-fsa/sherpa-onnx XCFramework as a single SPM-installable
// product for iOS and macOS consumers.
//
// Architecture:
//
//   ┌──────────────────────────────────────────────────────┐
//   │ Consumer app (e.g. ArticleQ)                         │
//   │   import CSherpaOnnx                                  │
//   │   (uses the upstream Swift wrapper                    │
//   │    SherpaOnnx.swift dropped into its OWN source tree) │
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
//   │   Headers expose the C API as the CSherpaOnnx Clang  │
//   │   module via Headers/module.modulemap.               │
//   └──────────────────────────────────────────────────────┘
//
// Why no Swift wrapper in the Sources/ tree:
//
// The upstream `swift-api-examples/SherpaOnnx.swift` declares its
// classes / structs / functions WITHOUT a `public` modifier — by
// design, since upstream expects you to drop the file directly into
// your app's source tree where module-internal visibility is fine.
//
// If we exposed it from THIS package as a separate Swift module,
// every consumer use would fail with "cannot find <type> in scope"
// because the internal symbols don't cross the SPM module boundary.
//
// Rewriting the upstream file to mark everything `public` would
// work, but creates ongoing maintenance friction for every upstream
// version bump (~2249 lines, ~150 declarations need touching). So:
// we ship the BINARY ONLY, and consumers copy SherpaOnnx.swift
// verbatim into their own source tree — matching exactly what
// upstream's README tells you to do.
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
            name: "CSherpaOnnx",
            targets: ["CSherpaOnnx"]
        ),
    ],
    targets: [
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
