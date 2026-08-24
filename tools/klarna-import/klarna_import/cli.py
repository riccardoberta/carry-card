"""Command-line entry point.

    klarna-import scan  <input_dir> --carrycard-folder <path> [-o preview.json]
    klarna-import apply <preview.json> --carrycard-folder <path>

Nothing in this CLI accepts a password, cookie, or token as an argument —
there is nothing to authenticate, since this tool only ever reads image
files you've already saved to disk yourself.
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

from .apply import apply_import
from .carrycard_io import load_json_array, now_iso8601
from .duplicates import classify_duplicates
from .models import IntermediateCard
from .report import render_migration_report, render_preview
from .scanner import scan_input_directory


def _cmd_scan(args: argparse.Namespace) -> int:
    input_dir = Path(args.input_dir).expanduser().resolve()
    carrycard_folder = Path(args.carrycard_folder).expanduser().resolve()

    cards = scan_input_directory(input_dir)
    existing_cards = load_json_array(carrycard_folder / "cards.json")
    classify_duplicates(cards, existing_cards)

    output_path = Path(args.output).expanduser().resolve() if args.output else input_dir / "preview.json"
    payload = {
        "source": "klarna",
        "importedAt": now_iso8601(),
        "cards": [c.to_json() for c in cards],
    }
    output_path.write_text(json.dumps(payload, indent=2, sort_keys=True, ensure_ascii=False), encoding="utf-8")

    print(render_preview(cards))
    print()
    print(f"Preview written to {output_path}")
    print(f"Edit that file to correct any 'needsReview' cards, then run:")
    print(f"  klarna-import apply {output_path} --carrycard-folder {carrycard_folder}")
    return 0


def _cmd_apply(args: argparse.Namespace) -> int:
    preview_path = Path(args.preview_file).expanduser().resolve()
    carrycard_folder = Path(args.carrycard_folder).expanduser().resolve()
    input_dir = preview_path.parent

    data = json.loads(preview_path.read_text(encoding="utf-8"))
    cards = [IntermediateCard.from_json(c) for c in data["cards"]]

    backup_root = carrycard_folder.parent / "backup-before-klarna-import"
    result = apply_import(cards, input_dir=input_dir, carrycard_folder=carrycard_folder, backup_root=backup_root)

    report = render_migration_report(cards, result.added, result.improved, result.skipped)
    print(report)

    report_path = preview_path.parent / "klarna-migration-report.txt"
    report_path.write_text(report, encoding="utf-8")
    print()
    print(f"Backup of the previous Carry-Card data: {backup_root}")
    print(f"Report written to: {report_path}")
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="klarna-import")
    subparsers = parser.add_subparsers(dest="command", required=True)

    scan_parser = subparsers.add_parser("scan", help="Scan screenshots and build an import preview.")
    scan_parser.add_argument("input_dir", help="Directory containing one subfolder per card (see README).")
    scan_parser.add_argument("--carrycard-folder", required=True, help="The Carry-Card sync folder, to detect duplicates.")
    scan_parser.add_argument("-o", "--output", help="Where to write the intermediate preview JSON (default: <input_dir>/preview.json).")
    scan_parser.set_defaults(func=_cmd_scan)

    apply_parser = subparsers.add_parser("apply", help="Apply a reviewed preview JSON into a real Carry-Card folder.")
    apply_parser.add_argument("preview_file", help="The (possibly hand-edited) preview.json from `scan`.")
    apply_parser.add_argument("--carrycard-folder", required=True, help="The Carry-Card sync folder to write into.")
    apply_parser.set_defaults(func=_cmd_apply)

    args = parser.parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
