"""Step 02 — Normalize taxon tokens to canonical subjects.

Input:  DataFrame from 01_atomize (column: taxon_token)
Output: Input + columns: subject, subject_type
Lookup: claim-network/lookups/subject_lookup.csv
        (token_verbatim → subject, subject_type)

Values not in subject_lookup go to review/needs_review_subjects.csv.
"""
import pandas as pd
from common import load_lookup, review_and_stop


def main(df: pd.DataFrame) -> pd.DataFrame:
    # STUB
    raise NotImplementedError("02_subjects not yet implemented")


if __name__ == "__main__":
    import sys; sys.exit("Run via run_synthesis.py")
