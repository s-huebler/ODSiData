"""Step 04 — Map relationship_verbatim to valence.

Input:  DataFrame from 03_taxonomy (column: relationship_verbatim)
Output: Input + column: valence (favourable | unfavourable | context)
Lookup: claim-network/lookups/valence_lookup.csv
        (relationship_verbatim → valence)

Values not in valence_lookup go to review/needs_review_valence.csv.
"""
import pandas as pd
from common import load_lookup, review_and_stop


def main(df: pd.DataFrame) -> pd.DataFrame:
    # STUB
    raise NotImplementedError("04_valence not yet implemented")


if __name__ == "__main__":
    import sys; sys.exit("Run via run_synthesis.py")
