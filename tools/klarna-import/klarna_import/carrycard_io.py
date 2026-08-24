"""Reads and writes Carry-Card's own file format exactly as it is defined in
the main app — see ``CarryCard/Services/CardStore.swift``,
``CarryCard/Services/SyncService.swift`` and ``CarryCard/Utilities/JSONCoding.swift``
in the repository root. This module is the *only* place that needs to change
if Carry-Card's on-disk schema ever changes.

``cards.json`` is a plain JSON array of card objects; ``deleted.json`` is a
plain JSON array of tombstones; logos live in a sibling ``logos/`` folder
named ``<uuid>.jpg``. Optional fields that are absent are omitted from the
JSON entirely (never written as ``null``), matching Swift's
``encodeIfPresent`` behavior for `Codable` optionals.
"""
from __future__ import annotations

import json
import shutil
import uuid
from datetime import datetime, timezone
from pathlib import Path


def now_iso8601() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def new_uuid() -> str:
    return str(uuid.uuid4()).upper()


def load_json_array(path: Path) -> list[dict]:
    if not path.exists():
        return []
    with path.open("r", encoding="utf-8") as f:
        data = json.load(f)
    if not isinstance(data, list):
        raise ValueError(f"{path} does not contain a JSON array as Carry-Card expects.")
    return data


def write_json_array_atomic(path: Path, items: list[dict]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp_path = path.with_suffix(path.suffix + ".tmp")
    with tmp_path.open("w", encoding="utf-8") as f:
        json.dump(items, f, indent=2, sort_keys=True, ensure_ascii=False)
    # Round-trip validate before committing.
    with tmp_path.open("r", encoding="utf-8") as f:
        json.load(f)
    tmp_path.replace(path)


def backup_carrycard_folder(carrycard_folder: Path, backup_root: Path) -> None:
    """Copies cards.json, deleted.json and logos/ (if present) into
    `backup_root`, never overwriting a pre-existing backup silently.
    """
    if backup_root.exists():
        raise FileExistsError(
            f"Backup destination already exists: {backup_root}. "
            f"Remove or rename it before running the import again."
        )
    backup_root.mkdir(parents=True)
    for name in ("cards.json", "deleted.json"):
        source = carrycard_folder / name
        if source.exists():
            shutil.copy2(source, backup_root / name)
    logos_source = carrycard_folder / "logos"
    if logos_source.is_dir():
        shutil.copytree(logos_source, backup_root / "logos")


def build_card_json(
    *,
    card_id: str,
    name: str,
    code: str,
    barcode_type: str,
    logo_file_name: str | None,
    sort_index: float,
    created_at: str,
    updated_at: str,
) -> dict:
    result = {
        "id": card_id,
        "name": name,
        "code": code,
        "barcodeType": barcode_type,
        "sortIndex": sort_index,
        "createdAt": created_at,
        "updatedAt": updated_at,
    }
    if logo_file_name is not None:
        result["logoFileName"] = logo_file_name
    return result
