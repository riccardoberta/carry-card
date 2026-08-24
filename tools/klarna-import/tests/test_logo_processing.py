from PIL import Image

from klarna_import.logo_processing import MAX_LOGO_DIMENSION, process_logo


def test_large_logo_is_resized_and_converted_to_jpeg(tmp_path):
    source = tmp_path / "logo.png"
    Image.new("RGB", (2000, 1000), "red").save(source)
    destination = tmp_path / "out.jpg"

    process_logo(source, destination)

    with Image.open(destination) as result:
        assert result.format == "JPEG"
        assert max(result.size) == MAX_LOGO_DIMENSION
        assert result.size == (MAX_LOGO_DIMENSION, MAX_LOGO_DIMENSION // 2)


def test_small_logo_is_not_upscaled(tmp_path):
    source = tmp_path / "logo.png"
    Image.new("RGB", (100, 50), "blue").save(source)
    destination = tmp_path / "out.jpg"

    process_logo(source, destination)

    with Image.open(destination) as result:
        assert result.size == (100, 50)


def test_transparent_png_is_flattened_to_rgb(tmp_path):
    source = tmp_path / "logo.png"
    Image.new("RGBA", (100, 100), (255, 0, 0, 128)).save(source)
    destination = tmp_path / "out.jpg"

    process_logo(source, destination)

    with Image.open(destination) as result:
        assert result.mode == "RGB"
