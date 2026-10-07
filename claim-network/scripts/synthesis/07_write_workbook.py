"""Step 07 — Assemble Claims_Synthesis3.xlsx.

Input:  DataFrame from 06_canonical (fully annotated atomic claims)
Output: claim-network/data/Claims_Synthesis3.xlsx with sheets:
        README, Canonical_Claims, Atomic_Claims, Nodes, Edges, Claims_annotated, Flags
        mirroring the structure of Claims_Synthesis2.xlsx.

Nodes and Edges are derived from the canonical claims and their paper references.
"""
import pandas as pd
from common import DATA_DIR


def main(df: pd.DataFrame) -> None:
    # STUB
    raise NotImplementedError("07_write_workbook not yet implemented")


if __name__ == "__main__":
    import sys; sys.exit("Run via run_synthesis.py")
