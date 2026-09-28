#!/usr/bin/env python3
"""Builds the dictionary bundled with JustSensei.

Layers, applied in this order — later ones never undo earlier ones:

  curated.json          hand-checked. Carries part of speech and JLPT level,
                        and the app treats those as authoritative.

  imported              ~6.8k Japanese/Korean pairs from the sibling JLPT study
                        app. Good glosses and readings; its level field was a
                        course tag, not a difficulty band, and was dropped. The
                        sibling project is not on every machine, so when it is
                        absent the previous build's imported rows are kept.

  corrections.json      fixes to imported rows, found by reviewing each gloss
                        against JMdict's English senses: Sino-Korean false
                        friends (配信 was 「배신」, betrayal), the gloss of
                        another reading (角 かく was 「뿔」, which is つの), typos
                        in readings (掻き消す かききえす).

  additions/*.json      new rows: the JLPT words the dictionary lacked, and
                        vocabulary idol lyrics lean on that no list has —
                        loanwords, onomatopoeia, fan words.

  data/jlpt-levels.tsv  JLPT levels (Jonathan Waller's lists, CC BY), filled in
                        where a row has none.

  data/jmdict-pos.tsv   parts of speech from JMdict (EDRDG, CC BY-SA 4.0),
                        filled in where a row has none. Regenerate it with
                        extract-jmdict.py when rows are added.

Usage:  python3 Scripts/build-dictionary.py [path/to/vocab.json]
"""
import json
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
SCRIPTS = ROOT / "Scripts"
CURATED = SCRIPTS / "curated.json"
CORRECTIONS = SCRIPTS / "corrections.json"
ADDITIONS = SCRIPTS / "additions"
LEVELS = SCRIPTS / "data" / "jlpt-levels.tsv"
POS = SCRIPTS / "data" / "jmdict-pos.tsv"
RESOURCES = ROOT / "Modules" / "JustSensei" / "Resources"
OUTPUT = RESOURCES / "seed-dictionary.json"
KANJI_OUTPUT = RESOURCES / "kanji-ko.json"
JLPT_APP = pathlib.Path.home() / "Git" / "jlpt-app" / "assets" / "data"
DEFAULT_IMPORT = JLPT_APP / "vocab.json"
DEFAULT_KANJI = JLPT_APP / "kanji_ko.json"

KANA = [(0x3040, 0x309F), (0x30A0, 0x30FF)]
CJK = [(0x4E00, 0x9FFF), (0x3400, 0x4DBF)]

# The app's PartOfSpeech raw values. Anything else decodes as 기타, so the
# older spellings are folded in rather than left to fall through.
PARTS = {"명사", "동사", "い형용사", "な형용사", "부사", "조사", "표현", "기타"}
PART_ALIASES = {"형용동사": "な형용사", "형용사": "い형용사", "관용구": "표현", "감동사": "표현"}
LEVELS_ALLOWED = {"N5", "N4", "N3", "N2", "N1"}


def is_japanese(text):
    return any(any(lo <= ord(c) <= hi for lo, hi in KANA + CJK) for c in text)


def read_tsv(path):
    rows = []
    for line in path.read_text().splitlines():
        if not line or line.startswith("#"):
            continue
        rows.append(line.split("\t"))
    return rows


def imported_rows(source, curated_keys):
    """The sibling app's rows, or — without it — the previous build's."""
    rows = []
    if source.exists():
        for row in json.loads(source.read_text()):
            word = (row.get("w") or "").strip()
            meaning = (row.get("m_ko") or "").strip()
            if not word or not meaning or not is_japanese(word):
                continue
            # Katakana headwords carry no separate reading in the source.
            reading = (row.get("r") or "").strip() or word
            rows.append({"l": word, "r": reading, "k": meaning})
        return rows, f"{source}"
    previous = json.loads(OUTPUT.read_text()) if OUTPUT.exists() else []
    rows = [r for r in previous if (r["l"], r["r"]) not in curated_keys]
    return rows, "the previous build"


