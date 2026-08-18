#!/usr/bin/env python3
"""Draws the app icon.

The mark is 歌 ("song") carrying its own furigana, うた. That pairing *is* the
app: a Japanese word with its reading printed above it. The ruby is sized so it
reads as an annotation at large sizes and settles into a light accent stroke at
40pt, leaving the kanji to carry recognition on its own.

Usage:  python3 Scripts/make-icon.py
"""
import pathlib

from PIL import Image, ImageDraw, ImageFont

ROOT = pathlib.Path(__file__).resolve().parent.parent
OUTPUT = ROOT / "App" / "Resources" / "Assets.xcassets" / "AppIcon.appiconset" / "icon-1024.png"

SIZE = 1024
JAPANESE = "/System/Library/Fonts/ヒラギノ角ゴシック W7.ttc"

# Same family as the player's mesh background: deep indigo drifting to plum.
TOP_LEFT = (18, 19, 34)
BOTTOM_RIGHT = (58, 36, 74)
GLOW = (128, 96, 168)


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
    radius = SIZE * 0.42
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

    # Sized so the pair sits inside the ~80% safe area an iOS mask leaves;
    # a glyph that reaches the edge looks cramped once the corners round off.
    kanji = ImageFont.truetype(JAPANESE, 400)
    ruby = ImageFont.truetype(JAPANESE, 104)

    centre_x = SIZE / 2
    centred(draw, "歌", kanji, centre_x, SIZE * 0.568, (255, 255, 255))
    # Sits above the kanji the way furigana does, in the app's muted ink.
    centred(draw, "うた", ruby, centre_x, SIZE * 0.285, (198, 188, 222))

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
