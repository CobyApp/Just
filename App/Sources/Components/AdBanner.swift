import GoogleMobileAds
import JustDesign
import SwiftUI
import UIKit

/// The app's only ad surface.
///
/// Where it may appear, and why only there: an ad is acceptable at a moment the
/// reader is not using the screen for anything. Two kinds of moment qualify.
/// The work just stopped — waiting for a song to be analysed, finishing a
/// quiz, finishing the day's review. Or the reading just ended — below the last
/// group on the home grid, after the last song of a group, after the last song
/// in 「내 노래」. Nowhere else.
///
/// Sized to its width (an adaptive banner). Google's *test* creatives come in
/// fixed sizes and sit letterboxed in black inside a wider slot; real fill is
/// built to the slot and has no such bars. Not a bug to chase in test mode.
///
/// Where it must not appear, for reasons worth writing down rather than
/// rediscovering: the lyrics and the player, which are the product; any screen
/// with a question on it, where an ad competes with the thing being learned;
/// and directly against a button, which invites the accidental taps AdMob's own
/// policy forbids. Every use below leaves space above it for that last reason.
///
/// A banner rather than an interstitial, deliberately. The wait exists because
/// the on-device model is working, and a video ad would compete with it for the
/// CPU and the neural engine — lengthening the very wait it was filling, and
/// heating the device while it did.
struct AdBanner: View {
    /// Google's public test unit. Real inventory needs the account holder's own
    /// id; this one always fills, which is what makes it useful for checking
    /// that the placement behaves.
    static let testUnitID = "ca-app-pub-3940256099942544/2934735716"

    let unitID: String

    /// Nothing is drawn until an ad actually arrives.
    ///
    /// A reserved empty rectangle is worse than no rectangle: it moves the
    /// progress and the artwork up the screen for a layout that may never be
    /// filled — no network, no inventory, a fresh install offline.
    @State private var height: CGFloat?

    var body: some View {
        // One instance, resized. Two branches of an `if` are two different
        // views to SwiftUI, so the arriving ad would replace the view that had
        // just loaded it — and the new one would request all over again.
        BannerRepresentable(unitID: unitID, height: $height)
            .frame(height: height ?? 0)
            .clipped()
            .animation(.easeInOut(duration: 0.2), value: height)
    }
}

private struct BannerRepresentable: UIViewRepresentable {
    let unitID: String
    @Binding var height: CGFloat?

    func makeUIView(context: Context) -> LoadingBannerView {
        let view = LoadingBannerView()
        view.adUnitID = unitID
        view.delegate = context.coordinator
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ view: LoadingBannerView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(height: $height) }

    final class Coordinator: NSObject, BannerViewDelegate {
        private let height: Binding<CGFloat?>

        init(height: Binding<CGFloat?>) {
            self.height = height
        }

        func bannerViewDidReceiveAd(_ bannerView: BannerView) {
            height.wrappedValue = bannerView.adSize.size.height
        }

        func bannerView(_ bannerView: BannerView, didFailToReceiveAdWithError error: Error) {
            // Stays at zero height. Nothing is said to the reader: an ad that
            // did not arrive is not their problem to hear about.
            height.wrappedValue = nil
        }
    }
}

/// Asks for its ad when it has somewhere to put one.
///
/// The request cannot be made from `updateUIView`. That runs before the view is
/// in a window, so the root view controller the SDK needs is still nil — and
/// nothing changes afterwards to bring it back, so the ad was never requested
/// at all. Moving into a window is the event that matters, so it is the one
/// listened for.
final class LoadingBannerView: BannerView {
    private var hasRequested = false

    override func didMoveToWindow() {
        super.didMoveToWindow()
        requestIfPossible()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // A second chance: the window can arrive before a width does.
        requestIfPossible()
    }

    private func requestIfPossible() {
        guard !hasRequested,
              let controller = window?.rootViewController,
              // The banner is sized from its own width, and asking with a
              // width of zero gets one built for the wrong screen.
              bounds.width > 0 || superview?.bounds.width ?? 0 > 0
        else { return }

        let width = bounds.width > 0 ? bounds.width : (superview?.bounds.width ?? 0)
        hasRequested = true
        adSize = currentOrientationAnchoredAdaptiveBanner(width: width)
        rootViewController = controller
        load(Request())
    }
}
