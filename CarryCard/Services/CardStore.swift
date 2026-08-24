import Foundation

/// Owns the local on-device database: `cards.json`, `deleted.json` and the
/// `logos/` folder inside Application Support. All file I/O happens off the
/// main actor. Writes are atomic so an interrupted write can never corrupt the
/// previously-saved database; a corrupted file on read is quarantined (renamed
/// aside) rather than crashing the app or silently discarding local data.
actor CardStore {
    nonisolated let directoryURL: URL
    nonisolated let logosDirectoryURL: URL
    private let cardsURL: URL
    private let deletedURL: URL
    private let fileManager = FileManager.default

    /// `baseDirectory` defaults to the app's Application Support directory;
    /// tests inject a temporary directory instead so runs never touch real data.
    init(baseDirectory: URL? = nil) {
        let appSupport = baseDirectory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        directoryURL = appSupport.appendingPathComponent("CarryCardData", isDirectory: true)
        cardsURL = directoryURL.appendingPathComponent("cards.json")
        deletedURL = directoryURL.appendingPathComponent("deleted.json")
        logosDirectoryURL = directoryURL.appendingPathComponent("logos", isDirectory: true)
        try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: logosDirectoryURL, withIntermediateDirectories: true)
    }

    func load() -> CardDatabase {
        let cards: [LoyaltyCard] = decodeOrQuarantine(from: cardsURL) ?? []
        let deleted: [DeletedCard] = decodeOrQuarantine(from: deletedURL) ?? []
        return CardDatabase(cards: cards, deletedCards: deleted)
    }

    func save(_ database: CardDatabase) throws {
        try writeAtomically(database.cards, to: cardsURL)
        try writeAtomically(database.deletedCards, to: deletedURL)
    }

    private func decodeOrQuarantine<T: Decodable>(from url: URL) -> T? {
        guard let data = try? Data(contentsOf: url), !data.isEmpty else { return nil }
        do {
            return try CarryCardJSON.decoder.decode(T.self, from: data)
        } catch {
            let quarantineURL = url.deletingPathExtension()
                .appendingPathExtension("corrupted-\(Int(Date().timeIntervalSince1970)).json")
            try? fileManager.moveItem(at: url, to: quarantineURL)
            return nil
        }
    }

    private func writeAtomically<T: Encodable>(_ value: T, to url: URL) throws {
        let data = try CarryCardJSON.encoder.encode(value)
        try data.write(to: url, options: .atomic)
    }
}
