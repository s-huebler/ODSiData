"""Step 03 — Assign taxonomic rank, subject group, and GTDB lineage to each subject.

Input:  DataFrame from 02_subjects (column: subject)
Output: Input + columns:
          rank_as_cited, subject_group   (from rank_lookup.csv — July 2026 values)
          gtdb_name, domain, phylum, class, order, family, genus, species,
          gtdb_reclassified              (from taxonomy_lookup.csv — GTDB r232)

Lookup files:
  claim-network/lookups/rank_lookup.csv        (subject → rank, subject_group)
  claim-network/lookups/taxonomy_lookup.csv    (subject → GTDB lineage)

Build taxonomy_lookup.csv first with build_taxonomy_lookup.py if it does not exist.
Subjects not found in rank_lookup go to review/needs_review_taxonomy.csv + stop.
"""
import sys
from pathlib import Path
import pandas as pd

sys.path.insert(0, str(Path(__file__).parent))
from common import load_lookup, LOOKUPS_DIR, review_and_stop

# Lineage columns added from taxonomy_lookup.csv
_LINEAGE_COLS = [
    "gtdb_name", "domain", "phylum", "class", "order",
    "family", "genus", "species", "gtdb_reclassified",
]


def main(df: pd.DataFrame) -> pd.DataFrame:
    # ── rank and subject_group (July 2026 values) ─────────────────────────────
    rank_lkp = load_lookup("rank_lookup.csv").set_index("subject")

    mapped_rank  = df["subject"].map(rank_lkp["rank_as_cited"])
    mapped_group = df["subject"].map(rank_lkp["subject_group"])

    unmapped = mapped_rank.isna()
    if unmapped.any():
        bad = df[unmapped][["atomic_id", "src_row", "citing", "subject"]].copy()
        review_and_stop(bad, "taxonomy",
                        f"{unmapped.sum()} subjects not found in rank_lookup.csv")

    df = df.copy()
    df["rank_as_cited"] = mapped_rank
    df["subject_group"] = mapped_group.fillna("")

    # ── GTDB lineage ──────────────────────────────────────────────────────────
    tax_path = LOOKUPS_DIR / "taxonomy_lookup.csv"
    if not tax_path.exists():
        print(f"[03_taxonomy] WARNING: {tax_path} not found — skipping GTDB lineage. "
              f"Run build_taxonomy_lookup.py to generate it.")
        for col in _LINEAGE_COLS:
            df[col] = ""
        return df

    tax_lkp = pd.read_csv(tax_path, dtype=str, keep_default_na=False).set_index("subject")

    for col in ["gtdb_name", "domain", "phylum", "class", "order",
                "family", "genus", "species"]:
        df[col] = df["subject"].map(tax_lkp[col]).fillna("")

    df["gtdb_reclassified"] = df["subject"].map(tax_lkp["reclassified"]).fillna("")

    n_reclassified = (df["gtdb_reclassified"] == "yes").sum()
    print(f"[03_taxonomy] {len(df)} rows: rank_as_cited + subject_group assigned; "
          f"GTDB lineage joined ({n_reclassified} reclassified subjects)")
    return df


if __name__ == "__main__":
    import sys; sys.exit("Run via run_synthesis.py")
