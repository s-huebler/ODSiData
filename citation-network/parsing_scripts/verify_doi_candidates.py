#!/usr/bin/env python3
"""
Verify / look up DOIs for dictionary_corrections_review.xlsx against Crossref.

Run on your Mac (it has Crossref access; the Claude sandbox does not):

    python3 citation-network/parsing_scripts/verify_doi_candidates.py \
        citation-network/Full_Network/corrections/dictionary_corrections_review.xlsx

What it does (read-only on the workbook):
  1. Tab 1_Faculty_Opinions, rows with doi_source = "candidate, verify":
     fetches the candidate DOI from Crossref and compares its title with true_title.
  2. Tabs 2_Lee_2025_wrong_links and 3_Other_wrong_links, rows with no proposed DOI
     (and not assessed "OK"): searches Crossref with the citation text and reports the
     best hit, EXCLUDING Faculty Opinions (10.3410/...) records, which caused the
     original problem.

Writes verify_results.csv next to the workbook. Nothing else is changed.
Needs: openpyxl (already used by reflink_claims.py). Standard library otherwise.
"""
import csv
import json
import re
import sys
import time
import urllib.parse
import urllib.request
from pathlib import Path

import openpyxl

MAILTO = "sophhuebler@gmail.com"  # Crossref "polite pool"
UA = f"ODSiData-doi-verify/1.0 (mailto:{MAILTO})"
STOP = set("the a an of and in on for with to by from at as is are or via its their after "
           "during between into vs versus using".split())


def words(s):
    s = re.sub(r"<[^>]+>|\\emph|[{}$]", "", (s or "").lower())
    return [w for w in re.findall(r"[a-z0-9]+", s) if w not in STOP and len(w) > 2]


def overlap(title, text):
    """Share of the title's content words that appear in text (0-1)."""
    tw = words(title)
    if not tw:
        return 0.0
    f = set(words(text))
    return round(sum(w in f for w in tw) / len(tw), 2)


def get(url):
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    for attempt in range(4):
        try:
            with urllib.request.urlopen(req, timeout=30) as r:
                return json.load(r)
        except urllib.error.HTTPError as e:
            if e.code == 404:
                return None
            time.sleep(2 * (attempt + 1))
        except Exception:
            time.sleep(2 * (attempt + 1))
    return None


def describe(item):
    title = (item.get("title") or [""])[0]
    auth = (item.get("author") or [{}])[0].get("family", "")
    yr = ""
    for k in ("published-print", "published-online", "issued"):
        dp = (item.get(k) or {}).get("date-parts")
        if dp and dp[0] and dp[0][0]:
            yr = dp[0][0]
            break
    journal = (item.get("container-title") or [""])[0]
    return title, auth, yr, journal


def sheet_rows(wb, name):
    ws = wb[name]
    rows = list(ws.iter_rows(values_only=True))
    hdr = rows[0]
    return [dict(zip(hdr, r)) for r in rows[1:]]


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    xlsx = Path(sys.argv[1])
    wb = openpyxl.load_workbook(xlsx, read_only=True)
    out = []

    # 1. Verify candidate DOIs
    for r in sheet_rows(wb, "1_Faculty_Opinions"):
        if (r.get("doi_source") or "").startswith("candidate"):
            doi = r["proposed_doi"]
            j = get("https://api.crossref.org/works/" + urllib.parse.quote(doi))
            if not j:
                out.append(dict(tab="1", key=r["bad_bibtex"], mode="verify", doi=doi,
                                status="DOI NOT FOUND", crossref_title="", author="", year="",
                                journal="", title_match=""))
            else:
                t, a, y, jn = describe(j["message"])
                sc = overlap(r["true_title"], t)
                out.append(dict(tab="1", key=r["bad_bibtex"], mode="verify", doi=doi,
                                status="OK" if sc >= 0.85 else "MISMATCH - check",
                                crossref_title=t, author=a, year=y, journal=jn, title_match=sc))
            time.sleep(1)

    # 2. Look up missing DOIs
    for tab, key_cols in (("2_Lee_2025_wrong_links", ("citing_bibtex", "local_number")),
                          ("3_Other_wrong_links", ("citing_bibtex", "local_number"))):
        for r in sheet_rows(wb, tab):
            if r.get("proposed_doi"):
                continue
            if str(r.get("assessment") or "").startswith(("OK", "probably OK")):
                continue
            cit = re.sub(r"https?://doi\.org/\S+|- DOI.*$|- PubMed.*$", "", r["full_citation"] or "")
            if not cit.strip() or cit.startswith("("):
                continue
            q = urllib.parse.urlencode({"query.bibliographic": cit[:300], "rows": 5,
                                        "select": "DOI,title,author,issued,published-print,"
                                                  "published-online,container-title,type",
                                        "mailto": MAILTO})
            j = get("https://api.crossref.org/works?" + q)
            items = [i for i in (j or {}).get("message", {}).get("items", [])
                     if not i["DOI"].lower().startswith("10.3410/")
                     and i.get("type") not in ("peer-review", "posted-content")]
            key = "/".join(str(r[k]) for k in key_cols)
            if not items:
                out.append(dict(tab=tab[0], key=key, mode="lookup", doi="", status="NO HIT",
                                crossref_title="", author="", year="", journal="", title_match=""))
            else:
                best = max(items, key=lambda i: overlap((i.get("title") or [""])[0], cit))
                t, a, y, jn = describe(best)
                sc = overlap(t, cit)
                out.append(dict(tab=tab[0], key=key, mode="lookup", doi=best["DOI"],
                                status="LIKELY" if sc >= 0.85 else "WEAK - check",
                                crossref_title=t, author=a, year=y, journal=jn, title_match=sc))
            time.sleep(1)

    dest = xlsx.with_name("verify_results.csv")
    with open(dest, "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=list(out[0].keys()))
        w.writeheader()
        w.writerows(out)
    print(f"Wrote {len(out)} rows -> {dest}")
    for s in ("OK", "LIKELY", "MISMATCH - check", "WEAK - check", "DOI NOT FOUND", "NO HIT"):
        n = sum(o["status"] == s for o in out)
        if n:
            print(f"  {s}: {n}")


if __name__ == "__main__":
    main()
