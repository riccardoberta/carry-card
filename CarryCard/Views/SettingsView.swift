import SwiftUI
import UniformTypeIdentifiers

/// Minimal settings screen. Synchronization is entirely optional — with no
/// folder selected, Carry-Card simply works as a local-only app.
struct SettingsView: View {
    @EnvironmentObject private var syncService: SyncService
    @Environment(\.dismiss) private var dismiss

    @State private var showingFolderPicker = false
    @State private var showingDisconnectConfirmation = false
    @State private var isSyncing = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Carry-Card stores every loyalty card on this device and works fully offline.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Synchronization") {
                    LabeledContent("Status") {
                        statusLabel
                    }

                    if syncService.state.isEnabled {
                        LabeledContent("Folder", value: syncService.state.folderDisplayName ?? "—")

                        if let lastSync = syncService.state.lastSuccessfulSyncAt {
                            LabeledContent("Last Synced", value: lastSync.formatted(date: .abbreviated, time: .shortened))
                        }

                        if let error = syncService.state.lastErrorMessage {
                            Label(error, systemImage: "exclamationmark.triangle.fill")
                                .font(.footnote)
                                .foregroundStyle(.orange)
                        }

                        Button {
                            Task {
                                isSyncing = true
                                await syncService.sync()
                                isSyncing = false
                            }
                        } label: {
                            if isSyncing {
                                ProgressView()
                            } else {
                                Label("Sync Now", systemImage: "arrow.triangle.2.circlepath")
                            }
                        }
                        .disabled(isSyncing)

                        Button("Change Sync Folder") { showingFolderPicker = true }

                        Button("Disconnect Sync Folder", role: .destructive) {
                            showingDisconnectConfirmation = true
                        }
                    } else {
                        Text("Choose a folder — such as one from iCloud Drive, Google Drive or another Files provider — to keep your cards in sync across devices.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)

                        Button("Choose Sync Folder") { showingFolderPicker = true }
                    }
                }

                Section("About") {
                    LabeledContent("Version", value: appVersion)
                    Text("Carry-Card collects no analytics and has no servers or accounts. Your cards never leave this device unless you choose a sync folder.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showingFolderPicker) {
                FolderPickerView { url in
                    guard let url else { return }
                    Task { await syncService.setFolder(url) }
                }
            }
            .confirmationDialog(
                "Disconnect Sync Folder?",
                isPresented: $showingDisconnectConfirmation,
                titleVisibility: .visible
            ) {
                Button("Disconnect", role: .destructive) { syncService.disconnect() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Your cards stay on this device. They just won't sync until you choose a folder again.")
            }
        }
    }

    @ViewBuilder
    private var statusLabel: some View {
        switch syncService.state.status {
        case .neverSynced:
            Text(syncService.state.isEnabled ? "Not yet synced" : "Off")
                .foregroundStyle(.secondary)
        case .syncing:
            Text("Syncing…").foregroundStyle(.secondary)
        case .success:
            Label("Up to date", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        case .failure:
            Label("Sync issue", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        }
    }

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
}

#Preview {
    SettingsView()
        .environmentObject(PreviewData.listViewModel.syncService)
}
