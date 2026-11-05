#!/usr/bin/env python3
"""Parse the References section of each paper into a CSV with (number, first_author, year, doi)."""
import re
import csv
from pathlib import Path

BASE = Path("/Users/sophiehuebler/Documents/ODSi/ODSiData/claim-network/framework/text_raw")
RAW = Path("/Users/sophiehuebler/Documents/ODSi/ODSiData/claim-network/framework/raw")
RAW.mkdir(exist_ok=True)

# Which pages hold references for each paper
REF_RANGES = {
    "Moses_2026":      list(range(12, 18)),
    "Paredes_2026":    list(range(19, 24)),
    "Samarkhazan_2025":list(range(12, 16)),
    "Weber_2026":      [8, 9, 10],
}

# Where references actually start on the first page (lines to skip up through "References")
def gather_text(paper):
    pages = REF_RANGES[paper]
    out = []
    for pn in pages:
        p = BASE / paper / f"p{pn:02d}.txt"
        txt = p.read_text(encoding="utf-8", errors="ignore")
        out.append(txt)
    return "\n".join(out)

def normalize_text(txt):
    # strip page banner lines
    cleaned = []
    for line in txt.splitlines():
        s = line.strip()
        if not s:
            continue
        # drop lone page numbers or banner lines
        if re.match(r"^(GUT MICROBES|\d+\s*$|.*Soleimani Samarkhazan.*|.*Bone Marrow Transplantation.*|.*Nature Reviews Cancer.*|.*A\. B\. MOSES AND A\. C\. YEH.*|.*D\. Weber.*|Review article\s*$|Page \d+ of \d+)", s):
            continue
        cleaned.append(line.rstrip())
    return cleaned

def parse_moses(lines):
    """Moses refs look like:   N. Authors. Title. Journal. YYYY;...  doi: 10.XX/..."""
    # Join lines into ref chunks by detecting leading number pattern
    entries = []
    cur = None
    pat = re.compile(r"^\s*(\d+)\.\s+(.*)")
    for line in lines:
        m = pat.match(line)
        if m:
            if cur is not None:
                entries.append(cur)
            cur = {"number": int(m.group(1)), "text": m.group(2)}
        else:
            if cur is not None:
                cur["text"] += " " + line.strip()
    if cur is not None:
        entries.append(cur)
    rows = []
    for e in entries:
        t = e["text"]
        # first author = word before first space or comma
        m_auth = re.match(r"((?:[Vv]an\s+(?:den\s+|der\s+)?|[Dd]e\s+|[Dd]a\s+|[Ll]e\s+)?[A-Z][A-Za-zÀ-ÿ\-']+)", t)
        first_author = m_auth.group(1).strip() if m_auth else ""
        m_year = re.search(r"\b(19|20)\d{2}\b", t)
        year = m_year.group(0) if m_year else ""
        m_doi = re.search(r"doi:\s*(10\.\S+?)(?:\.$|\s|$)", t, re.IGNORECASE)
        if not m_doi:
            m_doi = re.search(r"(10\.\d{4,9}/[^\s;]+)", t)
        doi = m_doi.group(1).rstrip(".,;") if m_doi else ""
        rows.append({"number": e["number"], "first_author": first_author, "year": year, "doi": doi})
    return rows

def parse_paredes(lines):
    """Paredes refs:  N.    Author, X. & Author, Y. Title. Journal YY, pages (YYYY)."""
    entries = []
    cur = None
    pat = re.compile(r"^\s*(\d+)\.\s+(.*)")
    for line in lines:
        m = pat.match(line)
        if m:
            if cur is not None:
                entries.append(cur)
            cur = {"number": int(m.group(1)), "text": m.group(2)}
        else:
            if cur is not None:
                cur["text"] += " " + line.strip()
    if cur is not None:
        entries.append(cur)
    rows = []
    for e in entries:
        t = e["text"]
        m_auth = re.match(r"((?:[Vv]an\s+(?:den\s+|der\s+)?|[Dd]e\s+|[Dd]a\s+|[Ll]e\s+)?[A-Z][A-Za-zÀ-ÿ\-']+)", t)
        first_author = m_auth.group(1).strip() if m_auth else ""
        m_year = re.search(r"\((\d{4})\)", t) or re.search(r"\b(19|20)\d{2}\b", t)
        year = m_year.group(1) if m_year and m_year.lastindex else (m_year.group(0) if m_year else "")
        if not m_year:
            year = ""
        doi = ""
        rows.append({"number": e["number"], "first_author": first_author, "year": year, "doi": doi})
    return rows

