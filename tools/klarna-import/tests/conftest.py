"""Shared helpers for generating synthetic barcode images so tests never
depend on any real Klarna data."""
from __future__ import annotations

import io
from pathlib import Path

import qrcode
from barcode import get as get_barcode_class
from barcode.writer import ImageWriter
from PIL import Image


def make_ean13_image(payload_without_check_digit: str, path: Path) -> str:
    """Writes an EAN-13 PNG and returns the full 13-digit code (with check digit)."""
    code = get_barcode_class("ean13", payload_without_check_digit, writer=ImageWriter())
    with open(path, "wb") as f:
        code.write(f, options={"write_text": False, "quiet_zone": 4})
    return code.ean


def make_code128_image(value: str, path: Path) -> None:
    code = get_barcode_class("code128", value, writer=ImageWriter())
    with open(path, "wb") as f:
        code.write(f, options={"write_text": False, "quiet_zone": 4})


def make_qr_image(value: str, path: Path) -> None:
    img = qrcode.make(value)
    img.save(path)


def make_blank_image(path: Path) -> None:
    Image.new("RGB", (200, 100), "white").save(path)
