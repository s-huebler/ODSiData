"""Initialize the citation-network SQLite database.

Usage (from citation-network/):
    python scripts/02_init_db.py
    python scripts/02_init_db.py --db db/citations.sqlite --schema scripts/schema.sql

Re-running is safe: CREATE TABLE IF NOT EXISTS is used throughout.
"""

import argparse
import sqlite3
from pathlib import Path


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--db", default="db/citations.sqlite")
    ap.add_argument("--schema", default="scripts/schema.sql")
    args = ap.parse_args()

    db_path = Path(args.db)
    db_path.parent.mkdir(parents=True, exist_ok=True)
    schema_sql = Path(args.schema).read_text(encoding="utf-8")

    conn = sqlite3.connect(db_path)
    try:
        conn.executescript(schema_sql)
        conn.commit()
    finally:
        conn.close()
    print(f"initialized {db_path}")


if __name__ == "__main__":
    main()
