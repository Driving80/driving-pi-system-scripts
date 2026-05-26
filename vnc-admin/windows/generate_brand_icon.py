"""Generate drivingtech-admin.ico for the VNC admin desktop shortcut.

Brand: drivingtech.it_ — slate background + lime terminal glyph + magenta cursor.
Output: multi-size .ico (256, 128, 64, 48, 32, 16) for Windows taskbar.
"""
from __future__ import annotations

from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

# Brand palette (acid triad on slate)
SLATE = (26, 29, 35)
LIME = (160, 255, 0)
MAGENTA = (255, 26, 140)

# Sizes to embed in the .ico
ICON_SIZES = [(256, 256), (128, 128), (64, 64), (48, 48), (32, 32), (16, 16)]


def _draw_frame(size: int) -> Image.Image:
    img = Image.new("RGBA", (size, size), SLATE + (255,))
    draw = ImageDraw.Draw(img)

    # Rounded corner mask (subtle, ~8% radius)
    radius = max(2, size // 12)
    draw.rounded_rectangle((0, 0, size - 1, size - 1), radius=radius, fill=SLATE + (255,))

    # Terminal prompt glyph: ">" centered, lime
    # Use default font; size proportionally
    glyph_size = max(8, int(size * 0.55))
    try:
        font = ImageFont.truetype("consola.ttf", glyph_size)
    except (OSError, IOError):
        try:
            font = ImageFont.truetype("DejaVuSansMono-Bold.ttf", glyph_size)
        except (OSError, IOError):
            font = ImageFont.load_default()

    text = ">"
    # Use textbbox if available (Pillow >= 10), else textsize fallback
    try:
        bbox = draw.textbbox((0, 0), text, font=font)
        tw, th = bbox[2] - bbox[0], bbox[3] - bbox[1]
        offset_x, offset_y = bbox[0], bbox[1]
    except AttributeError:
        tw, th = draw.textsize(text, font=font)
        offset_x = offset_y = 0

    x = (size - tw) // 2 - offset_x - int(size * 0.08)
    y = (size - th) // 2 - offset_y - int(size * 0.03)
    draw.text((x, y), text, font=font, fill=LIME + (255,))

    # Magenta cursor block to the right of the ">"
    cursor_w = max(2, int(size * 0.18))
    cursor_h = max(2, int(size * 0.04))
    cx = x + tw + max(1, int(size * 0.02))
    cy = y + th - cursor_h - int(size * 0.05)
    draw.rectangle((cx, cy, cx + cursor_w, cy + cursor_h), fill=MAGENTA + (255,))

    return img


def generate_icon(output_path: Path) -> None:
    """Generate a multi-size .ico at output_path."""
    output_path = Path(output_path)
    output_path.parent.mkdir(parents=True, exist_ok=True)

    # Largest frame is master; PIL packs others via sizes= param
    master = _draw_frame(ICON_SIZES[0][0])
    master.save(
        output_path,
        format="ICO",
        sizes=ICON_SIZES,
        bitmap_format="bmp",
    )


if __name__ == "__main__":
    default_out = Path(__file__).resolve().parent / "drivingtech-admin.ico"
    generate_icon(default_out)
    print(f"Generated: {default_out}")
