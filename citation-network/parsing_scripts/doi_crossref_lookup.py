import os
import re
import time
import random
import requests
import pandas as pd
from rapidfuzz import fuzz

INPUT_PATH = os.path.expanduser("~/Documents/ODSi/ODSiData/citation-network/Catch_Doi/missed_dois.xlsx")
OUTPUT_PATH = os.path.expanduser("~/Documents/ODSi/ODSiData/citation-network/Catch_Doi/reran_dois.xlsx")
SHEET_NAME = "missed_dois"

DOI_PATTERN = re.compile(r'^10\.\d{4,9}/\S+$')
CROSSREF_URL = "https://api.crossref.org/works"
USER_AGENT = "mailto:sophhuebler@gmail.com"


def parse_citation(text):
    """Extract year, first author surname, and rough title from a citation string."""
    year_match = re.search(r'\b(19|20)\d{2}\b', str(text))
    year = int(year_match.group()) if year_match else None

    # First token that looks like a surname (before year or comma)
    author_match = re.match(r'^([A-Za-z][A-Za-zÀ-ÿ\-\']+)', str(text).strip())
    first_author = author_match.group(1).lower() if author_match else ""

    return year, first_author


def crossref_lookup(citation_text, timeout=5):
    """Query Crossref and return the best candidate's (doi, title, year, authors) or None."""
    params = {"query.bibliographic": citation_text, "rows": 3, "select": "DOI,title,published,author"}
    headers = {"User-Agent": USER_AGENT}

    deadline = time.time() + timeout
    backoff = 0.5

    while True:
        remaining = deadline - time.time()
        if remaining <= 0:
            return None
        try:
            resp = requests.get(
                CROSSREF_URL,
                params=params,
                headers=headers,
                timeout=min(remaining, timeout)
            )
        except (requests.exceptions.Timeout, requests.exceptions.ConnectionError):
            return None

        if resp.status_code == 200:
            break
        elif resp.status_code in (429, 500, 502, 503, 504):
            sleep_time = min(backoff, deadline - time.time() - 0.1)
            if sleep_time <= 0:
                return None
            time.sleep(sleep_time)
            backoff *= 2
        else:
            return None

    try:
        items = resp.json().get("message", {}).get("items", [])
    except Exception:
        return None

    return items


def confidence_check(items, citation_text, cite_year, cite_author):
    """Return best (doi, title) if confident, else (None, None)."""
    citation_lower = citation_text.lower()

    for item in items:
        doi = item.get("DOI", "").strip()
        if not doi or not DOI_PATTERN.match(doi):
            continue

        titles = item.get("title", [])
        if not titles:
            continue
        candidate_title = titles[0]

        # Year check
        pub = item.get("published", {})
        parts = pub.get("date-parts", [[]])[0] if pub else []
        cand_year = parts[0] if parts else None

        # Author check
        authors = item.get("author", [])
        author_surnames = [a.get("family", "").lower() for a in authors]

        # Similarity
        sim = fuzz.token_set_ratio(candidate_title.lower(), citation_lower)

        year_ok = (cand_year is not None and cite_year is not None and abs(cand_year - cite_year) <= 1)
        author_ok = cite_author and any(cite_author in s for s in author_surnames)

        if sim >= 95:
            return doi, candidate_title
        if sim >= 88 and year_ok and author_ok:
            return doi, candidate_title

    return None, None


def main():
    # Load from OUTPUT_PATH if it exists (resume support)
    if os.path.exists(OUTPUT_PATH):
        print(f"Resuming from existing output: {OUTPUT_PATH}")
        df = pd.read_excel(OUTPUT_PATH, sheet_name=SHEET_NAME, dtype=str)
    else:
        df = pd.read_excel(INPUT_PATH, sheet_name=SHEET_NAME, dtype=str)

    df = df.where(pd.notna(df), "")  # replace NaN with ""

    has_doi_source = "doi_source" in df.columns

    # Rows needing lookup
    todo_indices = df.index[df["doi"].str.strip() == ""].tolist()
    total_todo = len(todo_indices)
    print(f"Rows to process: {total_todo}")

    filled = 0
    blank = 0
    processed = 0
    newly_filled_dois = []  # (index, doi) for spot-check

    for idx in todo_indices:
        citation = str(df.at[idx, "full_citation"])
        cite_year, cite_author = parse_citation(citation)

        items = crossref_lookup(citation, timeout=5)

        if items:
            doi, title = confidence_check(items, citation, cite_year, cite_author)
        else:
            doi, title = None, None

        if doi:
            df.at[idx, "doi"] = doi
            if has_doi_source:
                df.at[idx, "doi_source"] = "crossref"
            filled += 1
            newly_filled_dois.append((idx, doi))
        else:
            if has_doi_source and df.at[idx, "doi_source"].strip() == "":
                df.at[idx, "doi_source"] = "blank"
            blank += 1

        processed += 1

        # Checkpoint every 25 rows
        if processed % 25 == 0:
            df.to_excel(OUTPUT_PATH, sheet_name=SHEET_NAME, index=False)
            print(f"Checkpoint: {processed}/{total_todo} rows processed, "
                  f"{filled} filled via Crossref, {blank} left blank — saved to {OUTPUT_PATH}")

        # Polite delay
        time.sleep(random.uniform(0.3, 1.0))

    # Final save
    df.to_excel(OUTPUT_PATH, sheet_name=SHEET_NAME, index=False)
    print(f"\nFinal save: {processed}/{total_todo} rows processed, "
          f"{filled} filled via Crossref, {blank} left blank.")

    # --- Spot-check 3–5 newly filled DOIs ---
    spot_sample = newly_filled_dois[:5]
    print(f"\nSpot-checking {len(spot_sample)} DOIs...")
    for sidx, sdoi in spot_sample:
        url = f"https://doi.org/{sdoi}"
        try:
            r = requests.head(url, allow_redirects=True, timeout=8)
            status = r.status_code
        except Exception as e:
            status = str(e)
        print(f"  {sdoi} → {url} [{status}]")

    # --- Flag abbrev_citation collisions with differing DOIs ---
    print("\nChecking for abbrev_citation DOI mismatches...")
    if "abbrev_citation" in df.columns:
        grp = df[df["doi"].str.strip() != ""].groupby("abbrev_citation")["doi"].apply(
            lambda x: x.str.strip().unique().tolist()
        )
        mismatches = grp[grp.apply(len) > 1]
        if mismatches.empty:
            print("  No mismatches found.")
        else:
            for abbrev, dois in mismatches.items():
                # Find citing papers for this abbrev
                cp_set = df.loc[
                    (df["abbrev_citation"] == abbrev) & (df["doi"].str.strip() != ""),
                    "citing_paper"
                ].unique().tolist()
                print(f"  MISMATCH: {abbrev} → {dois} (citing_paper(s): {cp_set})")
    else:
        print("  No abbrev_citation column found.")

    print("\nDone.")


if __name__ == "__main__":
    main()
