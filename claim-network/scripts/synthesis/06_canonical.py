"""Step 06 — Assign canonical claim IDs and aggregate per-claim statistics.

Input:  DataFrame from 05_mechanism (columns: subject, rank_as_cited, valence,
        mechanism_categories, mechanism_primary, src_row, citing, ref_id,
        ref_label, evidence, source, subject_group, atomic_id)
Output: Input + columns: canonical_claim_id, canonical_claim, is_new_claim
        Side-effects:
          - Appends new claims to lookups/canonical_claims.csv (first_seen = today)
          - Writes review/new_claims_<YYYY-MM-DD>.csv listing any new claim triples

Lookup: claim-network/lookups/canonical_claims.csv
        (subject + rank_as_cited + valence → canonical_claim_id, claim_label)

New claims are auto-assigned the next free integer ID; they are never blocked.
IDs are never renumbered or reused.

Label convention (mirrors July 2026 synthesis):
  unfavourable : "{subject} ({rank}) exacerbates GVHD"
  favourable   : "{subject} ({rank}) protective in GVHD"
  context      : "{subject} ({rank}) context-dependent role in GVHD"
  For rank == "functional", the parenthetical is omitted.
"""
import sys
from datetime import date
from pathlib import Path
import pandas as pd

sys.path.insert(0, str(Path(__file__).parent))
from common import load_lookup, LOOKUPS_DIR, REVIEW_DIR


# ── label helpers ────────────────────────────────────────────────────────────

_VERB = {
    "unfavourable": "exacerbates GVHD",
    "favourable":   "protective in GVHD",
    "context":      "context-dependent role in GVHD",
}

def _make_label(subject: str, rank: str, valence: str) -> str:
    rank_part = f" ({rank})" if rank != "functional" else ""
    verb = _VERB.get(valence, f"– GVHD ({valence})")
    return f"{subject}{rank_part} {verb}"


# ── aggregation helper ────────────────────────────────────────────────────────

def _aggregate_claims(df: pd.DataFrame) -> pd.DataFrame:
    """Return Canonical_Claims-style aggregation over the atomic rows.

    Returns a DataFrame with one row per canonical_claim_id and columns:
    canonical_claim_id, canonical_claim, subject, subject_rank, subject_group,
    valence, outcome_domain, mechanism_categories, n_atomic_claims,
    n_primary_refs, n_reviews, reviews
    """
    rows = []
    for cid, grp in df.groupby("canonical_claim_id", sort=False):
        first = grp.iloc[0]

        # mechanism counts (skip blank rows)
        mech_parts = []
        for mc in grp["mechanism_categories"].dropna():
            for cat in mc.split(";"):
                cat = cat.strip()
                if cat:
                    mech_parts.append(cat)
        from collections import Counter
        cat_counts = Counter(mech_parts)
        mech_str = ("; ".join(f"{c} ({n})" for c, n in
                               sorted(cat_counts.items(), key=lambda x: -x[1]))
                    if cat_counts else None)

        # unique primary refs (exclude rows where ref_id is blank)
        primary_refs = grp["ref_id"].replace("", pd.NA).dropna().unique()

        # unique citing reviews
        citing_reviews = sorted(grp["citing"].unique())

        rows.append({
            "canonical_claim_id": cid,
            "canonical_claim":    grp["canonical_claim"].iloc[0],
            "subject":            first["subject"],
            "subject_rank":       first["rank_as_cited"],
            "subject_group":      first.get("subject_group", ""),
            "valence":            first["valence"],
            "outcome_domain":     "GVHD",
            "mechanism_categories": mech_str,
            "n_atomic_claims":    len(grp),
            "n_primary_refs":     len(primary_refs),
            "n_reviews":          len(citing_reviews),
            "reviews":            "; ".join(citing_reviews),
        })

    return pd.DataFrame(rows)


# ── main ─────────────────────────────────────────────────────────────────────

def main(df: pd.DataFrame) -> pd.DataFrame:
    today = date.today().isoformat()
    lkp_path = LOOKUPS_DIR / "canonical_claims.csv"
    lkp = pd.read_csv(lkp_path, dtype=str)

    # Build lookup: (subject, rank_as_cited, valence) → (claim_id, claim_label)
    key_cols = ["subject", "rank_as_cited", "valence"]
    lkp_index = lkp.set_index(key_cols)

    next_id = lkp["claim_id"].astype(int).max() + 1
    new_rows = []  # rows to append to canonical_claims.csv
    ids_out, labels_out, is_new_out = [], [], []

    for _, row in df.iterrows():
        key = (row["subject"], row["rank_as_cited"], row["valence"])
        if key in lkp_index.index:
            entry = lkp_index.loc[key]
            # handle duplicate index keys (same triple; take first)
            cid   = (entry["claim_id"].iloc[0]
                     if isinstance(entry["claim_id"], pd.Series)
                     else entry["claim_id"])
            label = (entry["claim_label"].iloc[0]
                     if isinstance(entry["claim_label"], pd.Series)
                     else entry["claim_label"])
            ids_out.append(int(cid))
            labels_out.append(label)
            is_new_out.append(False)
        else:
            # New claim — assign ID, generate label, register
            label = _make_label(row["subject"], row["rank_as_cited"], row["valence"])
            new_entry = {
                "claim_id":      next_id,
                "subject":       row["subject"],
                "rank_as_cited": row["rank_as_cited"],
                "valence":       row["valence"],
                "claim_label":   label,
                "first_seen":    today,
            }
            new_rows.append(new_entry)
            # Update the in-memory index so later rows get the same ID
            new_row_df = pd.DataFrame([new_entry]).set_index(key_cols)
            lkp_index = pd.concat([lkp_index, new_row_df])
            ids_out.append(next_id)
            labels_out.append(label)
            is_new_out.append(True)
            next_id += 1

    df = df.copy()
    df["canonical_claim_id"] = ids_out
    df["canonical_claim"]    = labels_out
    df["is_new_claim"]       = is_new_out

    # Persist new claims
    if new_rows:
        new_df = pd.DataFrame(new_rows)
        updated = pd.concat([lkp, new_df], ignore_index=True)
        updated.to_csv(lkp_path, index=False)
        out_path = REVIEW_DIR / f"new_claims_{today}.csv"
        new_df.to_csv(out_path, index=False)
        print(f"[06_canonical] {len(new_rows)} new claim(s) → {out_path}")

    print(f"[06_canonical] {df['canonical_claim_id'].nunique()} distinct canonical claims "
          f"({df['is_new_claim'].sum()} new)")
    return df


if __name__ == "__main__":
    import sys; sys.exit("Run via run_synthesis.py")
