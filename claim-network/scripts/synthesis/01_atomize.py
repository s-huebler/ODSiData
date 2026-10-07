"""Step 01 — Atomize claims.

Input:  claim-network/data/Claims_Master_reflinked.xlsx, Claims sheet
Output: DataFrame with one row per (source_row × taxon_token), columns:
        src_row, citing, citing_id, ref_id, ref_label,
        taxon_token, relationship_verbatim, mechanism_verbatim,
        evidence, source
Lookup: none (raw parse only)

Splits multi-taxa cells on ';' and produces one atomic row per token.
Filters to rows where Taxa or Nonspecific Microbes is non-empty.
"""
import pandas as pd
from common import DATA_DIR


def main(df_in=None):
    """Return atomized DataFrame. If df_in is None, reads from file."""
    # STUB
    raise NotImplementedError("01_atomize not yet implemented")


if __name__ == "__main__":
    result = main()
    print(f"[01_atomize] {len(result)} atomic rows")
