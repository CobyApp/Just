#!/usr/bin/env python3
"""Draws the app icon.

One character: 歌, "song". The earlier version stacked its furigana above it,
which was a neat summary of what the app does and too much for an icon — at
40pt the reading was texture, not information, and the kanji was already
carrying recognition on its own. An app called Just should not need two marks.

Usage:  python3 Scripts/make-icon.py
"""
import pathlib

from PIL import Image, ImageDraw, ImageFont

ROOT = pathlib.Path(__file__).resolve().parent.parent
OUTPUT = ROOT / "App" / "Resources" / "Assets.xcassets" / "AppIcon.appiconset" / "icon-1024.png"

SIZE = 1024
JAPANESE = "/System/Library/Fonts/ヒラギノ角ゴシック W7.ttc"

# Same family as the player's mesh background: deep indigo drifting to plum.
TOP_LEFT = (20, 20, 32)
BOTTOM_RIGHT = (52, 34, 68)
GLOW = (104, 78, 150)


def background():
    """Diagonal gradient with a soft glow behind the glyph."""
    base = Image.new("RGB", (SIZE, SIZE))
    pixels = base.load()
    for y in range(SIZE):
        for x in range(SIZE):
            # Diagonal position, normalised.
            t = (x + y) / (2 * SIZE - 2)
            pixels[x, y] = tuple(
                round(TOP_LEFT[i] + (BOTTOM_RIGHT[i] - TOP_LEFT[i]) * t)
                for i in range(3)
            )

    glow = Image.new("RGB", (SIZE, SIZE), (0, 0, 0))
    draw = ImageDraw.Draw(glow)
    centre = SIZE * 0.54
    radius = SIZE * 0.48
    # Concentric discs approximate a radial falloff without a blur pass.
    steps = 60
    for step in range(steps, 0, -1):
        fraction = step / steps
        r = radius * fraction
        intensity = (1 - fraction) ** 2
        draw.ellipse(
            [centre - r, centre - r, centre + r, centre + r],
            fill=tuple(round(c * intensity) for c in GLOW),
        )
    return Image.blend(base, Image.blend(base, glow, 0.0), 0.0) if False else _screen(base, glow)


def _screen(base, glow):
    """Screen blend: lightens without washing the gradient out."""
    out = base.copy()
    b = base.load()
    g = glow.load()
    o = out.load()
    for y in range(SIZE):
        for x in range(SIZE):
            br, bg, bb = b[x, y]
            gr, gg, gb = g[x, y]
            o[x, y] = (
                255 - (255 - br) * (255 - gr) // 255,
                255 - (255 - bg) * (255 - gg) // 255,
                255 - (255 - bb) * (255 - gb) // 255,
            )
    return out


def centred(draw, text, font, centre_x, baseline_y, fill):
    left, top, right, bottom = draw.textbbox((0, 0), text, font=font)
    draw.text(
        (centre_x - (left + right) / 2, baseline_y - (top + bottom) / 2),
        text,
        font=font,
        fill=fill,
    )


def main():
    image = background()
    draw = ImageDraw.Draw(image)

    # Sized to sit inside the ~80% safe area an iOS mask leaves; a glyph that
    # reaches the edge looks cramped once the corners round off.
    kanji = ImageFont.truetype(JAPANESE, 470)
    centred(draw, "歌", kanji, SIZE / 2, SIZE / 2, (255, 255, 255))

    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    image.save(OUTPUT)
    print(f"{OUTPUT.relative_to(ROOT)} ({OUTPUT.stat().st_size // 1024} KB)")

    # A contact sheet for eyeballing small-size legibility. Written outside the
    # asset catalog so Xcode never treats it as a shipped image.
    sheet = Image.new("RGB", (520, 200), (150, 150, 155))
    x = 20
    for size in (180, 120, 60, 40):
        sheet.paste(image.resize((size, size), Image.LANCZOS), (x, (200 - size) // 2))
        x += size + 20
    sheet_path = ROOT / "Scripts" / "icon-sizes.png"
    sheet.save(sheet_path)
    print(f"{sheet_path.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
