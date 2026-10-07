#!/usr/bin/env python3
"""Build graph_data3.json for the GVHD claims/evidence network.

Reads  Claims_Synthesis3.xlsx (default) or argv[1].
Writes claim-network/data/graph_data3.json (default) or argv[2].

Differences from build_graph_json_from_synthesis.py (the July/v2 builder):
  - Claim nodes carry rank_level (numeric), GTDB lineage fields, domain_sector.
  - Each taxon claim has lineage_parent: claim_id of the nearest same-valence
    ancestor that is itself a claim node (used for optional taxonomy links).
  - subjgroup/CLOSTRIDIA clustering hack removed; grouping comes from lineage.
  - Paper nodes and edge semantics (CITES, SUPPORTS) are unchanged.

Node schema:
  claim  → id, label, ntype="claim", rank_as_cited, rank_level (int|null),
            domain_sector, valence, gtdb_name, domain, phylum, class, order,
            family, genus, species, gtdb_reclassified, nprimary, size,
            lineage_parent (claim_id str | null)
  paper  → id, label, ntype="paper", role (review|primary),
            ntouched, size
"""

import json
import sys
from collections import OrderedDict, defaultdict
from pathlib import Path

import pandas as pd

HERE = Path(__file__).resolve().parent
DATA_DIR = HERE.parent / "data"

if len(sys.argv) > 1:
    XLSX = Path(sys.argv[1])
    if not XLSX.is_absolute():
        XLSX = Path.cwd() / XLSX
    OUT_JSON = Path(sys.argv[2]) if len(sys.argv) > 2 else XLSX.with_suffix(".json")
else:
    XLSX     = DATA_DIR / "Claims_Synthesis3.xlsx"
    OUT_JSON = DATA_DIR / "graph_data3.json"


# ── Rank vocabulary ───────────────────────────────────────────────────────────

_RANK_LEVEL = {
    "strain": 0, "species": 1, "genus": 2, "family": 3,
    "order": 4, "class": 5, "phylum": 6, "domain": 7,
}

# GTDB lineage columns ordered from lowest rank to highest
_LINEAGE_RANKS = ["species", "genus", "family", "order", "class", "phylum", "domain"]

# Which column in the lineage dict gives the ancestor name at each rank
_LINEAGE_COL = {r: r for r in _LINEAGE_RANKS}   # column name == rank name


def _rank_level(rank: str):
    return _RANK_LEVEL.get(rank, None)


def _domain_sector(domain: str, rank: str) -> str:
    if rank == "functional":
        return "functional group"
    if rank == "molecular_pattern":
        return "molecular pattern"
    d = domain or ""
    if d in ("Bacteria", "Archaea", "Eukaryota", "Virus"):
        return d
    return "other"


# ── Load workbook ─────────────────────────────────────────────────────────────

def _load_sheet(path: Path, sheet: str) -> pd.DataFrame:
    return pd.read_excel(path, sheet_name=sheet, dtype=str).fillna("")


atomic = _load_sheet(XLSX, "Atomic_Claims")
canon  = _load_sheet(XLSX, "Canonical_Claims")

# Numeric claim IDs
canon["canonical_claim_id"] = canon["canonical_claim_id"].astype(int)
atomic["canonical_claim_id"] = atomic["canonical_claim_id"].astype(int)
atomic["src_row"] = atomic["src_row"].astype(int)

# ── Per-claim lineage (first atomic row is representative) ────────────────────
# Maps canonical_claim_id → lineage dict (GTDB columns)
_LIN_COLS = ["gtdb_name", "domain", "phylum", "class", "order",
             "family", "genus", "species", "gtdb_reclassified"]

claim_lineage: dict = {}
for cid, grp in atomic.groupby("canonical_claim_id"):
    first = grp.iloc[0]
    claim_lineage[cid] = {c: first.get(c, "") for c in _LIN_COLS}


# ── Build claim lookup indexes for lineage_parent resolution ──────────────────
# Index 1: (subject_as_cited, rank, valence) → claim_id
# Index 2: (gtdb_name,        rank, valence) → claim_id
# Both built from canonical_claims.

_by_cited: dict = {}
_by_gtdb:  dict = {}

for _, row in canon.iterrows():
    cid     = row["canonical_claim_id"]
    subject = row["subject"]
    rank    = row["subject_rank"]
    valence = row["valence"]
    gname   = claim_lineage[cid]["gtdb_name"]

    _by_cited[(subject, rank, valence)] = cid
    if gname:
        _by_gtdb[(gname, rank, valence)] = cid


