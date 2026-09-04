import Foundation
import GoogleMobileAds
import Observation
import UIKit

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

    /// Fewer lines than this and the analysis is over before the ad closes.
    static let minimumPendingLines = 5
    static let minimumGap: TimeInterval = 120

    private let unitID: String
    private var ad: InterstitialAd?
    private var isLoading = false
    private var lastShown: Date?
    private var offeredTrackIDs: Set<String> = []
    /// Set when a show was asked for before the ad had loaded. Answered when
    /// it loads, if the wait is still on.
    private var pending: (() -> Bool)?
    private(set) var isPresenting = false

    init(unitID: String = AnalysisInterstitial.testUnitID) {
        self.unitID = unitID
    }

    /// Fetches the next ad so it is ready when a song starts analysing.
    func preload() async {
        guard ad == nil, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        // Nothing is said to the reader when an ad fails to arrive; an ad that
        // did not come is not their problem to hear about.
        ad = try? await InterstitialAd.load(with: unitID, request: Request())
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

    private func present() {
        guard let ad else { return }
        self.ad = nil
        isPresenting = true
        lastShown = .now
        // The SDK finds the front-most controller when none is given, which is
        // the full-screen player cover here.
        ad.present(from: nil)
    }

    // MARK: FullScreenContentDelegate

    nonisolated func adDidDismissFullScreenContent(_ ad: FullScreenPresentingAd) {
        Task { @MainActor in
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
