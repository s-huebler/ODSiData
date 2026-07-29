#!/usr/bin/env python3
"""
doi_crossref_lookup_v2.py  —  robust DOI recovery for messy citation batches.

Rewrite of doi_crossref_lookup.py, motivated by ~1,100 rows in
citation-network/Catch_Doi/missed_dois2_ai.csv that the original script could not
handle. Root causes fixed here:

  1. ENCODING (mojibake). The AI batch is double-encoded UTF-8:
     "215‚Äì233" (en-dash), "D‚ÄôSouza" (apostrophe), "M√ºller" (ü). Garbled author
     names / page ranges wrecked the Crossref bibliographic query. -> ftfy repair,
     and (per request) the cleaned text is written back to the output.

  2. INPUT FORMAT. Original was hardwired to missed_dois.xlsx / sheet "missed_dois"
     with abbrev_citation + doi_source columns. This batch is a CSV with different
     columns (has "N", no abbrev_citation/doi_source). -> auto-detect CSV vs XLSX
     and adapt to whatever columns are present.

  3. EMBEDDED DOIs. ~52 rows already contain the DOI in the text
     ("doi: 10.1126/science.1237439"). The old script never looked; it always
     queried Crossref and applied a strict gate. -> extract embedded DOIs first
     (free, exact), validate against Crossref only for a sanity 200.

  4. SCRAPER-TAIL / URL NOISE. ~100 rows end in "- DOI - PMC - PubMed"; some are
     "Available at http... Accessed...". This noise both polluted the query and,
     worse, tanked the confidence score because the old code compared the candidate
     TITLE against the WHOLE citation. -> strip tails/URLs before querying and
     compare title against the citation's TITLE span, plus author/year signals.

  5. NON-ARTICLES. Books ("...eds. Elsevier Inc.; 2017"), web pages, CIBMTR slides
     have no journal DOI and should be marked "no_doi_expected", not counted as
     failures.

Output columns added / populated: doi, doi_source, full_citation_clean, match_score.

Usage:
    python doi_crossref_lookup_v2.py                 # full file
    python doi_crossref_lookup_v2.py --limit 100     # first 100 TODO rows (sample)
    python doi_crossref_lookup_v2.py --sample 100    # random 100 TODO rows (seeded)
    python doi_crossref_lookup_v2.py --input X.csv --output Y.csv

Requires: requests, pandas, rapidfuzz, ftfy   (openpyxl if reading/writing .xlsx)
"""

import os
import re
import sys
import time
import random
import argparse

import requests
import pandas as pd
from rapidfuzz import fuzz

try:
    import ftfy
    _HAVE_FTFY = True
except ImportError:
    _HAVE_FTFY = False


# ----------------------------------------------------------------------------- #
# Config
# ----------------------------------------------------------------------------- #
DEFAULT_INPUT = os.path.expanduser(
    "~/Documents/ODSi/ODSiData/citation-network/Catch_Doi/missed_dois2_ai.csv"
)
CROSSREF_URL = "https://api.crossref.org/works"
CONTACT_EMAIL = "sophhuebler@gmail.com"
# Crossref asks for a real UA with contact info; this also earns the "polite pool".
USER_AGENT = f"ODSiData-DOI-recovery/2.0 (mailto:{CONTACT_EMAIL})"

DOI_VALID = re.compile(r"^10\.\d{4,9}/\S+$")
# Embedded-DOI finder: grab a DOI sitting inside citation text.
DOI_IN_TEXT = re.compile(r"10\.\d{4,9}/[^\s\"'<>,;)\]]+", re.I)

CITATION_COL = "full_citation"
DOI_COL = "doi"
# Values in the doi column that mean "still needs a lookup".
BLANK_TOKENS = {"", "na", "n/a", "none", "null", "nan"}