def main():
    source = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT_IMPORT

    curated = json.loads(CURATED.read_text())
    curated_keys = {(r["l"], r["r"]) for r in curated}
    imported, origin = imported_rows(source, curated_keys)

    # Corrections apply to imported rows only; curated rows are already
    # checked, and a correction aimed at one is a mistake in the correction.
    fixes = {(c["l"], c["r"]): c for c in json.loads(CORRECTIONS.read_text())} if CORRECTIONS.exists() else {}
    corrected = 0
    for row in imported:
        fix = fixes.get((row["l"], row["r"]))
        if not fix:
            continue
        if fix.get("k"):
            row["k"] = fix["k"]
        if fix.get("r_new"):
            row["r"] = fix["r_new"]
        if fix.get("l_new"):
            row["l"] = fix["l_new"]
        corrected += 1

    additions = []
    for path in sorted(ADDITIONS.glob("*.json")) if ADDITIONS.exists() else []:
        additions += json.loads(path.read_text())

    entries, seen = [], set()
    counts = {"curated": 0, "imported": 0, "added": 0}
    for tier, rows in (("curated", curated), ("imported", imported), ("added", additions)):
        for row in rows:
            word, reading, meaning = row.get("l", "").strip(), row.get("r", "").strip(), row.get("k", "").strip()
            if not word or not reading or not meaning or not is_japanese(word):
                continue
            key = (word, reading)
            if key in seen:
                continue
            seen.add(key)
            entry = {"l": word, "r": reading, "k": meaning}
            part = PART_ALIASES.get(row.get("p"), row.get("p"))
            if part in PARTS:
                entry["p"] = part
            if row.get("j") in LEVELS_ALLOWED:
                entry["j"] = row["j"]
            entries.append(entry)
            counts[tier] += 1

    # Levels: exact (headword, reading) first; a headword alone only when the
    # list gives it one level, so 「上手」 as じょうず does not take the level of
    # うわて.
    exact, by_word = {}, {}
    for word, reading, level in read_tsv(LEVELS):
        exact.setdefault((word, reading), level)
        by_word.setdefault(word, set()).add(level)
    levelled = 0
    for entry in entries:
        if "j" in entry:
            continue
        level = exact.get((entry["l"], entry["r"]))
        if not level and len(by_word.get(entry["l"], ())) == 1:
            level = next(iter(by_word[entry["l"]]))
        if level:
            entry["j"] = level
            levelled += 1

    parts = {}
    if POS.exists():
        for word, reading, part in read_tsv(POS):
            parts[(word, reading)] = part
    tagged = 0
    for entry in entries:
        if "p" not in entry and (part := parts.get((entry["l"], entry["r"]))) in PARTS:
            entry["p"] = part
            tagged += 1

    # A build that loses most of the dictionary is a mistake, not an edit.
    if OUTPUT.exists() and "--shrink" not in sys.argv:
        previous = len(json.loads(OUTPUT.read_text()))
        if len(entries) < previous * 0.9:
            sys.exit(f"refusing to write: {len(entries)} entries would replace {previous}.")

    OUTPUT.write_text(json.dumps(entries, ensure_ascii=False, separators=(",", ":")) + "\n")
    with_level = sum(1 for e in entries if "j" in e)
    with_part = sum(1 for e in entries if "p" in e)
    print(
        f"{len(entries)} entries ({counts['curated']} curated, {counts['imported']} imported "
        f"from {origin}, {counts['added']} added); {corrected} corrected\n"
        f"levels: {with_level} ({levelled} filled from the JLPT lists); "
        f"parts of speech: {with_part} ({tagged} from JMdict)\n"
        f"-> {OUTPUT.relative_to(ROOT)} ({OUTPUT.stat().st_size // 1024} KB)"
    )


def build_kanji():
    """Korean sound/meaning readings for kanji (음/훈).

    A Korean learner already knows most of these characters from Sino-Korean
    vocabulary: seeing that 夢 is 「몽」 links it to 몽상 and 악몽 instantly, which
    is a shortcut no amount of Japanese-side explanation provides.
    """
    if not DEFAULT_KANJI.exists():
        print(f"note: {DEFAULT_KANJI} not found — kanji readings left as they are")
        return

    source = json.loads(DEFAULT_KANJI.read_text())
    table = {
        char: readings
        for char, readings in source.items()
        # Rows exist for characters with no Korean reading at all (々).
        if isinstance(readings, list) and len(readings) >= 1 and readings[0].strip()
    }
    KANJI_OUTPUT.write_text(json.dumps(table, ensure_ascii=False, separators=(",", ":")) + "\n")
    print(f"{len(table)} kanji -> {KANJI_OUTPUT.relative_to(ROOT)} ({KANJI_OUTPUT.stat().st_size // 1024} KB)")


if __name__ == "__main__":
    main()
    build_kanji()
