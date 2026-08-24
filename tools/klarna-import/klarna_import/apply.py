"""Safely merges reviewed intermediate cards into a real Carry-Card folder.

Order of operations (see spec step 13 "Safe import transaction"):
  1. Load and validate the existing database.
  2. Back up the existing folder in full.
  3. Build the merged database in memory.
  4. Write it to temporary files and validate they decode.
  5. Atomically replace the real files.
  6. Copy logo images in.

Only cards with status "ready" are ever written. "needsReview", "skipped"
and "possibleDuplicate" cards are always left out — the caller must resolve
them (by editing the intermediate JSON and re-running) before they can be
imported. This function never deletes or overwrites an existing card's
`code`/`barcodeType`/`name` — at most it adds a missing logo.
"""
from __future__ import annotations

from pathlib import Path

from .carrycard_io import (
    backup_carrycard_folder,
    build_card_json,
    load_json_array,
    new_uuid,
    now_iso8601,
    write_json_array_atomic,
)
from .logo_processing import process_logo
from .models import CardStatus, DuplicateClassification, IntermediateCard


class ApplyResult:
    def __init__(self):
        self.added: list[IntermediateCard] = []
        self.improved: list[IntermediateCard] = []
        self.skipped: list[IntermediateCard] = []


def apply_import(
    cards: list[IntermediateCard],
    *,
    input_dir: Path,
    carrycard_folder: Path,
    backup_root: Path,
) -> ApplyResult:
    existing_cards = load_json_array(carrycard_folder / "cards.json")
    existing_deleted = load_json_array(carrycard_folder / "deleted.json")  # validated, left untouched

    backup_carrycard_folder(carrycard_folder, backup_root)

    by_id = {c["id"]: c for c in existing_cards}
    max_sort_index = max((c.get("sortIndex", 0) for c in existing_cards), default=0.0)

    result = ApplyResult()
    new_logo_copies: list[tuple[Path, Path]] = []  # (source, destination)

    for card in cards:
        if card.status != CardStatus.READY:
            result.skipped.append(card)
            continue

        if card.duplicate.classification == DuplicateClassification.POSSIBLE_DUPLICATE:
            # Never silently merge an uncertain match.
            result.skipped.append(card)
            continue

        if card.duplicate.classification == DuplicateClassification.EXISTING:
            existing = by_id.get(card.duplicate.matched_card_id)
            if existing is None:
                result.skipped.append(card)
                continue
            if not existing.get("logoFileName") and card.logo_path:
                logo_file_name = f"{new_uuid()}.jpg"
                existing["logoFileName"] = logo_file_name
                existing["updatedAt"] = now_iso8601()
                new_logo_copies.append((input_dir / card.logo_path, carrycard_folder / "logos" / logo_file_name))
                result.improved.append(card)
            else:
                result.skipped.append(card)
            continue

        # New card.
        max_sort_index += 1
        logo_file_name = None
        if card.logo_path:
            logo_file_name = f"{new_uuid()}.jpg"
            new_logo_copies.append((input_dir / card.logo_path, carrycard_folder / "logos" / logo_file_name))

        timestamp = now_iso8601()
        new_card = build_card_json(
            card_id=new_uuid(),
            name=card.name,
            code=card.code,
            barcode_type=card.barcode_type,
            logo_file_name=logo_file_name,
            sort_index=max_sort_index,
            created_at=timestamp,
            updated_at=timestamp,
        )
        existing_cards.append(new_card)
        result.added.append(card)

    # `write_json_array_atomic` writes to a sibling `.tmp` file, validates it
    # decodes as JSON, and only then atomically renames it over the real
    # file — so the real cards.json/deleted.json are never left half-written.
    write_json_array_atomic(carrycard_folder / "cards.json", existing_cards)
    write_json_array_atomic(carrycard_folder / "deleted.json", existing_deleted)

    for source, destination in new_logo_copies:
        process_logo(source, destination)

    return result
