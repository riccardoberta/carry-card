from klarna_import.duplicates import classify_duplicates
from klarna_import.models import DuplicateClassification, IntermediateCard


def _card(name, code):
    return IntermediateCard(source_id=f"klarna-{name}", name=name, code=code, barcode_type="ean13")


def test_exact_barcode_match_is_existing():
    existing = [{"id": "abc-123", "name": "Esselunga", "code": "8001234567890"}]
    card = _card("Esselunga Fidelity", "8001234567890")  # name differs, code is authoritative

    classify_duplicates([card], existing)

    assert card.duplicate.classification == DuplicateClassification.EXISTING
    assert card.duplicate.matched_card_id == "abc-123"


def test_name_only_match_is_possible_duplicate_not_auto_merged():
    existing = [{"id": "abc-123", "name": "IKEA Family", "code": "999999999999"}]
    card = _card("IKEA Family", "111111111111")  # same name, different code

    classify_duplicates([card], existing)

    assert card.duplicate.classification == DuplicateClassification.POSSIBLE_DUPLICATE
    assert card.duplicate.matched_card_id == "abc-123"


def test_no_match_is_new():
    existing = [{"id": "abc-123", "name": "Other Store", "code": "555555555555"}]
    card = _card("Brand New Store", "222222222222")

    classify_duplicates([card], existing)

    assert card.duplicate.classification == DuplicateClassification.NEW
    assert card.duplicate.matched_card_id is None


def test_normalization_ignores_case_and_punctuation():
    existing = [{"id": "abc-123", "name": "north-market!", "code": "1"}]
    card = _card("North Market", "2")

    classify_duplicates([card], existing)

    assert card.duplicate.classification == DuplicateClassification.POSSIBLE_DUPLICATE


def test_multiple_name_matches_flagged_without_a_specific_id():
    existing = [
        {"id": "a", "name": "Chain Store", "code": "1"},
        {"id": "b", "name": "Chain Store", "code": "2"},
    ]
    card = _card("Chain Store", "3")

    classify_duplicates([card], existing)

    assert card.duplicate.classification == DuplicateClassification.POSSIBLE_DUPLICATE
    assert card.duplicate.matched_card_id is None
