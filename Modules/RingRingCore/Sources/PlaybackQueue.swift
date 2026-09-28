import Foundation

/// The list a song was opened from, so the mini player can step through it.
///
/// Opening a song from a group, from 「내 노래」, or from the shelf makes that
/// list the queue. There is no shuffle and no wrap-around: the ends are the
/// ends, and a button that does nothing is disabled rather than surprising.
public struct PlaybackQueue: Equatable, Sendable {
    public private(set) var tracks: [Track]

    public init(_ tracks: [Track]) {
        self.tracks = tracks
    }

    public static let empty = PlaybackQueue([])

    public func next(after current: Track) -> Track? {
        guard let index = tracks.firstIndex(where: { $0.id == current.id }),
              index + 1 < tracks.count else { return nil }
        return tracks[index + 1]
    }

    public func previous(before current: Track) -> Track? {
        guard let index = tracks.firstIndex(where: { $0.id == current.id }),
              index > 0 else { return nil }
        return tracks[index - 1]
    }
}
