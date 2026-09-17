// swift-tools-version: 6.0
import PackageDescription

#if TUIST
import ProjectDescription

// No product-type override: this SDK ships as a prebuilt binary XCFramework,
// and asking Tuist to rebuild it as a framework leaves the Swift module visible
// while the binary goes unlinked. Only the deployment target is set — Xcode 27
// refuses anything below 15.0, and the SDK's generated projects declare 12.0
// and 13.0.
let packageSettings = PackageSettings(
    baseSettings: .settings(base: ["IPHONEOS_DEPLOYMENT_TARGET": "15.0"]),
    targetSettings: [
        "GoogleMobileAds": ["IPHONEOS_DEPLOYMENT_TARGET": "15.0"],
        "GoogleMobileAdsTarget": ["IPHONEOS_DEPLOYMENT_TARGET": "15.0"],
        "GoogleUserMessagingPlatform": ["IPHONEOS_DEPLOYMENT_TARGET": "15.0"],
        "UserMessagingPlatformTarget": ["IPHONEOS_DEPLOYMENT_TARGET": "15.0"],
    ]
)
#endif

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
