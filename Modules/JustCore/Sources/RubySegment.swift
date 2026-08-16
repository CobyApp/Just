import Foundation

/// One chunk of Japanese text with an optional reading printed above it.
///
/// Lives in Core rather than next to the furigana logic so the design system
/// can render it without depending on the analysis module.
public struct RubySegment: Identifiable, Hashable, Sendable {
    public let id: Int
    public let base: String
    /// nil when the base is already kana and needs no annotation.
    public let ruby: String?

    public init(id: Int, base: String, ruby: String?) {
        self.id = id
        self.base = base
        self.ruby = ruby
    }
}
