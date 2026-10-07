"""Step 07 — Assemble Claims_Synthesis3.xlsx.

Input:  DataFrame from 06_canonical (fully annotated atomic claims)
Output: claim-network/data/Claims_Synthesis3.xlsx with sheets matching
        Claims_Synthesis2.xlsx structure:
        README, Canonical_Claims, Atomic_Claims, Nodes, Edges,
        Claims_annotated, Flags, Pipeline
"""
import sys
from collections import Counter, OrderedDict
from datetime import datetime, date
from pathlib import Path

import openpyxl
import pandas as pd

sys.path.insert(0, str(Path(__file__).parent))
from common import DATA_DIR, LOOKUPS_DIR


# ── sheet builders ────────────────────────────────────────────────────────────

def _build_canonical_claims(df: pd.DataFrame) -> pd.DataFrame:
    """Aggregate atomic rows into one row per canonical claim."""
    rows = []
    for cid, grp in df.groupby("canonical_claim_id", sort=True):
        first = grp.iloc[0]

        # mechanism counts (skip blank / NaN rows)
        mech_parts = []
        for mc in grp["mechanism_categories"].dropna():
            mc = str(mc).strip()
            if mc:
                for cat in mc.split(";"):
                    cat = cat.strip()
                    if cat:
                        mech_parts.append(cat)
        cat_counts = Counter(mech_parts)
        mech_str = ("; ".join(f"{c} ({n})" for c, n in
                               sorted(cat_counts.items(), key=lambda x: -x[1]))
                    if cat_counts else None)

        primary_refs   = grp["ref_id"].replace("", pd.NA).dropna().unique()
        citing_reviews = sorted(grp["citing"].unique())

        rows.append({
            "canonical_claim_id": cid,
            "canonical_claim":    first["canonical_claim"],
            "subject":            first["subject"],
            "subject_rank":       first["rank_as_cited"],
            "subject_group":      first.get("subject_group", ""),
            "gtdb_phylum":        first.get("phylum", ""),
            "valence":            first["valence"],
            "outcome_domain":     "GVHD",
            "mechanism_categories": mech_str,
            "n_atomic_claims":    len(grp),
            "n_primary_refs":     len(primary_refs),
            "n_reviews":          len(citing_reviews),
            "reviews":            "; ".join(citing_reviews),
        })

    return pd.DataFrame(rows)


def _build_atomic_claims(df: pd.DataFrame) -> pd.DataFrame:
    """Return Atomic_Claims sheet columns in July 2026 order."""
    col_map = {
        "mechanism_categories": "mechanism_category",
        "rank_as_cited":        "subject_rank",
        "taxon_token":          "taxon",   # July uses 'taxon', not 'taxon_token'
    }
    out = df.rename(columns=col_map)

    if "taxa_cell_verbatim" not in out.columns:
        out["taxa_cell_verbatim"] = None

    cols = [
        "atomic_id", "src_row", "canonical_claim_id", "canonical_claim",
        "taxon", "subject", "subject_rank", "subject_group", "valence",
        "relationship_verbatim", "mechanism_category", "mechanism_primary",
        "mechanism_verbatim", "citing", "citing_id", "ref_id", "ref_label",
        "evidence", "source", "taxa_cell_verbatim",
        # GTDB r232 lineage columns (additive; not in July 2026 synthesis)
        "gtdb_name", "domain", "phylum", "class", "order",
        "family", "genus", "species", "gtdb_reclassified",
    ]
    for c in cols:
        if c not in out.columns:
            out[c] = None
    return out[cols]


def _build_nodes(df: pd.DataFrame) -> pd.DataFrame:
    """One row per unique paper node (citing or referenced)."""
    citing_ids  = {}  # id -> label
    primary_ids = {}

    for _, row in df.iterrows():
        cit_id, cit_lab = row.get("citing_id", ""), row.get("citing", "")
        ref_id, ref_lab = row.get("ref_id", ""),   row.get("ref_label", "")
        if cit_id:
            citing_ids[cit_id] = cit_lab or cit_id
        if ref_id:
            primary_ids.setdefault(ref_id, ref_lab or ref_id)

    # count claim-edges per node
    citing_edge_counts  = Counter(df["citing_id"].replace("", pd.NA).dropna())
    primary_edge_counts = Counter(df["ref_id"].replace("", pd.NA).dropna())

    rows = []
    for nid, label in sorted(citing_ids.items(),
                              key=lambda x: -citing_edge_counts.get(x[0], 0)):
        rows.append({"node_id": nid, "label": label, "role": "citing",
                     "n_claim_edges": citing_edge_counts.get(nid, 0)})
    for nid, label in sorted(primary_ids.items(),
                              key=lambda x: -primary_edge_counts.get(x[0], 0)):
        if nid not in citing_ids:
            rows.append({"node_id": nid, "label": label, "role": "referenced",
                         "n_claim_edges": primary_edge_counts.get(nid, 0)})
    return pd.DataFrame(rows)


