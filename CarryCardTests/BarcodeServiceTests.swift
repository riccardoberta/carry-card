import Testing
import CoreGraphics
@testable import CarryCard

struct BarcodeServiceTests {
    private let service: BarcodeGenerating = BarcodeService()
    private let targetSize = CGSize(width: 600, height: 200)

    @Test(arguments: [
        ("6291041500213", BarcodeType.ean13),
        ("1234567", BarcodeType.ean8),
        ("425261", BarcodeType.upce),
        ("ABC-123", BarcodeType.code39),
        ("TEST93", BarcodeType.code93),
        ("0123456789", BarcodeType.code128),
        ("https://example.com/loyalty/1", BarcodeType.qr),
        ("SAMPLE PDF417 DATA", BarcodeType.pdf417),
        ("SAMPLE AZTEC DATA", BarcodeType.aztec)
    ])
    func generatesAnImageForEachSupportedType(value: String, type: BarcodeType) {
        let image = service.generate(value: value, type: type, targetSize: targetSize)
        #expect(image != nil)
    }

    @Test func returnsNilForEmptyValue() {
        let image = service.generate(value: "", type: .code128, targetSize: targetSize)
        #expect(image == nil)
    }

    @Test func returnsNilForInvalidEAN13Value() {
        let image = service.generate(value: "not-digits", type: .ean13, targetSize: targetSize)
        #expect(image == nil)
    }

    @Test func returnsNilForDegenerateTargetSize() {
        let image = service.generate(value: "123456789012", type: .ean13, targetSize: .zero)
        #expect(image == nil)
    }
}
