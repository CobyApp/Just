import SwiftUI

/// A screen with nothing in it yet, and what to do about that.
///
/// Wraps `ContentUnavailableView` rather than replacing it: the system view
/// already handles layout, Dynamic Type and accessibility, and redrawing it by
/// hand would give all of that up. What this adds is one place to decide the
/// button's style — and a named `actionTitle`, so that offering a way forward is
/// a visible decision at every call site rather than something easy to forget.
///
/// Seven of the app's ten empty screens had no action at all. Three of those
/// were dead ends the reader could only leave by finding the tab bar themselves.
public struct JustEmptyState: View {
    private let icon: String
    private let title: String
    private let message: String
    private let actionTitle: String?
    private let action: (() -> Void)?

    /// - Parameters:
    ///   - actionTitle: nil when there is genuinely nothing to offer — a search
    ///     with no results wants a different query, not a button, and "nothing
    ///     left to review" is a finish line rather than a failure.
    public init(
        icon: String,
        title: String,
        message: String,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) {
        self.icon = icon
        self.title = title
        self.message = message
        self.actionTitle = actionTitle
        self.action = action
    }

    public var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: icon)
        } description: {
            Text(message)
        } actions: {
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.justPrimary)
            }
        }
    }
}
