#!/usr/bin/env python3
"""Collect every approved row from every review into reviews/claims.csv.

    python3 claim-network/scripts/assemble_claims.py

One row per approved claim per cited reference (ref_string '[32,33]' becomes two rows). Field
values come from decisions.json, so edits made in the viewer or at discussion are kept. Stops
if any review still has an unresolved 'discuss' (pass --allow-open to skip those rows instead).
"""
import sys
from claimlib import CLAIMS, FIELDS, review_dirs, load_json, write_csv, explode_refs

COLS = ["statement_id", "citing_label", "paper", "location", "quote",
        "taxon_as_cited", "taxon_rank_as_cited", "direction", "evidence_as_stated", "evidence",
        "mechanism_broad", "mechanism_specific", "target_type", "intervention",
        "mechanism_as_named", "mechanism_assignment", "ref_string",
        "edited", "review_note", "discussion", "codebook_version"]


def main(allow_open=False):
    rows, problems = [], []
    for d in review_dirs():
        prop = load_json(d / "proposals.json")
        dec = load_json(d / "decisions.json", {})
        items = [it for it in prop["items"] if it["kind"] == "proposal"]
        n_app = 0
        for it in items:
            r = dec.get(it["id"])
            state = r["decision"] if r else "undecided"
            if state in ("discuss", "undecided"):
                problems.append(f"{d.name} {it['id']}: {state}")
                continue
            if state != "approve":
                continue
            n_app += 1
            f = {**it["fields"], **(r.get("fields") or {})}
            base = {k: f.get(k, "") for k in FIELDS}
            base.update(statement_id=it["id"], citing_label=prop["citing_bibtex"], paper=d.name,
                        location=it["location"], quote=it["quote"], edited=str(bool(r.get("edited"))),
                        review_note=r.get("review_note", ""), discussion=r.get("discussion", ""),
                        codebook_version=prop.get("codebook_version", ""))
            for ref in explode_refs(base["ref_string"]):
                rows.append({**base, "ref_string": ref})
        print(f"{d.name}: {n_app} approved of {len(items)} proposals")
    if problems:
        print(("Skipped (open):" if allow_open else "Unresolved, fix before assembling:"))
        for p in problems: print("  ", p)
        if not allow_open:
            sys.exit(1)
    write_csv(CLAIMS, rows, COLS)
    print(f"wrote {CLAIMS} ({len(rows)} rows)")


if __name__ == "__main__":
    main(allow_open="--allow-open" in sys.argv)
