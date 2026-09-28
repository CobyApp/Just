import UIKit

/// Physical feedback for answers.
///
/// A quiz that only changes colour makes the user re-read the screen to learn
/// whether they were right. A tap tells them before their eyes get there, which
/// matters most in the drill loop where they answer dozens in a row.
@MainActor
public enum Haptics {
    public static func correct() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    public static func nearMiss() {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }

    public static func wrong() {
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }

    /// For a state change the user asked for — a toggle, a card advancing.
    public static func tick() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}
