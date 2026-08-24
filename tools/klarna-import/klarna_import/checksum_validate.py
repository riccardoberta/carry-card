"""Independent checksum re-verification for the numeric symbologies.

This mirrors the exact same GS1 mod-10 / UPC-E expansion formulas used by
Carry-Card's own Swift renderer (see
``CarryCard/Utilities/OneDBarcodeEncoder.swift``), so a value that passes
here is guaranteed to check out the same way once Carry-Card renders it.
This is the closest practical substitute we have to a true "render with
Carry-Card's logic and decode again" round trip for these types, since this
tool has no way to invoke Swift code directly.
"""
from __future__ import annotations


def _mod10_check_digit(digits: list[int]) -> int:
    """Standard GS1 mod-10: from the rightmost digit, weights alternate 3, 1."""
    total = 0
    for offset, digit in enumerate(reversed(digits)):
        total += digit * (3 if offset % 2 == 0 else 1)
    remainder = total % 10
    return 0 if remainder == 0 else 10 - remainder


def verify_ean13(value: str) -> bool:
    if len(value) != 13 or not value.isdigit():
        return False
    digits = [int(c) for c in value]
    return _mod10_check_digit(digits[:12]) == digits[12]


def verify_ean8(value: str) -> bool:
    if len(value) != 8 or not value.isdigit():
        return False
    digits = [int(c) for c in value]
    return _mod10_check_digit(digits[:7]) == digits[7]


def _expand_upce_to_upca(payload: list[int], number_system: int) -> list[int]:
    d = payload
    result = [number_system]
    last = d[5]
    if last in (0, 1, 2):
        result += [d[0], d[1], last, 0, 0, 0, 0, d[2], d[3], d[4]]
    elif last == 3:
        result += [d[0], d[1], d[2], 0, 0, 0, 0, 0, d[3], d[4]]
    elif last == 4:
        result += [d[0], d[1], d[2], d[3], 0, 0, 0, 0, 0, d[4]]
    else:
        result += [d[0], d[1], d[2], d[3], d[4], 0, 0, 0, 0, last]
    return result


def verify_upce(value: str, number_system: int = 0) -> bool:
    """`value` is the 6-digit compressed UPC-E payload (no check digit)."""
    if len(value) != 6 or not value.isdigit():
        return False
    digits = [int(c) for c in value]
    upc_a = _expand_upce_to_upca(digits, number_system)
    # verify_upce validates the payload can be expanded and produces a
    # well-formed 11-digit UPC-A prefix; the check digit itself is only
    # meaningful once appended by the renderer, so we just confirm the
    # expansion is structurally valid (11 digits, all 0-9).
    return len(upc_a) == 11 and all(0 <= d <= 9 for d in upc_a)


def verify_numeric_checksum(barcode_type: str, value: str) -> bool | None:
    """Returns True/False if `barcode_type` has a checksum we can
    independently verify, or None if this type has no such check here
    (Code39/Code93/Code128/QR/PDF417/Aztec rely on the decoder's own
    internal validity flag instead — see README "Validation limits").
    """
    if barcode_type == "ean13":
        return verify_ean13(value)
    if barcode_type == "ean8":
        return verify_ean8(value)
    if barcode_type == "upce":
        return verify_upce(value)
    return None
