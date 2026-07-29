"""Match each ref to a paper_id in papers; populate refs.resolved_paper_id.

Match strategy, in order:
  1. DOI exact match (case-insensitive, stripped).
  2. Normalized title fuzzy match (rapidfuzz token_set_ratio >= threshold).
Refs that fail both keep resolved_paper_id = NULL and are listed at the end
so you can hand-fix obvious near-misses with UPDATE statements.

Without this step, the graph export only sees within-paper local numbers
and cannot form cross-paper edges -- so run this after every new PDF batch.

Usage (from citation-network/):
    python scripts/06_resolve_refs.py
    python scripts/06_resolve_refs.py --threshold 88 --db db/citations.sqlite
"""

import argparse
import re
import sqlite3
from typing import Optional

from rapidfuzz import fuzz, process


def normalize(s: Optional[str]) -> str:
    if not s:
        return ""
    s = s.lower()
    s = re.sub(r"[^a-z0-9 ]+", " ", s)
    s = re.sub(r"\s+", " ", s).strip()
    return s


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--db", default="db/citations.sqlite")
    ap.add_argument("--threshold", type=int, default=90,
                    help="rapidfuzz token_set_ratio score 0-100 for title match")
    ap.add_argument("--reset", action="store_true",
                    help="clear resolved_paper_id before matching")
    args = ap.parse_args()

    conn = sqlite3.connect(args.db)
    cur = conn.cursor()

    if args.reset:
        cur.execute("UPDATE refs SET resolved_paper_id = NULL")
        conn.commit()

    papers = cur.execute(
        "SELECT paper_id, title, doi FROM papers"
    ).fetchall()
    if not papers:
        print("no papers in the corpus yet")
        return

    by_doi = {p[2].lower().strip(): p[0] for p in papers if p[2]}
    titles_norm = {normalize(p[1]): p[0] for p in papers if p[1]}
    title_keys = list(titles_norm.keys())

    refs = cur.execute(
        "SELECT ref_id, doi, title FROM refs WHERE resolved_paper_id IS NULL"
    ).fetchall()

    matched_doi = matched_title = 0
    unresolved = []
    for ref_id, doi, title in refs:
        target = None
        if doi:
            target = by_doi.get(doi.lower().strip())
            if target:
                matched_doi += 1
        if not target and title and title_keys:
            best = process.extractOne(
                normalize(title), title_keys, scorer=fuzz.token_set_ratio
            )
            if best and best[1] >= args.threshold:
                target = titles_norm[best[0]]
                matched_title += 1
        if target:
            cur.execute(
                "UPDATE refs SET resolved_paper_id = ? WHERE ref_id = ?",
                (target, ref_id),
            )
        else:
            unresolved.append((ref_id, title or "(no title)"))

    conn.commit()
    conn.close()

    total = matched_doi + matched_title + len(unresolved)
    print(f"resolved by DOI:   {matched_doi}")
    print(f"resolved by title: {matched_title}")
    print(f"unresolved:        {len(unresolved)} / {total}")
    if unresolved:
        print("\nfirst 15 unresolved (ref_id  title):")
        for rid, t in unresolved[:15]:
            print(f"  {rid:>5}  {t[:90]}")
