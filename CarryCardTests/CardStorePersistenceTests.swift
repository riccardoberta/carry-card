import Testing
import Foundation
@testable import CarryCard

struct CardStorePersistenceTests {
    // `.iso8601` encoding has whole-second precision; comparing a reloaded
    // card against one built with `Date()` (sub-second precision) would fail
    // on the timestamp alone even though persistence worked correctly.
    private static let wholeSecondDate = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeTemporaryStore() -> (CardStore, URL) {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        return (CardStore(baseDirectory: base), base)
    }

    @Test func loadingFreshStoreReturnsEmptyDatabase() async {
        let (store, _) = makeTemporaryStore()
        let database = await store.load()
        #expect(database.cards.isEmpty)
        #expect(database.deletedCards.isEmpty)
    }

    @Test func savedDatabaseCanBeReloaded() async throws {
        let (store, _) = makeTemporaryStore()
        let card = LoyaltyCard(
            name: "Cinema Plus", code: "998877", barcodeType: .qr,
            createdAt: Self.wholeSecondDate, updatedAt: Self.wholeSecondDate
        )
        let database = CardDatabase(cards: [card], deletedCards: [])

        try await store.save(database)
        let reloaded = await store.load()

        #expect(reloaded.cards == [card])
    }

    @Test func missingRemoteFilesDoNotCrashAndYieldEmptyDatabase() async {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = CardStore(baseDirectory: base)
        // No save() was ever called; cards.json/deleted.json simply don't exist.
        let database = await store.load()
        #expect(database.cards.isEmpty)
    }

    @Test func corruptedLocalJSONIsQuarantinedNotCrashing() async throws {
        let (store, base) = makeTemporaryStore()
        // Force directory creation, then overwrite cards.json with garbage.
        _ = await store.load()
        let cardsURL = base.appendingPathComponent("CarryCardData/cards.json")
        try "{ this is not valid JSON".data(using: .utf8)!.write(to: cardsURL)

        let database = await store.load()

        #expect(database.cards.isEmpty)

        let directoryContents = try FileManager.default.contentsOfDirectory(
            at: base.appendingPathComponent("CarryCardData"),
            includingPropertiesForKeys: nil
        )
        let hasQuarantineFile = directoryContents.contains { $0.lastPathComponent.contains("corrupted") }
        #expect(hasQuarantineFile)
    }

    @Test func savingTwiceOverwritesPreviousContentAtomically() async throws {
        let (store, _) = makeTemporaryStore()
        let cardV1 = LoyaltyCard(
            name: "V1", code: "111", barcodeType: .code128,
            createdAt: Self.wholeSecondDate, updatedAt: Self.wholeSecondDate
        )
        let cardV2 = LoyaltyCard(
            name: "V2", code: "222", barcodeType: .code128,
            createdAt: Self.wholeSecondDate, updatedAt: Self.wholeSecondDate
        )

        try await store.save(CardDatabase(cards: [cardV1], deletedCards: []))
        try await store.save(CardDatabase(cards: [cardV2], deletedCards: []))

        let reloaded = await store.load()
        #expect(reloaded.cards == [cardV2])
    }
}
