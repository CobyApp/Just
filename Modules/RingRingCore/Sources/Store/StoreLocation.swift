import Foundation
import os
import SwiftData

/// Where the SwiftData store lives on disk, and the one-time copy that put it
/// there.
///
/// The store used to be opened with a bare `ModelConfiguration()`, whose
/// `groupContainer` defaults to `.automatic`. With no App Group entitlement that
/// means the app's own Application Support; the moment the widget added
/// `group.com.coby.ringring`, the same call silently switched to the group
/// container — and anyone updating from a pre-widget build opened an empty
/// library while their words sat in the old file.
///
/// The group container is now named explicitly, and a store left at the old
/// location is carried over before the container opens.
///
/// SwiftData does not document where its default store goes. What this relies
/// on, as observed on iOS 17 through 26:
/// - without a group container: `<Application Support>/default.store`
/// - with one: `<group container>/Library/Application Support/default.store`
/// each with SQLite's `-wal` and `-shm` beside it, and a `.default_SUPPORT`
/// directory when any attribute uses external storage. If that ever stops
/// holding, the copy simply finds nothing to copy — the old files are never
/// deleted, so nothing is lost either.
enum StoreLocation {
    static let appGroup = WidgetStore.appGroup
    static let storeName = "default.store"

    /// Every file and directory that together make up one store.
    static let storeFiles = [
        storeName,
        storeName + "-wal",
        storeName + "-shm",
        ".default_SUPPORT",
    ]

    /// Where builds before the App Group entitlement kept the store.
    static var legacyDirectory: URL { URL.applicationSupportDirectory }

    /// Where SwiftData keeps the store for `groupContainer: .identifier(appGroup)`.
    /// Nil when the entitlement is missing, as it is in unit tests.
    static var groupDirectory: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroup)?
            .appending(path: "Library/Application Support", directoryHint: .isDirectory)
    }

    enum Outcome: Equatable {
        /// No old store, or nothing needed doing.
        case nothingToDo
        /// The old store was copied into the group container.
        case copied
        /// Both exist and the group store has data of its own; it is kept.
        case keptExisting
        /// The copy failed and was rolled back; worth trying again next launch.
        case failed
    }

    /// Copies the store at `legacy` into `group` when the group has no store
    /// worth keeping.
    ///
    /// "Worth keeping" covers the case the plain existence check misses: a
    /// build that shipped with the entitlement but without this copy already
    /// created an *empty* store in the group container on first launch. That
    /// empty file is replaced; a group store with any words or songs in it is
    /// left alone, since merging two libraries is not something to attempt
    /// silently at launch.
    ///
    /// Copied rather than moved, so a failure here — or a wrong guess about
    /// SwiftData's paths — can never cost the original.
    static func migrate(
        from legacy: URL,
        to group: URL,
        schema: Schema,
        fileManager: FileManager = .default
    ) -> Outcome {
        let source = legacy.appending(path: storeName)
        let destination = group.appending(path: storeName)
        guard fileManager.fileExists(atPath: source.path(percentEncoded: false)) else {
            return .nothingToDo
        }

        if fileManager.fileExists(atPath: destination.path(percentEncoded: false)) {
            // In its own pool so the container that looked is closed before
            // the files it looked at are removed and replaced.
            let isEmpty = autoreleasepool { isEmptyStore(at: destination, schema: schema) }
            guard isEmpty else {
                // Two libraries; the group one wins and the old file stays on
                // disk untouched. Logged, since those words are now unseen.
                Logger(subsystem: "com.coby.ringring", category: "store")
                    .notice("legacy store left in place: group store already has data")
                return .keptExisting
            }
            for name in storeFiles {
                try? fileManager.removeItem(at: group.appending(path: name))
            }
        }

        var copied: [URL] = []
        do {
            try fileManager.createDirectory(at: group, withIntermediateDirectories: true)
            for name in storeFiles {
                let from = legacy.appending(path: name)
                guard fileManager.fileExists(atPath: from.path(percentEncoded: false)) else { continue }
                let to = group.appending(path: name)
                try fileManager.copyItem(at: from, to: to)
                copied.append(to)
            }
            return .copied
        } catch {
            // Half a store is worse than none: SQLite would open the main file
            // without its write-ahead log and quietly drop the latest writes.
            for url in copied { try? fileManager.removeItem(at: url) }
            return .failed
        }
    }

    /// True when the store at `url` holds no words and no songs.
    ///
    /// Opens it in a container of its own, released before returning so the
    /// files are closed by the time the caller touches them. A store that will
    /// not open counts as not empty: better to leave an unreadable file alone
    /// than to delete it on a guess.
    private static func isEmptyStore(at url: URL, schema: Schema) -> Bool {
        guard let container = try? ModelContainer(
            for: schema,
            configurations: ModelConfiguration(url: url)
        ) else { return false }
        let context = ModelContext(container)
        let words = (try? context.fetchCount(FetchDescriptor<VocabEntry>())) ?? 1
        let songs = (try? context.fetchCount(FetchDescriptor<StudySong>())) ?? 1
        return words == 0 && songs == 0
    }
}
