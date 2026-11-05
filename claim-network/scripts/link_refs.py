#!/usr/bin/env python3
"""Link claims to the citation network: reviews/claims.csv -> reviews/claims_linked.csv.

    python3 claim-network/scripts/link_refs.py

The key into citation-network/Full_Network/citing_dictionary.csv is (citing_bibtex,
local_number), which gives citing_id, ref_id and ref_label (the dictionary's ref_bibtex), so the
claims share IDs with the citation network.

- Numbered citations ('[30]') give local_number directly.
- Author-year citations ('Taur 2014') are matched to a number through reviews/<paper>/refs.csv
  (from parse_refs.py) by first-author surname and year, using a DOI in the citation if present
  to break ties.

ref_match records how each row was linked: number, author_year, author_year_doi, uncited,
unresolved(<n> candidates), not_in_dictionary. ref_check is FALSE when the review's printed first
author for that number is not in the dictionary citation (refs.csv), worth a look.
"""
import re
from collections import defaultdict
from claimlib import CLAIMS, CLAIMS_LINKED, REVIEWS, DICTIONARY, read_csv, write_csv, ascii_lower

OUT_COLS = ["citing_id", "citing_label", "ref_id", "ref_label", "taxon", "taxon_rank",
            "direction", "evidence", "mechanism_broad", "mechanism_specific", "target_type",
            "intervention", "mechanism_assignment", "statement_id", "paper", "location",
            "taxon_as_cited", "taxon_rank_as_cited", "evidence_as_stated", "mechanism_as_named",
            "ref_string", "ref_number", "ref_match", "ref_check", "quote",
            "edited", "review_note", "discussion", "codebook_version"]


def surname(s):
    return ascii_lower(s).replace("-", " ").split(" ")[0] if s else ""


def main():
    claims = read_csv(CLAIMS)
    dic = {}
    citing_ids = {}
    for r in read_csv(DICTIONARY):
        dic[(r["citing_bibtex"], int(r["local_number"]))] = r
        citing_ids[r["citing_bibtex"]] = r["citing_id"]
    refs_cache = {}

    def refs_for(paper):
        if paper not in refs_cache:
            p = REVIEWS / paper / "refs.csv"
            refs_cache[paper] = read_csv(p) if p.exists() else None
        return refs_cache[paper]

    counts = defaultdict(int)
    for c in claims:
        bib, s = c["citing_label"], c["ref_string"].strip()
        c["citing_id"] = citing_ids.get(bib, "")
        num, how = None, ""
        if not s:
            how = "uncited"
        elif re.fullmatch(r"\[\d+\]", s):
            num, how = int(s[1:-1]), "number"
        else:
            refs = refs_for(c["paper"])
            m = re.match(r"(.+?)\s+(\d{4})[a-z]?\s*(?:\((.*)\))?$", s)
            if refs is None:
                how = "unresolved(no refs.csv)"
            elif not m:
                how = "unresolved(unparsed)"
            else:
                au, yr, doi = surname(m.group(1)), m.group(2), (m.group(3) or "").lower()
                cand = [r for r in refs if surname(r["first_author"]) == au and r["year"] == yr]
                if len(cand) > 1 and doi:
                    cand = [r for r in cand if r["doi"] and (r["doi"].lower() in doi or doi in r["doi"].lower())] or cand
                    how = "author_year_doi"
                if len(cand) == 1:
                    num, how = int(cand[0]["number"]), how or "author_year"
                else:
                    how = f"unresolved({len(cand)} candidates)"
        c["ref_number"] = num if num is not None else ""
        c["ref_check"] = ""
        if num is not None:
            d = dic.get((bib, num))
            if d is None:
                how = "not_in_dictionary"
            else:
                c["ref_id"], c["ref_label"] = d["ref_id"], d["ref_bibtex"]
                refs = refs_for(c["paper"])
                if refs:
                    rr = next((r for r in refs if int(r["number"]) == num), None)
                    if rr:
                        c["ref_check"] = rr["dict_match"]
        c["ref_match"] = how
        counts[how] += 1
    write_csv(CLAIMS_LINKED, claims, OUT_COLS)
    print(f"wrote {CLAIMS_LINKED} ({len(claims)} rows); ref_match: {dict(counts)}")
    for c in claims:
        if c["ref_match"] not in ("number", "author_year", "author_year_doi") or c["ref_check"] == "FALSE":
            print(f"  {c['statement_id']} {c['ref_string']!r}: {c['ref_match']} {'(author check FALSE)' if c['ref_check'] == 'FALSE' else ''}")


if __name__ == "__main__":
    main()