def _build_edges(df: pd.DataFrame) -> pd.DataFrame:
    """One row per atomic claim, matching July 2026 Edges sheet.

    All atomic rows are included — even those with blank ref_id (these appear
    with NaN source_id/target_id, matching the July workbook convention).
    """
    rows = []
    seen: dict = {}  # (source_id, target_id, cid) -> True (dup detection)

    for _, row in df.iterrows():
        src_id  = row.get("citing_id", "") or ""
        src_lab = row.get("citing", "")    or ""
        tgt_id  = row.get("ref_id", "")    or ""
        tgt_lab = row.get("ref_label", "") or ""
        cid     = row.get("canonical_claim_id", "")
        mc      = row.get("mechanism_categories", "") or ""

        if src_id and tgt_id:
            key = (src_id, tgt_id, cid)
            dup = key in seen
            seen[key] = True
        else:
            # blank ref row — never a duplicate
            dup = False

        rows.append({
            "source_id":          src_id or None,
            "source_label":       src_lab or None,
            "target_id":          tgt_id or None,
            "target_label":       tgt_lab or None,
            "canonical_claim_id": cid,
            "canonical_claim":    row.get("canonical_claim", ""),
            "subject":            row.get("subject", ""),
            "subject_rank":       row.get("rank_as_cited", ""),
            "valence":            row.get("valence", ""),
            "mechanism_category": mc or None,
            "evidence":           row.get("evidence", ""),
            "source":             row.get("source", ""),
            "atomic_id":          row.get("atomic_id", ""),
            "duplicate_edge":     "duplicate" if dup else None,
        })

    return pd.DataFrame(rows)


def _build_claims_annotated(df: pd.DataFrame) -> pd.DataFrame:
    """One row per source row, aggregating all atomic claims from that row."""
    rows = []
    for src_row, grp in df.groupby("src_row", sort=True):
        first = grp.iloc[0]

        cids   = "; ".join(str(c) for c in grp["canonical_claim_id"].tolist())
        claims = " | ".join(grp["canonical_claim"].tolist())
        subj_r = "; ".join(
            f"{r['subject']} ({r['rank_as_cited']})" for _, r in grp.iterrows()
        )
        # mechanism_category: unique categories from this row (no counts)
        all_cats = []
        for mc in grp["mechanism_categories"].dropna():
            mc = str(mc).strip()
            if mc:
                for cat in mc.split(";"):
                    cat = cat.strip()
                    if cat and cat not in all_cats:
                        all_cats.append(cat)
        mech_cat = "; ".join(all_cats) if all_cats else None

        rows.append({
            "src_row":              src_row,
            "citing":               first.get("citing", ""),
            "citing_id":            first.get("citing_id", ""),
            "ref_id":               first.get("ref_id", ""),
            "ref_label":            first.get("ref_label", ""),
            "taxa_verbatim":        first.get("taxa_cell_verbatim", ""),
            "relationship_verbatim": first.get("relationship_verbatim", ""),
            "mechanism_verbatim":   first.get("mechanism_verbatim", ""),
            "canonical_claim_ids":  cids,
            "canonical_claims":     claims,
            "subjects_ranked":      subj_r,
            "valence":              first.get("valence", ""),
            "mechanism_category":   mech_cat,
        })

    return pd.DataFrame(rows)


def _build_flags() -> pd.DataFrame:
    return pd.read_csv(LOOKUPS_DIR / "july_flags.csv", dtype=str)


