import Foundation

/// Owns the in-memory list of loyalty cards shown on the main screen and is the
/// single place that mutates the local database (create, update, delete, reorder).
/// Every mutation persists immediately and then opportunistically triggers a
/// background sync, per the app's "local-first, sync when convenient" design.
@MainActor
final class CardListViewModel: ObservableObject {
    @Published private(set) var cards: [LoyaltyCard] = []
    @Published private(set) var isLoaded = false
    @Published private(set) var featuredCard: LoyaltyCard?

    let cardStore: CardStore
    let imageStore: ImageStore
    let syncService: SyncService
    private let recentlyUsedStore: RecentlyUsedStore

    init(
        cardStore: CardStore,
        imageStore: ImageStore,
        syncService: SyncService,
        recentlyUsedStore: RecentlyUsedStore = RecentlyUsedStore()
    ) {
        self.cardStore = cardStore
        self.imageStore = imageStore
        self.syncService = syncService
        self.recentlyUsedStore = recentlyUsedStore
    }

    /// Records that `card` was just opened, so it becomes (or stays) the featured
    /// card at the top of the list. Purely local — see `RecentlyUsedStore`.
    func markUsed(_ card: LoyaltyCard) {
        recentlyUsedStore.markUsed(card.id)
        featuredCard = card
    }

    func loadCards() async {
        let database = await cardStore.load()
        cards = database.cards.sorted { $0.sortIndex < $1.sortIndex }
        featuredCard = recentlyUsedStore.mostRecentCard(in: cards)
        isLoaded = true
    }

    /// Runs a sync pass and reloads the local database afterward — a sync can pull
    /// in cards or edits from another device, and those only reach `cards` (and the
    /// UI) once this reload happens. Call this instead of `syncService.sync()`
    /// directly anywhere the result should be reflected on screen.
    func syncAndReload() async {
        await syncService.sync()
        await loadCards()
    }

    /// Inserts a new card or replaces an existing one with the same id.
    func save(_ card: LoyaltyCard) async {
        var database = await cardStore.load()
        var updated = card
        updated.updatedAt = Date()
        if let index = database.cards.firstIndex(where: { $0.id == card.id }) {
            database.cards[index] = updated
        } else {
            if updated.sortIndex == 0 {
                let maxIndex = database.cards.map(\.sortIndex).max() ?? 0
                updated.sortIndex = maxIndex + 1
            }
            database.cards.append(updated)
        }
        database.deletedCards.removeAll { $0.id == card.id }

        try? await cardStore.save(database)
        cards = database.cards.sorted { $0.sortIndex < $1.sortIndex }
        await syncAndReload()
    }

    func delete(_ card: LoyaltyCard) async {
        var database = await cardStore.load()
        database.cards.removeAll { $0.id == card.id }
        database.deletedCards.removeAll { $0.id == card.id }
        database.deletedCards.append(DeletedCard(id: card.id, deletedAt: Date()))

        try? await cardStore.save(database)
        cards = database.cards.sorted { $0.sortIndex < $1.sortIndex }

        if let logoFileName = card.logoFileName {
            let stillReferenced = database.cards.contains { $0.logoFileName == logoFileName }
            if !stillReferenced {
                await imageStore.deleteLogo(fileName: logoFileName)
            }
        }

        await syncAndReload()
    }

    func move(fromOffsets source: IndexSet, toOffset destination: Int) async {
        var reordered = cards
        reordered.move(fromOffsets: source, toOffset: destination)
        for (index, var card) in reordered.enumerated() {
            card.sortIndex = Double(index)
            card.updatedAt = Date()
            reordered[index] = card
        }
        cards = reordered

        var database = await cardStore.load()
        for card in reordered {
            if let index = database.cards.firstIndex(where: { $0.id == card.id }) {
                database.cards[index] = card
            }
        }
        try? await cardStore.save(database)
        await syncAndReload()
    }
}
