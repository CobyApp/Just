#!/usr/bin/env python3
"""Draw the minimal fallback icon used by release automation.

The shipped artwork is image-generated, while this deterministic version keeps
the same cream, coral note, and single lavender dot if the asset is rebuilt
offline. Nothing else is allowed into the mark: no text, gloss, or decoration.

Usage: python3 Scripts/make-icon.py
"""
import pathlib

from PIL import Image, ImageDraw

ROOT = pathlib.Path(__file__).resolve().parent.parent
OUTPUT = ROOT / "App" / "Resources" / "Assets.xcassets" / "AppIcon.appiconset" / "icon-1024.png"

SIZE = 1024
SCALE = 4
CREAM = (255, 248, 245)
PINK = (255, 95, 143)
LAVENDER = (140, 120, 247)


def scaled(values):
    return tuple(round(value * SCALE) for value in values)


def main():
    image = Image.new("RGB", (SIZE * SCALE, SIZE * SCALE), CREAM)
    draw = ImageDraw.Draw(image)

    draw.ellipse(scaled((244, 575, 474, 805)), fill=PINK)
    draw.ellipse(scaled((550, 625, 750, 825)), fill=PINK)
    draw.rounded_rectangle(scaled((392, 278, 474, 690)), radius=160, fill=PINK)
    draw.rounded_rectangle(scaled((668, 385, 750, 715)), radius=160, fill=PINK)
    draw.polygon(
        [scaled((414, 278)), scaled((750, 408)), scaled((750, 505)), scaled((414, 375))],
        fill=PINK,
    )
    draw.ellipse(scaled((772, 326, 842, 396)), fill=LAVENDER)

    image = image.resize((SIZE, SIZE), Image.Resampling.LANCZOS)

    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    image.save(OUTPUT, optimize=True)
    print(f"{OUTPUT.relative_to(ROOT)} ({OUTPUT.stat().st_size // 1024} KB)")


if __name__ == "__main__":
    main()
