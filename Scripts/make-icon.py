#!/usr/bin/env python3
"""Draws the app icon.

A heart with 「歌」 — song — inside it, and sparkles around it.

The mark has to say two things at once: idols, and Japanese. A kanji alone said
the second and not the first, which was right for a J-pop study app and is
wrong for this one. A heart alone says the first and not the second, and there
are a thousand pink heart icons. The kanji inside is what joins them.

A speech-bubble tail was tried and dropped: a heart already ends in a point, so
a tail gave the silhouette two of them and it read as a rendering mistake at
small sizes. The sparkles say 「idol」 without touching the outline, and they
are the same mark the app's own tab bar uses.

Bright, because the app opens bright. The dark half is the lyrics screen, and an
icon should look like the screen you see first.

Usage:  python3 Scripts/make-icon.py
"""
import math
import pathlib

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = pathlib.Path(__file__).resolve().parent.parent
OUTPUT = ROOT / "App" / "Resources" / "Assets.xcassets" / "AppIcon.appiconset" / "icon-1024.png"

SIZE = 1024
JAPANESE = "/System/Library/Fonts/ヒラギノ角ゴシック W7.ttc"

# The group cards' own family: hot pink into a softer coral, on cream.
TOP_LEFT = (255, 209, 232)
BOTTOM_RIGHT = (255, 233, 214)
HEART_TOP = (255, 92, 147)
HEART_BOTTOM = (255, 138, 106)
INK = (255, 255, 255)


def gradient(size, top_left, bottom_right):
    """Diagonal two-colour ramp."""
    image = Image.new("RGB", (size, size))
    pixels = image.load()
    for y in range(size):
        for x in range(size):
            t = (x + y) / (2 * (size - 1))
            pixels[x, y] = tuple(
                round(a + (b - a) * t) for a, b in zip(top_left, bottom_right)
            )
    return image


def heart_mask(size, scale=0.62, drop=0.46):
    """A heart, drawn from its own equation rather than two circles.

    Two circles and a triangle leaves corners where they meet; the parametric
    curve is smooth all the way round, which matters at 40pt where a kink reads
    as a rendering error.
    """
    mask = Image.new("L", (size, size), 0)
    draw = ImageDraw.Draw(mask)
    points = []
    for step in range(721):
        t = math.radians(step / 2)
        x = 16 * math.sin(t) ** 3
        y = 13 * math.cos(t) - 5 * math.cos(2 * t) - 2 * math.cos(3 * t) - math.cos(4 * t)
        points.append(
            (
                size / 2 + x * size * scale / 32,
                size * drop - y * size * scale / 32,
            )
        )
    draw.polygon(points, fill=255)
    return mask


def sparkle(draw, cx, cy, r, fill):
    """A four-point star, the idol mark."""
    pinch = r * 0.28
    draw.polygon(
        [
            (cx, cy - r), (cx + pinch, cy - pinch), (cx + r, cy), (cx + pinch, cy + pinch),
            (cx, cy + r), (cx - pinch, cy + pinch), (cx - r, cy), (cx - pinch, cy - pinch),
        ],
        fill=fill,
    )


def main():
    base = gradient(SIZE, TOP_LEFT, BOTTOM_RIGHT)

    shape = heart_mask(SIZE, scale=0.60, drop=0.50)

    # A soft shadow under the heart, so it sits on the cream rather than in it.
    shadow = shape.filter(ImageFilter.GaussianBlur(SIZE * 0.03))
    base.paste(Image.new("RGB", (SIZE, SIZE), (214, 150, 178)), (0, int(SIZE * 0.012)), shadow)

    heart = gradient(SIZE, HEART_TOP, HEART_BOTTOM)
    base.paste(heart, (0, 0), shape)

    # 歌 inside it. Sized to the heart's waist rather than the canvas, or it
    # spills over the curve where the two lobes meet.
    draw = ImageDraw.Draw(base)

    # Sparkles: one large, two small, placed where the heart leaves room.
    sparkle(draw, SIZE * 0.80, SIZE * 0.20, SIZE * 0.075, INK)
    sparkle(draw, SIZE * 0.17, SIZE * 0.30, SIZE * 0.045, INK)
    sparkle(draw, SIZE * 0.86, SIZE * 0.66, SIZE * 0.035, INK)

    font = ImageFont.truetype(JAPANESE, int(SIZE * 0.30))
    box = draw.textbbox((0, 0), "歌", font=font)
    draw.text(
        (
            (SIZE - (box[2] - box[0])) / 2 - box[0],
            SIZE * 0.47 - (box[3] - box[1]) / 2 - box[1],
        ),
        "歌",
        font=font,
        fill=INK,
    )

    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    base.save(OUTPUT)
    print(f"{OUTPUT.relative_to(ROOT)} ({OUTPUT.stat().st_size // 1024} KB)")


if __name__ == "__main__":
    main()
