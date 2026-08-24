import UIKit

/// Manages logo image files on disk for a given directory (the local `logos/`
/// folder, or the equivalent folder inside the sync destination). Images are
/// resized, compressed and stored as separate files — never embedded as raw
/// data inside the JSON database.
actor ImageStore {
    let directoryURL: URL
    private let fileManager = FileManager.default

    init(directoryURL: URL) {
        self.directoryURL = directoryURL
        try? fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    }

    /// Resizes, compresses and saves `image`, returning the generated file name.
    @discardableResult
    func saveLogo(_ image: UIImage, preferredID: UUID = UUID()) throws -> String {
        let resized = ImageUtilities.resizedForLogo(image)
        guard let data = ImageUtilities.jpegData(from: resized) else {
            throw ImageStoreError.encodingFailed
        }
        let fileName = "\(preferredID.uuidString).jpg"
        let url = directoryURL.appendingPathComponent(fileName)
        try data.write(to: url, options: .atomic)
        return fileName
    }

    func loadImageData(fileName: String) -> Data? {
        let url = directoryURL.appendingPathComponent(fileName)
        return try? Data(contentsOf: url)
    }

    func deleteLogo(fileName: String) {
        let url = directoryURL.appendingPathComponent(fileName)
        try? fileManager.removeItem(at: url)
    }

    /// All logo file names currently present in this directory.
    func allFileNames() -> Set<String> {
        let names = try? fileManager.contentsOfDirectory(atPath: directoryURL.path)
        return Set(names ?? [])
    }
}

enum ImageStoreError: Error {
    case encodingFailed
}
