"""Step 03 — Assign taxonomic rank and subject group to each subject.

Input:  DataFrame from 02_subjects (column: subject)
Output: Input + columns: rank_as_cited, subject_group
Lookup: claim-network/lookups/rank_lookup.csv
        (subject → rank_as_cited, subject_group)

Values not in rank_lookup go to review/needs_review_taxonomy.csv + stop.
"""
import sys
from pathlib import Path
import pandas as pd

sys.path.insert(0, str(Path(__file__).parent))
from common import load_lookup, review_and_stop


def main(df: pd.DataFrame) -> pd.DataFrame:
    lkp = load_lookup("rank_lookup.csv").set_index("subject")

    mapped_rank  = df["subject"].map(lkp["rank_as_cited"])
    mapped_group = df["subject"].map(lkp["subject_group"])

    unmapped_mask = mapped_rank.isna()
    if unmapped_mask.any():
        bad = df[unmapped_mask][
            ["atomic_id", "src_row", "citing", "subject"]
        ].copy()
        review_and_stop(bad, "taxonomy",
                        f"{unmapped_mask.sum()} subjects not found in rank_lookup.csv")

    df = df.copy()
    df["rank_as_cited"]  = mapped_rank
    df["subject_group"]  = mapped_group.fillna("")
    return df


if __name__ == "__main__":
    import sys; sys.exit("Run via run_synthesis.py")
