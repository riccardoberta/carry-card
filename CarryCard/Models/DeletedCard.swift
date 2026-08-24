import Foundation

/// A tombstone recording that a card was deleted, so the deletion can
/// propagate to other devices during synchronization instead of being
/// silently reintroduced by an older remote copy of the card.
struct DeletedCard: Codable, Equatable, Sendable {
    let id: UUID
    let deletedAt: Date
}