def _build_readme_text(df: pd.DataFrame, cc: pd.DataFrame,
                       input_file: str, run_date: str) -> list:
    """Return list of (row, col, value) triples for the README sheet."""
    n_atomic  = len(df)
    n_canon   = df["canonical_claim_id"].nunique()
    n_papers  = (df["ref_id"].replace("", pd.NA).dropna().nunique() +
                 df["citing_id"].replace("", pd.NA).dropna().nunique())
    n_edges   = df[df["ref_id"].replace("", pd.NA).notna()].shape[0]
    n_src     = df["src_row"].nunique()

    text = f"""GVHD Microbiome Claims Network — Synthesis Workbook
Generated by: claim-network/scripts/synthesis/run_synthesis.py
Input: {input_file}
Run date: {run_date}

=== Batch 3 counts ===
{n_atomic} atomic claims | {n_canon} canonical claims | {n_papers} paper nodes
{n_edges} edges | from {n_src} source rows

=== Synthesis rules (inherited from Batch 2, July 2026) ===

Canonical claim identity = subject@rank + valence toward GVHD.
Mechanism is NOT folded into claim identity (changed from Batch 1).

Valence vocabulary:
  favourable   = microbe/group is protective (reduces GVHD severity/incidence)
  unfavourable = microbe/group is exacerbative (increases GVHD severity/incidence)
  context      = immunomodulatory, complex or direction depends on context

Claim labels:
  unfavourable: "Subject (rank) exacerbates GVHD"
  favourable:   "Subject (rank) protective in GVHD"
  context:      "Subject (rank) context-dependent role in GVHD"
  (rank omitted in parenthetical for subject_rank=functional)

Canonical claim IDs are stable integers assigned in discovery order.
IDs from Batch 2 (1–109) are reused unchanged.
New IDs ≥ 110 are assigned on first appearance.

mechanism_categories in Canonical_Claims:
  "CategoryA (count); CategoryB (count); ..." sorted by count descending.
  Derived from Mechanism General column → mechanism_lookup.csv.

=== Pipeline ===
The scripted pipeline (Batch 3 onwards) reproduces this workbook from
Claims_Master_reflinked.xlsx using steps 01–07 in
claim-network/scripts/synthesis/. Lookup tables in claim-network/lookups/
encode all manual synthesis decisions. New claims are auto-assigned IDs and
written to review/new_claims_<date>.csv for human review.
"""
    return text


def _pipeline_metadata(df: pd.DataFrame, input_file: str) -> pd.DataFrame:
    """Return a one-page pipeline provenance table."""
    from pathlib import Path as _P
    lkp_dir = LOOKUPS_DIR
    lkp_counts = {}
    for p in sorted(lkp_dir.glob("*.csv")):
        try:
            n = sum(1 for _ in open(p)) - 1  # rows excl. header
            lkp_counts[p.name] = n
        except Exception:
            lkp_counts[p.name] = "?"

    rows = [
        ("input_file",      input_file),
        ("run_date",        date.today().isoformat()),
        ("n_source_rows",   df["src_row"].nunique()),
        ("n_atomic_claims", len(df)),
        ("n_canonical",     df["canonical_claim_id"].nunique()),
        ("n_new_claims",    int(df.get("is_new_claim", pd.Series(False)).sum())),
    ]
    for name, count in lkp_counts.items():
        rows.append((f"lookup:{name}", count))

    return pd.DataFrame(rows, columns=["key", "value"])


# ── writer ────────────────────────────────────────────────────────────────────

def _write_sheet(ws, df: pd.DataFrame) -> None:
    ws.append(list(df.columns))
    for row in df.itertuples(index=False, name=None):
        ws.append([None if (isinstance(v, float) and pd.isna(v))
                   else v for v in row])


def main(df: pd.DataFrame) -> None:
    out_path   = DATA_DIR / "Claims_Synthesis3.xlsx"
    input_file = "Claims_Master_reflinked.xlsx"
    run_date   = date.today().isoformat()

    cc_df  = _build_canonical_claims(df)
    ac_df  = _build_atomic_claims(df)
    nd_df  = _build_nodes(df)
    ed_df  = _build_edges(df)
    ca_df  = _build_claims_annotated(df)
    fl_df  = _build_flags()
    pl_df  = _pipeline_metadata(df, input_file)
    readme = _build_readme_text(df, cc_df, input_file, run_date)

    wb = openpyxl.Workbook()
    # Remove default sheet
    wb.remove(wb.active)

    # README sheet (plain text in A1)
    ws_readme = wb.create_sheet("README")
    for i, line in enumerate(readme.splitlines(), start=1):
        ws_readme.cell(row=i, column=1, value=line)

    _write_sheet(wb.create_sheet("Canonical_Claims"), cc_df)
    _write_sheet(wb.create_sheet("Atomic_Claims"),    ac_df)
    _write_sheet(wb.create_sheet("Nodes"),            nd_df)
    _write_sheet(wb.create_sheet("Edges"),            ed_df)
    _write_sheet(wb.create_sheet("Claims_annotated"), ca_df)
    _write_sheet(wb.create_sheet("Flags"),            fl_df)
    _write_sheet(wb.create_sheet("Pipeline"),         pl_df)

    wb.save(out_path)
    print(f"[07_write_workbook] → {out_path}")
    print(f"  {len(cc_df)} canonical claims, {len(ac_df)} atomic claims, "
          f"{len(nd_df)} nodes, {len(ed_df)} edges")


if __name__ == "__main__":
    import sys; sys.exit("Run via run_synthesis.py")
