#!/usr/bin/env python3
"""Build taxonomy_lookup.csv from GTDB r232 taxonomy files.

For each subject in rank_lookup.csv, look up the canonical GTDB lineage,
handling known NCBI→GTDB reclassifications and non-GTDB taxa (fungi, viruses).

Inputs:
  claim-network/lookups/gtdb_cache/bac120_taxonomy.tsv.gz
  claim-network/lookups/gtdb_cache/ar53_taxonomy.tsv.gz
  claim-network/lookups/rank_lookup.csv

Outputs:
  claim-network/lookups/taxonomy_lookup.csv
  claim-network/review/gtdb_reclassifications.csv

Run standalone: python build_taxonomy_lookup.py
"""
import gzip
import sys
from collections import defaultdict
from pathlib import Path

import pandas as pd

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from common import LOOKUPS_DIR, REVIEW_DIR

GTDB_CACHE   = LOOKUPS_DIR / "gtdb_cache"
GTDB_RELEASE = "r232"

RANK_LEVELS  = ["domain", "phylum", "class", "order", "family", "genus", "species"]
_RANK_IDX    = {r: i for i, r in enumerate(RANK_LEVELS)}
_RANK_PREFIX = {"domain": "d__", "phylum": "p__", "class": "c__",
                "order": "o__",  "family": "f__", "genus": "g__", "species": "s__"}


# ── NCBI → GTDB name mappings (reclassifications) ────────────────────────────
# Each entry: ncbi_name → (gtdb_canonical_name, human_readable_note)
NCBI_TO_GTDB = {
    # Phylum renames
    "Firmicutes":              ("Bacillota",                   "NCBI Firmicutes → GTDB p__Bacillota"),
    "Bacteroidetes":           ("Bacteroidota",                "NCBI Bacteroidetes → GTDB p__Bacteroidota"),
    "Proteobacteria":          ("Pseudomonadota",              "NCBI Proteobacteria → GTDB p__Pseudomonadota"),
    "Cyanobacteria":           ("Cyanobacteriota",             "NCBI Cyanobacteria → GTDB p__Cyanobacteriota"),
    # Family renames
    "Odoribacteraceae":        ("Marinifilaceae",              "NCBI Odoribacteraceae → GTDB f__Marinifilaceae"),
    # Species reclassifications (genus transfers)
    "Lactobacillus plantarum": ("Lactiplantibacillus plantarum",
                                "NCBI Lactobacillus → GTDB Lactiplantibacillus"),
    "Lactobacillus reuteri":   ("Limosilactobacillus reuteri",
                                "NCBI Lactobacillus → GTDB Limosilactobacillus"),
    "Lactobacillus rhamnosus": ("Lacticaseibacillus rhamnosus",
                                "NCBI Lactobacillus → GTDB Lacticaseibacillus"),
    "Eubacterium hallii":      ("Anaerobutyricum hallii",
                                "NCBI Eubacterium → GTDB Anaerobutyricum"),
    "Eubacterium rectale":     ("Roseburia rectalis",
                                "NCBI Eubacterium rectale → GTDB Roseburia rectalis"),
    "Ruminococcus gnavus":     ("Mediterraneibacter gnavus",
                                "NCBI Ruminococcus → GTDB Mediterraneibacter"),
    # GTDB polyphyletic suffixes (Clostridium is paraphyletic in GTDB)
    "Clostridium leptum":      ("Clostridium_A leptum",
                                "GTDB polyphyletic suffix: g__Clostridium_A"),
    "Clostridium scindens":    ("Clostridium_AP scindens",
                                "GTDB polyphyletic suffix: g__Clostridium_AP"),
    "Clostridium sporogenes":  ("Clostridium_F sporogenes",
                                "GTDB polyphyletic suffix: g__Clostridium_F"),
    "Clostridium savagella":   ("Dwaynesavagella gallinarum",
                                "NCBI Clostridium savagella → GTDB Dwaynesavagella gallinarum"),
}


