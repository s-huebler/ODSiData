"""Regression check: compare pipeline output against July 2026 synthesis.

Runs all implemented steps and compares against Claims_Synthesis2.xlsx
Atomic_Claims.

Checks (extended as steps are implemented):
  - (src_row, subject) multiset            [steps 01-02]
  - valence per src_row                    [step 04]
  - mechanism_category, mechanism_primary  [step 05]

Usage:
  python check_against_july.py
"""
import sys
from pathlib import Path
import pandas as pd

sys.path.insert(0, str(Path(__file__).parent))
from common import DATA_DIR
import importlib.util


def _load_module(name):
    path = Path(__file__).parent / f"{name}.py"
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def load_july() -> pd.DataFrame:
    df = pd.read_excel(DATA_DIR / "Claims_Synthesis2.xlsx",
                       sheet_name="Atomic_Claims", dtype=str)
    df["src_row"] = df["src_row"].astype(int)
    return df


def run_pipeline_steps() -> pd.DataFrame:
    """Run all implemented steps; skip stubs gracefully."""
    steps = ["01_atomize", "02_subjects", "04_valence", "05_mechanism"]
    df = None
    ran = []
    for name in steps:
        mod = _load_module(name)
        try:
            df = mod.main() if name == "01_atomize" else mod.main(df)
            ran.append(name)
        except NotImplementedError:
            print(f"  [{name}] STUB — skipping")
            break
    print(f"  Steps run: {', '.join(ran)}")
    return df


def _multiset_compare(july_df, mine_df):
    """Compare (src_row, subject) multisets — returns (n_matched, missing_df, extra_df)."""
    j_counts = july_df[["src_row", "subject"]].value_counts().rename("july_count")
    m_counts = mine_df[["src_row", "subject"]].value_counts().rename("mine_count")
    merged = (j_counts.to_frame().join(m_counts, how="outer")
              .fillna(0).astype(int).reset_index())
    merged["matched"] = merged[["july_count", "mine_count"]].min(axis=1)
    merged["missing"] = (merged["july_count"] - merged["mine_count"]).clip(lower=0)
    merged["extra"]   = (merged["mine_count"] - merged["july_count"]).clip(lower=0)
    return (merged["matched"].sum(),
            merged[merged["missing"] > 0].copy(),
            merged[merged["extra"] > 0].copy())


def _check_subjects(july, mine):
    """Section 1: (src_row, subject) multiset comparison."""
    print("\n── SUBJECTS ──────────────────────────────────────────────────")
    print(f"Row counts:  july={len(july)}  mine={len(mine)}")

    n_matched, missing_df, extra_df = _multiset_compare(july, mine)
    print(f"Matched:     {n_matched} / {len(july)} July rows")
    print(f"Missing:     {missing_df['missing'].sum()} (in July, not in mine)")
    print(f"Extra:       {extra_df['extra'].sum()} (in mine, not in July)")

    if not missing_df.empty:
        detail = missing_df.merge(
            july[["src_row", "taxon", "subject", "taxa_cell_verbatim", "citing"]]
            .drop_duplicates(["src_row", "subject"]),
            on=["src_row", "subject"], how="left",
        )
        print("\nMISSING:")
        print(detail[["src_row", "citing", "taxon", "subject",
                       "taxa_cell_verbatim"]].to_string(index=False))
    if not extra_df.empty:
        detail = extra_df.merge(
            mine[["src_row", "taxon_token", "subject", "taxa_cell_verbatim", "citing"]]
            .assign(src_row=lambda d: d["src_row"].astype(int))
            .drop_duplicates(["src_row", "subject"]),
            on=["src_row", "subject"], how="left",
        )
        print("\nEXTRA:")
        print(detail[["src_row", "citing", "taxon_token", "subject",
                       "taxa_cell_verbatim"]].to_string(index=False))

    if missing_df.empty and extra_df.empty:
        print("OK — all July rows reproduced exactly, no extras.")
    else:
        if not missing_df.empty:
            print(f"\nKnown: src_row 32 — July manually extracted parenthetical species "
                  f"(Clostridium leptum, Clostridium coccoides); algorithm strips "
                  f"parentheticals uniformly.")


def _check_per_src_row(july, mine, col_july, col_mine, label):
    """Compare a per-src_row column between July and mine.

    Takes the first value per src_row (all atoms from the same source row share
    the same value for valence/mechanism since those columns come from the source
    row, not from the individual taxon).
    """
    # One representative row per src_row
    j = (july[["src_row", col_july]]
         .drop_duplicates("src_row")
         .rename(columns={col_july: "july_val"})
         .set_index("src_row"))
    m = (mine[["src_row", col_mine]]
         .assign(src_row=lambda d: d["src_row"].astype(int))
         .drop_duplicates("src_row")
         .rename(columns={col_mine: "mine_val"})
         .set_index("src_row"))

    combined = j.join(m, how="inner")  # only rows present in both
    # Treat NaN as empty string for comparison
    j_val = combined["july_val"].fillna("")
    m_val = combined["mine_val"].fillna("")
    mismatches = combined[j_val != m_val].copy()

    n_rows = len(combined)
    n_ok   = n_rows - len(mismatches)
    print(f"\n── {label.upper()} ───────────────────────────────────────────────────")
    print(f"Rows compared: {n_rows}  OK: {n_ok}  Mismatches: {len(mismatches)}")

    if not mismatches.empty:
        print("\nMISMATCHES:")
        print(mismatches[["july_val", "mine_val"]].to_string())
    else:
        print("OK — all values match July.")


def check():
    print("Loading July synthesis …")
    july = load_july()

    print("Running pipeline …")
    mine = run_pipeline_steps()

    _check_subjects(july, mine)

    if "valence" in mine.columns:
        _check_per_src_row(july, mine, "valence", "valence", "valence")
    else:
        print("\n── VALENCE — step 04 not yet run")

    if "mechanism_categories" in mine.columns:
        _check_per_src_row(july, mine,
                           "mechanism_category", "mechanism_categories",
                           "mechanism categories")
        _check_per_src_row(july, mine,
                           "mechanism_primary", "mechanism_primary",
                           "mechanism primary")
        print("\nNote: 2 known mechanism_category mismatches (src_rows 72-73, verbatim")
        print("'Biomarker (ratio)'): July made context-dependent assignments for the same")
        print("verbatim string; recorded in review/seed_conflicts.csv. Primary matches.")
    else:
        print("\n── MECHANISM — step 05 not yet run")

    print("\n══ DONE ══════════════════════════════════════════════════════")


if __name__ == "__main__":
    check()
