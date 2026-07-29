"""Export the current claims table to an xlsx for manual review.

Each row is one claim. The cited papers are concatenated into a single
pipe-delimited column so they fit in the spreadsheet. Edit the
`paraphrased_claim` and `citation_role` columns; the next step will be a
re-import script that writes those edits back to SQLite.

Usage (from citation-network/):
    python scripts/04_export_review.py
    python scripts/04_export_review.py --db db/citations.sqlite --out claims_review.xlsx
    python scripts/04_export_review.py --only-needs-review
"""

import argparse
import sqlite3
from pathlib import Path

import pandas as pd

QUERY = """
SELECT
  c.claim_id,
  c.citing_paper_id,
  c.section,
  c.verbatim_sentence,
  c.paraphrased_claim,
  c.citation_role,
  c.needs_review,
  c.review_reason,
  GROUP_CONCAT(
    COALESCE(
      r.resolved_paper_id,
      TRIM(COALESCE(r.authors, '') || ' ' || COALESCE(CAST(r.year AS TEXT), '')),
      '[unresolved #' || CAST(r.local_number AS TEXT) || ']'
    ),
    ' | '
  ) AS cited_papers,
  GROUP_CONCAT(r.local_number, ',') AS cited_local_numbers
FROM claims c
LEFT JOIN citations ci ON ci.claim_id = c.claim_id
LEFT JOIN refs r       ON r.ref_id   = ci.ref_id
{where}
GROUP BY c.claim_id
ORDER BY c.citing_paper_id, c.claim_id
"""


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--db", default="db/citations.sqlite")
    ap.add_argument("--out", default="claims_review.xlsx")
    ap.add_argument("--only-needs-review", action="store_true")
    args = ap.parse_args()

    where = "WHERE c.needs_review = 1" if args.only_needs_review else ""
    conn = sqlite3.connect(args.db)
    try:
        df = pd.read_sql(QUERY.format(where=where), conn)
    finally:
        conn.close()

    out_path = Path(args.out)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    df.to_excel(out_path, index=False)
    print(f"wrote {len(df)} claims -> {out_path}")


if __name__ == "__main__":
    main()
