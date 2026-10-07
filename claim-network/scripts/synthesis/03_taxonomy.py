"""Step 03 — Assign taxonomic rank to each subject.

Input:  DataFrame from 02_subjects (column: subject)
Output: Input + column: rank_as_cited
Lookup: claim-network/lookups/rank_lookup.csv
        (subject → rank_as_cited)

Values not in rank_lookup go to review/needs_review_taxonomy.csv.
"""
import pandas as pd
from common import load_lookup, review_and_stop


def main(df: pd.DataFrame) -> pd.DataFrame:
    # STUB
    raise NotImplementedError("03_taxonomy not yet implemented")


if __name__ == "__main__":
    import sys; sys.exit("Run via run_synthesis.py")
