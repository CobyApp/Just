import ProjectDescription

// MARK: - Shared configuration

private let bundlePrefix = "com.coby.ringring"
private let iOSTarget: DeploymentTargets = .iOS("26.0")
private let allDevices: Destinations = [.iPhone, .iPad]

/// Matches the sibling `mana` project's convention: automatic signing with the
/// team id in the manifest, so `tuist generate` produces a device-buildable
/// project with no extra environment set up.
private let developmentTeam = "3Y8YH8GWMM"

/// Reads a `TUIST_*` variable, treating an empty value like an unset one — a
/// CI secret that was never added arrives as an empty string, not as nothing.
private func environmentString(_ value: Environment.Value?, default fallback: String) -> String {
    let string = value.getString(default: fallback)
    return string.isEmpty ? fallback : string
}

/// The version shown on the App Store. Set TUIST_MARKETING_VERSION before
/// `tuist generate` (the deploy workflow takes it from the `v*` tag) to ship a new one;
/// the default is what a plain local checkout builds as.
private let marketingVersion = environmentString(Environment.marketingVersion, default: "1.0.0")

/// AdMob ids, injected at generation time so the account holder's real ids
/// never live in the repository. Unset, they fall back to Google's public test
/// ids, which always fill and earn nothing — right for local builds, and
/// fastlane refuses to upload a build that still carries them.
private let adMobTestAppID = "ca-app-pub-3940256099942544~1458002511"
private let adMobTestInterstitialID = "ca-app-pub-3940256099942544/4411468910"
private let adMobAppID = environmentString(Environment.admobAppID, default: adMobTestAppID)
private let adMobInterstitialID = environmentString(
    Environment.admobInterstitialID,
    default: adMobTestInterstitialID
)

private let baseSettings: SettingsDictionary = [
    "DEVELOPMENT_TEAM": .string(developmentTeam),
    "CODE_SIGN_STYLE": "Automatic",
    "MARKETING_VERSION": .string(marketingVersion),
    "CURRENT_PROJECT_VERSION": "1",
    "SWIFT_VERSION": "6.0",
    "SWIFT_STRICT_CONCURRENCY": "complete",
    "ENABLE_USER_SCRIPT_SANDBOXING": "YES",
    "DEAD_CODE_STRIPPING": "YES",
    "SWIFT_EMIT_LOC_STRINGS": "YES",
    "LOCALIZED_STRING_SWIFTUI_SUPPORT": "YES",
]

/// Every module in `Modules/` is an iOS framework with the same shape,
/// so the target definition is generated rather than repeated five times.
///
/// `hasResources` also carries a module's own `PrivacyInfo.xcprivacy`: these
/// are dynamic frameworks, and Apple requires each one that calls a
/// required-reason API (UserDefaults, here) to ship its own manifest — the
/// app's manifest does not cover code inside an embedded framework.
private func module(
    _ name: String,
    dependencies: [TargetDependency] = [],
    hasResources: Bool = false
) -> Target {
    .target(
        name: name,
        destinations: allDevices,
        product: .framework,
        bundleId: "\(bundlePrefix).\(name.lowercased())",
        deploymentTargets: iOSTarget,
        infoPlist: .default,
        sources: ["Modules/\(name)/Sources/**"],
        resources: hasResources ? ["Modules/\(name)/Resources/**"] : nil,
        dependencies: dependencies,
        settings: .settings(base: baseSettings)
    )
}

// MARK: - Project

