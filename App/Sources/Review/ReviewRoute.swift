import Foundation

/// Route to the review screen, pushable from more than one tab.
///
/// Carries a token so every push is a new value. A reminder tapped while the
/// review screen was already on top set the path to an equal value, SwiftUI
/// kept the old screen, and it went on showing 「오늘 복습 끝」 over cards that
/// had since come due.
struct ReviewRoute: Hashable {
    var token = UUID()
}
