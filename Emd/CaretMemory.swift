import Foundation

/// Where the caret and the scroll sat when a post was last open.
struct CaretSpot: Codable {
    var caret: Int
    var scroll: Double
    var seen: Double
}

/// Reopening a post puts you back where you stopped. A post you have never opened starts at the top.
enum CaretMemory {
    private static let key = "caretSpots"
    private static let limit = 300
    /// Read from defaults once; every open and close after that works in memory. Main thread only.
    nonisolated(unsafe) private static var loaded: [String: CaretSpot]?

    static func spot(for post: String) -> CaretSpot? {
        load()[post]
    }

    static func remember(_ spot: CaretSpot, for post: String) {
        var spots = load()
        spots[post] = spot
        let kept = trimmed(spots)
        loaded = kept
        store(kept)
    }

    private static func trimmed(_ spots: [String: CaretSpot]) -> [String: CaretSpot] {
        guard spots.count > limit else { return spots }
        let kept = spots.sorted { $0.value.seen > $1.value.seen }.prefix(limit)
        return Dictionary(uniqueKeysWithValues: kept.map { ($0.key, $0.value) })
    }

    private static func load() -> [String: CaretSpot] {
        if let loaded { return loaded }
        let data = UserDefaults.standard.data(forKey: key)
        let spots = data.flatMap { try? JSONDecoder().decode([String: CaretSpot].self, from: $0) } ?? [:]
        loaded = spots
        return spots
    }

    private static func store(_ spots: [String: CaretSpot]) {
        guard let data = try? JSONEncoder().encode(spots) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
