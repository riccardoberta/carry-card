from klarna_import.models import CardStatus, Confidence
from klarna_import.scanner import scan_input_directory

from .conftest import make_blank_image, make_ean13_image, make_qr_image


def test_scans_a_ready_card_with_logo(tmp_path):
    card_dir = tmp_path / "Esselunga"
    card_dir.mkdir()
    full_code = make_ean13_image("800123456789", card_dir / "barcode.png")
    make_blank_image(card_dir / "logo.png")

    cards = scan_input_directory(tmp_path)

    assert len(cards) == 1
    card = cards[0]
    assert card.name == "Esselunga"
    assert card.code == full_code
    assert card.barcode_type == "ean13"
    assert card.status == CardStatus.READY
    assert card.confidence.code == Confidence.HIGH
    assert card.logo_path == "Esselunga/logo.png"
    assert card.confidence.logo == Confidence.HIGH


def test_missing_barcode_file_needs_review(tmp_path):
    card_dir = tmp_path / "Example Store"
    card_dir.mkdir()
    make_blank_image(card_dir / "logo.png")

    cards = scan_input_directory(tmp_path)

    assert cards[0].status == CardStatus.NEEDS_REVIEW
    assert cards[0].code is None
    assert "No file named 'barcode.*'" in cards[0].notes[0]


def test_undecodable_barcode_needs_review(tmp_path):
    card_dir = tmp_path / "Blurry Card"
    card_dir.mkdir()
    make_blank_image(card_dir / "barcode.png")

    cards = scan_input_directory(tmp_path)

    assert cards[0].status == CardStatus.NEEDS_REVIEW


def test_source_id_is_stable_and_has_no_klarna_identifiers(tmp_path):
    card_dir = tmp_path / "IKEA Family"
    card_dir.mkdir()
    make_qr_image("MEMBER-998877", card_dir / "barcode.png")

    cards_a = scan_input_directory(tmp_path)
    cards_b = scan_input_directory(tmp_path)

    assert cards_a[0].source_id == cards_b[0].source_id
    assert cards_a[0].source_id.startswith("klarna-ikea-family-")


def test_scans_multiple_cards_sorted_by_folder_name(tmp_path):
    for name, payload in [("Zeta Club", "111"), ("Alpha Club", "222")]:
        card_dir = tmp_path / name
        card_dir.mkdir()
        make_qr_image(payload, card_dir / "barcode.png")

    cards = scan_input_directory(tmp_path)

    assert [c.name for c in cards] == ["Alpha Club", "Zeta Club"]
