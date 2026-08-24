import Foundation

/// The full local (or remote) state: all cards plus deletion tombstones.
/// This is the unit that gets persisted to `cards.json` / `deleted.json`
/// and merged during synchronization.
struct CardDatabase: Codable, Equatable, Sendable {
    var cards: [LoyaltyCard]
    var deletedCards: [DeletedCard]

    static let empty = CardDatabase(cards: [], deletedCards: [])

    /// Deterministically merges this database with another (e.g. local vs. remote)
    /// using last-write-wins semantics, per card UUID:
    ///
    /// - If a card exists on only one side, it is kept.
    /// - If a card exists on both sides, the one with the newer `updatedAt` wins.
    /// - A tombstone beats any card version whose `updatedAt` is not newer than
    ///   the tombstone's `deletedAt` (i.e. a deletion wins over an older or
    ///   equally-old edit).
    /// - A card edited *after* it was deleted (its `updatedAt` is later than the
    ///   tombstone's `deletedAt`) is restored — the edit wins over the tombstone.
    /// - Tombstones are merged by keeping, per id, the most recent `deletedAt`.
    ///
    /// The result is independent of argument order, making repeated merges stable.
    func merged(with other: CardDatabase) -> CardDatabase {
        var cardsByID: [UUID: LoyaltyCard] = [:]
        for card in cards + other.cards {
            if let existing = cardsByID[card.id] {
                cardsByID[card.id] = existing.updatedAt >= card.updatedAt ? existing : card
            } else {
                cardsByID[card.id] = card
            }
        }

        var tombstonesByID: [UUID: DeletedCard] = [:]
        for tombstone in deletedCards + other.deletedCards {
            if let existing = tombstonesByID[tombstone.id] {
                tombstonesByID[tombstone.id] = existing.deletedAt >= tombstone.deletedAt ? existing : tombstone
            } else {
                tombstonesByID[tombstone.id] = tombstone
            }
        }

        var resultCards: [UUID: LoyaltyCard] = [:]
        for (id, card) in cardsByID {
            if let tombstone = tombstonesByID[id] {
                if card.updatedAt > tombstone.deletedAt {
                    resultCards[id] = card
                }
            } else {
                resultCards[id] = card
            }
        }

        let orderedCards = resultCards.values.sorted { lhs, rhs in
            if lhs.sortIndex != rhs.sortIndex { return lhs.sortIndex < rhs.sortIndex }
            return lhs.createdAt < rhs.createdAt
        }

        return CardDatabase(cards: orderedCards, deletedCards: Array(tombstonesByID.values))
    }
}
