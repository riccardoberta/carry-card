import AVFoundation
import UIKit

/// A single successfully decoded barcode: its value plus which symbology produced it.
struct ScannedBarcode: Equatable, Sendable {
    let value: String
    let type: BarcodeType
}

enum BarcodeScannerError: Error, Sendable {
    case cameraUnavailable
    case permissionDenied
}

/// Owns the `AVCaptureSession` used to scan loyalty-card barcodes with the device
/// camera. Session setup and start/stop run on a dedicated serial background queue
/// (the standard AVFoundation pattern) so the main thread and UI never block.
///
/// `@unchecked Sendable`: `captureSession`/`metadataOutput` are only ever touched
/// from `sessionQueue`, and the `@Published` properties are only ever written from
/// the main queue (the metadata delegate is registered with `queue: .main`, and
/// every background mutation hops back via `DispatchQueue.main.async`) — the
/// serial queue is the manual synchronization the compiler can't see.
///
/// Stops itself automatically after the first successful detection so the same
/// code is never reported twice for one scan session.
final class BarcodeScannerService: NSObject, ObservableObject, @unchecked Sendable {
    @Published private(set) var isRunning = false
    @Published private(set) var lastDetection: ScannedBarcode?

    let captureSession = AVCaptureSession()
    private let metadataOutput = AVCaptureMetadataOutput()
    private let sessionQueue = DispatchQueue(label: "app.carrycard.scanner.session")
    private var hasConfigured = false
    private var hasDetectedThisSession = false

    static let supportedMetadataTypes: [AVMetadataObject.ObjectType] = [
        .ean8, .ean13, .upce, .code39, .code39Mod43, .code93, .code128, .qr, .pdf417, .aztec
    ]

    static func currentAuthorizationStatus() -> AVAuthorizationStatus {
        AVCaptureDevice.authorizationStatus(for: .video)
    }

    /// Requests camera permission if not yet determined; returns whether access is granted.
    func requestCameraAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .video)
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }

    /// Prepares the capture session (camera input + metadata output). Safe to call
    /// repeatedly; configuration only happens once.
    func configureSessionIfNeeded(completion: @escaping @Sendable (Result<Void, BarcodeScannerError>) -> Void) {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if self.hasConfigured {
                DispatchQueue.main.async { completion(.success(())) }
                return
            }
            self.captureSession.beginConfiguration()
            defer { self.captureSession.commitConfiguration() }

            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                  let input = try? AVCaptureDeviceInput(device: device),
                  self.captureSession.canAddInput(input) else {
                DispatchQueue.main.async { completion(.failure(.cameraUnavailable)) }
                return
            }
            self.captureSession.addInput(input)

            guard self.captureSession.canAddOutput(self.metadataOutput) else {
                DispatchQueue.main.async { completion(.failure(.cameraUnavailable)) }
                return
            }
            self.captureSession.addOutput(self.metadataOutput)
            self.metadataOutput.setMetadataObjectsDelegate(self, queue: .main)
            self.metadataOutput.metadataObjectTypes = Self.supportedMetadataTypes.filter {
                self.metadataOutput.availableMetadataObjectTypes.contains($0)
            }

            self.hasConfigured = true
            DispatchQueue.main.async { completion(.success(())) }
        }
    }

    func start() {
        hasDetectedThisSession = false
        lastDetection = nil
        sessionQueue.async { [weak self] in
            guard let self, !self.captureSession.isRunning else { return }
            self.captureSession.startRunning()
            DispatchQueue.main.async { self.isRunning = true }
        }
    }

    func stop() {
        sessionQueue.async { [weak self] in
            guard let self, self.captureSession.isRunning else { return }
            self.captureSession.stopRunning()
            DispatchQueue.main.async { self.isRunning = false }
        }
    }

    /// Clears the last detection so scanning can be attempted again (e.g. user
    /// chose "Scan Again" after reviewing a misread code).
    func resetDetection() {
        hasDetectedThisSession = false
        lastDetection = nil
    }
}

extension BarcodeScannerService: AVCaptureMetadataOutputObjectsDelegate {
    func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        guard !hasDetectedThisSession else { return }
        guard let object = metadataObjects.first(where: { $0 is AVMetadataMachineReadableCodeObject }) as? AVMetadataMachineReadableCodeObject,
              let stringValue = object.stringValue,
              let barcodeType = Self.barcodeType(for: object.type) else { return }

        hasDetectedThisSession = true
        lastDetection = ScannedBarcode(value: stringValue, type: barcodeType)
        stop()
    }

    private static func barcodeType(for objectType: AVMetadataObject.ObjectType) -> BarcodeType? {
        switch objectType {
        case .ean8: return .ean8
        case .ean13: return .ean13
        case .upce: return .upce
        case .code39, .code39Mod43: return .code39
        case .code93: return .code93
        case .code128: return .code128
        case .qr: return .qr
        case .pdf417: return .pdf417
        case .aztec: return .aztec
        default: return nil
        }
    }
}
