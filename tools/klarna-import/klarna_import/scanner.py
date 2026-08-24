"""Walks an input directory of user-supplied screenshots and builds the list
of `IntermediateCard`s. Expected layout::

    input/
        Esselunga/
            barcode.jpg
            logo.png        (optional)
        IKEA Family/
            barcode.png

Each subdirectory of the input directory is one card. The subdirectory name
is used as the initial merchant-name guess (editable later) and as the seed
for a stable, non-secret `sourceId`.
"""
from __future__ import annotations

import hashlib
from pathlib import Path

from .models import CardStatus, Confidence, FieldConfidence, IntermediateCard
from .zxing_decoder import decode_barcode_image

_IMAGE_SUFFIXES = {".png", ".jpg", ".jpeg", ".heic", ".webp"}


def _find_file(directory: Path, prefix: str) -> Path | None:
    matches = sorted(
        p for p in directory.iterdir()
        if p.is_file() and p.suffix.lower() in _IMAGE_SUFFIXES and p.name.lower().startswith(prefix)
    )
    return matches[0] if matches else None


def _source_id_for(folder_name: str) -> str:
    # Derived only from the local folder name the user chose — never from any
    # Klarna identifier, credential, or session data.
    digest = hashlib.sha1(folder_name.encode("utf-8")).hexdigest()[:10]
    slug = "".join(c if c.isalnum() else "-" for c in folder_name.lower()).strip("-")
    return f"klarna-{slug}-{digest}"


def scan_input_directory(input_dir: Path) -> list[IntermediateCard]:
    cards: list[IntermediateCard] = []

    if not input_dir.is_dir():
        raise FileNotFoundError(f"Input directory not found: {input_dir}")

    for card_dir in sorted(p for p in input_dir.iterdir() if p.is_dir()):
        cards.append(_scan_one_card(card_dir))

    return cards


def _scan_one_card(card_dir: Path) -> IntermediateCard:
    name = card_dir.name
    source_id = _source_id_for(name)
    barcode_file = _find_file(card_dir, "barcode")
    logo_file = _find_file(card_dir, "logo")

    card = IntermediateCard(
        source_id=source_id,
        name=name,
        code=None,
        barcode_type=None,
        logo_path=str(logo_file.relative_to(card_dir.parent)) if logo_file else None,
    )

    if logo_file is not None:
        card.confidence.logo = Confidence.HIGH

    if barcode_file is None:
        card.status = CardStatus.NEEDS_REVIEW
        card.notes.append(f"No file named 'barcode.*' found in {card_dir.name}/.")
        return card

    result = decode_barcode_image(barcode_file)
    card.notes.extend(result.notes)

    if not result.ok:
        card.status = CardStatus.NEEDS_REVIEW
        card.code = result.code
        card.barcode_type = result.barcode_type
        card.confidence.code = Confidence.LOW if result.code else Confidence.UNKNOWN
        card.confidence.barcode_type = Confidence.LOW if result.barcode_type else Confidence.UNKNOWN
        return card

    card.code = result.code
    card.barcode_type = result.barcode_type
    card.confidence.code = Confidence(result.confidence)
    card.confidence.barcode_type = Confidence(result.confidence)
    card.status = CardStatus.READY
    return card
