import ProjectDescription

// MARK: - Shared configuration

private let bundlePrefix = "com.coby.just"
private let iOSTarget: DeploymentTargets = .iOS("26.0")
private let allDevices: Destinations = [.iPhone, .iPad]

/// Matches the sibling `mana` project's convention: automatic signing with the
/// team id in the manifest, so `tuist generate` produces a device-buildable
/// project with no extra environment set up.
private let developmentTeam = "3Y8YH8GWMM"

private let baseSettings: SettingsDictionary = [
    "DEVELOPMENT_TEAM": .string(developmentTeam),
    "CODE_SIGN_STYLE": "Automatic",
    "MARKETING_VERSION": "1.0.0",
    "CURRENT_PROJECT_VERSION": "1",
    "SWIFT_VERSION": "6.0",
    "SWIFT_STRICT_CONCURRENCY": "complete",
    "ENABLE_USER_SCRIPT_SANDBOXING": "YES",
    "DEAD_CODE_STRIPPING": "YES",
]

/// Every module in `Modules/` is an iOS framework with the same shape,
/// so the target definition is generated rather than repeated five times.
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
    name: "Just",
    organizationName: "Coby",
    options: .options(
        defaultKnownRegions: ["ko", "ja", "en"],
        developmentRegion: "ko"
    ),
    settings: .settings(base: baseSettings),
    targets: [
        // Domain models, SwiftData schema, spaced-repetition scheduler.
        module("JustCore"),

        // Design system: palette extraction, mesh background, furigana text.
        module("JustDesign", dependencies: [
            .target(name: "JustCore"),
            .target(name: "JustSensei"),
        ]),

        // MusicKit catalog search + ApplicationMusicPlayer.
        module("JustMusic", dependencies: [.target(name: "JustCore")]),

        // LRCLIB client and LRC parsing.
        module("JustLyrics", dependencies: [.target(name: "JustCore")]),

        // Tokenization, readings, and the on-device analysis engine.
        module(
            "JustSensei",
            dependencies: [.target(name: "JustCore")],
            hasResources: true
        ),

        .target(
            name: "Just",
            destinations: allDevices,
            product: .app,
            bundleId: bundlePrefix,
            deploymentTargets: iOSTarget,
            infoPlist: .extendingDefault(with: [
                "CFBundleDisplayName": "우타링",
                // Driven by the build settings, not literals. Tuist's default
                // hardcodes these, which would silently discard the build
                // number fastlane passes as CURRENT_PROJECT_VERSION and make
                // every TestFlight upload collide with the last one.
                "CFBundleShortVersionString": "$(MARKETING_VERSION)",
                "CFBundleVersion": "$(CURRENT_PROJECT_VERSION)",
                "NSAppleMusicUsageDescription":
                    "좋아하는 아이돌 그룹의 곡을 불러오고 재생해 가사로 일본어를 공부하기 위해 Apple Music을 씁니다.",
                // Keeps playback going while the screen locks during a song.
                "UIBackgroundModes": ["audio"],
                "UILaunchScreen": ["UIColorName": ""],
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
                "GADApplicationIdentifier": "ca-app-pub-3940256099942544~1458002511",
                // Banner ads only, on the analysis wait screen. Personalised
                // advertising would need an App Tracking Transparency prompt
                // and a tracking declaration; this app asks for neither.
                "GADIsAdManagerApp": false,
                "UIUserInterfaceStyle": "Dark",
                // Lets notifications and the widget deep-link into a screen.
                "CFBundleURLTypes": [
                    [
                        "CFBundleURLName": "\(bundlePrefix)",
                        "CFBundleURLSchemes": ["just"],
                    ],
                ],
            ]),
            sources: ["App/Sources/**"],
            resources: ["App/Resources/**"],
            entitlements: "App/Just.entitlements",
            dependencies: [
                .target(name: "JustWidget"),
                .target(name: "JustCore"),
                .target(name: "JustDesign"),
                .target(name: "JustMusic"),
                .target(name: "JustLyrics"),
                .target(name: "JustSensei"),
                .external(name: "GoogleMobileAds"),
            ],
            settings: .settings(base: baseSettings.merging([
                "TARGETED_DEVICE_FAMILY": "1,2",
            ]) { _, new in new })
        ),

        // Reads a snapshot the app publishes into the shared container, so it
        // never opens the app's database.
        .target(
            name: "JustWidget",
            destinations: allDevices,
            product: .appExtension,
            bundleId: "\(bundlePrefix).widget",
            deploymentTargets: iOSTarget,
            infoPlist: .extendingDefault(with: [
                "CFBundleDisplayName": "우타링",
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
            entitlements: "Widget/JustWidget.entitlements",
            dependencies: [.target(name: "JustCore")],
            settings: .settings(base: baseSettings)
        ),

        // Covers the pure logic only — parsing, scheduling, string handling.
        // That is where every bug so far has actually lived, and it is the part
        // that can be checked without a device, an account or a model.
        .target(
            name: "JustTests",
            destinations: allDevices,
            product: .unitTests,
            bundleId: "\(bundlePrefix).tests",
            deploymentTargets: iOSTarget,
            infoPlist: .default,
            sources: ["Tests/**"],
            dependencies: [
                .target(name: "JustCore"),
                .target(name: "JustLyrics"),
                .target(name: "JustSensei"),
                            .target(name: "JustMusic"),
                            .target(name: "JustDesign"),
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
        // Hosting the existing JustTests instead would have put an app launch
        // in front of a suite that finishes in under a second and runs on every
        // change. Two targets keeps both properties.
        .target(
            name: "JustReport",
            destinations: allDevices,
            product: .unitTests,
            bundleId: "\(bundlePrefix).report",
            deploymentTargets: iOSTarget,
            infoPlist: .default,
            sources: ["Report/**"],
            dependencies: [
                .target(name: "Just"),
                .target(name: "JustCore"),
                .target(name: "JustLyrics"),
                .target(name: "JustSensei"),
            ],
            settings: .settings(base: baseSettings)
        ),
    ],
    schemes: [
        // The default scheme tests the fast suite only, so `xcodebuild test`
        // and CI stay as they were. The report is asked for by name.
        .scheme(
            name: "Just",
            shared: true,
            buildAction: .buildAction(targets: ["Just"]),
            testAction: .targets(["JustTests"]),
            runAction: .runAction(executable: "Just")
        ),
        .scheme(
            name: "JustReport",
            shared: true,
            buildAction: .buildAction(targets: ["Just", "JustReport"]),
            testAction: .targets(["JustReport"]),
            runAction: .runAction(executable: "Just")
        ),
    ]
)
