import ProjectDescription

// MARK: - Shared configuration

private let bundlePrefix = "com.coby.just"
private let iOSTarget: DeploymentTargets = .iOS("26.0")
private let allDevices: Destinations = [.iPhone, .iPad]

private let baseSettings: SettingsDictionary = [
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
        module("JustDesign", dependencies: [.target(name: "JustCore")]),

        // YouTube Data API v3 search + IFrame player bridge.
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
                "CFBundleDisplayName": "Just",
                "NSAppleMusicUsageDescription":
                    "곡을 검색하고 재생해 가사로 일본어를 공부하기 위해 Apple Music에 접근합니다.",
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
                "UIUserInterfaceStyle": "Dark",
            ]),
            sources: ["App/Sources/**"],
            resources: ["App/Resources/**"],
            dependencies: [
                .target(name: "JustCore"),
                .target(name: "JustDesign"),
                .target(name: "JustMusic"),
                .target(name: "JustLyrics"),
                .target(name: "JustSensei"),
            ],
            settings: .settings(base: baseSettings.merging([
                "TARGETED_DEVICE_FAMILY": "1,2",
            ]) { _, new in new })
        ),
    ]
)
