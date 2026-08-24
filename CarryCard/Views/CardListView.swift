import SwiftUI

/// The main screen: "open the app, immediately see your loyalty cards."
struct CardListView: View {
    @EnvironmentObject private var viewModel: CardListViewModel
    @Environment(\.scenePhase) private var scenePhase

    @State private var showingEditor = false
    @State private var showingSettings = false
    @State private var selectedCard: LoyaltyCard?
    @State private var pendingDeletion: LoyaltyCard?

    private let gridColumns = [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoaded && viewModel.cards.isEmpty {
                    emptyState
                } else {
                    cardList
                }
            }
            .navigationTitle("Carry-Card")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showingSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Settings")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingEditor = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                    }
                    .accessibilityLabel("Add card")
                }
            }
            .navigationDestination(item: $selectedCard) { card in
                CardDetailView(card: card)
            }
            .sheet(isPresented: $showingEditor) {
                CardEditorView(existingCard: nil, imageStore: viewModel.imageStore)
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
            }
            .confirmationDialog(
                "Delete this card?",
                isPresented: Binding(
                    get: { pendingDeletion != nil },
                    set: { if !$0 { pendingDeletion = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    if let card = pendingDeletion {
                        Task { await viewModel.delete(card) }
                    }
                    pendingDeletion = nil
                }
                Button("Cancel", role: .cancel) { pendingDeletion = nil }
            } message: {
                if let name = pendingDeletion?.name {
                    Text("\"\(name)\" will be removed from all your synced devices.")
                }
            }
        }
        .task { await viewModel.loadCards() }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                Task { await viewModel.syncAndReload() }
            }
        }
    }

    private var cardList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if let featured = viewModel.featuredCard {
                    Button {
                        selectedCard = featured
                    } label: {
                        CardRowView(card: featured, imageStore: viewModel.imageStore, style: .featured)
                    }
                    .buttonStyle(.plain)
                }

                LazyVGrid(columns: gridColumns, spacing: 14) {
                    ForEach(viewModel.cards) { card in
                        Button {
                            selectedCard = card
                        } label: {
                            CardRowView(card: card, imageStore: viewModel.imageStore, style: .grid)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button(role: .destructive) {
                                pendingDeletion = card
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        .draggable(card.id.uuidString) {
                            CardRowView(card: card, imageStore: viewModel.imageStore, style: .grid)
                                .frame(width: 160)
                        }
                        .dropDestination(for: String.self) { droppedIDs, _ in
                            handleDrop(droppedIDs, onto: card)
                        }
                    }
                }
            }
            .padding(.horizontal)
            .padding(.top, 4)
            .padding(.bottom, 24)
        }
        .refreshable {
            await viewModel.syncAndReload()
        }
    }

    private func handleDrop(_ droppedIDStrings: [String], onto targetCard: LoyaltyCard) -> Bool {
        guard let draggedIDString = droppedIDStrings.first,
              let draggedID = UUID(uuidString: draggedIDString),
              draggedID != targetCard.id,
              let fromIndex = viewModel.cards.firstIndex(where: { $0.id == draggedID }),
              let toIndex = viewModel.cards.firstIndex(where: { $0.id == targetCard.id })
        else { return false }

        let destination = toIndex > fromIndex ? toIndex + 1 : toIndex
        Task { await viewModel.move(fromOffsets: IndexSet(integer: fromIndex), toOffset: destination) }
        return true
    }

    private var emptyState: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "wallet.pass")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)
            Text("No cards yet")
                .font(.title2.weight(.semibold))
            Text("Add your loyalty cards to keep them all in one place.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Button {
                showingEditor = true
            } label: {
                Label("Add Your First Card", systemImage: "plus")
                    .fontWeight(.semibold)
                    .padding(.horizontal, 8)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.top, 6)
            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    CardListView()
        .environmentObject(PreviewData.listViewModel)
}
