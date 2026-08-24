"""Local, offline barcode decoding for a screenshot/photo of a loyalty card.

Nothing in this module talks to Klarna or any network service — it only
reads image files the user has already saved to disk (after taking a
screenshot in their own, already-authenticated Klarna app).
"""
from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
from typing import Optional

import zxingcpp
from PIL import Image

from .checksum_validate import verify_numeric_checksum

# zxing-cpp format name -> Carry-Card BarcodeType raw value. Formats not
# listed here are not supported by Carry-Card and are reported as such
# rather than silently dropped or mis-mapped.
_FORMAT_MAP = {
    "EAN-13": "ean13",
    "EAN-8": "ean8",
    "UPC-E": "upce",
    "Code 39": "code39",
    "Code 93": "code93",
    "Code 128": "code128",
    "QR Code": "qr",
    "PDF417": "pdf417",
    "Aztec": "aztec",
}


@dataclass
class DecodeResult:
    ok: bool
    code: Optional[str] = None
    barcode_type: Optional[str] = None
    confidence: str = "unknown"       # "high" | "medium" | "low"
    notes: list[str] = None

    def __post_init__(self):
        if self.notes is None:
            self.notes = []


def decode_barcode_image(image_path: Path) -> DecodeResult:
    """Decodes the single most likely barcode in `image_path`.

    High confidence requires: exactly one candidate found, the decoder's own
    checksum validation passing, and (for EAN-13/EAN-8/UPC-E) our own
    independent checksum re-verification also passing.
    """
    try:
        image = Image.open(image_path)
        image.load()
    except Exception as error:  # noqa: BLE001 - report, don't crash the batch
        return DecodeResult(ok=False, notes=[f"Could not open image: {error}"])

    results = zxingcpp.read_barcodes(image, return_errors=True)

    if not results:
        return DecodeResult(ok=False, notes=["No barcode detected in the image."])

    if len(results) > 1:
        candidates = ", ".join(f"{r.format}:{r.text}" for r in results)
        return DecodeResult(
            ok=False,
            notes=[f"Multiple barcodes detected in one image ({candidates}); crop to a single barcode."],
        )

    result = results[0]
    format_name = str(result.format)
    barcode_type = _FORMAT_MAP.get(format_name)
    text = result.text

    if barcode_type is None:
        return DecodeResult(
            ok=False,
            code=text,
            notes=[f"Decoded as '{format_name}', which Carry-Card does not support. "
                   f"Re-enter this card manually with a supported type."],
        )

    if result.error:
        return DecodeResult(
            ok=False,
            code=text,
            barcode_type=barcode_type,
            notes=[f"Decoder reported an error: {result.error}"],
        )

    if not result.valid:
        return DecodeResult(
            ok=False,
            code=text,
            barcode_type=barcode_type,
            notes=["Decoder could not confirm this barcode's internal checksum; image may be damaged or blurry."],
        )

    # Independent re-check for the numeric symbologies (see checksum_validate.py).
    independent_check = verify_numeric_checksum(barcode_type, text)
    if independent_check is False:
        return DecodeResult(
            ok=False,
            code=text,
            barcode_type=barcode_type,
            notes=["Independent checksum re-verification failed; do not trust this value."],
        )

    confidence = "high" if independent_check in (True, None) else "medium"
    notes = []
    if independent_check is None:
        notes.append(
            f"'{barcode_type}' has no independent checksum re-check in this tool; "
            f"confidence is based on the decoder's own validation only."
        )

    return DecodeResult(ok=True, code=text, barcode_type=barcode_type, confidence=confidence, notes=notes)
