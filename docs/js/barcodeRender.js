// Barcode rendering — the web equivalent of BarcodeService.swift. Delegates the
// actual symbol generation to bwip-js (loaded globally as `window.bwipjs`), which
// draws directly to a canvas with sharp, unsmoothed bars — no interpolation step
// to fight, unlike the native Core Image + hand-rolled-encoder split we needed there.

const BCID = {
  ean8: "ean8",
  ean13: "ean13",
  upce: "upce",
  code39: "code39",
  code93: "code93",
  code128: "code128",
  qr: "qrcode",
  pdf417: "pdf417",
  aztec: "azteccode",
};

/**
 * Renders `value` as `barcodeType` onto `canvas`, sized to roughly fill
 * `targetWidth` x `targetHeight` CSS pixels. Returns true on success, false if
 * this value/type combination couldn't be encoded (e.g. non-numeric value for
 * an EAN type) — the caller should show a clear "couldn't render" state rather
 * than guessing at a fallback image.
 */
export function renderBarcode(canvas, value, barcodeType, targetWidth, targetHeight) {
  const bcid = BCID[barcodeType];
  if (!bcid || !value) return false;

  try {
    const isSquare = barcodeType === "qr" || barcodeType === "aztec";
    const scale = window.devicePixelRatio > 1 ? 3 : 2;
    const options = {
      bcid,
      text: value,
      scale,
      includetext: false,
      backgroundcolor: "FFFFFF",
      paddingwidth: 4,
      paddingheight: 4,
    };
    if (!isSquare) options.height = 14;
    window.bwipjs.toCanvas(canvas, options);
    canvas.style.width = isSquare ? `${targetHeight}px` : `${targetWidth}px`;
    canvas.style.height = `${targetHeight}px`;
    canvas.style.imageRendering = "pixelated";
    return true;
  } catch (error) {
    console.warn("Barcode render failed", barcodeType, value, error);
    return false;
  }
}