# ── Non-GTDB taxa: fungi, viruses, abbreviated/informal names ────────────────
# Values: lineage dict + match_method + note
NON_GTDB = {
    "Candida": {
        "domain": "Eukaryota", "phylum": "Ascomycota", "class": "Saccharomycetes",
        "order": "Saccharomycetales", "family": "Debaryomycaceae",
        "genus": "Candida", "species": "",
        "match_method": "manual",
        "note": "Fungal genus; NCBI taxonomy; not in GTDB",
    },
    "Trichoderma": {
        "domain": "Eukaryota", "phylum": "Ascomycota", "class": "Sordariomycetes",
        "order": "Hypocreales", "family": "Hypocreaceae",
        "genus": "Trichoderma", "species": "",
        "match_method": "manual",
        "note": "Fungal genus; NCBI taxonomy; not in GTDB",
    },
    "Picobirnavirus": {
        "domain": "Virus", "phylum": "", "class": "", "order": "",
        "family": "Picobirnaviridae", "genus": "Picobirnavirus", "species": "",
        "match_method": "manual",
        "note": "Dsegmented dsRNA virus; not in GTDB",
    },
    "B. mimicus": {
        "domain": "Bacteria", "phylum": "Pseudomonadota", "class": "Gammaproteobacteria",
        "order": "Vibrionales", "family": "Vibrionaceae",
        "genus": "Vibrio", "species": "Vibrio mimicus",
        "match_method": "manual",
        "note": "Abbreviated binomial; interpreted as Vibrio mimicus; GTDB g__Vibrio",
    },
    "C. perfringens": {
        "domain": "Bacteria", "phylum": "Bacillota", "class": "Clostridia",
        "order": "Eubacteriales", "family": "Peptostreptococcaceae",
        "genus": "Clostridium", "species": "Clostridium perfringens",
        "match_method": "manual",
        "note": "Abbreviated binomial; Clostridium perfringens; GTDB g__Clostridium",
    },
    "Streptococci": {
        "domain": "Bacteria", "phylum": "Bacillota", "class": "Bacilli",
        "order": "Lactobacillales", "family": "Streptococcaceae",
        "genus": "Streptococcus", "species": "",
        "match_method": "manual",
        "note": "Informal plural; corresponds to GTDB g__Streptococcus",
    },
    "Clostridium coccoides)": {
        "domain": "Bacteria", "phylum": "Bacillota", "class": "Clostridia",
        "order": "", "family": "", "genus": "", "species": "",
        "match_method": "manual",
        "note": "Artifact: trailing ')' from July src_row 32 parenthetical extraction; "
                "species identity uncertain (likely Blautia coccoides or related)",
    },
}


# ── GTDB TSV parsing ──────────────────────────────────────────────────────────

def _parse_gtdb_tsv(path: Path) -> list:
    """Return list of taxonomy strings from a GTDB taxonomy TSV.gz."""
    strings = []
    with gzip.open(path, 'rt') as f:
        for line in f:
            parts = line.rstrip('\n').split('\t', 1)
            if len(parts) == 2:
                strings.append(parts[1])
    return strings


def _build_indexes(tax_strings: list) -> dict:
    """Build dict: rank → name → representative lineage_dict.

    For each rank level, stores the lineage of the first genome seen with
    that name (genome order in the TSV is stable across runs).
    """
    indexes = {rank: {} for rank in RANK_LEVELS}
    for tax_str in tax_strings:
        segs = tax_str.split(';')
        if len(segs) != 7:
            continue
        lin = {}
        for rank, pref, seg in zip(RANK_LEVELS,
                                    ["d__", "p__", "c__", "o__", "f__", "g__", "s__"],
                                    segs):
            lin[rank] = seg[3:] if seg.startswith(pref) else seg

        for rank in RANK_LEVELS:
            name = lin[rank]
            if name and name not in indexes[rank]:
                indexes[rank][name] = dict(lin)

    return indexes


# ── Lineage helpers ───────────────────────────────────────────────────────────

def _truncate(lin: dict, rank: str) -> dict:
    """Return lineage with levels below `rank` zeroed out."""
    idx = _RANK_IDX.get(rank, len(RANK_LEVELS) - 1)
    return {r: (lin.get(r, "") if i <= idx else "")
            for i, r in enumerate(RANK_LEVELS)}


def _lookup_in_indexes(name: str, rank: str, indexes: dict):
    """Return lineage dict for name at given rank, or None if not found."""
    if rank not in indexes:
        return None
    return indexes[rank].get(name)


# ── Per-subject dispatcher ────────────────────────────────────────────────────

def _not_applicable(rank: str) -> dict:
    return {
        "gtdb_name": "", **{r: "" for r in RANK_LEVELS},
        "match_method": "not_applicable", "reclassified": "no",
        "note": f"rank={rank} is not a GTDB biological taxon",
    }


def _not_found(subject: str, rank: str) -> dict:
    return {
        "gtdb_name": "", **{r: "" for r in RANK_LEVELS},
        "match_method": "not_found", "reclassified": "no",
        "note": f"No match in GTDB {GTDB_RELEASE} at rank={rank}",
    }


