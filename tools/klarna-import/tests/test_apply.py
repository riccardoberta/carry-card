import json

from klarna_import.apply import apply_import
from klarna_import.models import (
    CardStatus,
    Confidence,
    DuplicateClassification,
    DuplicateInfo,
    FieldConfidence,
    IntermediateCard,
)

from .conftest import make_blank_image


def _setup_carrycard_folder(tmp_path, existing_cards):
    folder = tmp_path / "Carry-Card"
    folder.mkdir()
    (folder / "cards.json").write_text(json.dumps(existing_cards))
    (folder / "deleted.json").write_text("[]")
    return folder


def test_ready_new_card_is_added(tmp_path):
    carrycard_folder = _setup_carrycard_folder(tmp_path, [])
    input_dir = tmp_path / "input"
    input_dir.mkdir()

    card = IntermediateCard(
        source_id="klarna-example-abc123",
        name="Example Store",
        code="0012345678905",
        barcode_type="ean13",
        status=CardStatus.READY,
        confidence=FieldConfidence(code=Confidence.HIGH, barcode_type=Confidence.HIGH),
        duplicate=DuplicateInfo(classification=DuplicateClassification.NEW),
    )

    result = apply_import(
        [card], input_dir=input_dir, carrycard_folder=carrycard_folder,
        backup_root=tmp_path / "backup-before-klarna-import",
    )

    assert len(result.added) == 1
    written = json.loads((carrycard_folder / "cards.json").read_text())
    assert len(written) == 1
    assert written[0]["code"] == "0012345678905"
    assert isinstance(written[0]["code"], str)
    assert written[0]["barcodeType"] == "ean13"
    assert written[0]["name"] == "Example Store"
    assert "id" in written[0] and "createdAt" in written[0] and "updatedAt" in written[0]
    assert "logoFileName" not in written[0]  # no logo supplied -> key omitted, not null


def test_needs_review_card_is_never_written(tmp_path):
    carrycard_folder = _setup_carrycard_folder(tmp_path, [])
    input_dir = tmp_path / "input"
    input_dir.mkdir()

    card = IntermediateCard(
        source_id="klarna-blurry-xyz",
        name="Blurry Card",
        code=None,
        barcode_type=None,
        status=CardStatus.NEEDS_REVIEW,
    )

    result = apply_import(
        [card], input_dir=input_dir, carrycard_folder=carrycard_folder,
        backup_root=tmp_path / "backup-before-klarna-import",
    )

    assert len(result.added) == 0
    assert card in result.skipped
    written = json.loads((carrycard_folder / "cards.json").read_text())
    assert written == []


def test_existing_card_gets_missing_logo_added_but_barcode_untouched(tmp_path):
    existing = [{
        "id": "existing-id-1",
        "name": "IKEA Family",
        "code": "999999999999",
        "barcodeType": "code128",
        "sortIndex": 1.0,
        "createdAt": "2025-01-01T00:00:00Z",
        "updatedAt": "2025-01-01T00:00:00Z",
    }]
    carrycard_folder = _setup_carrycard_folder(tmp_path, existing)
    input_dir = tmp_path / "input"
    (input_dir / "IKEA Family").mkdir(parents=True)
    make_blank_image(input_dir / "IKEA Family" / "logo.png")

    card = IntermediateCard(
        source_id="klarna-ikea-family",
        name="IKEA Family",
        code="999999999999",  # exact match -> would classify as EXISTING
        barcode_type="code128",
        logo_path="IKEA Family/logo.png",
        status=CardStatus.READY,
        duplicate=DuplicateInfo(classification=DuplicateClassification.EXISTING, matched_card_id="existing-id-1"),
    )

    result = apply_import(
        [card], input_dir=input_dir, carrycard_folder=carrycard_folder,
        backup_root=tmp_path / "backup-before-klarna-import",
    )

    assert len(result.improved) == 1
    assert len(result.added) == 0
    written = json.loads((carrycard_folder / "cards.json").read_text())
    assert len(written) == 1  # no duplicate card created
    assert written[0]["code"] == "999999999999"  # untouched
    assert written[0]["barcodeType"] == "code128"  # untouched
    assert "logoFileName" in written[0]
    logo_path = carrycard_folder / "logos" / written[0]["logoFileName"]
    assert logo_path.exists()


def test_possible_duplicate_is_never_auto_merged(tmp_path):
    existing = [{"id": "existing-id-1", "name": "Chain Store", "code": "111", "sortIndex": 1.0,
                 "createdAt": "2025-01-01T00:00:00Z", "updatedAt": "2025-01-01T00:00:00Z"}]
    carrycard_folder = _setup_carrycard_folder(tmp_path, existing)
    input_dir = tmp_path / "input"
    input_dir.mkdir()

    card = IntermediateCard(
        source_id="klarna-chain-store",
        name="Chain Store",
        code="222",  # different code, same name
        barcode_type="code128",
        status=CardStatus.READY,
        duplicate=DuplicateInfo(classification=DuplicateClassification.POSSIBLE_DUPLICATE, matched_card_id="existing-id-1"),
    )

    result = apply_import(
        [card], input_dir=input_dir, carrycard_folder=carrycard_folder,
        backup_root=tmp_path / "backup-before-klarna-import",
    )

    assert len(result.added) == 0
    assert len(result.improved) == 0
    assert card in result.skipped
    written = json.loads((carrycard_folder / "cards.json").read_text())
    assert len(written) == 1  # only the original existing card


def test_backup_is_created_before_any_write(tmp_path):
    existing = [{"id": "existing-id-1", "name": "Existing", "code": "1", "sortIndex": 1.0,
                 "createdAt": "2025-01-01T00:00:00Z", "updatedAt": "2025-01-01T00:00:00Z"}]
    carrycard_folder = _setup_carrycard_folder(tmp_path, existing)
    input_dir = tmp_path / "input"
    input_dir.mkdir()
    backup_root = tmp_path / "backup-before-klarna-import"

    apply_import([], input_dir=input_dir, carrycard_folder=carrycard_folder, backup_root=backup_root)

    backed_up = json.loads((backup_root / "cards.json").read_text())
    assert backed_up == existing
