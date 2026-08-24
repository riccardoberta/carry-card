import Foundation

/// A single loyalty card stored locally and, optionally, synchronized.
struct LoyaltyCard: Identifiable, Codable, Equatable, Hashable, Sendable {
    let id: UUID

    var name: String
    var code: String
    var barcodeType: BarcodeType

    var logoFileName: String?
    var backgroundColor: CodableColor?

    /// Controls display order in the wallet list. Lower values sort first.
    /// A `Double` lets a card be reordered between two neighbors without
    /// renumbering the whole collection.
    var sortIndex: Double

    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        code: String,
        barcodeType: BarcodeType,
        logoFileName: String? = nil,
        backgroundColor: CodableColor? = nil,
        sortIndex: Double = 0,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.code = code
        self.barcodeType = barcodeType
        self.logoFileName = logoFileName
        self.backgroundColor = backgroundColor
        self.sortIndex = sortIndex
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// Last four characters of the code, useful for a compact hint on the wallet card.
    var codeSuffix: String {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 4 else { return trimmed }
        return String(trimmed.suffix(4))
    }
}
