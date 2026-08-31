// swift-tools-version: 6.0
import PackageDescription

// No `PackageSettings` product-type override: this SDK ships as a prebuilt
// binary XCFramework, and asking Tuist to rebuild it as a framework leaves the
// Swift module visible while the binary goes unlinked.

let package = Package(
    name: "JustDependencies",
    dependencies: [
        // Banner ads on the analysis wait screen. Pinned to a minor version:
        // this SDK ships as a binary and its releases change API often enough
        // that a floating major would break the build without a code change.
        .package(
            url: "https://github.com/googleads/swift-package-manager-google-mobile-ads.git",
            from: "13.9.0"
        ),
    ]
)
