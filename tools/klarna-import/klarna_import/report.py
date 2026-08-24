"""Human-readable rendering of the import preview and the final migration
report. Never prints anything related to authentication — there is none to
print, since this tool never handles Klarna credentials, cookies or tokens.
"""
from __future__ import annotations

from .models import CardStatus, DuplicateClassification, IntermediateCard


def render_preview(cards: list[IntermediateCard]) -> str:
    lines: list[str] = []
    for card in cards:
        lines.append(card.name)
        lines.append(f"Barcode: {card.code if card.code else 'unknown'}")
        lines.append(f"Type: {card.barcode_type if card.barcode_type else 'unknown'}")
        lines.append(f"Logo: {'found' if card.logo_path else 'none'}")
        lines.append(f"Duplicate: {card.duplicate.classification.value}"
                      + (f" (matches {card.duplicate.matched_card_id})" if card.duplicate.matched_card_id else ""))
        lines.append(f"Status: {card.status.value}")
        if card.notes:
            for note in card.notes:
                lines.append(f"  note: {note}")
        lines.append("")

    ready = sum(1 for c in cards if c.status == CardStatus.READY)
    needs_review = sum(1 for c in cards if c.status == CardStatus.NEEDS_REVIEW)
    skipped = sum(1 for c in cards if c.status == CardStatus.SKIPPED)
    new_count = sum(1 for c in cards if c.duplicate.classification == DuplicateClassification.NEW)
    existing_count = sum(1 for c in cards if c.duplicate.classification == DuplicateClassification.EXISTING)
    possible_dup = sum(1 for c in cards if c.duplicate.classification == DuplicateClassification.POSSIBLE_DUPLICATE)

    lines.append("Summary")
    lines.append("-------")
    lines.append(f"Cards discovered: {len(cards)}")
    lines.append(f"Ready to import: {ready}")
    lines.append(f"Need review: {needs_review}")
    lines.append(f"Skipped: {skipped}")
    lines.append(f"New: {new_count}")
    lines.append(f"Already in Carry-Card: {existing_count}")
    lines.append(f"Possible duplicates (verify manually): {possible_dup}")

    return "\n".join(lines)


def render_migration_report(
    cards: list[IntermediateCard],
    added: list[IntermediateCard],
    improved: list[IntermediateCard],
    skipped: list[IntermediateCard],
) -> str:
    lines = ["Klarna -> Carry-Card Migration", ""]
    lines.append(f"Klarna cards discovered: {len(cards)}")
    lines.append("")
    lines.append("New cards added:")
    lines.append(str(len(added)))
    lines.append("")
    lines.append("Existing cards improved:")
    lines.append(str(len(improved)))
    lines.append("")
    lines.append("Skipped (needs review / duplicate not merged):")
    lines.append(str(len(skipped)))
    lines.append("")
    lines.append("Details")
    lines.append("-------")
    for card in cards:
        outcome = "added" if card in added else "improved existing" if card in improved else "skipped"
        lines.append(f"{card.name}: {outcome} (status={card.status.value}, duplicate={card.duplicate.classification.value})")
    return "\n".join(lines)
