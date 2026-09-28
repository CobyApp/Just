#!/usr/bin/env python3
"""Builds seed-dictionary-en.json: the same headword set as the Korean seed,
with English meanings taken straight from JMdict (which is natively J->E).

Usage: python3 build-en-dict.py jmdict-eng.json /Users/coby/Git/Just
"""
import json, sys, pathlib

jmdict_path, repo = sys.argv[1], pathlib.Path(sys.argv[2])
seed_ko = repo / "Modules/RingRingSensei/Resources/seed-dictionary.json"
out = repo / "Modules/RingRingSensei/Resources/seed-dictionary-en.json"

jm = json.load(open(jmdict_path))
words = jm["words"]

# Index words by every kanji and kana surface they carry.
by_kanji, by_kana = {}, {}
for i, w in enumerate(words):
    for k in w.get("kanji", []):
        by_kanji.setdefault(k["text"], []).append(i)
    for k in w.get("kana", []):
        by_kana.setdefault(k["text"], []).append(i)

def kana_of(w):
    return {k["text"] for k in w.get("kana", [])}

def glosses(w, limit=3):
    """First sense's English glosses (a couple more from the next sense when the
    first is thin), commas between, capped so a card stays short."""
    out = []
    for sense in w.get("sense", []):
        for g in sense.get("gloss", []):
            if g.get("lang", "eng") == "eng":
                t = g["text"].strip()
                if t and t not in out:
                    out.append(t)
        if len(out) >= limit:
            break
    return ", ".join(out[:limit])

def best_english(l, r):
    # Words where the seed headword appears, kanji first (more specific).
    cands = by_kanji.get(l, []) + by_kana.get(l, [])
    if not cands:
        return None
    # Prefer a candidate whose reading matches the seed's.
    for i in cands:
        if r in kana_of(words[i]):
            g = glosses(words[i])
            if g:
                return g
    for i in cands:
        g = glosses(words[i])
        if g:
            return g
    return None

seed = json.load(open(seed_ko))
result = []
matched = 0
misses = []
for e in seed:
    en = best_english(e["l"], e["r"])
    if en:
        matched += 1
    else:
        misses.append(f'{e["l"]}({e["r"]})')
        en = e["k"]  # fall back to the Korean rather than shipping a blank card
    result.append({"l": e["l"], "r": e["r"], "k": en,
                   "p": e.get("p"), "j": e.get("j")})

json.dump(result, open(out, "w"), ensure_ascii=False)
print(f"entries: {len(result)}  matched: {matched} ({matched*100//len(result)}%)  misses: {len(misses)}")
print("first misses:", misses[:30])
