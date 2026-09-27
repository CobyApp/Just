import Foundation
import GoogleMobileAds
import Observation
import UIKit
import os
import UserMessagingPlatform

/// Google's consent flow (UMP), and the gate every ad request goes through.
///
/// The SDK is started, and ads are requested, only once UMP says
/// `canRequestAds`. Where no consent is required that is immediately; in the
/// EEA and the UK it is after the reader has answered Google's form. Consent
/// given on an earlier launch counts straight away, so a returning reader's
/// first ad is not held up by the network round-trip.
@MainActor
final class AdsConsent {
    static let shared = AdsConsent()

    private var isGathering = false
    private var didStartSDK = false

    var canRequestAds: Bool { ConsentInformation.shared.canRequestAds }

    /// True where the reader must be able to change their answer later (the
    /// EEA and the UK). A settings row calling `presentPrivacyOptions()` is
    /// expected to be shown only when this is set.
    var isPrivacyOptionsRequired: Bool {
        ConsentInformation.shared.privacyOptionsRequirementStatus == .required
    }

    /// Refreshes consent at launch and shows Google's form if it is required.
    func gather() async {
        guard !isGathering else { return }
        isGathering = true
        defer { isGathering = false }

        startSDKIfAllowed()
        do {
            try await ConsentInformation.shared.requestConsentInfoUpdate(with: RequestParameters())
            if let controller = Self.presentingController() {
                try await ConsentForm.loadAndPresentIfRequired(from: controller)
            }
        } catch {
            // Offline, or the form failed to load. Consent from an earlier
            // launch still applies; with none, ads simply stay off until the
            // next launch tries again. Nothing is said to the reader.
        }
        startSDKIfAllowed()
    }

    /// Reopens Google's form so the reader can change their answer.
    func presentPrivacyOptions() async {
        guard let controller = Self.presentingController() else { return }
        try? await ConsentForm.presentPrivacyOptionsForm(from: controller)
        startSDKIfAllowed()
    }

    private func startSDKIfAllowed() {
        guard canRequestAds, !didStartSDK else { return }
        didStartSDK = true
        MobileAds.shared.start(completionHandler: nil)
    }

    private static func presentingController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        var top = scene?.keyWindow?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
}

/// The app's only ad: one full-screen ad while a song is being analysed.
///
/// Where it appears, and why only there: the wait for analysis is the one
/// moment the reader is not using the screen for anything — the lyrics are
/// not ready, and nothing they do shortens the wait. The banners that used to
/// sit under lists were taken out: a strip below the last row was read as
/// clutter at the end of every screen, and it earned little.
///
/// Where it must not appear: over the lyrics or the player, which are the
/// product; over a quiz; over the choice of translation mode, which is a
/// question the reader is answering. So it is shown after the choice, once
/// analysis has actually started, and only when there is enough left to
/// analyse that the wait is real.
///
/// Once per song opened, and never twice within two minutes — a reader
/// flipping through a group's songs is not shown an ad on every one.
@MainActor
@Observable
final class AnalysisInterstitial: NSObject, FullScreenContentDelegate {
    static let shared = AnalysisInterstitial()

    /// Google's public test unit. Real inventory needs the account holder's own
    /// id; this one always fills, which is what makes it useful for checking
    /// that the placement behaves.
    static let testUnitID = "ca-app-pub-3940256099942544/4411468910"

    /// The unit to request from. Debug builds always use the test unit, so a
    /// development build never serves (or clicks) real inventory. Release
    /// builds read the id `tuist generate` wrote into Info.plist from
    /// TUIST_ADMOB_INTERSTITIAL_ID, which is the test unit when that was unset.
    static var configuredUnitID: String {
        #if DEBUG
        return testUnitID
        #else
        let id = Bundle.main.object(forInfoDictionaryKey: "AdMobInterstitialUnitID") as? String
        guard let id, !id.isEmpty else { return testUnitID }
        return id
        #endif
    }

    /// Fewer lines than this and the analysis is over before the ad closes.
    static let minimumPendingLines = 5
    static let minimumGap: TimeInterval = 120

    private static let log = Logger(subsystem: "com.coby.just", category: "analysis")

    private let unitID: String
    private var ad: InterstitialAd?
    private var isLoading = false
    private var lastShown: Date?
    private var offeredTrackIDs: Set<String> = []
    /// Set when a show was asked for before the ad had loaded. Answered when
    /// it loads, if the wait is still on.
    private var pending: (() -> Bool)?
    private(set) var isPresenting = false

    init(unitID: String = AnalysisInterstitial.configuredUnitID) {
        self.unitID = unitID
        // The SDK otherwise reconfigures the app's audio session when an ad
        // loads or plays, which interrupted the song's clip mid-way. The app
        // owns its session; the SDK is told so.
        MobileAds.shared.audioVideoManager.isAudioSessionApplicationManaged = true
    }

    /// Fetches the next ad so it is ready when a song starts analysing.
    func preload() async {
        // No ad is requested before the consent flow allows one.
        guard ad == nil, !isLoading, AdsConsent.shared.canRequestAds else { return }
        isLoading = true
        defer { isLoading = false }
        // Nothing is said to the reader when an ad fails to arrive; an ad that
        // did not come is not their problem to hear about.
        ad = try? await InterstitialAd.load(with: unitID, request: Self.nonPersonalizedRequest())
        ad?.fullScreenContentDelegate = self
        if let pending, pending() {
            self.pending = nil
            present()
        }
    }

    /// Shows the ad for this song's analysis, if it is worth showing.
    ///
    /// - Parameters:
    ///   - trackID: the song, so a song is offered at most one ad.
    ///   - pendingLines: how much analysis is left.
    ///   - stillWaiting: asked again if the ad arrives late — a wait that has
    ///     ended gets no ad after the fact.
    func show(for trackID: String, pendingLines: Int, stillWaiting: @escaping () -> Bool) {
        guard pendingLines >= Self.minimumPendingLines,
              !offeredTrackIDs.contains(trackID),
              !isPresenting,
              lastShown.map({ Date.now.timeIntervalSince($0) >= Self.minimumGap }) ?? true
        else { return }
        offeredTrackIDs.insert(trackID)
        if ad != nil {
            present()
        } else {
            pending = stillWaiting
            Task { await preload() }
        }
    }

    /// Every request asks for non-personalised ads (`npa=1`): the app does not
    /// do personalised advertising, whatever the consent answer allows.
    private static func nonPersonalizedRequest() -> Request {
        let request = Request()
        let extras = Extras()
        extras.additionalParameters = ["npa": "1"]
        request.register(extras)
        return request
    }

    private func present() {
        guard let ad else { return }
        self.ad = nil
        isPresenting = true
        lastShown = .now
        Self.log.info("ad presented")
        // The SDK finds the front-most controller when none is given, which is
        // the full-screen player cover here.
        ad.present(from: nil)
    }

    // MARK: FullScreenContentDelegate

    nonisolated func adDidDismissFullScreenContent(_ ad: FullScreenPresentingAd) {
        Task { @MainActor in
            Self.log.info("ad dismissed")
            isPresenting = false
            await preload()
        }
    }

    nonisolated func ad(_ ad: FullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: Error) {
        Task { @MainActor in
            isPresenting = false
            await preload()
        }
    }
}
