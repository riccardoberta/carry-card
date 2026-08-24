import UIKit

/// Transient state for the add/edit card form. Builds a `LoyaltyCard` on save,
/// handling logo persistence (a picked image is saved as a separate file, never
/// embedded in the card record) but leaving the actual database write to
/// `CardListViewModel`.
@MainActor
final class CardEditorViewModel: ObservableObject {
    @Published var name: String
    @Published var code: String
    @Published var barcodeType: BarcodeType
    @Published var backgroundColor: CodableColor
    @Published var logoImage: UIImage?
    @Published var isSaving = false
    @Published var validationMessage: String?

    let isEditingExistingCard: Bool
    let existingCard: LoyaltyCard?
    var initialLogoFileName: String? { existingCard?.logoFileName }

    private let imageStore: ImageStore
    private var existingLogoFileName: String?
    private var logoWasCleared = false
    private var colorWasManuallySet: Bool

    init(existingCard: LoyaltyCard?, imageStore: ImageStore) {
        self.existingCard = existingCard
        self.isEditingExistingCard = existingCard != nil
        self.imageStore = imageStore
        self.name = existingCard?.name ?? ""
        self.code = existingCard?.code ?? ""
        self.barcodeType = existingCard?.barcodeType ?? .code128
        self.backgroundColor = existingCard?.backgroundColor ?? CodableColor.defaultPalette[0]
        self.existingLogoFileName = existingCard?.logoFileName
        self.colorWasManuallySet = existingCard?.backgroundColor != nil
    }

    var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func applyScannedBarcode(_ scanned: ScannedBarcode) {
        code = scanned.value
        barcodeType = scanned.type
    }

    func setBackgroundColor(_ color: CodableColor) {
        backgroundColor = color
        colorWasManuallySet = true
    }

    func setLogo(_ image: UIImage?) {
        logoImage = image
        logoWasCleared = (image == nil)
    }

    /// Persists a picked logo (if any) and returns the card to save, or `nil` if
    /// the form is invalid or the logo couldn't be written to disk.
    func buildCardForSaving() async -> LoyaltyCard? {
        guard isValid else {
            validationMessage = "Enter a merchant name and a code."
            return nil
        }
        isSaving = true
        defer { isSaving = false }

        var logoFileName = existingLogoFileName
        if let logoImage {
            do {
                logoFileName = try await imageStore.saveLogo(logoImage)
                if let old = existingLogoFileName, old != logoFileName {
                    await imageStore.deleteLogo(fileName: old)
                }
            } catch {
                validationMessage = "The logo image couldn't be saved."
                return nil
            }
        } else if logoWasCleared {
            if let old = existingLogoFileName {
                await imageStore.deleteLogo(fileName: old)
            }
            logoFileName = nil
        }

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCode = code.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalColor = colorWasManuallySet ? backgroundColor : CodableColor.derived(from: trimmedName)

        if var updated = existingCard {
            updated.name = trimmedName
            updated.code = trimmedCode
            updated.barcodeType = barcodeType
            updated.logoFileName = logoFileName
            updated.backgroundColor = finalColor
            return updated
        }

        return LoyaltyCard(
            name: trimmedName,
            code: trimmedCode,
            barcodeType: barcodeType,
            logoFileName: logoFileName,
            backgroundColor: finalColor
        )
    }
}
