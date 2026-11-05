#!/usr/bin/env python3
"""Check a review's proposals.json against the codebook before it goes to the viewer.

    python3 claim-network/scripts/validate_proposals.py guo2024

Checks: required keys, controlled values, derived fields (mechanism_broad, target_type), ID
format and uniqueness, and that every quote is found verbatim in the paper text. Exits 1 on any
error. Quote matching here approximates the viewer; the viewer's own 'not placed' list is final.
"""
import re, sys
from claimlib import (REVIEWS, SKILLS, VOCAB, FIELDS, load_json, mechanism_broad, markdown_plain,
                      norm_text)

TOP = ["paper_key", "skill", "citing_bibtex", "statement_prefix", "codebook_version", "title", "items"]


def main(key):
    p = load_json(REVIEWS / key / "proposals.json")
    if p is None:
        sys.exit(f"missing reviews/{key}/proposals.json")
    errs, warns = [], []
    for k in TOP:
        if k not in p:
            errs.append(f"top-level key missing: {k}")
    md_path = SKILLS / p.get("skill", "?") / "references" / "paper.md"
    text = markdown_plain(md_path.read_text(encoding="utf-8")) if md_path.exists() else ""
    if not text:
        errs.append(f"paper text not found: {md_path}")
    pre = p.get("statement_prefix", "")
    seen = set()
    for it in p.get("items", []):
        i = it.get("id", "?")
        if i in seen: errs.append(f"{i}: duplicate id")
        seen.add(i)
        kind = it.get("kind")
        pat = rf"^{pre}_\d{{3}}$" if kind == "proposal" else rf"^{pre}_S\d{{2}}$"
        if not re.match(pat, i): errs.append(f"{i}: id does not match {pat}")
        if kind not in ("proposal", "skipped"): errs.append(f"{i}: kind must be proposal or skipped")
        for k in ("quote", "location"):
            if not it.get(k): errs.append(f"{i}: missing {k}")
        if text and it.get("quote") and norm_text(it["quote"]) not in text:
            errs.append(f"{i}: quote not found in paper text: {it['quote'][:70]}...")
        if kind == "skipped":
            if not it.get("note"): errs.append(f"{i}: skipped item needs a reason in note")
            continue
        f = it.get("fields", {})
        for k in FIELDS:
            if k not in f: errs.append(f"{i}: field missing: {k}")
        for k, allowed in VOCAB.items():
            if k in f and f[k] not in allowed: errs.append(f"{i}: {k}={f[k]!r} not in codebook values")
        if f.get("mechanism_specific") and f.get("mechanism_broad") != mechanism_broad(f["mechanism_specific"]):
            errs.append(f"{i}: mechanism_broad should be {mechanism_broad(f['mechanism_specific'])!r}")
        want_tt = "mechanism" if f.get("taxon_rank_as_cited") == "functional group" else "taxon"
        if f.get("target_type") != want_tt: errs.append(f"{i}: target_type should be {want_tt}")
        if not f.get("taxon_as_cited"): errs.append(f"{i}: taxon_as_cited empty")
        if not f.get("ref_string"): warns.append(f"{i}: uncited")
    n = sum(it.get("kind") == "proposal" for it in p.get("items", []))
    s = sum(it.get("kind") == "skipped" for it in p.get("items", []))
    print(f"{key}: {n} proposals, {s} skipped, codebook {p.get('codebook_version')}")
    for w in warns: print("  warn:", w)
    for e in errs: print("  ERROR:", e)
    print("OK" if not errs else f"{len(errs)} error(s)")
    return 1 if errs else 0


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    sys.exit(main(sys.argv[1]))
