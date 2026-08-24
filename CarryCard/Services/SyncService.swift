import Foundation

/// Synchronizes the local card database with an optional folder chosen through
/// `SyncFolderManager`. Designed for one user with a couple of devices — not a
/// realtime collaborative store — so each sync is a full, deterministic,
/// last-write-wins merge (see `CardDatabase.merged(with:)`), not an incremental diff.
///
/// A sync attempt either fully succeeds (local and remote both end up holding the
/// merged state) or fully fails and leaves local data untouched, so a flaky
/// connection or an unmounted File Provider can never destroy local cards.
@MainActor
final class SyncService: ObservableObject {
    @Published private(set) var state: SyncState

    private let cardStore: CardStore
    private let folderManager: SyncFolderManager
    private let defaults: UserDefaults
    private let stateKey = "app.carrycard.syncState"
    private var isSyncing = false

    init(cardStore: CardStore, folderManager: SyncFolderManager, defaults: UserDefaults = .standard) {
        self.cardStore = cardStore
        self.folderManager = folderManager
        self.defaults = defaults

        if let data = defaults.data(forKey: stateKey),
           let saved = try? CarryCardJSON.decoder.decode(SyncState.self, from: data) {
            state = saved
        } else {
            state = .disabled
        }
        state.isEnabled = folderManager.isConfigured
        state.folderDisplayName = folderManager.folderDisplayName
    }

    /// Adopts a newly-picked folder and immediately attempts a first sync.
    func setFolder(_ url: URL) async {
        do {
            try folderManager.saveFolder(url)
            state.isEnabled = true
            state.folderDisplayName = folderManager.folderDisplayName
            state.lastErrorMessage = nil
            persistState()
            await sync()
        } catch {
            state.lastErrorMessage = error.localizedDescription
            persistState()
        }
    }

    /// Forgets the sync folder. Local cards are never touched.
    func disconnect() {
        folderManager.disconnect()
        state = .disabled
        persistState()
    }

    /// Runs one full sync pass, if a folder is configured and no sync is already
    /// in flight. Safe to call opportunistically (app becomes active, after an
    /// edit, "Sync Now") — overlapping calls are coalesced rather than queued.
    func sync() async {
        guard folderManager.isConfigured, !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }

        state.status = .syncing
        do {
            let mergedDatabase = try await performRemoteMergeAndWrite()
            try await cardStore.save(mergedDatabase)
            state.status = .success
            state.lastSuccessfulSyncAt = Date()
            state.lastErrorMessage = nil
            state.folderDisplayName = folderManager.folderDisplayName
        } catch {
            state.status = .failure
            state.lastErrorMessage = error.localizedDescription
        }
        persistState()
    }

    // MARK: - Sync body

    /// Reads the remote database, merges it with the local one, writes the merged
    /// result and logos back to the sync folder, and returns the merged database
    /// for the caller to save locally. Runs off the main actor.
    private func performRemoteMergeAndWrite() async throws -> CardDatabase {
        let localDatabase = await cardStore.load()
        let localLogosDirectory = cardStore.logosDirectoryURL
        let folderManager = self.folderManager

        return try await Task.detached(priority: .utility) {
            try folderManager.withAccessibleFolder { rootURL in
                let syncDirectory = Self.resolveSyncDirectory(root: rootURL)
                let remoteLogosDirectory = syncDirectory.appendingPathComponent("logos", isDirectory: true)
                try FileManager.default.createDirectory(at: syncDirectory, withIntermediateDirectories: true)
                try FileManager.default.createDirectory(at: remoteLogosDirectory, withIntermediateDirectories: true)

                let remoteDatabase = Self.readDatabase(in: syncDirectory)
                let merged = localDatabase.merged(with: remoteDatabase)

                Self.copyLogos(
                    for: merged.cards,
                    from: localLogosDirectory,
                    to: remoteLogosDirectory
                )
                Self.copyLogos(
                    for: merged.cards,
                    from: remoteLogosDirectory,
                    to: localLogosDirectory
                )

                try Self.writeDatabase(merged, to: syncDirectory)
                return merged
            }
        }.value
    }

    /// If the user selected the "Carry-Card" folder itself, sync files live
    /// directly inside it; otherwise a "Carry-Card" subfolder is used so we don't
    /// scatter files into an unrelated folder the user picked.
    private nonisolated static func resolveSyncDirectory(root: URL) -> URL {
        if root.lastPathComponent.caseInsensitiveCompare("Carry-Card") == .orderedSame {
            return root
        }
        return root.appendingPathComponent("Carry-Card", isDirectory: true)
    }

    private nonisolated static func readDatabase(in directory: URL) -> CardDatabase {
        let cards: [LoyaltyCard] = readJSON(directory.appendingPathComponent("cards.json")) ?? []
        let deleted: [DeletedCard] = readJSON(directory.appendingPathComponent("deleted.json")) ?? []
        return CardDatabase(cards: cards, deletedCards: deleted)
    }

    private nonisolated static func writeDatabase(_ database: CardDatabase, to directory: URL) throws {
        let cardsData = try CarryCardJSON.encoder.encode(database.cards)
        let deletedData = try CarryCardJSON.encoder.encode(database.deletedCards)
        try cardsData.write(to: directory.appendingPathComponent("cards.json"), options: .atomic)
        try deletedData.write(to: directory.appendingPathComponent("deleted.json"), options: .atomic)
    }

    private nonisolated static func readJSON<T: Decodable>(_ url: URL) -> T? {
        guard let data = try? Data(contentsOf: url), !data.isEmpty else { return nil }
        return try? CarryCardJSON.decoder.decode(T.self, from: data)
    }

    /// Copies any logo referenced by `cards` that exists in `source` but not yet
    /// in `destination`. Never deletes — sync only ever adds missing files.
    private nonisolated static func copyLogos(for cards: [LoyaltyCard], from source: URL, to destination: URL) {
        let fileManager = FileManager.default
        for card in cards {
            guard let fileName = card.logoFileName else { continue }
            let sourceURL = source.appendingPathComponent(fileName)
            let destinationURL = destination.appendingPathComponent(fileName)
            guard fileManager.fileExists(atPath: sourceURL.path),
                  !fileManager.fileExists(atPath: destinationURL.path) else { continue }
            try? fileManager.copyItem(at: sourceURL, to: destinationURL)
        }
    }

    private func persistState() {
        guard let data = try? CarryCardJSON.encoder.encode(state) else { return }
        defaults.set(data, forKey: stateKey)
    }
}
