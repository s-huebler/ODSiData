"""Step 04 — Map relationship_verbatim to valence.

Input:  DataFrame from 03_taxonomy (column: relationship_verbatim)
Output: Input + columns: valence (favourable | unfavourable | context), valence_flag
Lookup: claim-network/lookups/valence_lookup.csv
        (relationship_verbatim → valence, rule)
Flags:  claim-network/lookups/july_flags.csv
        rows where field='valence' are attached as valence_flag

Matching: exact string match after stripping leading/trailing whitespace.
Case is preserved (source values match lookup keys as-is).
Unmapped → review/needs_review_valence.csv + non-zero exit.
"""
import sys
from pathlib import Path
import pandas as pd

sys.path.insert(0, str(Path(__file__).parent))
from common import load_lookup, review_and_stop


def main(df: pd.DataFrame) -> pd.DataFrame:
    lkp = load_lookup("valence_lookup.csv").set_index("relationship_verbatim")
    flags = load_lookup("july_flags.csv")
    valence_flags = (flags[flags["field"] == "valence"]
                     .set_index("src_row")["flag"])

    rv = df["relationship_verbatim"].str.strip()
    mapped = rv.map(lkp["valence"])

    unmapped_mask = mapped.isna()
    if unmapped_mask.any():
        bad = df[unmapped_mask][
            ["atomic_id", "src_row", "citing", "relationship_verbatim"]
        ].copy()
        review_and_stop(bad, "valence",
                        f"{unmapped_mask.sum()} relationship values not found "
                        f"in valence_lookup.csv")

    df = df.copy()
    df["valence"] = mapped

    # Attach July flag text for any flagged src_rows (field=valence)
    df["valence_flag"] = (df["src_row"].astype(str)
                          .map(valence_flags)
                          .fillna(""))
    return df


if __name__ == "__main__":
    import sys; sys.exit("Run via run_synthesis.py")
