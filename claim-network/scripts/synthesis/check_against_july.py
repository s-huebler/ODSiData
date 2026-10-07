"""Regression check: compare pipeline output against July 2026 synthesis.

Runs steps 01_atomize and 02_subjects, then compares the resulting
(src_row, subject) multiset against Claims_Synthesis2.xlsx Atomic_Claims.

Usage:
  python check_against_july.py

Prints:
  - Total counts (mine vs July)
  - Count of matched, missing (in July but not mine), extra (in mine not July)
  - Full tables for each discrepancy category

Extended by later prompts to include valence, mechanism, canonical claim checks.
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
    mod01 = _load_module("01_atomize")
    mod02 = _load_module("02_subjects")
    df = mod01.main()
    df = mod02.main(df)
    return df


def _make_key_df(df: pd.DataFrame, src_col: str, subj_col: str,
                 label: str) -> pd.DataFrame:
    """Return sorted (src_row, subject) frame with a source label."""
    return (df[[src_col, subj_col]]
            .rename(columns={src_col: "src_row", subj_col: "subject"})
            .assign(src_row=lambda d: d["src_row"].astype(int))
            .sort_values(["src_row", "subject"])
            .reset_index(drop=True)
            .assign(_from=label))


def _multiset_compare(july_df, mine_df):
    """Compare (src_row, subject) multisets.

    Returns (n_matched, missing_df, extra_df) where missing rows are in July
    but not mine and extra rows are in mine but not July.  Uses per-key count
    comparison so duplicate keys (e.g. two Clostridia rows for the same src_row
    when both 'Clostridium clusters IV' and 'XIVa' map to Clostridia) are
    handled correctly rather than generating a Cartesian product.
    """
    j_counts = (july_df[["src_row", "subject"]]
                .value_counts().rename("july_count"))
    m_counts = (mine_df[["src_row", "subject"]]
                .value_counts().rename("mine_count"))

    merged = (j_counts.to_frame().join(m_counts, how="outer")
              .fillna(0).astype(int).reset_index())

    merged["matched"] = merged[["july_count", "mine_count"]].min(axis=1)
    merged["missing"] = (merged["july_count"] - merged["mine_count"]).clip(lower=0)
    merged["extra"]   = (merged["mine_count"] - merged["july_count"]).clip(lower=0)

    n_matched = merged["matched"].sum()
    missing_df = merged[merged["missing"] > 0].copy()
    extra_df   = merged[merged["extra"]   > 0].copy()
    return n_matched, missing_df, extra_df


def check():
    print("Loading July synthesis …")
    july = load_july()

    print("Running pipeline steps 01–02 …")
    mine = run_pipeline_steps()

    print(f"\nRow counts:  july={len(july)}  mine={len(mine)}")

    n_matched, missing_df, extra_df = _multiset_compare(july, mine)

    print(f"Matched:     {n_matched} / {len(july)} July rows")
    print(f"Missing:     {missing_df['missing'].sum()} (in July, not in mine)")
    print(f"Extra:       {extra_df['extra'].sum()} (in mine, not in July)")

    if not missing_df.empty:
        print("\n--- MISSING (in July but not mine) ---")
        # Annotate with July verbatim taxon for context
        detail = missing_df.merge(
            july[["src_row", "taxon", "subject", "taxa_cell_verbatim", "citing"]]
            .drop_duplicates(["src_row", "subject"]),
            on=["src_row", "subject"], how="left",
        )
        print(detail[["src_row", "citing", "taxon", "subject",
                       "taxa_cell_verbatim"]].to_string(index=False))

    if not extra_df.empty:
        print("\n--- EXTRA (in mine but not July) ---")
        detail = extra_df.merge(
            mine[["src_row", "taxon_token", "subject", "taxa_cell_verbatim", "citing"]]
            .assign(src_row=lambda d: d.src_row.astype(int))
            .drop_duplicates(["src_row", "subject"]),
            on=["src_row", "subject"], how="left",
        )
        print(detail[["src_row", "citing", "taxon_token", "subject",
                       "taxa_cell_verbatim"]].to_string(index=False))

    print("\n--- SUMMARY ---")
    if missing_df.empty and extra_df.empty:
        print("OK — all July rows reproduced exactly, no extras.")
    else:
        if not missing_df.empty:
            print(f"MISSING {missing_df['missing'].sum()}: subjects present in July but absent in mine.")
        if not extra_df.empty:
            print(f"EXTRA {extra_df['extra'].sum()}: subjects present in mine but absent in July.")


if __name__ == "__main__":
    check()
