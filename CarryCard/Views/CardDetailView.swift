import SwiftUI

/// Shows the merchant, a high-contrast barcode ready to scan, and the
/// human-readable code. While this screen is visible, screen brightness is
/// raised so retail scanners can read the barcode reliably; the previous
/// brightness is restored on exit.
struct CardDetailView: View {
    let card: LoyaltyCard

    @EnvironmentObject private var viewModel: CardListViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var showingEditor = false
    @State private var showingDeleteConfirmation = false
    @State private var barcodeImage: UIImage?
    @State private var previousBrightness: CGFloat?

    private let barcodeService: BarcodeGenerating = BarcodeService()

    private var currentCard: LoyaltyCard {
        viewModel.cards.first(where: { $0.id == card.id }) ?? card
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                header
                barcodeSection
                Text(currentCard.code)
                    .font(.system(.title3, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)
            .padding(.bottom, 40)
        }
        .navigationTitle(currentCard.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Edit") { showingEditor = true }
            }
            ToolbarItem(placement: .bottomBar) {
                Button(role: .destructive) {
                    showingDeleteConfirmation = true
                } label: {
                    Label("Delete Card", systemImage: "trash")
                }
            }
        }
        .sheet(isPresented: $showingEditor) {
            CardEditorView(existingCard: currentCard, imageStore: viewModel.imageStore)
        }
        .confirmationDialog(
            "Delete \(currentCard.name)?",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                Task {
                    await viewModel.delete(currentCard)
                    dismiss()
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .onAppear { raiseBrightness() }
        .onDisappear { restoreBrightness() }
        .task(id: currentCard.code + currentCard.barcodeType.rawValue) { renderBarcode() }
    }

    private var header: some View {
        VStack(spacing: 12) {
            LogoView(imageStore: viewModel.imageStore, fileName: currentCard.logoFileName, merchantName: currentCard.name, size: 72)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill((currentCard.backgroundColor ?? CodableColor.derived(from: currentCard.name)).color)
                )
            Text(currentCard.name)
                .font(.title2.weight(.semibold))
        }
    }

    private var barcodeSection: some View {
        Group {
            if let barcodeImage {
                Image(uiImage: barcodeImage)
                    .interpolation(.none)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(.secondarySystemBackground))
                    .frame(height: 160)
                    .overlay {
                        Text("This barcode type couldn't be rendered.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding()
                    }
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.white))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loyalty card barcode, number \(currentCard.code)")
    }

    private func renderBarcode() {
        let targetSize = CGSize(width: 900, height: 320)
        barcodeImage = barcodeService.generate(value: currentCard.code, type: currentCard.barcodeType, targetSize: targetSize)
    }

    private func raiseBrightness() {
        previousBrightness = UIScreen.main.brightness
        UIScreen.main.brightness = max(UIScreen.main.brightness, 0.9)
    }

    private func restoreBrightness() {
        if let previousBrightness {
            UIScreen.main.brightness = previousBrightness
        }
    }
}

#Preview {
    NavigationStack {
        CardDetailView(card: PreviewData.sampleCards[0])
            .environmentObject(PreviewData.listViewModel)
    }
}
