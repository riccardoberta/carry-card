import SwiftUI

/// The main screen: "open the app, immediately see your loyalty cards."
struct CardListView: View {
    @EnvironmentObject private var viewModel: CardListViewModel
    @Environment(\.scenePhase) private var scenePhase

    @State private var showingEditor = false
    @State private var showingSettings = false
    @State private var selectedCard: LoyaltyCard?
    @State private var pendingDeletion: LoyaltyCard?

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
                ToolbarItemGroup(placement: .topBarLeading) {
                    Button {
                        showingSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Settings")

                    if !viewModel.cards.isEmpty {
                        EditButton()
                    }
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
                Task { await viewModel.syncService.sync() }
            }
        }
    }

    private var cardList: some View {
        List {
            ForEach(viewModel.cards) { card in
                Button {
                    selectedCard = card
                } label: {
                    CardRowView(card: card, imageStore: viewModel.imageStore)
                }
                .buttonStyle(.plain)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        pendingDeletion = card
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
            .onMove { source, destination in
                Task { await viewModel.move(fromOffsets: source, toOffset: destination) }
            }
            .onDelete { offsets in
                if let index = offsets.first {
                    pendingDeletion = viewModel.cards[index]
                }
            }
        }
        .listStyle(.plain)
        .listRowSpacing(-36)
        .scrollContentBackground(.hidden)
        .padding(.top, 4)
        .refreshable {
            await viewModel.syncService.sync()
            await viewModel.loadCards()
        }
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
