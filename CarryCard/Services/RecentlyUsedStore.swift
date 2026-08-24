import Foundation

/// Tracks which card was viewed most recently, purely as a local UI convenience —
/// deliberately **not** part of `LoyaltyCard` and never synced. "Recently used" is a
/// per-device browsing habit, not a fact about the card: syncing it would mean a mere
/// glance at a card on one device could out-rank a real edit made on another, which
/// has nothing to do with what `updatedAt` is for.
final class RecentlyUsedStore {
    private let key = "app.carrycard.recentlyUsed"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func markUsed(_ id: UUID) {
        var map = loadMap()
        map[id.uuidString] = Date()
        saveMap(map)
    }

    /// The card in `cards` with the most recent recorded use, if any card has ever
    /// been viewed on this device.
    func mostRecentCard(in cards: [LoyaltyCard]) -> LoyaltyCard? {
        let map = loadMap()
        return cards
            .compactMap { card in map[card.id.uuidString].map { (card, $0) } }
            .max { $0.1 < $1.1 }?
            .0
    }

    private func loadMap() -> [String: Date] {
        guard let data = defaults.data(forKey: key),
              let decoded = try? CarryCardJSON.decoder.decode([String: Date].self, from: data) else {
            return [:]
        }
        return decoded
    }

    private func saveMap(_ map: [String: Date]) {
        guard let data = try? CarryCardJSON.encoder.encode(map) else { return }
        defaults.set(data, forKey: key)
    }
}
