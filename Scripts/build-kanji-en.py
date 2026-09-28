#!/usr/bin/env python3
"""Builds kanji-en.json: an English meaning for each kanji the app ships,
taken from kanjidic2 (which is natively J->E).

The app's Korean kanji table (kanji-ko.json) fixes the character set; this
writes the same characters with their English meanings so an English reader gets
「dream, vision」 under 夢 where a Korean reader gets 「몽 · 꿈」.

kanjidic2 is not in the repository. Fetch kanjidic2-en-*.json from
github.com/scriptin/jmdict-simplified/releases.

kanjidic2 is © the Electronic Dictionary Research and Development Group,
CC BY-SA 4.0; the derived table carries the same licence.

Usage: python3 Scripts/build-kanji-en.py path/to/kanjidic2-en.json
"""
import json, sys, pathlib

kd_path = sys.argv[1]
root = pathlib.Path(__file__).resolve().parent.parent
ko = root / "Modules/RingRingSensei/Resources/kanji-ko.json"
out = root / "Modules/RingRingSensei/Resources/kanji-en.json"

charset = set(json.load(open(ko)).keys())
kd = json.load(open(kd_path))

meanings = {}
for c in kd["characters"]:
    lit = c["literal"]
    if lit not in charset:
        continue
    rm = c.get("readingMeaning")
    if not rm:
        continue
    ms = []
    for g in rm.get("groups", []):
        for m in g.get("meanings", []):
            if m.get("lang", "en") == "en":
                t = m["value"].strip()
                if t and t not in ms:
                    ms.append(t)
    if ms:
        # [sound, meaning] to match the Korean file's shape; sound stays empty
        # because the word's own furigana already gives the reading.
        meanings[lit] = ["", ", ".join(ms[:3])]

result = {c: meanings.get(c, ["", ""]) for c in charset}
json.dump(result, open(out, "w"), ensure_ascii=False)
have = sum(1 for c in charset if meanings.get(c))
print(f"kanji: {len(charset)}  with English: {have}")
