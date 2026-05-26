"""Tests for generate_brand_icon.py — verifies .ico output multi-size and palette."""
from pathlib import Path
import struct
import sys

import pytest
from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "windows"))
from generate_brand_icon import generate_icon  # noqa: E402


def test_generates_ico_file(tmp_path: Path) -> None:
    out = tmp_path / "test.ico"
    generate_icon(out)
    assert out.exists()
    assert out.stat().st_size > 1000  # multi-size ico ~ several KB


def test_ico_has_multiple_sizes(tmp_path: Path) -> None:
    out = tmp_path / "test.ico"
    generate_icon(out)
    img = Image.open(out)
    # PIL exposes .ico sizes via .info or via iterating frames
    sizes = set()
    for size in img.info.get("sizes", []):
        sizes.add(size)
    # If sizes info absent, fall back to iterating
    if not sizes:
        i = 0
        while True:
            try:
                img.seek(i)
                sizes.add(img.size)
                i += 1
            except EOFError:
                break
    assert (256, 256) in sizes or (128, 128) in sizes, f"expected large size, got {sizes}"
    assert (16, 16) in sizes, f"expected 16x16, got {sizes}"


def test_palette_has_brand_colors(tmp_path: Path) -> None:
    """The largest frame should contain pixels matching brand colors (lime + slate)."""
    out = tmp_path / "test.ico"
    generate_icon(out)
    img = Image.open(out)
    # Seek to largest frame
    largest_idx = 0
    largest_size = 0
    i = 0
    while True:
        try:
            img.seek(i)
            if img.size[0] > largest_size:
                largest_size = img.size[0]
                largest_idx = i
            i += 1
        except EOFError:
            break
    img.seek(largest_idx)
    rgb = img.convert("RGB")
    pixels = list(rgb.getdata())

    # Brand lime #A0FF00 = (160, 255, 0) should appear (with tolerance for antialias)
    # lime has high R (~160), very high G (~255), and very low B (~0)
    lime_hits = sum(1 for r, g, b in pixels if r > 100 and g > 200 and b < 50)
    # Brand slate #1a1d23 should dominate background
    slate_hits = sum(1 for r, g, b in pixels if r < 40 and g < 40 and b < 50)

    assert lime_hits > 10, f"too few lime pixels: {lime_hits}"
    assert slate_hits > len(pixels) // 4, f"slate should dominate: {slate_hits}/{len(pixels)}"
