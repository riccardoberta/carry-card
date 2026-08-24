import json

import pytest

from klarna_import.carrycard_io import (
    backup_carrycard_folder,
    build_card_json,
    load_json_array,
    write_json_array_atomic,
)


def test_load_json_array_missing_file_returns_empty_list(tmp_path):
    assert load_json_array(tmp_path / "cards.json") == []


def test_load_json_array_rejects_non_array(tmp_path):
    path = tmp_path / "cards.json"
    path.write_text(json.dumps({"not": "an array"}))
    with pytest.raises(ValueError):
        load_json_array(path)


def test_write_json_array_atomic_round_trips(tmp_path):
    path = tmp_path / "cards.json"
    items = [{"id": "1", "code": "0012345"}]

    write_json_array_atomic(path, items)

    assert json.loads(path.read_text()) == items
    assert not path.with_suffix(".json.tmp").exists()


def test_write_json_array_atomic_preserves_string_codes_with_leading_zeros(tmp_path):
    path = tmp_path / "cards.json"
    write_json_array_atomic(path, [{"code": "001234"}])

    raw = path.read_text()
    assert '"001234"' in raw  # written as a quoted string, not a bare number


def test_build_card_json_omits_absent_optional_fields():
    card = build_card_json(
        card_id="ID1", name="Store", code="0099", barcode_type="ean13",
        logo_file_name=None, sort_index=1.0, created_at="2026-01-01T00:00:00Z",
        updated_at="2026-01-01T00:00:00Z",
    )
    assert "logoFileName" not in card
    assert card["code"] == "0099"


def test_backup_carrycard_folder_copies_everything(tmp_path):
    carrycard_folder = tmp_path / "Carry-Card"
    carrycard_folder.mkdir()
    (carrycard_folder / "cards.json").write_text("[]")
    (carrycard_folder / "deleted.json").write_text("[]")
    logos = carrycard_folder / "logos"
    logos.mkdir()
    (logos / "a.jpg").write_bytes(b"fake")

    backup_root = tmp_path / "backup-before-klarna-import"
    backup_carrycard_folder(carrycard_folder, backup_root)

    assert (backup_root / "cards.json").exists()
    assert (backup_root / "deleted.json").exists()
    assert (backup_root / "logos" / "a.jpg").read_bytes() == b"fake"


def test_backup_refuses_to_overwrite_existing_backup(tmp_path):
    carrycard_folder = tmp_path / "Carry-Card"
    carrycard_folder.mkdir()
    backup_root = tmp_path / "backup-before-klarna-import"
    backup_root.mkdir()

    with pytest.raises(FileExistsError):
        backup_carrycard_folder(carrycard_folder, backup_root)
