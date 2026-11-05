"""Step 02 — Normalize taxon tokens to canonical subjects.

Input:  DataFrame from 01_atomize (column: taxon_token)
Output: Input + columns: subject, subject_type
Lookup: claim-network/lookups/subject_lookup.csv
        (token_verbatim → subject, subject_type)

Matching: exact string match after stripping leading/trailing whitespace.
No fuzzy matching.  Unmapped tokens → review/needs_review_subjects.csv + stop.
"""
import sys
from pathlib import Path
import pandas as pd

sys.path.insert(0, str(Path(__file__).parent))
from common import load_lookup, review_and_stop


def main(df: pd.DataFrame) -> pd.DataFrame:
    lkp = load_lookup("subject_lookup.csv").set_index("token_verbatim")

    tokens = df["taxon_token"].str.strip()
    mapped = tokens.map(lkp["subject"])
    types_  = tokens.map(lkp["subject_type"])

    unmapped_mask = mapped.isna()
    if unmapped_mask.any():
        bad = df[unmapped_mask][
            ["atomic_id", "src_row", "citing", "taxon_token", "taxa_cell_verbatim"]
        ].copy()
        review_and_stop(bad, "subjects",
                        f"{unmapped_mask.sum()} taxon tokens not found in subject_lookup.csv")

    df = df.copy()
    df["subject"] = mapped
    df["subject_type"] = types_
    return df


if __name__ == "__main__":
    import sys; sys.exit("Run via run_synthesis.py")
