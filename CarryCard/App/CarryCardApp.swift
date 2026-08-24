import SwiftUI

@main
struct CarryCardApp: App {
    @StateObject private var listViewModel: CardListViewModel
    @StateObject private var syncService: SyncService

    init() {
        let cardStore = CardStore()
        let folderManager = SyncFolderManager()
        let sync = SyncService(cardStore: cardStore, folderManager: folderManager)
        let imageStore = ImageStore(directoryURL: cardStore.logosDirectoryURL)

        _syncService = StateObject(wrappedValue: sync)
        _listViewModel = StateObject(wrappedValue: CardListViewModel(cardStore: cardStore, imageStore: imageStore, syncService: sync))
    }

    var body: some Scene {
        WindowGroup {
            CardListView()
                .environmentObject(listViewModel)
                .environmentObject(syncService)
        }
    }
}