def _lineage_parent(cid: int, rank: str, valence: str):
    """Return the claim_id string of the nearest same-valence ancestor claim."""
    if rank not in _RANK_LEVEL:
        return None                       # functional / molecular_pattern
    current_idx = _LINEAGE_RANKS.index(rank) if rank in _LINEAGE_RANKS else -1
    if current_idx < 0:
        return None

    lin = claim_lineage[cid]
    # Walk from the next rank up through domain
    for parent_rank in _LINEAGE_RANKS[current_idx + 1:]:
        ancestor_gtdb = lin.get(_LINEAGE_COL[parent_rank], "")
        if not ancestor_gtdb:
            continue
        # Check GTDB-name index first (handles reclassified taxa)
        pid = _by_gtdb.get((ancestor_gtdb, parent_rank, valence))
        if pid is not None and pid != cid:
            return f"CLAIM_{pid}"
        # Check cited-name index (handles GTDB=NCBI names)
        pid = _by_cited.get((ancestor_gtdb, parent_rank, valence))
        if pid is not None and pid != cid:
            return f"CLAIM_{pid}"

    return None


# ── Claim label ───────────────────────────────────────────────────────────────

def _claim_label(row: pd.Series) -> str:
    subj    = row["subject"]
    valence = row["valence"]
    rank    = row["subject_rank"]
    if rank not in ("functional", "molecular_pattern"):
        rank_part = f" ({rank})" if rank else ""
    else:
        rank_part = ""
    if valence == "favourable":
        return f"{subj}{rank_part} protective in GVHD"
    if valence == "unfavourable":
        return f"{subj}{rank_part} exacerbates GVHD"
    if valence == "context":
        return f"{subj}{rank_part} context-dependent role in GVHD"
    return f"{subj}{rank_part} – GVHD ({valence})"


# ── Collect primary/review sets (drive edge building) ────────────────────────

primaries: OrderedDict = OrderedDict()    # ref_id → label
reviews:   OrderedDict = OrderedDict()    # citing_id → label
supports:  OrderedDict = OrderedDict()    # (ref_id, cid) → {valence, w}
cites:     OrderedDict = OrderedDict()    # (citing_id, ref_id) → {valence, w}
claim_primaries: dict  = defaultdict(set) # cid → set(ref_id)
review_claims:   dict  = defaultdict(set) # citing_id → set(cid)
primary_claims:  dict  = defaultdict(set) # ref_id → set(cid)

for _, a in atomic.iterrows():
    cid     = a["canonical_claim_id"]
    cit_id  = a["citing_id"]
    cit_lab = a["citing"]
    ref_id  = a["ref_id"]
    ref_lab = a["ref_label"]
    val     = a["valence"]

    if cit_id:
        reviews.setdefault(cit_id, cit_lab or cit_id)
        review_claims[cit_id].add(cid)
    if ref_id:
        primaries.setdefault(ref_id, ref_lab or ref_id)
        primary_claims[ref_id].add(cid)
        claim_primaries[cid].add(ref_id)
        k = (ref_id, cid)
        if k in supports:
            supports[k]["w"] += 1
        else:
            supports[k] = {"valence": val, "w": 1}
    if cit_id and ref_id:
        k = (cit_id, ref_id)
        if k in cites:
            cites[k]["w"] += 1
        else:
            cites[k] = {"valence": val, "w": 1}

review_ids  = set(reviews)
primary_ids = set(primaries) - review_ids


# ── Build nodes ───────────────────────────────────────────────────────────────

nodes = []
node_ids: set = set()

# Claim nodes
for _, row in canon.sort_values("canonical_claim_id").iterrows():
    cid     = row["canonical_claim_id"]
    rank    = row["subject_rank"]
    valence = row["valence"]
    lin     = claim_lineage[cid]
    npr     = len(claim_primaries[cid])
    nid     = f"CLAIM_{cid}"

    nodes.append({"data": {
        "id":               nid,
        "label":            _claim_label(row),
        "ntype":            "claim",
        "rank_as_cited":    rank,
        "rank_level":       _rank_level(rank),
        "domain_sector":    _domain_sector(lin["domain"], rank),
        "valence":          valence,
        "gtdb_name":        lin["gtdb_name"],
        "domain":           lin["domain"],
        "phylum":           lin["phylum"],
        "class":            lin["class"],
        "order":            lin["order"],
        "family":           lin["family"],
        "genus":            lin["genus"],
        "species":          lin["species"],
        "gtdb_reclassified": lin["gtdb_reclassified"],
        "nprimary":         npr,
        "size":             26 + npr * 4,
        "lineage_parent":   _lineage_parent(cid, rank, valence),
    }})
    node_ids.add(nid)

