"""Data model for the intermediate migration file.

This mirrors (but is independent of) Carry-Card's own Swift model — see
``CarryCard/Models/LoyaltyCard.swift`` and ``BarcodeType.swift`` in the main
repository, which are the source of truth. Barcode/code values are always
plain ``str`` here: they must never pass through an ``int`` anywhere in this
pipeline, or a leading zero would silently disappear.
"""
from __future__ import annotations

from dataclasses import dataclass, field
from enum import Enum
from typing import Optional


# Exactly the symbologies Carry-Card's BarcodeType enum supports. Do not add
# to this list without also adding the case in the Swift enum.
CARRYCARD_BARCODE_TYPES = {
    "ean8", "ean13", "upce", "code39", "code93", "code128", "qr", "pdf417", "aztec",
}


class Confidence(str, Enum):
    HIGH = "high"
    MEDIUM = "medium"
    LOW = "low"
    UNKNOWN = "unknown"


class CardStatus(str, Enum):
    READY = "ready"
    NEEDS_REVIEW = "needsReview"
    SKIPPED = "skipped"


class DuplicateClassification(str, Enum):
    NEW = "new"
    EXISTING = "existing"
    POSSIBLE_DUPLICATE = "possibleDuplicate"


@dataclass
class FieldConfidence:
    code: Confidence = Confidence.UNKNOWN
    barcode_type: Confidence = Confidence.UNKNOWN
    logo: Confidence = Confidence.UNKNOWN

    def to_json(self) -> dict:
        return {"code": self.code.value, "barcodeType": self.barcode_type.value, "logo": self.logo.value}


@dataclass
class DuplicateInfo:
    classification: DuplicateClassification = DuplicateClassification.NEW
    matched_card_id: Optional[str] = None
    match_reason: Optional[str] = None

    def to_json(self) -> dict:
        return {
            "classification": self.classification.value,
            "matchedCardId": self.matched_card_id,
            "matchReason": self.match_reason,
        }


@dataclass
class IntermediateCard:
    """One loyalty card as discovered by the scanner, before it becomes a
    Carry-Card ``LoyaltyCard``. Nothing here is authentication material —
    ``source_id`` is derived only from the local input folder name.
    """

    source_id: str
    name: str
    code: Optional[str]                 # ALWAYS a string; never cast to int.
    barcode_type: Optional[str]         # one of CARRYCARD_BARCODE_TYPES, or None
    logo_path: Optional[str] = None     # path relative to the input directory
    status: CardStatus = CardStatus.NEEDS_REVIEW
    confidence: FieldConfidence = field(default_factory=FieldConfidence)
    notes: list[str] = field(default_factory=list)
    duplicate: DuplicateInfo = field(default_factory=DuplicateInfo)

    def to_json(self) -> dict:
        return {
            "sourceId": self.source_id,
            "name": self.name,
            "code": self.code,
            "barcodeType": self.barcode_type,
            "logoPath": self.logo_path,
            "confidence": self.confidence.to_json(),
            "status": self.status.value,
            "notes": self.notes,
            "duplicate": self.duplicate.to_json(),
        }

    @staticmethod
    def from_json(data: dict) -> "IntermediateCard":
        confidence_data = data.get("confidence", {})
        duplicate_data = data.get("duplicate", {})
        code = data.get("code")
        if code is not None and not isinstance(code, str):
            # A hand-edited JSON file put a bare number in — refuse to guess,
            # this is exactly the leading-zero trap. Caller should fix the file.
            raise ValueError(
                f"Card {data.get('sourceId')!r}: 'code' must be a JSON string, "
                f"got {type(code).__name__} ({code!r}). Quote it to preserve leading zeros."
            )
        return IntermediateCard(
            source_id=data["sourceId"],
            name=data["name"],
            code=code,
            barcode_type=data.get("barcodeType"),
            logo_path=data.get("logoPath"),
            status=CardStatus(data.get("status", "needsReview")),
            confidence=FieldConfidence(
                code=Confidence(confidence_data.get("code", "unknown")),
                barcode_type=Confidence(confidence_data.get("barcodeType", "unknown")),
                logo=Confidence(confidence_data.get("logo", "unknown")),
            ),
            notes=list(data.get("notes", [])),
            duplicate=DuplicateInfo(
                classification=DuplicateClassification(duplicate_data.get("classification", "new")),
                matched_card_id=duplicate_data.get("matchedCardId"),
                match_reason=duplicate_data.get("matchReason"),
            ),
        )
