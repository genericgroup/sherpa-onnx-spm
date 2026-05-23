# sherpa-onnx-spm

Swift Package Manager wrapper for [k2-fsa/sherpa-onnx](https://github.com/k2-fsa/sherpa-onnx).

The upstream project doesn't ship a `Package.swift` — it publishes
platform-specific XCFramework tarballs as Release assets and expects
consumers to drop the Swift wrapper sources into their project
manually. This repo wraps both into a single SPM-installable package
so iOS / macOS apps can add sherpa-onnx via
`File → Add Package Dependencies` in Xcode.

## What's bundled

| Component | Source | License |
|---|---|---|
| `sherpa-onnx.xcframework` — universal static lib | Merged from upstream's `sherpa-onnx-v1.13.2-ios.tar.bz2` + `sherpa-onnx-v1.13.2-macos-xcframework-static.tar.bz2` Release assets | Apache 2.0 |
| ONNX Runtime 1.17.1 — statically merged into the XCFramework slices | Upstream sherpa-onnx Release bundle | MIT |
| `Sources/SherpaOnnx/SherpaOnnx.swift` — Swift API wrapper | Verbatim copy of upstream's `swift-api-examples/SherpaOnnx.swift` with one added `import CSherpaOnnx` line (upstream relies on an Xcode bridging header that SPM packages can't use) | Apache 2.0 |

See [`NOTICE`](NOTICE) for full upstream attribution.

## Installation

In Xcode: **File → Add Package Dependencies** → paste this URL:

```
https://github.com/genericgroup/sherpa-onnx-spm.git
```

Pin to **Exact Version** `1.13.2` (matching the upstream sherpa-onnx
tag this release wraps).

In `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/genericgroup/sherpa-onnx-spm.git",
             exact: "1.13.2"),
],
targets: [
    .target(
        name: "YourTarget",
        dependencies: [
            .product(name: "SherpaOnnx", package: "sherpa-onnx-spm"),
        ]
    ),
]
```

## Platform support

- **iOS:** arm64 device, arm64 / x86_64 Simulator
- **macOS:** arm64 / x86_64
- **Minimum versions:** iOS 16, macOS 13 (per `Package.swift`)
- **Universal XCFramework:** one binary covers all three slices, no
  conditional linking needed in consumer projects

## Usage

```swift
import SherpaOnnx

// Configure a Kokoro TTS model.
var ttsConfig = sherpaOnnxOfflineTtsConfig(
    model: sherpaOnnxOfflineTtsModelConfig(
        kokoro: sherpaOnnxOfflineTtsKokoroModelConfig(
            model: "/path/to/kokoro-model.onnx",
            voices: "/path/to/voices.bin",
            tokens: "/path/to/tokens.txt",
            dataDir: "/path/to/espeak-ng-data"
        )
    )
)
let tts = SherpaOnnxOfflineTtsWrapper(config: &ttsConfig)

// Generate audio.
let audio = tts.generate(text: "Hello, world.", sid: 0, speed: 1.0)
// audio.samples is [Float], audio.sampleRate is Int.
```

For other model families (Piper VITS, Matcha, etc.) see
[upstream Swift examples](https://github.com/k2-fsa/sherpa-onnx/tree/master/swift-api-examples).

## Version pinning + upgrades

Releases of this repo are tagged to exactly match the upstream
sherpa-onnx version they wrap. To upgrade:

1. Read upstream changelog
2. Update the wrapper via the build script:
   ```sh
   scripts/build-xcframework.sh <new-version>
   ```
   (See [`scripts/build-xcframework.sh`](scripts/build-xcframework.sh) — runs the same download + libtool-combine + xcodebuild -create-xcframework + zip + checksum pipeline used for v1.13.2.)
3. Tag a new release with the matching version
4. Bump SPM dependency in consumer projects

## Why a wrapper repo at all?

Upstream sherpa-onnx ships:

1. `sherpa-onnx-vN-ios.tar.bz2` — iOS slices, dynamic-linked to a
   separate `onnxruntime.xcframework`
2. `sherpa-onnx-vN-macos-xcframework-static.tar.bz2` — macOS slice
   with ONNX Runtime statically merged
3. `swift-api-examples/SherpaOnnx.swift` + a bridging header — not
   packaged

That's three artifacts in two different linkage configurations, none
of which are SPM-consumable directly. This wrapper does the
otherwise-manual work once: combines the iOS sherpa-onnx static lib
with its matching ONNX Runtime static lib (so all iOS slices have
ONNX Runtime merged in, matching the macOS slice's existing
configuration), runs `xcodebuild -create-xcframework` to produce one
universal XCFramework, adds a Clang module map so Swift can `import`
the C API directly, and ships a `Package.swift`.

## License

The wrapper code (this repo's `Package.swift`, scripts, and docs) is
Apache 2.0 — see [`LICENSE`](LICENSE).

The bundled XCFramework and Swift wrapper source are derived from
upstream sherpa-onnx (Apache 2.0) and ONNX Runtime (MIT). See
[`NOTICE`](NOTICE) for full attribution.

## Not affiliated with k2-fsa

This is a third-party wrapper maintained for the
[ArticleQ](https://github.com/genericgroup/Reader) iOS / macOS app.
It is not endorsed by or affiliated with the k2-fsa team. For
questions about the underlying sherpa-onnx project, file issues
[upstream](https://github.com/k2-fsa/sherpa-onnx/issues).
