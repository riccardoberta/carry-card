"""Compares scanned Klarna cards against the existing Carry-Card database to
avoid creating duplicate cards. An exact barcode-payload match is the
strongest signal; a normalized-name-only match is flagged for human review
rather than auto-merged, since two different cards can share a merchant name.
"""
from __future__ import annotations

import re

from .models import DuplicateClassification, DuplicateInfo, IntermediateCard


def _normalize_name(name: str) -> str:
    return re.sub(r"[^a-z0-9]+", "", name.lower())


def classify_duplicates(cards: list[IntermediateCard], existing_cards: list[dict]) -> None:
    """Mutates each card's `.duplicate` in place."""
    by_code = {c["code"]: c for c in existing_cards if c.get("code")}
    by_normalized_name: dict[str, list[dict]] = {}
    for c in existing_cards:
        by_normalized_name.setdefault(_normalize_name(c.get("name", "")), []).append(c)

    for card in cards:
        if card.code and card.code in by_code:
            match = by_code[card.code]
            card.duplicate = DuplicateInfo(
                classification=DuplicateClassification.EXISTING,
                matched_card_id=match["id"],
                match_reason="Exact barcode payload match.",
            )
            continue

        normalized = _normalize_name(card.name)
        name_matches = by_normalized_name.get(normalized, [])
        if len(name_matches) == 1:
            card.duplicate = DuplicateInfo(
                classification=DuplicateClassification.POSSIBLE_DUPLICATE,
                matched_card_id=name_matches[0]["id"],
                match_reason="Merchant name matches an existing card, but the barcode payload differs "
                             "(or could not be decoded) — verify manually before merging.",
            )
            continue
        if len(name_matches) > 1:
            card.duplicate = DuplicateInfo(
                classification=DuplicateClassification.POSSIBLE_DUPLICATE,
                matched_card_id=None,
                match_reason=f"{len(name_matches)} existing cards share this merchant name — verify manually.",
            )
            continue

        card.duplicate = DuplicateInfo(classification=DuplicateClassification.NEW)