# ----------------------------------------------------------------------------- #
# Text cleaning
# ----------------------------------------------------------------------------- #
def fix_encoding(text):
    """Repair double-encoded UTF-8 (mojibake). Returns cleaned string."""
    if text is None:
        return ""
    s = str(text)
    if _HAVE_FTFY:
        s = ftfy.fix_text(s)
    else:
        # Best-effort fallback if ftfy isn't installed: reverse the common
        # UTF-8-as-CP1252 round trip.
        try:
            s = s.encode("cp1252").decode("utf-8")
        except (UnicodeEncodeError, UnicodeDecodeError):
            pass
    # Normalize non-breaking spaces that ftfy leaves in the scraper tails.
    s = s.replace("\xa0", " ")
    return s.strip()


# Trailing database breadcrumbs left by PubMed/PMC scrapers.
_TAIL = re.compile(
    r"\s*(?:-\s*(?:DOI|PMC|PubMed|Free\s+PMC\s+article|Google\s+Scholar))+\s*$",
    re.I,
)
_URL = re.compile(r"https?://\S+|www\.\S+", re.I)
_AVAILABLE = re.compile(r"\s*Available at.*$", re.I | re.S)
_DOI_PHRASE = re.compile(r"\bdoi:\s*\S+", re.I)


def strip_noise(text):
    """Remove scraper tails, URLs, and 'Available at ... Accessed ...' clutter so
    the string sent to Crossref is closer to a clean bibliographic reference."""
    s = text
    s = _AVAILABLE.sub("", s)
    s = _URL.sub("", s)
    s = _DOI_PHRASE.sub("", s)
    # Strip the trailing "- DOI - PMC - PubMed" chain (may repeat).
    prev = None
    while prev != s:
        prev = s
        s = _TAIL.sub("", s)
    return re.sub(r"\s{2,}", " ", s).strip(" .-\t")


def looks_non_article(text):
    """Heuristic: reference that will not have a journal DOI (book, web page,
    conference slides, dataset). Used to skip futile Crossref calls."""
    t = text.lower()
    if re.search(r"available at|accessed |cibmtr|clinicaltrials\.gov|https?://", t):
        return True
    if re.search(
        r"\b\d+(?:st|nd|rd|th)\s+ed\b|\beds?\.\b|\beditor|\bpress[;,.]| wiley| elsevier"
        r"| springer|academic press|john wiley",
        t,
    ):
        return True
    return False


def parse_citation(text):
    """Extract (year, first_author_surname, title_span) from a cleaned citation.

    title_span is the sentence most likely to be the article title: for Vancouver
    style ("Authors. Title. Journal. Year;vol:pages.") the title is the segment
    right before the journal/year block. Falls back to the whole string.
    """
    year_match = re.search(r"\b(19|20)\d{2}\b", text)
    year = int(year_match.group()) if year_match else None

    author_match = re.match(r"^\s*([A-Za-zÀ-ÿ][A-Za-zÀ-ÿ'\-]+)", text)
    first_author = author_match.group(1).lower() if author_match else ""

    # Split into sentence-ish segments; the title is usually the 2nd segment
    # (after the author list) and does not contain "et al" or a year.
    segs = [s.strip() for s in re.split(r"(?<=[.?])\s+", text) if s.strip()]
    title_span = text
    for seg in segs:
        low = seg.lower()
        if len(seg) < 15:
            continue
        if "et al" in low or re.match(r"^[A-Z][a-z]+ [A-Z]{1,3}[,.]", seg):
            continue  # looks like the author list
        if re.search(r"\b(19|20)\d{2}\b", seg) and ";" in seg:
            continue  # looks like the journal/year/volume block
        title_span = seg
        break
    return year, first_author, title_span


# ----------------------------------------------------------------------------- #
# Crossref
# ----------------------------------------------------------------------------- #
_SESSION = requests.Session()
_SESSION.headers.update({"User-Agent": USER_AGENT})


