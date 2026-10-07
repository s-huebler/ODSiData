"""Step 05 — Map mechanism_verbatim to controlled vocabulary categories.

Input:  DataFrame from 04_valence (column: mechanism_verbatim)
Output: Input + columns: mechanism_categories (semicolon-joined), mechanism_primary
Lookup: claim-network/lookups/mechanism_lookup.csv
        (mechanism_verbatim → categories, primary_category)

Blank/null mechanism_verbatim is allowed (not all claims have a mechanism).
Non-blank values not in mechanism_lookup go to review/needs_review_mechanism.csv.
"""
import pandas as pd
from common import load_lookup, review_and_stop


def main(df: pd.DataFrame) -> pd.DataFrame:
    # STUB
    raise NotImplementedError("05_mechanism not yet implemented")


if __name__ == "__main__":
    import sys; sys.exit("Run via run_synthesis.py")