# Review paper nodes
for rid in reviews:
    nt  = len(review_claims[rid])
    nid = rid
    nodes.append({"data": {
        "id": nid, "label": reviews[rid], "ntype": "paper", "role": "review",
        "ntouched": nt, "size": 20 + nt * 3,
    }})
    node_ids.add(nid)

# Primary paper nodes
for pid in primaries:
    if pid in review_ids:
        continue
    nt  = len(primary_claims[pid])
    nid = pid
    nodes.append({"data": {
        "id": nid, "label": primaries[pid], "ntype": "paper", "role": "primary",
        "ntouched": nt, "size": 20 + nt * 3,
    }})
    node_ids.add(nid)


# ── Build edges ───────────────────────────────────────────────────────────────

edges = []
i = 0

for (ref_id, cid), v in supports.items():
    if ref_id in review_ids:
        continue
    i += 1
    edges.append({"data": {
        "id": f"e{i}", "source": ref_id, "target": f"CLAIM_{cid}",
        "etype": "SUPPORTS", "valence": v["valence"] or "other",
        "weight": v["w"], "ewidth": 1.5 + v["w"] * 0.7,
    }})

for (cit_id, ref_id), v in cites.items():
    if cit_id == ref_id:
        continue
    i += 1
    edges.append({"data": {
        "id": f"e{i}", "source": cit_id, "target": ref_id,
        "etype": "CITES", "valence": v["valence"] or "other",
        "weight": v["w"], "ewidth": 1.5 + v["w"] * 0.7,
    }})


# ── Validate ──────────────────────────────────────────────────────────────────

bad_edges = []
for e in edges:
    src, tgt = e["data"]["source"], e["data"]["target"]
    if src not in node_ids:
        bad_edges.append(f"source {src!r} missing")
    if tgt not in node_ids:
        bad_edges.append(f"target {tgt!r} missing")

if bad_edges:
    print(f"ERROR: {len(bad_edges)} dangling edge endpoint(s):")
    for msg in bad_edges[:20]:
        print(f"  {msg}")
    sys.exit(1)

# Validate every taxon claim has rank_level and domain_sector
bad_claims = []
for n in nodes:
    d = n["data"]
    if d["ntype"] != "claim":
        continue
    rank = d["rank_as_cited"]
    if rank in ("functional", "molecular_pattern"):
        continue
    if d["rank_level"] is None:
        bad_claims.append(f"CLAIM_{d['id']} rank_level is None (rank={rank!r})")
    if not d["domain"]:
        bad_claims.append(f"{d['id']} domain is blank (rank={rank!r})")

if bad_claims:
    print(f"WARNING: {len(bad_claims)} claim nodes with incomplete lineage:")
    for msg in bad_claims[:10]:
        print(f"  {msg}")


# ── Write ─────────────────────────────────────────────────────────────────────

out = {"nodes": nodes, "edges": edges}
OUT_JSON.parent.mkdir(parents=True, exist_ok=True)
with open(OUT_JSON, "w") as f:
    json.dump(out, f)

# Summary
nclaim = sum(1 for n in nodes if n["data"]["ntype"] == "claim")
nrev   = sum(1 for n in nodes if n["data"].get("role") == "review")
nprim  = sum(1 for n in nodes if n["data"].get("role") == "primary")
nsup   = sum(1 for e in edges if e["data"]["etype"] == "SUPPORTS")
ncit   = sum(1 for e in edges if e["data"]["etype"] == "CITES")
npar   = sum(1 for n in nodes
             if n["data"]["ntype"] == "claim"
             and n["data"]["lineage_parent"] is not None)
nrec   = sum(1 for n in nodes
             if n["data"]["ntype"] == "claim"
             and n["data"]["gtdb_reclassified"] == "yes")

print(f"nodes={len(nodes)}  (claims={nclaim} reviews={nrev} primaries={nprim})")
print(f"edges={len(edges)}  (SUPPORTS={nsup} CITES={ncit})")
print(f"lineage_parent set on {npar}/{nclaim} claim nodes")
print(f"gtdb_reclassified on {nrec}/{nclaim} claim nodes")
print(f"→ {OUT_JSON}")