def crossref_query(citation_text, rows=5, timeout=8):
    """Query Crossref bibliographic search; return list of candidate items."""
    params = {
        "query.bibliographic": citation_text,
        "rows": rows,
        "select": "DOI,title,published,author,container-title,type",
    }
    deadline = time.time() + timeout * 2
    backoff = 1.0
    while time.time() < deadline:
        try:
            resp = _SESSION.get(CROSSREF_URL, params=params, timeout=timeout)
        except (requests.exceptions.Timeout, requests.exceptions.ConnectionError):
            return []
        if resp.status_code == 200:
            try:
                return resp.json().get("message", {}).get("items", [])
            except ValueError:
                return []
        if resp.status_code in (429, 500, 502, 503, 504):
            time.sleep(min(backoff, deadline - time.time()))
            backoff *= 2
            continue
        return []
    return []


def doi_resolves(doi, timeout=8):
    """Confirm an embedded DOI is real by checking Crossref has metadata for it."""
    try:
        r = _SESSION.get(f"{CROSSREF_URL}/{doi}", timeout=timeout)
        return r.status_code == 200
    except requests.exceptions.RequestException:
        return False


def score_candidate(item, cite_year, cite_author, title_span, full_clean):
    """Multi-signal confidence score in [0,100]."""
    titles = item.get("title") or []
    if not titles:
        return 0.0, None
    cand_title = titles[0]

    # Title similarity: compare candidate title to the citation's TITLE span
    # (not the whole citation) — this is the key fix vs. the original.
    sim_title = fuzz.token_set_ratio(cand_title.lower(), title_span.lower())
    sim_full = fuzz.token_set_ratio(cand_title.lower(), full_clean.lower())
    sim = max(sim_title, sim_full)

    pub = item.get("published", {}) or {}
    parts = (pub.get("date-parts") or [[]])[0]
    cand_year = parts[0] if parts else None
    year_ok = (
        cand_year is not None
        and cite_year is not None
        and abs(cand_year - cite_year) <= 1
    )

    surnames = [a.get("family", "").lower() for a in (item.get("author") or [])]
    author_ok = bool(cite_author) and any(cite_author in s for s in surnames if s)

    score = sim + (6 if year_ok else 0) + (6 if author_ok else 0)
    return min(score, 100.0), cand_title


def confident_doi(items, cite_year, cite_author, title_span, full_clean,
                  accept=88.0):
    """Return (doi, score, title) for the best candidate over threshold, else Nones."""
    best = (None, 0.0, None)
    for item in items:
        doi = (item.get("DOI") or "").strip().lower()
        if not doi or not DOI_VALID.match(doi):
            continue
        score, title = score_candidate(
            item, cite_year, cite_author, title_span, full_clean
        )
        if score > best[1]:
            best = (doi, score, title)
    if best[1] >= accept:
        return best
    return (None, best[1], best[2])


# ----------------------------------------------------------------------------- #
# IO helpers
# ----------------------------------------------------------------------------- #
def load_table(path):
    if path.lower().endswith((".xlsx", ".xls")):
        return pd.read_excel(path, dtype=str)
    # utf-8 first; the AI batch is technically valid utf-8 (mojibake lives in the
    # decoded text, which fix_encoding repairs), so this succeeds.
    try:
        return pd.read_csv(path, dtype=str, encoding="utf-8")
    except UnicodeDecodeError:
        return pd.read_csv(path, dtype=str, encoding="latin-1")


def save_table(df, path):
    if path.lower().endswith((".xlsx", ".xls")):
        df.to_excel(path, index=False)
    else:
        df.to_csv(path, index=False, encoding="utf-8")


def is_blank(val):
    return str(val).strip().lower() in BLANK_TOKENS