let project = Project(
    name: "RingRing",
    organizationName: "Coby",
    options: .options(
        defaultKnownRegions: ["ko", "ja", "en"],
        developmentRegion: "ko"
    ),
    settings: .settings(base: baseSettings),
    targets: [
        // Domain models, SwiftData schema, spaced-repetition scheduler.
        module("RingRingCore"),

        // Design system: palette extraction, mesh background, furigana text.
        module("RingRingDesign", dependencies: [
            .target(name: "RingRingCore"),
            .target(name: "RingRingSensei"),
        ], hasResources: true),

        module("RingRingMusic", dependencies: [.target(name: "RingRingCore")]),

        // LRCLIB client and LRC parsing.
        module("RingRingLyrics", dependencies: [.target(name: "RingRingCore")]),

        // Tokenization, readings, and the on-device analysis engine.
        module(
            "RingRingSensei",
            dependencies: [.target(name: "RingRingCore")],
            hasResources: true
        ),

        .target(
            name: "RingRing",
            destinations: allDevices,
            product: .app,
            bundleId: bundlePrefix,
            deploymentTargets: iOSTarget,
            infoPlist: .extendingDefault(with: [
                "CFBundleDisplayName": "링링",
                // Driven by the build settings, not literals. Tuist's default
                // hardcodes these, which would silently discard the build
                // number fastlane passes as CURRENT_PROJECT_VERSION and make
                // every TestFlight upload collide with the last one.
                "CFBundleShortVersionString": "$(MARKETING_VERSION)",
                "CFBundleVersion": "$(CURRENT_PROJECT_VERSION)",
                // Keeps playback going while the screen locks during a song.
                "UIBackgroundModes": ["audio"],
                // 「이미지 저장」 in the share sheet for a lyric card. Without
                // this key the system kills the app the moment it is tapped.
                "NSPhotoLibraryAddUsageDescription": "가사 카드를 사진 앱에 저장합니다.",
                // The YouTube Data API key, for finding a song's video. Set
                // TUIST_YOUTUBE_API_KEY before `tuist generate`; without it the
                // app plays 30-second clips.
                "YouTubeAPIKey": .string(Environment.youtubeAPIKey.getString(default: "")),
                // The home's cream-pink with the icon in the middle, so the app does
                // not open on a black screen and then turn pink.
                "UILaunchScreen": ["UIColorName": "LaunchBackground", "UIImageName": "LaunchMark"],
                "ITSAppUsesNonExemptEncryption": false,
                "UISupportedInterfaceOrientations": [
                    "UIInterfaceOrientationPortrait",
                ],
                "UISupportedInterfaceOrientations~ipad": [
                    "UIInterfaceOrientationPortrait",
                    "UIInterfaceOrientationPortraitUpsideDown",
                    "UIInterfaceOrientationLandscapeLeft",
                    "UIInterfaceOrientationLandscapeRight",
                ],
                "NSAppTransportSecurity": ["NSAllowsArbitraryLoads": false],
                // AdMob refuses to start without this and takes the app down
                // with it. Google's public test application id: real earnings
                // need the account holder's own, and shipping someone else's
                // placeholder would serve no ads at all.
                // Set TUIST_ADMOB_APP_ID for a release; unset, this is
                // Google's public test application id (see `adMobAppID`).
                "GADApplicationIdentifier": .string(adMobAppID),
                // Read by `AnalysisInterstitial` in Release builds. Debug builds
                // always use the test unit, so development never touches real
                // inventory. Set TUIST_ADMOB_INTERSTITIAL_ID for a release.
                "AdMobInterstitialUnitID": .string(adMobInterstitialID),
                // One interstitial, on the analysis wait screen. Ads are
                // requested as non-personalised and only after Google's UMP
                // consent flow allows it. Personalised advertising would need
                // an App Tracking Transparency prompt and a tracking
                // declaration; this app asks for neither.
                "GADIsAdManagerApp": false,
                // Lets ad networks attribute installs through Apple's
                // SKAdNetwork, which needs no tracking permission. Google's
                // own id is the minimum; the full list of third-party buyers
                // Google publishes can be appended here.
                "SKAdNetworkItems": [
                    ["SKAdNetworkIdentifier": "cstr6suwn9.skadnetwork"],
                ],
                "UIUserInterfaceStyle": "Dark",
                // Lets notifications and the widget deep-link into a screen.
                "CFBundleURLTypes": [
                    [
                        "CFBundleURLName": "\(bundlePrefix)",
                        "CFBundleURLSchemes": ["ringring"],
                    ],
                ],
            ]),
            sources: ["App/Sources/**"],
            resources: ["App/Resources/**"],
            entitlements: "App/RingRing.entitlements",
            dependencies: [
                .target(name: "RingRingWidget"),
                .target(name: "RingRingCore"),
                .target(name: "RingRingDesign"),
                .target(name: "RingRingMusic"),
                .target(name: "RingRingLyrics"),
                .target(name: "RingRingSensei"),
                .external(name: "GoogleMobileAds"),
                // Google's consent SDK. Already resolved as a dependency of
                // GoogleMobileAds; named here because the app imports it.
                .external(name: "GoogleUserMessagingPlatform"),
            ],
            settings: .settings(base: baseSettings.merging([
                "TARGETED_DEVICE_FAMILY": "1,2",
            ]) { _, new in new })
        ),

        // Reads a snapshot the app publishes into the shared container, so it
        // never opens the app's database.
        .target(
            name: "RingRingWidget",
            destinations: allDevices,
            product: .appExtension,
            bundleId: "\(bundlePrefix).widget",
            deploymentTargets: iOSTarget,
            infoPlist: .extendingDefault(with: [
                "CFBundleDisplayName": "링링",
                // Same reason as the app target, and additionally: an extension
                // whose version differs from its container is rejected at
                // upload. Tuist's default hardcodes 1.0/1, so without these the
                // widget stays behind while fastlane bumps the app.
                "CFBundleShortVersionString": "$(MARKETING_VERSION)",
                "CFBundleVersion": "$(CURRENT_PROJECT_VERSION)",
                "NSExtension": [
                    "NSExtensionPointIdentifier": "com.apple.widgetkit-extension",
                ],
            ]),
            sources: ["Widget/Sources/**"],
            resources: ["Widget/Resources/**"],
            entitlements: "Widget/RingRingWidget.entitlements",
            dependencies: [.target(name: "RingRingCore")],
            settings: .settings(base: baseSettings)
        ),

        // Covers the pure logic only — parsing, scheduling, string handling.
        // That is where every bug so far has actually lived, and it is the part
        // that can be checked without a device, an account or a model.
        .target(
            name: "RingRingTests",
            destinations: allDevices,
            product: .unitTests,
            bundleId: "\(bundlePrefix).tests",
            deploymentTargets: iOSTarget,
            infoPlist: .default,
            sources: ["Tests/**"],
            dependencies: [
                .target(name: "RingRingCore"),
                .target(name: "RingRingLyrics"),
                .target(name: "RingRingSensei"),
                            .target(name: "RingRingMusic"),
                            .target(name: "RingRingDesign"),
            ],
            settings: .settings(base: baseSettings)
        ),

        // The measurement harness, which is a different kind of thing from the
        // tests above: it asserts almost nothing and instead runs the real
        // analyser over fixed lines and prints what came out, so two runs can
        // be compared.
        //
        // Its own target for one reason — it is hosted by the app, and a hosted
        // target can run on a device. The simulator's on-device model has gone
        // missing three times in a day, and the phone in the room has a real
        // one. Being unable to measure has blocked more work than any bug.
        //
        // Hosting the existing RingRingTests instead would have put an app launch
        // in front of a suite that finishes in under a second and runs on every
        // change. Two targets keeps both properties.
        .target(
            name: "RingRingReport",
            destinations: allDevices,
            product: .unitTests,
            bundleId: "\(bundlePrefix).report",
            deploymentTargets: iOSTarget,
            infoPlist: .default,
            sources: ["Report/**"],
            dependencies: [
                .target(name: "RingRing"),
                .target(name: "RingRingCore"),
                .target(name: "RingRingLyrics"),
                .target(name: "RingRingSensei"),
            ],
            settings: .settings(base: baseSettings)
        ),
    ],
    schemes: [
        // The default scheme tests the fast suite only, so `xcodebuild test`
        // and CI stay as they were. The report is asked for by name.
        .scheme(
            name: "RingRing",
            shared: true,
            buildAction: .buildAction(targets: ["RingRing"]),
            testAction: .targets(["RingRingTests"]),
            runAction: .runAction(executable: "RingRing")
        ),
        .scheme(
            name: "RingRingReport",
            shared: true,
            buildAction: .buildAction(targets: ["RingRing", "RingRingReport"]),
            testAction: .targets(["RingRingReport"]),
            runAction: .runAction(executable: "RingRing")
        ),
    ]
)
