import Foundation

/// Small in-memory cache for preferred-time trip searches.
/// Keyed by `fromCode-toCode-preferredMinute`; entries expire after `ttl`
/// seconds so scrolling the wheel or reopening the sheet within 2 minutes
/// never re-queries the API.
actor TripsSearchCache {
    private struct Entry {
        let minutes: [Int]
        let fetchedAt: Date
    }

    private var entries: [String: Entry] = [:]
    private let ttl: TimeInterval

    init(ttl: TimeInterval = 120) {
        self.ttl = ttl
    }

    /// Cached departure minutes if a fresh-enough entry exists; nil otherwise.
    func value(for key: String, now: Date = Date()) -> [Int]? {
        guard let entry = entries[key], now.timeIntervalSince(entry.fetchedAt) < ttl else {
            return nil
        }
        return entry.minutes
    }

    func store(_ minutes: [Int], for key: String, now: Date = Date()) {
        entries[key] = Entry(minutes: minutes, fetchedAt: now)
    }
}
