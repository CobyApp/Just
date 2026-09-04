import Foundation
import Observation
import SwiftUI

/// Which guide cards the reader has closed.
///
/// A guide explains a screen the first few times; after that it is a card in
/// the way of the content it explained. Each guide has an id, the ✕ on it
/// records that id here, and the card stays gone across launches. Settings
/// can bring them all back.
@MainActor
@Observable
public final class GuideDismissals {
    public static let shared = GuideDismissals()

    private static let key = "guides.dismissed"
    private let defaults: UserDefaults
    public private(set) var dismissed: Set<String>

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        dismissed = Set(defaults.stringArray(forKey: Self.key) ?? [])
    }

    public func isDismissed(_ id: String) -> Bool { dismissed.contains(id) }

    public func dismiss(_ id: String) {
        dismissed.insert(id)
        save()
    }

    public func restoreAll() {
        dismissed.removeAll()
        save()
    }

    private func save() {
        defaults.set(Array(dismissed).sorted(), forKey: Self.key)
    }
}

/// True inside a guide that has a ✕, so the guide leaves room for it.
///
/// The ✕ is an overlay; without this the last words of a one-line hint ran
/// underneath it.
private struct GuideIsDismissibleKey: EnvironmentKey {
    static let defaultValue = false
}

public extension EnvironmentValues {
    var guideIsDismissible: Bool {
        get { self[GuideIsDismissibleKey.self] }
        set { self[GuideIsDismissibleKey.self] = newValue }
    }
}

/// Puts a ✕ on a guide and removes the guide once it is pressed.
private struct DismissibleGuide: ViewModifier {
    let id: String

    func body(content: Content) -> some View {
        let store = GuideDismissals.shared
        if !store.isDismissed(id) {
            content
                .environment(\.guideIsDismissible, true)
                .overlay(alignment: .topTrailing) {
                    Button {
                        withAnimation(.easeOut(duration: 0.22)) { store.dismiss(id) }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(JustTheme.Ink.secondary)
                            .frame(width: 28, height: 28)
                            .background(JustTheme.Surface.panel, in: .circle)
                    }
                    .buttonStyle(.plain)
                    .padding(6)
                    .accessibilityLabel("안내 닫기")
                }
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
        }
    }
}

public extension View {
    /// Marks a guide card or hint as closable. The id names the guide, not the
    /// screen — the same id anywhere closes together.
    func dismissibleGuide(_ id: String) -> some View {
        modifier(DismissibleGuide(id: id))
    }
}
