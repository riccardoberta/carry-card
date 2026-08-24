import Foundation

/// Fictional sample data for SwiftUI previews only. No real corporate names or logos.
enum PreviewData {
    static let sampleCards: [LoyaltyCard] = [
        LoyaltyCard(
            name: "North Market",
            code: "6291041500213",
            barcodeType: .ean13,
            backgroundColor: CodableColor.defaultPalette[1],
            sortIndex: 0
        ),
        LoyaltyCard(
            name: "Daily Club",
            code: "0123456789",
            barcodeType: .code128,
            backgroundColor: CodableColor.defaultPalette[0],
            sortIndex: 1
        ),
        LoyaltyCard(
            name: "Green Store",
            code: "ABCD1234",
            barcodeType: .code39,
            backgroundColor: CodableColor.defaultPalette[2],
            sortIndex: 2
        ),
        LoyaltyCard(
            name: "Cinema Plus",
            code: "https://example.com/loyalty/998877",
            barcodeType: .qr,
            backgroundColor: CodableColor.defaultPalette[4],
            sortIndex: 3
        )
    ]

    /// A throwaway `ImageStore` pointing at a temporary directory, for previews only.
    static let imageStore = ImageStore(directoryURL: FileManager.default.temporaryDirectory.appendingPathComponent("CarryCardPreviewLogos"))

    @MainActor
    static var listViewModel: CardListViewModel {
        let cardStore = CardStore()
        let folderManager = SyncFolderManager(defaults: UserDefaults(suiteName: "preview") ?? .standard)
        let syncService = SyncService(cardStore: cardStore, folderManager: folderManager)
        let viewModel = CardListViewModel(cardStore: cardStore, imageStore: imageStore, syncService: syncService)
        return viewModel
    }
}
