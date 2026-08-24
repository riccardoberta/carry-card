import Foundation

/// Abstracts folder selection and persistent access to an arbitrary, user-chosen
/// folder exposed through the iOS Files app — iCloud Drive, a local File Provider,
/// or a third-party provider such as Google Drive's Files integration. The rest of
/// the app only ever sees a plain, already-accessible `URL`; it never needs to know
/// which provider is behind it.
///
/// iOS (unlike macOS) has no `.withSecurityScope` bookmark option: a bookmark
/// created from a URL handed out by `UIDocumentPickerViewController` is implicitly
/// security-scoped, and resolving it later yields a URL that must be bracketed
/// with `startAccessingSecurityScopedResource()` / `stopAccessingSecurityScopedResource()`.
/// `@unchecked Sendable`: the only mutable state is `UserDefaults`, which is
/// itself thread-safe; there is no other shared mutable state to race on. This
/// lets the manager be captured by the background task that performs sync I/O.
final class SyncFolderManager: @unchecked Sendable {
    enum ManagerError: Error, LocalizedError {
        case noFolderSelected
        case bookmarkResolutionFailed
        case accessDenied

        var errorDescription: String? {
            switch self {
            case .noFolderSelected: return "No sync folder is selected."
            case .bookmarkResolutionFailed: return "The sync folder could not be located. Choose it again in Settings."
            case .accessDenied: return "Carry-Card doesn't have permission to access the sync folder."
            }
        }
    }

    private let bookmarkKey = "app.carrycard.syncFolderBookmark"
    private let displayNameKey = "app.carrycard.syncFolderDisplayName"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var isConfigured: Bool { defaults.data(forKey: bookmarkKey) != nil }

    var folderDisplayName: String? { defaults.string(forKey: displayNameKey) }

    /// Stores persistent access to a folder URL obtained from the document picker.
    func saveFolder(_ url: URL) throws {
        let didStart = url.startAccessingSecurityScopedResource()
        defer { if didStart { url.stopAccessingSecurityScopedResource() } }

        guard let bookmarkData = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) else {
            throw ManagerError.bookmarkResolutionFailed
        }
        defaults.set(bookmarkData, forKey: bookmarkKey)
        defaults.set(url.lastPathComponent, forKey: displayNameKey)
    }

    /// Forgets the selected folder. The app continues to work as local-only.
    func disconnect() {
        defaults.removeObject(forKey: bookmarkKey)
        defaults.removeObject(forKey: displayNameKey)
    }

    /// Resolves the stored bookmark and runs `body` with security-scoped access
    /// active for its duration, refreshing the bookmark transparently if it was
    /// stale. Access is always released before returning, even if `body` throws.
    func withAccessibleFolder<T>(_ body: (URL) throws -> T) throws -> T {
        guard let bookmarkData = defaults.data(forKey: bookmarkKey) else {
            throw ManagerError.noFolderSelected
        }

        var isStale = false
        let url: URL
        do {
            url = try URL(
                resolvingBookmarkData: bookmarkData,
                options: [],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
        } catch {
            throw ManagerError.bookmarkResolutionFailed
        }

        guard url.startAccessingSecurityScopedResource() else {
            throw ManagerError.accessDenied
        }
        defer { url.stopAccessingSecurityScopedResource() }

        if isStale, let refreshedBookmark = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) {
            defaults.set(refreshedBookmark, forKey: bookmarkKey)
        }
        defaults.set(url.lastPathComponent, forKey: displayNameKey)

        return try body(url)
    }
}
