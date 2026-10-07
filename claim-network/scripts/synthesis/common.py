"""Shared paths and helpers for the claims synthesis pipeline.

Paths are relative to the repo root (two levels up from this file).
"""
from pathlib import Path
import pandas as pd

REPO_ROOT = Path(__file__).parent.parent.parent
DATA_DIR = REPO_ROOT / "claim-network" / "data"
LOOKUPS_DIR = REPO_ROOT / "claim-network" / "lookups"
REVIEW_DIR = REPO_ROOT / "claim-network" / "review"
OUTPUT_DIR = REPO_ROOT / "claim-network" / "output"

REVIEW_DIR.mkdir(parents=True, exist_ok=True)


def load_lookup(name: str) -> pd.DataFrame:
    """Load a lookup CSV from LOOKUPS_DIR."""
    return pd.read_csv(LOOKUPS_DIR / name, dtype=str, keep_default_na=False)


def review_and_stop(df: pd.DataFrame, step_name: str, message: str) -> None:
    """Write df to review/needs_review_{step_name}.csv and raise SystemExit."""
    path = REVIEW_DIR / f"needs_review_{step_name}.csv"
    df.to_csv(path, index=False)
    raise SystemExit(f"[{step_name}] {message}\n  → {len(df)} rows written to {path}")
