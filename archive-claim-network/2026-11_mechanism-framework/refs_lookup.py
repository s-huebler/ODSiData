#!/usr/bin/env python3
"""Look up references for a paper by number list, e.g.:
  python3 refs_lookup.py Moses_2026 3 4 9-15
Produces 'FirstAuthor Year (DOI)' separated by '; '
"""
import csv, sys, re
from pathlib import Path

BASE = Path("/Users/sophiehuebler/Documents/ODSi/ODSiData/claim-network/framework/raw")

def expand(args):
    out = []
    for a in args:
        if "-" in a:
            lo, hi = a.split("-", 1)
            out.extend(range(int(lo), int(hi)+1))
        else:
            out.append(int(a))
    return out

paper = sys.argv[1]
nums = expand(sys.argv[2:])

refs = {}
with (BASE / f"refs_{paper}.csv").open() as f:
    for r in csv.DictReader(f):
        refs[int(r["number"])] = r

parts = []
for n in nums:
    if n in refs:
        r = refs[n]
        doi = r["doi"]
        if doi:
            parts.append(f"{r['first_author']} {r['year']} ({doi})")
        else:
            parts.append(f"{r['first_author']} {r['year']}")
    else:
        parts.append(f"[{n}:missing]")
print("; ".join(parts))
