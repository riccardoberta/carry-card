import Foundation

/// Coarse status of the most recent (or in-progress) synchronization,
/// surfaced in Settings. Never blocks card usage.
enum SyncStatusKind: String, Codable, Sendable {
    case neverSynced
    case syncing
    case success
    case failure
}

/// Persisted, user-visible synchronization state. This is intentionally
/// separate from the security-scoped bookmark data owned by `SyncFolderManager` —
/// the rest of the app should only ever need this lightweight summary.
struct SyncState: Codable, Equatable, Sendable {
    var isEnabled: Bool
    var folderDisplayName: String?
    var lastSuccessfulSyncAt: Date?
    var status: SyncStatusKind
    var lastErrorMessage: String?

    static let disabled = SyncState(
        isEnabled: false,
        folderDisplayName: nil,
        lastSuccessfulSyncAt: nil,
        status: .neverSynced,
        lastErrorMessage: nil
    )
}