def _resolve(subject: str, rank: str, indexes: dict) -> dict:
    """Return a result dict for one subject row."""
    # Not a biological taxon
    if rank in ("functional", "molecular_pattern"):
        return _not_applicable(rank)

    # Non-GTDB taxa (fungi, viruses, artifacts, informal names)
    if subject in NON_GTDB:
        entry = NON_GTDB[subject]
        lin   = {r: entry[r] for r in RANK_LEVELS}
        trunc = _truncate(lin, rank) if rank in _RANK_IDX else lin
        return {
            "gtdb_name":   trunc.get(rank, ""),
            **{r: trunc[r] for r in RANK_LEVELS},
            "match_method": entry["match_method"],
            "reclassified": "no",
            "note":         entry["note"],
        }

    # NCBI → GTDB reclassification
    if subject in NCBI_TO_GTDB:
        gtdb_name, note = NCBI_TO_GTDB[subject]
        lin = _lookup_in_indexes(gtdb_name, rank, indexes)
        if lin is not None:
            trunc = _truncate(lin, rank)
        else:
            trunc = {r: "" for r in RANK_LEVELS}
            note  = note + "; lineage not found in GTDB TSV"
        return {
            "gtdb_name":   gtdb_name,
            **{r: trunc[r] for r in RANK_LEVELS},
            "match_method": "ncbi_reclassified",
            "reclassified": "yes",
            "note":         note,
        }

    # Exact GTDB match
    lin = _lookup_in_indexes(subject, rank, indexes)
    if lin is not None:
        trunc = _truncate(lin, rank)
        return {
            "gtdb_name":   subject,
            **{r: trunc[r] for r in RANK_LEVELS},
            "match_method": "exact_gtdb",
            "reclassified": "no",
            "note":         "",
        }

    return _not_found(subject, rank)


# ── Main ──────────────────────────────────────────────────────────────────────

def main():
    print("Loading GTDB r232 taxonomy files …")
    bac_strings = _parse_gtdb_tsv(GTDB_CACHE / "bac120_taxonomy.tsv.gz")
    arc_strings = _parse_gtdb_tsv(GTDB_CACHE / "ar53_taxonomy.tsv.gz")
    all_strings = bac_strings + arc_strings
    print(f"  bac120: {len(bac_strings):,} genomes")
    print(f"  ar53:   {len(arc_strings):,} genomes")

    print("Building taxonomy indexes …")
    indexes = _build_indexes(all_strings)
    for rank in RANK_LEVELS:
        print(f"  {rank}: {len(indexes[rank]):,} unique names")

    print("\nLoading rank_lookup.csv …")
    rank_lkp = pd.read_csv(LOOKUPS_DIR / "rank_lookup.csv", dtype=str,
                            keep_default_na=False)
    print(f"  {len(rank_lkp)} subjects")

    rows      = []
    not_found = []

    for _, row in rank_lkp.iterrows():
        subject = row["subject"]
        rank    = row["rank_as_cited"]
        result  = _resolve(subject, rank, indexes)

        rows.append({
            "subject":       subject,
            "rank_as_cited": rank,
            "gtdb_name":     result["gtdb_name"],
            "gtdb_rank":     (rank if result["match_method"] not in
                              ("not_applicable", "not_found", "manual") else ""),
            **{r: result[r] for r in RANK_LEVELS},
            "match_method":  result["match_method"],
            "reclassified":  result["reclassified"],
            "gtdb_release":  GTDB_RELEASE if result["match_method"] != "not_applicable" else "",
            "note":          result["note"],
        })

        if result["match_method"] == "not_found":
            not_found.append({"subject": subject, "rank_as_cited": rank})

    out_df   = pd.DataFrame(rows)
    out_path = LOOKUPS_DIR / "taxonomy_lookup.csv"
    out_df.to_csv(out_path, index=False)
    print(f"\n→ {out_path}  ({len(out_df)} rows)")

    mc = out_df["match_method"].value_counts()
    print("\nMatch method summary:")
    for method, count in mc.items():
        print(f"  {method:20s} {count}")

    # Reclassifications report
    reclassified = out_df[out_df["reclassified"] == "yes"]
    if not reclassified.empty:
        rc_path = REVIEW_DIR / "gtdb_reclassifications.csv"
        reclassified[["subject", "rank_as_cited", "gtdb_name",
                       "phylum", "note"]].to_csv(rc_path, index=False)
        print(f"\n→ {rc_path}  ({len(reclassified)} reclassified subjects)")

    if not_found:
        print(f"\nWARNING: {len(not_found)} subjects not found in GTDB:")
        for nf in not_found:
            print(f"  {nf['subject']} ({nf['rank_as_cited']})")
    else:
        print("\nAll subjects resolved.")

    return out_df


if __name__ == "__main__":
    main()
