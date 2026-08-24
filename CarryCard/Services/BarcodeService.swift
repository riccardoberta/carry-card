import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit

/// Renders a loyalty-card code into a scannable barcode image for a given symbology.
protocol BarcodeGenerating {
    func generate(value: String, type: BarcodeType, targetSize: CGSize) -> UIImage?
}

/// Generates barcode images from a stored code value. QR, Code 128, PDF417 and
/// Aztec are produced with Core Image's built-in generators; EAN-13, EAN-8, UPC-E,
/// Code 39 and Code 93 (which Core Image cannot generate) are rendered from an
/// explicit module pattern via `OneDBarcodeEncoder`.
///
/// All output is scaled using nearest-neighbor sampling only (`interpolationQuality
/// = .none`), never smoothed, so bar edges stay sharp for retail scanners.
final class BarcodeService: BarcodeGenerating {
    private let context = CIContext()

    func generate(value: String, type: BarcodeType, targetSize: CGSize) -> UIImage? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, targetSize.width > 1, targetSize.height > 1 else { return nil }

        switch type {
        case .qr, .code128, .pdf417, .aztec:
            return generateWithCoreImage(value: trimmed, type: type, targetSize: targetSize)
        case .ean8, .ean13, .upce, .code39, .code93:
            return generateFromModulePattern(value: trimmed, type: type, targetSize: targetSize)
        }
    }

    // MARK: - Core Image backed symbologies

    private func generateWithCoreImage(value: String, type: BarcodeType, targetSize: CGSize) -> UIImage? {
        guard let data = value.data(using: .isoLatin1) ?? value.data(using: .utf8) else { return nil }

        let outputImage: CIImage?
        switch type {
        case .qr:
            let filter = CIFilter.qrCodeGenerator()
            filter.message = data
            filter.correctionLevel = "M"
            outputImage = filter.outputImage
        case .code128:
            let filter = CIFilter.code128BarcodeGenerator()
            filter.message = data
            filter.quietSpace = 6
            outputImage = filter.outputImage
        case .pdf417:
            let filter = CIFilter.pdf417BarcodeGenerator()
            filter.message = data
            outputImage = filter.outputImage
        case .aztec:
            let filter = CIFilter.aztecCodeGenerator()
            filter.message = data
            filter.correctionLevel = 23
            outputImage = filter.outputImage
        default:
            outputImage = nil
        }

        guard let ciImage = outputImage else { return nil }
        let extent = ciImage.extent
        guard extent.width > 0, extent.height > 0, extent.width.isFinite, extent.height.isFinite else { return nil }
        guard let smallCGImage = context.createCGImage(ciImage, from: extent) else { return nil }

        let scaleX = max(1, Int(targetSize.width / extent.width))
        let scaleY = max(1, Int(targetSize.height / extent.height))
        let scale = max(1, min(scaleX, scaleY))
        let finalSize = CGSize(width: extent.width * CGFloat(scale), height: extent.height * CGFloat(scale))

        return Self.renderCrisp(cgImage: smallCGImage, size: finalSize)
    }

    // MARK: - Custom module-pattern symbologies

    private func generateFromModulePattern(value: String, type: BarcodeType, targetSize: CGSize) -> UIImage? {
        let pattern: String
        do {
            switch type {
            case .ean13: pattern = try OneDBarcodeEncoder.ean13Pattern(value: value)
            case .ean8: pattern = try OneDBarcodeEncoder.ean8Pattern(value: value)
            case .upce: pattern = try OneDBarcodeEncoder.upceePattern(value: value)
            case .code39: pattern = try OneDBarcodeEncoder.code39Pattern(value: value)
            case .code93: pattern = try OneDBarcodeEncoder.code93Pattern(value: value)
            default: return nil
            }
        } catch {
            return nil
        }

        let quietZoneModules = 10
        let totalModules = pattern.count + quietZoneModules * 2
        let modulePixelWidth = max(1, Int(targetSize.width) / totalModules)
        let width = modulePixelWidth * totalModules
        let height = max(1, Int(targetSize.height))

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format)

        return renderer.image { context in
            let cg = context.cgContext
            cg.interpolationQuality = .none
            cg.setFillColor(UIColor.white.cgColor)
            cg.fill(CGRect(x: 0, y: 0, width: width, height: height))
            cg.setFillColor(UIColor.black.cgColor)
            for (index, module) in pattern.enumerated() where module == "1" {
                let x = (quietZoneModules + index) * modulePixelWidth
                cg.fill(CGRect(x: x, y: 0, width: modulePixelWidth, height: height))
            }
        }
    }

    // MARK: - Shared crisp scaling

    private static func renderCrisp(cgImage: CGImage, size: CGSize) -> UIImage? {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { context in
            let cg = context.cgContext
            cg.interpolationQuality = .none
            cg.setFillColor(UIColor.white.cgColor)
            cg.fill(CGRect(origin: .zero, size: size))
            cg.draw(cgImage, in: CGRect(origin: .zero, size: size))
        }
    }
}
