from klarna_import.checksum_validate import verify_ean13, verify_ean8, verify_upce, verify_numeric_checksum


def test_verify_ean13_accepts_valid_check_digit():
    assert verify_ean13("4006381333931") is True


def test_verify_ean13_rejects_wrong_check_digit():
    assert verify_ean13("4006381333930") is False


def test_verify_ean13_preserves_and_checks_leading_zero_values():
    # 001234567891 + check digit 2 = 0012345678912
    assert verify_ean13("0012345678912") is True


def test_verify_ean8_accepts_valid_check_digit():
    assert verify_ean8("96385074") is True


def test_verify_ean8_rejects_wrong_length():
    assert verify_ean8("1234567") is False


def test_verify_upce_accepts_well_formed_payload():
    assert verify_upce("425261") is True


def test_verify_upce_rejects_non_digit():
    assert verify_upce("42526A") is False


def test_verify_numeric_checksum_dispatches_by_type():
    assert verify_numeric_checksum("ean13", "4006381333931") is True
    assert verify_numeric_checksum("code128", "ANYTHING") is None
    assert verify_numeric_checksum("qr", "ANYTHING") is None
