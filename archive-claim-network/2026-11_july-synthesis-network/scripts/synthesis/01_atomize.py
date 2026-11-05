"""Step 01 — Atomize claims.

Input:  claim-network/data/Claims_Master_reflinked.xlsx, Claims sheet
Output: DataFrame with one row per (source_row × taxon_token), columns:
        atomic_id, src_row, citing, cited, citing_id, ref_id, ref_label,
        taxon_token, taxa_cell_verbatim, relationship_verbatim,
        mechanism_verbatim, evidence, source
Lookup: none (raw parse only)

Tokenization rules (reproduce July 2026 synthesis):
  - If Taxa is non-empty: split on "; ", then ", ", then " and " (in that order).
    taxa_cell_verbatim = verbatim cell content.
  - If Taxa is empty and Nonspecific Microbes is non-empty: whole cell = single
    token, no splitting. taxa_cell_verbatim = None (matches July Atomic_Claims).
  - Both empty → row goes to review/needs_review_atomize.csv; not silently dropped.
"""
import re
import sys
from pathlib import Path
import pandas as pd

# Allow running directly from the synthesis/ directory
sys.path.insert(0, str(Path(__file__).parent))
from common import DATA_DIR, REVIEW_DIR

CLAIMS_FILE = DATA_DIR / "Claims_Master_reflinked.xlsx"

_COLS_PASSTHROUGH = [
    "Citing", "Cited", "citing_id", "ref_id", "ref_label",
    "Suspected Relationship to GVHD",
    "Mechanism General", "Mechanism Specific", "Mechanism Detailed",
    "Therapeutic Implication", "Evidence", "Source",
]


def _strip_parentheticals(text: str) -> str:
    """Remove parenthetical qualifiers such as '(obligate anaerobes)' or
    '(post-HSCT)'.  Matches the July 2026 synthesis convention of collapsing
    'Taxon (qualifier)' → 'Taxon' before tokenising.

    Multi-token parentheticals like '(Faecalibacterium, Roseburia, …)' are also
    stripped; the July synthesis treated them as illustrative rather than as
    additional claim subjects.  (The single exception — src_row 32 — was a
    manual editorial decision that cannot be reproduced algorithmically.)
    """
    return re.sub(r'\s*\([^)]*\)', '', text).strip()


def _split_taxa_cell(cell: str) -> list:
    """Split a Taxa cell into individual tokens using July 2026 delimiter logic.

    Steps:
    1. Strip parenthetical qualifiers from the whole cell.
    2. Split on '; ' (semicolons), then ', ' (commas), then ' and '.
    3. Strip any leading 'and ' from each token (Oxford-comma artefact:
       '…Salmonela, and Clostridium' → split on ', ' → 'and Clostridium').
    """
    clean = _strip_parentheticals(cell)
    parts = re.split(r';\s+', clean)
    parts2 = []
    for p in parts:
        parts2.extend(re.split(r',\s+', p))
    parts3 = []
    for p in parts2:
        parts3.extend(re.split(r'\s+and\s+', p))
    tokens = []
    for t in parts3:
        t = t.strip()
        t = re.sub(r'^and\s+', '', t, flags=re.IGNORECASE).strip()
        if t:
            tokens.append(t)
    return tokens


def main(df_in=None):
    """Return atomized DataFrame. If df_in is None, reads from file."""
    if df_in is not None:
        raw = df_in
    else:
        raw = pd.read_excel(CLAIMS_FILE, sheet_name="Claims",
                            dtype=str, keep_default_na=False)

    rows_out = []
    review_rows = []

    for i, row in raw.iterrows():
        src_row = i + 2  # Excel row number (1-indexed header + 1-indexed data)
        taxa = row.get("Taxa", "").strip()
        nonspec = row.get("Nonspecific Microbes", "").strip()

        passthrough = {
            "src_row": src_row,
            **{col: row.get(col, "") for col in _COLS_PASSTHROUGH},
        }

        if taxa:
            tokens = _split_taxa_cell(taxa)
            cell_verbatim = taxa
            for tok in tokens:
                rows_out.append({
                    **passthrough,
                    "taxon_token": tok,
                    "taxa_cell_verbatim": cell_verbatim,
                })
        elif nonspec:
            # Whole cell is one token; taxa_cell_verbatim stays None per July convention
            rows_out.append({
                **passthrough,
                "taxon_token": nonspec,
                "taxa_cell_verbatim": None,
            })
        else:
            review_rows.append({**passthrough, "taxon_token": "", "taxa_cell_verbatim": ""})

    if review_rows:
        review_path = REVIEW_DIR / "needs_review_atomize.csv"
        pd.DataFrame(review_rows).to_csv(review_path, index=False)
        print(f"[01_atomize] WARNING: {len(review_rows)} rows with empty Taxa and "
              f"Nonspecific Microbes written to {review_path}")

    df = pd.DataFrame(rows_out)

    # Assign atomic_id AT001, AT002, ... in source order
    width = max(3, len(str(len(df))))
    df.insert(0, "atomic_id", [f"AT{str(i+1).zfill(width)}" for i in range(len(df))])

    # Rename passthrough columns to tidy names
    df = df.rename(columns={
        "Citing": "citing",
        "Cited": "cited",
        "Suspected Relationship to GVHD": "relationship_verbatim",
        "Mechanism General": "mechanism_verbatim",
        "Mechanism Specific": "mechanism_specific",
        "Mechanism Detailed": "mechanism_detailed",
        "Therapeutic Implication": "therapeutic_implication",
        "Evidence": "evidence",
        "Source": "source",
    })

    return df


if __name__ == "__main__":
    result = main()
    print(f"[01_atomize] {len(result)} atomic rows from "
          f"{result['src_row'].nunique()} source rows")
    print(result[["atomic_id", "src_row", "citing", "taxon_token",
                  "taxa_cell_verbatim"]].head(10).to_string())
