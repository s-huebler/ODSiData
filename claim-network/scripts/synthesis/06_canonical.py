"""Step 06 — Assign or create canonical claim IDs.

Input:  DataFrame from 05_mechanism (columns: subject, rank_as_cited, valence)
Output: Input + columns: canonical_claim_id, canonical_claim, is_new_claim
Lookup: claim-network/lookups/canonical_claims.csv
        (subject + rank_as_cited + valence → canonical_claim_id, canonical_claim)

Rows that match an existing canonical claim get its ID.
Rows that do not match go to review/needs_review_canonical.csv for human assignment.
"""
import pandas as pd
from common import load_lookup, review_and_stop


def main(df: pd.DataFrame) -> pd.DataFrame:
    # STUB
    raise NotImplementedError("06_canonical not yet implemented")


if __name__ == "__main__":
    import sys; sys.exit("Run via run_synthesis.py")
