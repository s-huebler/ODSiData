"""Step 05 — Map mechanism_verbatim to controlled vocabulary categories.

Input:  DataFrame from 04_valence (column: mechanism_verbatim, renamed from
        Mechanism General in 01_atomize)
Output: Input + columns: mechanism_categories (semicolon-joined), mechanism_primary,
        mechanism_flag
Lookup: claim-network/lookups/mechanism_lookup.csv
        (mechanism_verbatim → categories, primary_category)
Flags:  claim-network/lookups/july_flags.csv
        rows where field='mechanism' are attached as mechanism_flag

Blank/null mechanism_verbatim → mechanism_categories and mechanism_primary left
blank (NaN), matching July 2026 Atomic_Claims.  These rows are flagged with the
July 'blank-mechanism' flag where applicable.
Non-blank values not in mechanism_lookup → review/needs_review_mechanism.csv + stop.
"""
import sys
from pathlib import Path
import pandas as pd

sys.path.insert(0, str(Path(__file__).parent))
from common import load_lookup, review_and_stop


def main(df: pd.DataFrame) -> pd.DataFrame:
    lkp = load_lookup("mechanism_lookup.csv").set_index("mechanism_verbatim")
    flags = load_lookup("july_flags.csv")
    mech_flags = (flags[flags["field"] == "mechanism"]
                  .set_index("src_row")["flag"])

    mv = df["mechanism_verbatim"].str.strip()
    non_blank_mask = mv.ne("")

    # Check for non-blank values missing from the lookup
    non_blank_vals = mv[non_blank_mask]
    unmapped_mask = non_blank_mask & ~mv.isin(lkp.index)
    if unmapped_mask.any():
        bad = df[unmapped_mask][
            ["atomic_id", "src_row", "citing", "mechanism_verbatim"]
        ].copy()
        review_and_stop(bad, "mechanism",
                        f"{unmapped_mask.sum()} mechanism values not found "
                        f"in mechanism_lookup.csv")

    df = df.copy()
    df["mechanism_categories"] = mv.map(lkp["categories"])
    df["mechanism_primary"]    = mv.map(lkp["primary_category"])

    # Attach July flag text for flagged src_rows (field=mechanism)
    df["mechanism_flag"] = (df["src_row"].astype(str)
                            .map(mech_flags)
                            .fillna(""))
    return df


if __name__ == "__main__":
    import sys; sys.exit("Run via run_synthesis.py")
