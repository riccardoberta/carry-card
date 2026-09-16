// Live camera barcode scanning — the web equivalent of BarcodeScannerService.swift.
// Uses ZXing's browser build (loaded globally as `window.ZXing`) over getUserMedia.
// Stops itself after the first successful detection, same as the native scanner.

function buildFormatMap() {
  const { BarcodeFormat } = window.ZXing;
  return new Map([
    [BarcodeFormat.EAN_8, "ean8"],
    [BarcodeFormat.EAN_13, "ean13"],
    [BarcodeFormat.UPC_E, "upce"],
    [BarcodeFormat.CODE_39, "code39"],
    [BarcodeFormat.CODE_93, "code93"],
    [BarcodeFormat.CODE_128, "code128"],
    [BarcodeFormat.QR_CODE, "qr"],
    [BarcodeFormat.PDF_417, "pdf417"],
    [BarcodeFormat.AZTEC, "aztec"],
  ]);
}

export class BarcodeScanner {
  constructor() {
    this._reader = null;
    this._formatMap = null;
    this._stopped = true;
  }

  /** Starts scanning `videoElement`. Calls `onDetected({ value, barcodeType })`
   * exactly once, then stops itself. Throws if camera access is denied. */
  async start(videoElement, onDetected) {
    const { BrowserMultiFormatReader, DecodeHintType } = window.ZXing;
    this._formatMap = buildFormatMap();

    const hints = new Map();
    hints.set(DecodeHintType.POSSIBLE_FORMATS, [...this._formatMap.keys()]);
    this._reader = new BrowserMultiFormatReader(hints);
    this._stopped = false;

    await this._reader.decodeFromConstraints(
      { video: { facingMode: "environment" } },
      videoElement,
      (result, error) => {
        if (this._stopped || !result) return;
        const barcodeType = this._formatMap.get(result.getBarcodeFormat());
        if (!barcodeType) return; // decoded but not one of our supported types
        this.stop();
        onDetected({ value: result.getText(), barcodeType });
      }
    );
  }

  stop() {
    this._stopped = true;
    this._reader?.reset();
  }
}
