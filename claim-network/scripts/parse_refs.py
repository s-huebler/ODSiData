#!/usr/bin/env python3
"""Parse a review's reference list from its paper skill into reviews/<paper>/refs.csv.

    python3 claim-network/scripts/parse_refs.py guo2024

Reads the REFERENCES section of .claude/skills/<skill>/references/paper.md. Numbered lists use
the printed number; unnumbered (author-year) lists are numbered in printed order, which is how
the citation dictionary numbers them. Each reference is cross-checked against the citation
dictionary: the parsed first author must appear in the dictionary's full_citation for the same
number (column dict_match). A low match rate means the numbering disagrees and must be fixed
before linking.
"""
import re, sys
from claimlib import REVIEWS, SKILLS, DICTIONARY, load_json, read_csv, write_csv, ascii_lower

YEAR_RULES = [r"\((19|20)\d{2}[a-z]?\)", r"\b(19|20)\d{2}[a-z]?;", r"\b(19|20)\d{2}[a-z]?\.", r"\b(19|20)\d{2}\b"]


def first_author(t):
    t = re.sub(r"[*_]", "", t).strip()
    lead = re.match(r"^(?:[A-Z][a-z]?\.-?\s?)+\s*([A-Za-z][^,.;]{1,40}?)\s*,", t)
    if lead:                             # leading initials: "E.B. Margolis, ..." -> "Margolis"
        return lead.group(1)
    head = re.split(r",| et al| and |\.\s", t, maxsplit=1)[0]
    toks = head.split()
    while len(toks) > 1 and re.fullmatch(r"([A-Z]\.?-?){1,4}", toks[-1]):
        toks.pop()                       # drop trailing initials: "Taur Y" -> "Taur"
    return " ".join(toks).strip(" .")


def year_of(t):
    body = t.split(". ", 1)[1] if ". " in t else t     # skip the author block
    for rule in YEAR_RULES:
        m = re.search(rule, body)
        if m: return re.search(r"(19|20)\d{2}", m.group(0)).group(0)
    return ""


def parse(md):
    m = re.search(r"^#{1,3}\s*references?\b.*$", md, flags=re.I | re.M)
    if not m:
        sys.exit("No REFERENCES heading found in paper.md")
    rest = md[m.end():]
    nxt = re.search(r"^#{1,3}\s", rest, flags=re.M)
    block = rest[:nxt.start()] if nxt else rest
    entries = [e.strip() for e in re.split(r"\n\s*\n", block) if e.strip()]
    out = []
    numbered = sum(bool(re.match(r"^\[?\d+[.\]]\s", e)) for e in entries) > len(entries) / 2
    for i, e in enumerate(entries, 1):
        e = re.sub(r"\s+", " ", e)
        if numbered:
            mm = re.match(r"^\[?(\d+)[.\]]\s+(.*)", e)
            if not mm: continue
            n, t = int(mm.group(1)), mm.group(2)
        else:
            n, t = i, re.sub(r"^[-*]\s+", "", e)
        doi = re.search(r"10\.\d{4,9}/[^\s,;]+", t)
        out.append(dict(number=n, first_author=first_author(t), year=year_of(t),
                        doi=doi.group(0).rstrip(".") if doi else "", text=t))
    return out


def main(key):
    p = load_json(REVIEWS / key / "proposals.json")
    md = (SKILLS / p["skill"] / "references" / "paper.md").read_text(encoding="utf-8")
    refs = parse(md)
    dic = {int(r["local_number"]): r for r in read_csv(DICTIONARY) if r["citing_bibtex"] == p["citing_bibtex"]}
    ok = 0
    for r in refs:
        d = dic.get(r["number"])
        if d is None:
            r["dict_match"] = "not_in_dictionary"
        else:
            surname = ascii_lower(r["first_author"]).split(" ")[-1] if r["first_author"] else ""
            hit = bool(surname) and surname in ascii_lower(d["full_citation"])
            r["dict_match"] = "TRUE" if hit else "FALSE"
            ok += hit
    write_csv(REVIEWS / key / "refs.csv", refs, ["number", "first_author", "year", "doi", "dict_match", "text"])
    print(f"{key}: {len(refs)} references parsed; dictionary has {len(dic)} for {p['citing_bibtex']}; "
          f"first author agrees for {ok}/{len(refs)}")
    bad = [r for r in refs if r["dict_match"] != "TRUE"]
    for r in bad[:15]:
        d = dic.get(r["number"], {})
        print(f"  [{r['number']}] {r['dict_match']}: parsed '{r['first_author']}' | dictionary: {d.get('full_citation', '')[:90]}")
    if len(bad) > 15: print(f"  ... {len(bad) - 15} more")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    main(sys.argv[1])
