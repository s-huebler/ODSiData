#!/usr/bin/env python3
"""Manually correct is_references for each paper based on human inspection."""
import csv
from pathlib import Path

BASE = Path("/Users/sophiehuebler/Documents/ODSi/ODSiData/claim-network/framework/text")

# Reference pages per paper (pages that are mostly or entirely references)
REFS = {
    "Moses_2026":      [12, 13, 14, 15, 16, 17],
    "Paredes_2026":    [19, 20, 21, 22, 23],
    "Samarkhazan_2025":[13, 14, 15],  # p12 has main text + refs start; p15 is tail
    "Weber_2026":      [8, 9, 10],    # p4 has References column header in Table 2
}

for paper, ref_pages in REFS.items():
    pidx = BASE / paper / "page_index.csv"
    rows = []
    with pidx.open() as f:
        reader = csv.DictReader(f)
        for r in reader:
            r["is_references"] = str(int(r["page"]) in ref_pages)
            rows.append(r)
    with pidx.open("w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=rows[0].keys())
        writer.writeheader()
        for r in rows:
            writer.writerow(r)
    print(f"Updated {pidx}")
