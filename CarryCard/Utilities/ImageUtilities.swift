import UIKit
import CoreImage

/// Image resizing/compression helpers used when saving a user-picked logo,
/// and pixel-preserving scaling used when rendering barcodes.
enum ImageUtilities {
    /// Maximum edge length for a stored logo. Keeps files small while remaining
    /// crisp on any device screen.
    static let maxLogoDimension: CGFloat = 512

    /// Resizes `image` so its longest edge is at most `maxLogoDimension`,
    /// preserving aspect ratio. Images already smaller are returned unchanged.
    static func resizedForLogo(_ image: UIImage) -> UIImage {
        let size = image.size
        let longestEdge = max(size.width, size.height)
        guard longestEdge > maxLogoDimension, longestEdge > 0 else { return image }

        let scale = maxLogoDimension / longestEdge
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }

    /// JPEG-compresses `image` at a sensible quality for a small logo asset.
    static func jpegData(from image: UIImage, quality: CGFloat = 0.85) -> Data? {
        image.jpegData(compressionQuality: quality)
    }

    /// Scales a barcode `CIImage` up by an integer factor using nearest-neighbor
    /// sampling so bar edges stay perfectly sharp (no blur/interpolation),
    /// which matters for reliable scanning by retail barcode readers.
    static func nearestNeighborScaled(_ image: CIImage, scale: CGFloat) -> CIImage {
        image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
    }
}
