#!/usr/bin/env python3
"""Rebuild reviews/claims.csv, claims_linked.csv and taxa.csv from every review's decisions.

    python3 claim-network/scripts/run_pipeline.py

Runs assemble_claims -> link_refs -> harmonize_taxa. Run parse_refs.py <paper> once per review
first (it writes reviews/<paper>/refs.csv). The ring is rebuilt separately (scripts/ring/).
"""
import subprocess, sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
for step in ["assemble_claims.py", "link_refs.py", "harmonize_taxa.py"]:
    print(f"== {step}")
    if subprocess.run([sys.executable, str(HERE / step)]).returncode != 0:
        sys.exit(f"{step} failed; stopping")
