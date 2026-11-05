#!/usr/bin/env python3
"""Harmonize taxa to GTDB: fills taxon / taxon_rank in reviews/claims_linked.csv and writes
reviews/taxa.csv (one lineage row per taxon as cited, used by the taxonomy ring).

    python3 claim-network/scripts/harmonize_taxa.py

Order of lookup for each (taxon_as_cited, rank):
  1. lookups/taxonomy_lookup.csv  (curated entries and every earlier automatic match)
  2. GTDB release in lookups/gtdb_cache (r232), after applying lookups/taxon_synonyms.csv
     (NCBI -> GTDB names such as Firmicutes -> Bacillota). New matches are appended to
     taxonomy_lookup.csv with match_method auto_<how>, so each name is resolved once and can be
     corrected by hand there.
Functional groups keep their cited name with taxon_rank 'functional group'. Unmatched names keep
the cited name and are listed at the end; add a manual row to taxonomy_lookup.csv to fix them.
Where GTDB splits a name (e.g. Clostridium -> Clostridium, Clostridium_A ...), the largest
lineage is used and the split is recorded in the note.
"""
import collections, gzip, re
from claimlib import CLAIMS_LINKED, TAXA, LOOKUPS, read_csv, write_csv

R = ["domain", "phylum", "class", "order", "family", "genus", "species"]
LOOKUP = LOOKUPS / "taxonomy_lookup.csv"
SYN = LOOKUPS / "taxon_synonyms.csv"
LOOKUP_COLS = ["subject", "rank_as_cited", "gtdb_name", "gtdb_rank"] + R + \
              ["match_method", "reclassified", "gtdb_release", "note"]


def release():
    for line in (LOOKUPS / "gtdb_release.txt").read_text().splitlines():
        if line.startswith("release:"):
            return line.split(":", 1)[1].strip()
    return ""


def gtdb_index():
    cnt = collections.Counter()
    for fn in ["bac120_taxonomy.tsv.gz", "ar53_taxonomy.tsv.gz"]:
        with gzip.open(LOOKUPS / "gtdb_cache" / fn, "rt") as fh:
            for line in fh:
                cnt[line.rstrip("\n").split("\t")[1]] += 1
    idx = {r: collections.defaultdict(collections.Counter) for r in R}
    for lin, n in cnt.items():
        parts = [p[3:] for p in lin.split(";")]
        for i, r in enumerate(R):
            idx[r][parts[i]][tuple(parts[:i + 1])] += n
    base = lambda x: re.sub(r"_[A-Z]+\b", "", x)
    bidx = {r: collections.defaultdict(collections.Counter) for r in R}
    for r in R:
        for name, c in idx[r].items():
            for k, v in c.items():
                bidx[r][base(name)][k] += v
    return idx, bidx, base


def resolve(name, rank, syn, G):
    idx, bidx, base = G
    s = syn.get(name)
    q = s["gtdb_query"] if s else name
    rank = (s or {}).get("rank_fix") or rank
    notes = [f"name normalized {name} -> {q}"] if q != name else []
    if rank not in R:
        return None
    hit, how = idx[rank].get(q), "exact"
    if not hit:
        if rank == "species":
            cands = {k: v for k, v in idx["species"].items() if base(k) == q}
            if cands:
                hit = collections.Counter()
                for v in cands.values(): hit.update(v)
        else:
            hit = bidx[rank].get(q)
        how = "suffix_variant"
    if not hit:
        return None
    names = collections.Counter()
    for k, v in hit.items(): names[k[-1]] += v
    if len(names) > 1:
        notes.append("GTDB splits into " + ", ".join(f"{k}({v})" for k, v in names.most_common(6)) + "; used largest")
    top = names.most_common(1)[0][0]
    lin = max(((k, v) for k, v in hit.items() if k[-1] == top), key=lambda kv: kv[1])[0]
    d = dict(zip(R, list(lin) + [""] * (7 - len(lin))))
    d.update(gtdb_name=top, gtdb_rank=rank, match_method="auto_" + (how if top == q else how + "_renamed"),
             reclassified="yes" if top != name else "no", note="; ".join(notes))
    return d


def main():
    rows = read_csv(CLAIMS_LINKED)
    lookup = read_csv(LOOKUP)
    lk = {(r["subject"], r["rank_as_cited"]): r for r in lookup}
    syn = {r["name_as_cited"]: r for r in read_csv(SYN)} if SYN.exists() else {}
    G, rel, added, unmatched = None, release(), [], set()
    for c in rows:
        name, rank = c["taxon_as_cited"], c["taxon_rank_as_cited"]
        if rank == "functional group":
            c["taxon"], c["taxon_rank"] = name, "functional group"
            continue
        e = lk.get((name, rank))
        if e is None:
            G = G or gtdb_index()
            d = resolve(name, rank, syn, G)
            if d:
                e = {"subject": name, "rank_as_cited": rank, "gtdb_release": rel, **d}
                lk[(name, rank)] = e
                added.append(e)
        if e and e.get("gtdb_name"):
            c["taxon"], c["taxon_rank"] = e["gtdb_name"], e["gtdb_rank"]
        else:
            c["taxon"], c["taxon_rank"] = name, rank
            unmatched.add((name, rank))
    if added:
        write_csv(LOOKUP, lookup + added, LOOKUP_COLS)
    write_csv(CLAIMS_LINKED, rows, list(rows[0].keys()) if rows else [])
    # taxa.csv: lineage per (taxon, taxon_as_cited)
    taxa, seen = [], set()
    for c in rows:
        if c["taxon_rank"] == "functional group": continue
        key = (c["taxon"], c["taxon_as_cited"])
        if key in seen: continue
        seen.add(key)
        e = lk.get((c["taxon_as_cited"], c["taxon_rank_as_cited"]), {})
        taxa.append({"taxon": c["taxon"], "taxon_rank": c["taxon_rank"], "taxon_as_cited": c["taxon_as_cited"],
                     "taxon_rank_as_cited": c["taxon_rank_as_cited"], **{r: e.get(r, "") for r in R},
                     "match_method": e.get("match_method", "unmatched"), "note": e.get("note", "")})
    write_csv(TAXA, taxa, ["taxon", "taxon_rank", "taxon_as_cited", "taxon_rank_as_cited"] + R + ["match_method", "note"])
    print(f"harmonized {len(rows)} rows; {len(taxa)} distinct cited taxa; {len(added)} new GTDB matches added to taxonomy_lookup.csv")
    for e in added:
        flag = f"  -> {e['gtdb_name']}" if e["gtdb_name"] != e["subject"] else ""
        print(f"  new: {e['subject']} ({e['rank_as_cited']}){flag} [{e['match_method']}] {e['note']}")
    for n, r in sorted(unmatched):
        print(f"  UNMATCHED: {n} ({r}); add a manual row to lookups/taxonomy_lookup.csv")


if __name__ == "__main__":
    main()
