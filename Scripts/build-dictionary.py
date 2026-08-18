#!/usr/bin/env python3
"""Builds the dictionary bundled with JustSensei.

Two tiers go in, and the difference between them matters at runtime:

  curated.json   hand-checked. Carries part of speech and JLPT level, and the
                 app treats those as authoritative — they override whatever the
                 on-device model guessed.

  jlpt-app       ~6.8k Japanese/Korean pairs from the sibling JLPT study app.
                 Excellent glosses and readings, but its `lv` field is a course
                 tag (every row says "n1", including 안경 and 도서관), not a
                 difficulty band. Importing it as a JLPT level would be worse
                 than having none, so level and part of speech are dropped and
                 the model's guess is left standing for those words.

Usage:  python3 Scripts/build-dictionary.py [path/to/vocab.json]
"""
import json
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
CURATED = ROOT / "Scripts" / "curated.json"
OUTPUT = ROOT / "Modules" / "JustSensei" / "Resources" / "seed-dictionary.json"
DEFAULT_IMPORT = pathlib.Path.home() / "Git" / "jlpt-app" / "assets" / "data" / "vocab.json"

KANA = [(0x3040, 0x309F), (0x30A0, 0x30FF)]
CJK = [(0x4E00, 0x9FFF), (0x3400, 0x4DBF)]


def is_japanese(text):
    return any(
        any(lo <= ord(c) <= hi for lo, hi in KANA + CJK)
        for c in text
    )


def main():
    source = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT_IMPORT

    entries = []
    seen = set()

    # Curated first so it wins every collision.
    for row in json.loads(CURATED.read_text()):
        key = (row["l"], row["r"])
        seen.add(key)
        entries.append(row)

    imported = 0
    if source.exists():
        for row in json.loads(source.read_text()):
            word = (row.get("w") or "").strip()
            meaning = (row.get("m_ko") or "").strip()
            if not word or not meaning or not is_japanese(word):
                continue
            # Katakana headwords carry no separate reading in the source.
            reading = (row.get("r") or "").strip() or word
            key = (word, reading)
            if key in seen:
                continue
            seen.add(key)
            entries.append({"l": word, "r": reading, "k": meaning})
            imported += 1
    else:
        print(f"warning: {source} not found — writing curated entries only")

    OUTPUT.write_text(
        json.dumps(entries, ensure_ascii=False, separators=(",", ":")) + "\n"
    )
    print(
        f"{len(entries)} entries "
        f"({len(entries) - imported} curated, {imported} imported) "
        f"-> {OUTPUT.relative_to(ROOT)} "
        f"({OUTPUT.stat().st_size // 1024} KB)"
    )


if __name__ == "__main__":
    main()
