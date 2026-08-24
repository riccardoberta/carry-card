import Foundation

/// Barcode symbologies Carry-Card can scan and/or render.
enum BarcodeType: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case ean8
    case ean13
    case upce
    case code39
    case code93
    case code128
    case qr
    case pdf417
    case aztec

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .ean8: return "EAN-8"
        case .ean13: return "EAN-13"
        case .upce: return "UPC-E"
        case .code39: return "Code 39"
        case .code93: return "Code 93"
        case .code128: return "Code 128"
        case .qr: return "QR Code"
        case .pdf417: return "PDF417"
        case .aztec: return "Aztec"
        }
    }

    /// Whether `BarcodeService` can render this symbology.
    /// All cases are supported today: QR/PDF417/Aztec via Core Image,
    /// and the 1D symbologies via a dedicated pattern-table renderer.
    var isRenderingSupported: Bool { true }
}