# ----------------------------------------------------------------------------- #
# Main
# ----------------------------------------------------------------------------- #
def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--input", default=DEFAULT_INPUT)
    ap.add_argument("--output", default=None,
                    help="default: <input>_filled.<ext>")
    ap.add_argument("--limit", type=int, default=None,
                    help="process only the first N rows needing a DOI")
    ap.add_argument("--sample", type=int, default=None,
                    help="process a random N rows needing a DOI (seed 42)")
    ap.add_argument("--checkpoint", type=int, default=25)
    args = ap.parse_args()

    in_path = os.path.expanduser(args.input)
    if args.output:
        out_path = os.path.expanduser(args.output)
    else:
        base, ext = os.path.splitext(in_path)
        out_path = f"{base}_filled{ext}"

    # Resume from an existing output if present.
    src = out_path if os.path.exists(out_path) else in_path
    print(f"Reading: {src}")
    df = load_table(src)
    df = df.where(pd.notna(df), "")

    if CITATION_COL not in df.columns:
        sys.exit(f"ERROR: expected a '{CITATION_COL}' column; found {list(df.columns)}")

    for col in (DOI_COL, "doi_source", "full_citation_clean", "match_score"):
        if col not in df.columns:
            df[col] = ""

    # Pre-clean every citation once (cheap, and needed for the output column).
    for idx in df.index:
        if not str(df.at[idx, "full_citation_clean"]).strip():
            df.at[idx, "full_citation_clean"] = fix_encoding(df.at[idx, CITATION_COL])

    todo = [i for i in df.index if is_blank(df.at[i, DOI_COL])]
    if args.sample:
        random.seed(42)
        todo = sorted(random.sample(todo, min(args.sample, len(todo))))
    elif args.limit:
        todo = todo[: args.limit]

    print(f"Rows needing a DOI: {len(todo)}"
          f"{' (sampled/limited)' if (args.sample or args.limit) else ''}\n")

    stats = {"embedded": 0, "crossref": 0, "no_doi_expected": 0, "blank": 0}
    filled_examples = []

    for n, idx in enumerate(todo, 1):
        clean = df.at[idx, "full_citation_clean"]

        # 1) Embedded DOI in the text — fastest, most reliable.
        m = DOI_IN_TEXT.search(clean)
        doi = source = None
        score = 0.0
        if m:
            cand = m.group(0).rstrip(".").lower()
            if DOI_VALID.match(cand) and doi_resolves(cand):
                doi, source, score = cand, "embedded", 100.0

        # 2) Otherwise query Crossref on the de-noised citation.
        if not doi:
            query = strip_noise(clean)
            year, author, title_span = parse_citation(clean)
            items = crossref_query(query)
            cdoi, score, _ = confident_doi(items, year, author, title_span, clean)
            if cdoi:
                doi, source = cdoi, "crossref"
            elif looks_non_article(clean):
                source, score = "no_doi_expected", score

        # Record
        if doi:
            df.at[idx, DOI_COL] = doi
            df.at[idx, "doi_source"] = source
            df.at[idx, "match_score"] = round(score, 1)
            stats["embedded" if source == "embedded" else "crossref"] += 1
            if len(filled_examples) < 5:
                filled_examples.append((doi, source))
        else:
            df.at[idx, "doi_source"] = source or "blank"
            df.at[idx, "match_score"] = round(score, 1)
            stats["no_doi_expected" if source == "no_doi_expected" else "blank"] += 1

        if n % args.checkpoint == 0:
            save_table(df, out_path)
            print(f"[{n}/{len(todo)}] embedded={stats['embedded']} "
                  f"crossref={stats['crossref']} "
                  f"no_doi_expected={stats['no_doi_expected']} "
                  f"blank={stats['blank']}  (saved)")

        time.sleep(random.uniform(0.2, 0.6))  # polite to Crossref

    save_table(df, out_path)
    total_filled = stats["embedded"] + stats["crossref"]
    print(f"\nDONE. {total_filled}/{len(todo)} DOIs recovered "
          f"(embedded={stats['embedded']}, crossref={stats['crossref']}); "
          f"no_doi_expected={stats['no_doi_expected']}, blank={stats['blank']}")
    print(f"Output: {out_path}")

    # Spot-check a few resolved DOIs.
    if filled_examples:
        print("\nSpot-check (doi.org resolution):")
        for doi, src in filled_examples:
            try:
                r = _SESSION.head(f"https://doi.org/{doi}",
                                  allow_redirects=True, timeout=8)
                st = r.status_code
            except requests.exceptions.RequestException as e:
                st = type(e).__name__
            print(f"  [{src}] {doi} -> {st}")


if __name__ == "__main__":
    main()
