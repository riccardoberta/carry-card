import Testing
import Foundation
@testable import CarryCard

struct SyncFolderManagerTests {
    private func makeManager() -> SyncFolderManager {
        let suiteName = "SyncFolderManagerTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        return SyncFolderManager(defaults: defaults)
    }

    private func makeTemporaryFolder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func noFolderSelectedInitially() {
        let manager = makeManager()
        #expect(manager.isConfigured == false)
        #expect(manager.folderDisplayName == nil)
    }

    @Test func withAccessibleFolderThrowsWhenNothingSelected() {
        let manager = makeManager()
        #expect(throws: SyncFolderManager.ManagerError.self) {
            try manager.withAccessibleFolder { _ in }
        }
    }

    @Test func savingAndResolvingFolderRoundTrips() throws {
        let manager = makeManager()
        let folder = try makeTemporaryFolder()

        try manager.saveFolder(folder)
        #expect(manager.isConfigured)
        #expect(manager.folderDisplayName == folder.lastPathComponent)

        let resolvedPath = try manager.withAccessibleFolder { url in url.path }
        #expect(resolvedPath == folder.path)
    }

    @Test func disconnectClearsConfiguration() throws {
        let manager = makeManager()
        let folder = try makeTemporaryFolder()
        try manager.saveFolder(folder)

        manager.disconnect()

        #expect(manager.isConfigured == false)
        #expect(throws: SyncFolderManager.ManagerError.self) {
            try manager.withAccessibleFolder { _ in }
        }
    }
}
