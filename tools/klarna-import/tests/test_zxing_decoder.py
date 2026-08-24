from klarna_import.zxing_decoder import decode_barcode_image

from .conftest import make_blank_image, make_code128_image, make_ean13_image, make_qr_image


def test_decodes_ean13_and_preserves_leading_zeros(tmp_path):
    path = tmp_path / "barcode.png"
    full_code = make_ean13_image("001234567891", path)
    assert full_code.startswith("00")

    result = decode_barcode_image(path)

    assert result.ok is True
    assert result.code == full_code
    assert isinstance(result.code, str)
    assert result.barcode_type == "ean13"
    assert result.confidence == "high"


def test_decodes_code128(tmp_path):
    path = tmp_path / "barcode.png"
    make_code128_image("A1B2C3D4E5", path)

    result = decode_barcode_image(path)

    assert result.ok is True
    assert result.code == "A1B2C3D4E5"
    assert result.barcode_type == "code128"


def test_decodes_qr_code(tmp_path):
    path = tmp_path / "barcode.png"
    make_qr_image("LOYALTY-12345-XYZ", path)

    result = decode_barcode_image(path)

    assert result.ok is True
    assert result.code == "LOYALTY-12345-XYZ"
    assert result.barcode_type == "qr"


def test_blank_image_yields_no_result(tmp_path):
    path = tmp_path / "barcode.png"
    make_blank_image(path)

    result = decode_barcode_image(path)

    assert result.ok is False
    assert "No barcode detected" in result.notes[0]


def test_unreadable_file_does_not_crash(tmp_path):
    path = tmp_path / "barcode.png"
    path.write_bytes(b"not an image")

    result = decode_barcode_image(path)

    assert result.ok is False
    assert "Could not open image" in result.notes[0]
