"""Mirrors Carry-Card's own logo handling (see
``CarryCard/Utilities/ImageUtilities.swift``): resize so the longest edge is
at most 512px, and always store as JPEG — so imported logos aren't
unnecessarily large originals and match every other logo Carry-Card owns.
"""
from __future__ import annotations

from pathlib import Path

from PIL import Image

MAX_LOGO_DIMENSION = 512
JPEG_QUALITY = 85


def process_logo(source_path: Path, destination_path: Path) -> None:
    destination_path.parent.mkdir(parents=True, exist_ok=True)
    with Image.open(source_path) as image:
        image = image.convert("RGB")
        longest_edge = max(image.size)
        if longest_edge > MAX_LOGO_DIMENSION:
            scale = MAX_LOGO_DIMENSION / longest_edge
            new_size = (round(image.width * scale), round(image.height * scale))
            image = image.resize(new_size, Image.LANCZOS)
        image.save(destination_path, format="JPEG", quality=JPEG_QUALITY)
