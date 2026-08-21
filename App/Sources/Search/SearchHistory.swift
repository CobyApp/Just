import Foundation
import Observation

/// The last few things the user searched for.
///
/// Songs get looked up more than once — a learner comes back to the same artist
/// across sessions — and retyping a Japanese title on a Korean keyboard is
/// enough friction to be worth removing.
@MainActor
@Observable
final class SearchHistory {
    private static let key = "search.recent"
    private static let limit = 8

    private(set) var queries: [String]

    init() {
        queries = UserDefaults.standard.stringArray(forKey: Self.key) ?? []
    }

    /// Records a query, moving a repeat to the front rather than duplicating it.
    func record(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        // One- and two-character queries are usually the middle of typing
        // something longer, not a search worth remembering.
        guard trimmed.count >= 2 else { return }

        var updated = queries.filter { $0.caseInsensitiveCompare(trimmed) != .orderedSame }
        updated.insert(trimmed, at: 0)
        queries = Array(updated.prefix(Self.limit))
        persist()
    }

    func remove(_ query: String) {
        queries.removeAll { $0 == query }
        persist()
    }

    func clear() {
        queries = []
        persist()
    }

    private func persist() {
        UserDefaults.standard.set(queries, forKey: Self.key)
    }
}
