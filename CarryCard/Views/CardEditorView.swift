import PhotosUI
import SwiftUI
import UIKit

/// The add/edit card workflow: `+ -> Scan barcode -> Enter merchant -> Choose logo -> Save`.
/// Every field captured by the scanner remains editable afterwards.
struct CardEditorView: View {
    @EnvironmentObject private var listViewModel: CardListViewModel
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: CardEditorViewModel

    @State private var showingScanner: Bool
    @State private var photosPickerItem: PhotosPickerItem?
    @State private var showingCamera = false

    init(existingCard: LoyaltyCard?, imageStore: ImageStore) {
        // New cards open straight into the scanner, per the preferred workflow;
        // editing an existing card opens directly on the form.
        _showingScanner = State(initialValue: existingCard == nil)
        _viewModel = StateObject(wrappedValue: CardEditorViewModel(existingCard: existingCard, imageStore: imageStore))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Spacer()
                        logoPicker
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                }

                Section("Merchant") {
                    TextField("Merchant name", text: $viewModel.name)
                        .textInputAutocapitalization(.words)
                }

                Section("Loyalty Code") {
                    TextField("Code", text: $viewModel.code)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.system(.body, design: .monospaced))
                    Picker("Barcode Type", selection: $viewModel.barcodeType) {
                        ForEach(BarcodeType.allCases) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                    Button {
                        showingScanner = true
                    } label: {
                        Label("Scan Barcode", systemImage: "barcode.viewfinder")
                    }
                }

                Section("Color") {
                    colorSwatches
                }

                if let existingCard = viewModel.existingCard {
                    Section {
                        Button("Delete Card", role: .destructive) {
                            Task {
                                await listViewModel.delete(existingCard)
                                dismiss()
                            }
                        }
                    }
                }
            }
            .navigationTitle(viewModel.isEditingExistingCard ? "Edit Card" : "New Card")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                        .disabled(!viewModel.isValid || viewModel.isSaving)
                }
            }
            .alert("Couldn't Save Card", isPresented: showsValidationAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(viewModel.validationMessage ?? "")
            }
            .sheet(isPresented: $showingScanner) {
                BarcodeScannerView { scanned in
                    viewModel.applyScannedBarcode(scanned)
                    showingScanner = false
                }
            }
            .fullScreenCover(isPresented: $showingCamera) {
                CameraCaptureView { image in
                    if let image { viewModel.setLogo(image) }
                    showingCamera = false
                }
            }
        }
    }

    private var showsValidationAlert: Binding<Bool> {
        Binding(
            get: { viewModel.validationMessage != nil },
            set: { if !$0 { viewModel.validationMessage = nil } }
        )
    }

    private var logoPicker: some View {
        Menu {
            PhotosPicker("Choose from Library", selection: $photosPickerItem, matching: .images)
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button {
                    showingCamera = true
                } label: {
                    Label("Take Photo", systemImage: "camera")
                }
            }
            if viewModel.logoImage != nil || viewModel.initialLogoFileName != nil {
                Button("Remove Logo", role: .destructive) { viewModel.setLogo(nil) }
            }
        } label: {
            logoThumbnail
        }
        .onChange(of: photosPickerItem) { _, newItem in
            Task {
                if let data = try? await newItem?.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    viewModel.setLogo(image)
                }
            }
        }
        .accessibilityLabel("Choose logo")
        .accessibilityHint("Opens options to choose or take a merchant logo photo.")
    }

    private var logoThumbnail: some View {
        ZStack(alignment: .bottomTrailing) {
            if let logoImage = viewModel.logoImage {
                Image(uiImage: logoImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 96, height: 96)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            } else {
                LogoView(
                    imageStore: listViewModel.imageStore,
                    fileName: viewModel.initialLogoFileName,
                    merchantName: viewModel.name.isEmpty ? "?" : viewModel.name,
                    size: 96
                )
                .background(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(viewModel.backgroundColor.color)
                )
            }
            Image(systemName: "pencil.circle.fill")
                .font(.title2)
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, .blue)
                .background(Circle().fill(.white))
                .offset(x: 4, y: 4)
        }
        .frame(width: 96, height: 96)
    }

    private var colorSwatches: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 8), spacing: 12) {
            ForEach(Array(CodableColor.defaultPalette.enumerated()), id: \.offset) { _, swatch in
                Button {
                    viewModel.setBackgroundColor(swatch)
                } label: {
                    Circle()
                        .fill(swatch.color)
                        .frame(width: 32, height: 32)
                        .overlay {
                            if swatch == viewModel.backgroundColor {
                                Image(systemName: "checkmark")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.white)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Color swatch")
                .accessibilityAddTraits(swatch == viewModel.backgroundColor ? [.isSelected] : [])
            }
        }
        .padding(.vertical, 4)
    }

    private func save() async {
        if let card = await viewModel.buildCardForSaving() {
            await listViewModel.save(card)
            dismiss()
        }
    }
}

#Preview {
    CardEditorView(existingCard: nil, imageStore: PreviewData.imageStore)
        .environmentObject(PreviewData.listViewModel)
}
