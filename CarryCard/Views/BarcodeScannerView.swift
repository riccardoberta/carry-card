import AVFoundation
import SwiftUI

/// Live camera barcode scanner. Detects a code once, stops scanning, and lets
/// the user confirm or edit the result before it's applied to the card form.
struct BarcodeScannerView: View {
    let onConfirm: (ScannedBarcode) -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var scannerService = BarcodeScannerService()

    @State private var authorizationStatus: AVAuthorizationStatus = BarcodeScannerService.currentAuthorizationStatus()
    @State private var configurationFailed = false
    @State private var editableValue = ""

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                switch authorizationStatus {
                case .authorized:
                    if configurationFailed {
                        statusMessage("Camera Unavailable", "Carry-Card couldn't start the camera on this device.")
                    } else {
                        cameraPreview
                    }
                case .denied, .restricted:
                    permissionDeniedView
                case .notDetermined:
                    ProgressView().tint(.white)
                @unknown default:
                    permissionDeniedView
                }

                if let detection = scannerService.lastDetection {
                    confirmationCard(for: detection)
                }
            }
            .navigationTitle("Scan Barcode")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .tint(.white)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enter Manually") { dismiss() }
                        .tint(.white)
                }
            }
        }
        .task { await prepareCameraIfNeeded() }
        .onDisappear { scannerService.stop() }
        .preferredColorScheme(.dark)
    }

    private var cameraPreview: some View {
        CameraPreviewRepresentable(session: scannerService.captureSession)
            .ignoresSafeArea()
            .accessibilityLabel("Camera viewfinder for scanning a barcode")
            .overlay(alignment: .top) {
                Text("Point the camera at a loyalty card barcode")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.black.opacity(0.55), in: Capsule())
                    .padding(.top, 24)
            }
    }

    private var permissionDeniedView: some View {
        statusMessage(
            "Camera Access Needed",
            "Carry-Card uses the camera only to scan loyalty-card barcodes. Enable camera access in Settings to scan, or enter the code manually."
        ) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private func statusMessage(_ title: String, _ message: String, @ViewBuilder actions: () -> some View = { EmptyView() }) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "camera.metering.unknown")
                .font(.system(size: 44))
                .foregroundStyle(.white.opacity(0.8))
            Text(title)
                .font(.headline)
                .foregroundStyle(.white)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.75))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            actions()
        }
    }

    private func confirmationCard(for detection: ScannedBarcode) -> some View {
        VStack {
            Spacer()
            VStack(spacing: 14) {
                Text(detection.type.displayName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                TextField("Code", text: $editableValue)
                    .font(.system(.title3, design: .monospaced))
                    .multilineTextAlignment(.center)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                HStack(spacing: 12) {
                    Button("Scan Again") {
                        editableValue = ""
                        scannerService.resetDetection()
                        scannerService.start()
                    }
                    .buttonStyle(.bordered)

                    Button("Use This Code") {
                        onConfirm(ScannedBarcode(value: editableValue, type: detection.type))
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(editableValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(20)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .padding()
        }
        .onAppear { editableValue = detection.value }
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .animation(.default, value: scannerService.lastDetection)
    }

    private func prepareCameraIfNeeded() async {
        let granted = await scannerService.requestCameraAccess()
        authorizationStatus = BarcodeScannerService.currentAuthorizationStatus()
        guard granted else { return }

        scannerService.configureSessionIfNeeded { result in
            Task { @MainActor in
                switch result {
                case .success:
                    scannerService.start()
                case .failure:
                    configurationFailed = true
                }
            }
        }
    }
}

/// Hosts an `AVCaptureVideoPreviewLayer` for the live camera feed.
private struct CameraPreviewRepresentable: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.videoPreviewLayer.session = session
        view.videoPreviewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var videoPreviewLayer: AVCaptureVideoPreviewLayer {
            // swiftlint:disable:next force_cast
            layer as! AVCaptureVideoPreviewLayer
        }
    }
}

#Preview {
    BarcodeScannerView { _ in }
}