def parse_samarkhazan(lines):
    """Samarkhazan refs:  N. FirstAuth X, Second Y, et al. Title. Journal. YYYY;Vol(Issue):pages. (no doi)"""
    entries = []
    cur = None
    pat = re.compile(r"^\s*(\d+)\.\s+(.*)")
    for line in lines:
        m = pat.match(line)
        if m:
            if cur is not None:
                entries.append(cur)
            cur = {"number": int(m.group(1)), "text": m.group(2)}
        else:
            if cur is not None:
                cur["text"] += " " + line.strip()
    if cur is not None:
        entries.append(cur)
    rows = []
    for e in entries:
        t = e["text"]
        m_auth = re.match(r"((?:[Vv]an\s+(?:den\s+|der\s+)?|[Dd]e\s+|[Dd]a\s+|[Ll]e\s+)?[A-Z][A-Za-zÀ-ÿ\-']+)", t)
        first_author = m_auth.group(1).strip() if m_auth else ""
        m_year = re.search(r"\b(19|20)\d{2}\b", t)
        year = m_year.group(0) if m_year else ""
        doi = ""
        rows.append({"number": e["number"], "first_author": first_author, "year": year, "doi": doi})
    return rows

def parse_weber(lines):
    """Weber refs:  N. Authors ... Journal. YYYY;Vol:pages. https://doi.org/..."""
    entries = []
    cur = None
    pat = re.compile(r"^\s*(\d+)\.\s+(.*)")
    for line in lines:
        m = pat.match(line)
        if m:
            if cur is not None:
                entries.append(cur)
            cur = {"number": int(m.group(1)), "text": m.group(2)}
        else:
            if cur is not None:
                cur["text"] += " " + line.strip()
    if cur is not None:
        entries.append(cur)
    rows = []
    for e in entries:
        t = e["text"]
        m_auth = re.match(r"((?:[Vv]an\s+(?:den\s+|der\s+)?|[Dd]e\s+|[Dd]a\s+|[Ll]e\s+)?[A-Z][A-Za-zÀ-ÿ\-']+)", t)
        first_author = m_auth.group(1).strip() if m_auth else ""
        m_year = re.search(r"\b(19|20)\d{2}\b", t)
        year = m_year.group(0) if m_year else ""
        m_doi = re.search(r"doi\.org/(10\.\S+?)(?:\.$|\s|$)", t)
        if not m_doi:
            m_doi = re.search(r"(10\.\d{4,9}/[^\s;]+)", t)
        doi = m_doi.group(1).rstrip(".,;") if m_doi else ""
        rows.append({"number": e["number"], "first_author": first_author, "year": year, "doi": doi})
    return rows

PARSERS = {
    "Moses_2026": parse_moses,
    "Paredes_2026": parse_paredes,
    "Samarkhazan_2025": parse_samarkhazan,
    "Weber_2026": parse_weber,
}

for paper, parser in PARSERS.items():
    txt = gather_text(paper)
    lines = normalize_text(txt)
    rows = parser(lines)
    out = RAW / f"refs_{paper}.csv"
    with out.open("w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=["number","first_author","year","doi"])
        writer.writeheader()
        for r in rows:
            writer.writerow(r)
    print(f"{paper}: wrote {len(rows)} refs -> {out}")
    # peek
    if rows:
        print("  first:", rows[0])
        print("  last:", rows[-1])
