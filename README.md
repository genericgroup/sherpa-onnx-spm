# sherpa-onnx-spm

Swift Package Manager wrapper that exposes the
[k2-fsa/sherpa-onnx](https://github.com/k2-fsa/sherpa-onnx)
XCFramework as a single SPM-installable binary target for iOS and
macOS consumers.

The upstream project doesn't ship a `Package.swift` — it publishes
platform-specific XCFramework tarballs and expects consumers to wire
them into their projects manually. This repo does that wiring once:
combines the iOS + macOS tarballs into one universal XCFramework
(with ONNX Runtime statically merged into all slices), adds a Clang
module map so Swift can `import` the C API directly, and publishes
the result as a GitHub Release that SPM consumes via
`.binaryTarget(url:checksum:)`.

## What this package gives you

- **`CSherpaOnnx`** — a Swift Package product exposing the
  `CSherpaOnnx` Clang module. Importing it makes the entire
  sherpa-onnx C API available to Swift code:

  ```swift
  import CSherpaOnnx
  // SherpaOnnxOfflineTtsConfig, SherpaOnnxCreateOfflineTts(...), etc.
  // are now visible.
  ```

The package does NOT ship the Swift API wrapper. See below.

## How to consume

### 1. Add the SPM dependency in Xcode

**File → Add Package Dependencies** → paste:

```
https://github.com/genericgroup/sherpa-onnx-spm.git
```

Pin to **Exact Version `1.13.2`** (matching the upstream sherpa-onnx
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
            .product(name: "CSherpaOnnx", package: "sherpa-onnx-spm"),
        ]
    ),
]
```

### 2. Copy the upstream Swift API wrapper into your source tree

Download
[`swift-api-examples/SherpaOnnx.swift`](https://github.com/k2-fsa/sherpa-onnx/blob/v1.13.2/swift-api-examples/SherpaOnnx.swift)
from the upstream sherpa-onnx repo at the matching version tag
(v1.13.2) and drop it into your project's source tree (e.g.
`MyApp/Vendor/sherpa-onnx/SherpaOnnx.swift`).

Then prepend `import CSherpaOnnx` to the top of the file (the
upstream wrapper relies on an Xcode bridging header that doesn't
work in SPM; the import achieves the same effect):

```swift
import CSherpaOnnx     // ← add this line
import Foundation
// ... rest of the file unchanged
```

That's it. Your app code can now use the Swift API:

```swift
var ttsConfig = sherpaOnnxOfflineTtsConfig(...)
let tts = SherpaOnnxOfflineTtsWrapper(config: &ttsConfig)
let audio = tts.generate(text: "Hello.", sid: 0, speed: 1.0)
```

### Why "copy into your source tree" rather than expose from this package?

The upstream Swift wrapper declares its classes / structs / functions
without `public` modifiers — fine for its intended use (drop directly
into your app's module where everything is implicitly visible), but
fatal across an SPM module boundary, where consumers can't see
internal symbols. Rewriting the upstream file to add `public`
everywhere would work but creates ongoing maintenance friction for
version bumps. Easier path: ship the BINARY only, let consumers
drop the Swift wrapper into their own module.

## Platform support

- **iOS:** arm64 device, arm64 / x86_64 Simulator
- **macOS:** arm64 / x86_64
- **Minimum versions:** iOS 16, macOS 13 (per `Package.swift`)
- **Universal XCFramework:** one binary covers all three slices, no
  conditional linking needed in consumer projects

## What's bundled in the XCFramework

| Component | Source | License |
|---|---|---|
| `libsherpa-onnx.a` (per slice) | Merged from upstream's `sherpa-onnx-v1.13.2-ios.tar.bz2` + `sherpa-onnx-v1.13.2-macos-xcframework-static.tar.bz2` Release assets | Apache 2.0 |
| ONNX Runtime 1.17.1 — statically merged into the iOS slices via `libtool -static`; already merged into the macOS slice upstream | Upstream sherpa-onnx Release bundle | MIT |
| `sherpa-onnx/c-api/c-api.h` headers + `module.modulemap` | Verbatim from upstream | Apache 2.0 |

See [`NOTICE`](NOTICE) for full upstream attribution.

## Version pinning + upgrades

Releases of this repo are tagged to exactly match the upstream
sherpa-onnx version they wrap. To upgrade:

1. Read upstream changelog
2. Run the build script for the new version:
   ```sh
   scripts/build-xcframework.sh <new-version>
   ```
   It prints the new SHA-256 checksum to paste into `Package.swift`
3. Commit the `Package.swift` update, tag a new release, attach the
   new XCFramework zip
4. Bump SPM dependency in consumer projects + copy the matching
   `SherpaOnnx.swift` from upstream's matching tag

## License

The wrapper code (this repo's `Package.swift`, scripts, and docs) is
Apache 2.0 — see [`LICENSE`](LICENSE).

The bundled XCFramework is derived from upstream sherpa-onnx
(Apache 2.0) and ONNX Runtime (MIT). See [`NOTICE`](NOTICE) for full
attribution.

## Not affiliated with k2-fsa

This is a third-party wrapper maintained for the
[ArticleQ](https://github.com/genericgroup/Reader) iOS / macOS app.
It is not endorsed by or affiliated with the k2-fsa team. For
questions about the underlying sherpa-onnx project, file issues
[upstream](https://github.com/k2-fsa/sherpa-onnx/issues).
