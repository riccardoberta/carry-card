import Testing
import Foundation
@testable import CarryCard

struct CardDatabaseMergeTests {
    private func makeCard(
        id: UUID = UUID(),
        name: String = "Test Card",
        updatedAt: Date,
        sortIndex: Double = 0
    ) -> LoyaltyCard {
        LoyaltyCard(id: id, name: name, code: "12345", barcodeType: .code128, sortIndex: sortIndex, createdAt: updatedAt, updatedAt: updatedAt)
    }

    @Test func mergeUnionsDisjointCardSets() {
        let cardA = makeCard(name: "A", updatedAt: Date())
        let cardB = makeCard(name: "B", updatedAt: Date())
        let local = CardDatabase(cards: [cardA], deletedCards: [])
        let remote = CardDatabase(cards: [cardB], deletedCards: [])

        let merged = local.merged(with: remote)

        #expect(merged.cards.count == 2)
        #expect(Set(merged.cards.map(\.id)) == Set([cardA.id, cardB.id]))
    }

    @Test func newerLocalCardWinsOverOlderRemote() {
        let id = UUID()
        let older = makeCard(id: id, name: "Old Name", updatedAt: Date(timeIntervalSince1970: 1000))
        var newer = older
        newer.name = "New Name"
        newer.updatedAt = Date(timeIntervalSince1970: 2000)

        let local = CardDatabase(cards: [newer], deletedCards: [])
        let remote = CardDatabase(cards: [older], deletedCards: [])

        let merged = local.merged(with: remote)

        #expect(merged.cards.count == 1)
        #expect(merged.cards.first?.name == "New Name")
    }

    @Test func newerRemoteCardWinsOverOlderLocal() {
        let id = UUID()
        let older = makeCard(id: id, name: "Old Name", updatedAt: Date(timeIntervalSince1970: 1000))
        var newer = older
        newer.name = "New Name"
        newer.updatedAt = Date(timeIntervalSince1970: 2000)

        let local = CardDatabase(cards: [older], deletedCards: [])
        let remote = CardDatabase(cards: [newer], deletedCards: [])

        let merged = local.merged(with: remote)

        #expect(merged.cards.count == 1)
        #expect(merged.cards.first?.name == "New Name")
    }

    @Test func deletionTombstoneRemovesOlderCardVersion() {
        let id = UUID()
        let card = makeCard(id: id, updatedAt: Date(timeIntervalSince1970: 1000))
        let tombstone = DeletedCard(id: id, deletedAt: Date(timeIntervalSince1970: 2000))

        let local = CardDatabase(cards: [], deletedCards: [tombstone])
        let remote = CardDatabase(cards: [card], deletedCards: [])

        let merged = local.merged(with: remote)

        #expect(merged.cards.isEmpty)
        #expect(merged.deletedCards.contains(tombstone))
    }

    @Test func editAfterDeletionRestoresCard() {
        let id = UUID()
        let tombstone = DeletedCard(id: id, deletedAt: Date(timeIntervalSince1970: 1000))
        let editedAfterDeletion = makeCard(id: id, name: "Restored", updatedAt: Date(timeIntervalSince1970: 2000))

        let local = CardDatabase(cards: [], deletedCards: [tombstone])
        let remote = CardDatabase(cards: [editedAfterDeletion], deletedCards: [])

        let merged = local.merged(with: remote)

        #expect(merged.cards.count == 1)
        #expect(merged.cards.first?.name == "Restored")
    }

    @Test func editBeforeDeletionDoesNotResurrectCard() {
        let id = UUID()
        let editedBeforeDeletion = makeCard(id: id, name: "Stale Edit", updatedAt: Date(timeIntervalSince1970: 1000))
        let tombstone = DeletedCard(id: id, deletedAt: Date(timeIntervalSince1970: 2000))

        let local = CardDatabase(cards: [], deletedCards: [tombstone])
        let remote = CardDatabase(cards: [editedBeforeDeletion], deletedCards: [])

        let merged = local.merged(with: remote)

        #expect(merged.cards.isEmpty)
    }

    @Test func mergeIsOrderIndependentAndDeterministic() {
        let cardA = makeCard(name: "A", updatedAt: Date(timeIntervalSince1970: 1000))
        let cardB = makeCard(name: "B", updatedAt: Date(timeIntervalSince1970: 2000))
        let local = CardDatabase(cards: [cardA], deletedCards: [])
        let remote = CardDatabase(cards: [cardB], deletedCards: [])

        let mergedForward = local.merged(with: remote)
        let mergedBackward = remote.merged(with: local)

        #expect(Set(mergedForward.cards.map(\.id)) == Set(mergedBackward.cards.map(\.id)))
        #expect(mergedForward.cards.count == mergedBackward.cards.count)
    }

    @Test func mergingEmptyRemoteNeverDropsLocalCards() {
        let cardA = makeCard(name: "A", updatedAt: Date())
        let local = CardDatabase(cards: [cardA], deletedCards: [])
        let remote = CardDatabase.empty

        let merged = local.merged(with: remote)

        #expect(merged.cards.count == 1)
        #expect(merged.cards.first?.id == cardA.id)
    }

    @Test func tombstonesMergeKeepingMostRecentDeletion() {
        let id = UUID()
        let earlier = DeletedCard(id: id, deletedAt: Date(timeIntervalSince1970: 1000))
        let later = DeletedCard(id: id, deletedAt: Date(timeIntervalSince1970: 5000))

        let local = CardDatabase(cards: [], deletedCards: [earlier])
        let remote = CardDatabase(cards: [], deletedCards: [later])

        let merged = local.merged(with: remote)

        #expect(merged.deletedCards.count == 1)
        #expect(merged.deletedCards.first?.deletedAt == later.deletedAt)
    }
}
