#!/usr/bin/env python3
import os
import re
import csv
from pathlib import Path

BASE = Path("/Users/sophiehuebler/Documents/ODSi/ODSiData/claim-network/framework/text")

def analyze_page(txt):
    has_figure = bool(re.search(r"(?:Figure|Fig\.)\s*\d", txt))
    has_table = bool(re.search(r"Table\s+\d", txt))
    has_box = bool(re.search(r"Box\s+\d", txt))

    # References heading detection
    is_references = False
    lines = txt.splitlines()
    for i, line in enumerate(lines):
        stripped = line.strip()
        if re.match(r"^(References|REFERENCES|Bibliography|Literature Cited)\s*$", stripped):
            is_references = True
            break
    # Heuristic: if page has heavy prevalence of ref-list patterns
    if not is_references:
        ref_pattern = re.compile(r"^\s*(\d+\.?\s+[A-Z][A-Za-z]+|[A-Z][A-Za-z]+ [A-Z]{1,3}[,\s])")
        matches = sum(1 for line in lines if ref_pattern.match(line))
        nonblank = sum(1 for line in lines if line.strip())
        if nonblank > 0 and matches / nonblank > 0.35 and nonblank > 10:
            is_references = True

    words = len(txt.split())
    return has_figure, has_table, has_box, is_references, words

for paper_dir in BASE.iterdir():
    if not paper_dir.is_dir():
        continue
    rows = []
    pages = sorted(paper_dir.glob("p*.txt"))
    for p in pages:
        page_num = int(p.stem[1:])
        txt = p.read_text(encoding="utf-8", errors="ignore")
        hf, ht, hb, isr, w = analyze_page(txt)
        rows.append((page_num, hf, ht, hb, isr, w))
    out = paper_dir / "page_index.csv"
    with out.open("w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["page", "has_figure", "has_table", "has_box", "is_references", "words"])
        for row in rows:
            writer.writerow(row)
    print(f"Wrote {out} with {len(rows)} rows")
