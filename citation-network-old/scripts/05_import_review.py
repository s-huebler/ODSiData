"""Import paraphrased_claim edits from claims_review.xlsx back into SQLite.

Only `claim_id` and `paraphrased_claim` are read; every other column in the
xlsx is ignored on purpose. Rows with a blank paraphrase are skipped, so
re-running after a partial review pass is safe.

Usage (from citation-network/):
    python scripts/05_import_review.py
    python scripts/05_import_review.py --xlsx claims_review.xlsx --db db/citations.sqlite
"""

import argparse
import sqlite3
from pathlib import Path

import pandas as pd


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--xlsx", default="claims_review.xlsx")
    ap.add_argument("--db", default="db/citations.sqlite")
    args = ap.parse_args()

    xlsx_path = Path(args.xlsx)
    if not xlsx_path.exists():
        raise SystemExit(f"not found: {xlsx_path}")

    df = pd.read_excel(xlsx_path)
    required = {"claim_id", "paraphrased_claim"}
    missing = required - set(df.columns)
    if missing:
        raise SystemExit(f"xlsx is missing columns: {missing}")

    df = df[["claim_id", "paraphrased_claim"]].dropna(subset=["claim_id"])
    df["paraphrased_claim"] = (
        df["paraphrased_claim"].astype(str).str.strip()
    )
    df = df[~df["paraphrased_claim"].isin(["", "nan", "None"])]

    conn = sqlite3.connect(args.db)
    try:
        cur = conn.cursor()
        n = 0
        for cid, paraphrase in zip(df["claim_id"], df["paraphrased_claim"]):
            cur.execute(
                "UPDATE claims SET paraphrased_claim = ? WHERE claim_id = ?",
                (paraphrase, int(cid)),
            )
            n += cur.rowcount
        conn.commit()
    finally:
        conn.close()
    print(f"updated paraphrased_claim on {n} rows")


if __name__ == "__main__":
    main()
