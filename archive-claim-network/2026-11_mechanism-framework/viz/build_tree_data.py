#!/usr/bin/env python3
"""
build_tree_data.py
Reads claims_synthesis_framework.csv (target_type=taxon) and the Taxa sheet
from claims_synthesis_framework.xlsx, then writes tree_data.json for the
D3 taxonomic ring visualization.
"""

import json
import math
import sys
from pathlib import Path

import openpyxl
import pandas as pd

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------
BASE = Path(__file__).resolve().parent.parent  # claim-network/framework/
CSV_PATH = BASE / "claims_synthesis_framework.csv"
XLSX_PATH = BASE / "claims_synthesis_framework.xlsx"
OUT_PATH = BASE / "viz" / "tree_data.json"

# ---------------------------------------------------------------------------
# Rank order
# ---------------------------------------------------------------------------
RANKS = ["domain", "phylum", "class", "order", "family", "genus", "species"]
RANK_IDX = {r: i for i, r in enumerate(RANKS)}
TOP_LEVELS = ["phylum", "class", "order", "family", "genus"]

# ---------------------------------------------------------------------------
# 1. Load Taxa sheet (openpyxl, read_only=False per project rules)
# ---------------------------------------------------------------------------
wb = openpyxl.load_workbook(str(XLSX_PATH), read_only=False)
ws = wb["Taxa"]
headers = [cell.value for cell in next(ws.iter_rows(min_row=1, max_row=1))]
taxa_rows_raw = []
for row in ws.iter_rows(min_row=2, values_only=True):
    if any(v is not None for v in row):
        taxa_rows_raw.append(dict(zip(headers, row)))

# Deduplicate on canonical taxon name (keep first occurrence for lineage)
taxa_info = {}  # canonical taxon -> lineage dict
taxa_as_cited = {}  # canonical taxon -> list of taxon_as_cited values
for row in taxa_rows_raw:
    t = row["taxon"]
    if t not in taxa_info:
        taxa_info[t] = {
            "taxon_rank": row["taxon_rank"],
            "domain": row["domain"],
            "phylum": row["phylum"],
            "class": row["class"],
            "order": row["order"],
            "family": row["family"],
            "genus": row["genus"],
            "species": row["species"],
        }
        taxa_as_cited[t] = []
    cited = row["taxon_as_cited"]
    if cited and cited not in taxa_as_cited[t]:
        taxa_as_cited[t].append(cited)

# ---------------------------------------------------------------------------
# 2. Load CSV (taxon rows only)
# ---------------------------------------------------------------------------
df_all = pd.read_csv(CSV_PATH)
df = df_all[df_all["target_type"] == "taxon"].copy()

# Fill taxon_as_cited from CSV rows too (supplement xlsx)
for _, row in df.iterrows():
    t = row["taxon"]
    cited = row.get("taxon_as_cited", None)
    if t in taxa_as_cited and cited and str(cited) != "nan" and cited not in taxa_as_cited[t]:
        taxa_as_cited[t].append(cited)

# Add taxon_as_cited to taxa_info
for t in taxa_info:
    taxa_info[t]["taxon_as_cited"] = taxa_as_cited.get(t, [t])
    rank = taxa_info[t]["taxon_rank"]
    taxa_info[t]["italic"] = rank in ("genus", "species")

# ---------------------------------------------------------------------------
# 3. Papers
# ---------------------------------------------------------------------------
papers = {}
for _, row in df.iterrows():
    rid = row["ref_id"]
    if rid not in papers:
        papers[rid] = row["ref_label"]

# ---------------------------------------------------------------------------
# 4. Edges — aggregate (ref_id, taxon, direction, evidence)
# ---------------------------------------------------------------------------
edge_keys = {}  # (ref_id, taxon, direction, evidence) -> {width, rows}

for _, row in df.iterrows():
    key = (row["ref_id"], row["taxon"], row["direction"], row["evidence"])
    if key not in edge_keys:
        edge_keys[key] = {"width": 0, "rows": []}
    edge_keys[key]["width"] += 1
    quote_raw = row.get("quote", "") or ""
    quote = str(quote_raw)[:300] if quote_raw else ""
    edge_keys[key]["rows"].append({
        "statement_id": row.get("statement_id", ""),
        "citing_label": row.get("citing_label", ""),
        "intervention": row.get("intervention", "") if "intervention" in row else "",
        "quote": quote,
        "mechanism_specific": row.get("mechanism_specific", "") or "",
        "mechanism_broad": row.get("mechanism_broad", "") or "",
    })

edges = []
for (ref_id, taxon, direction, evidence), info in edge_keys.items():
    edges.append({
        "ref_id": ref_id,
        "ref_label": papers.get(ref_id, ref_id),
        "taxon": taxon,
        "direction": direction,
        "evidence": evidence,
        "width": info["width"],
        "rows": info["rows"],
    })

# ---------------------------------------------------------------------------
# 5. Level counts
# ---------------------------------------------------------------------------
def taxon_visible_at_level(taxon, level):
    """A taxon is visible at level L if:
    - RANK_IDX[taxon_rank] >= RANK_IDX[level]  (taxon rank is at or below level)
    - taxon has non-null value at level L in its lineage
    """
    info = taxa_info.get(taxon)
    if not info:
        return False
    rank = info.get("taxon_rank")
    if rank not in RANK_IDX:
        return False
    if RANK_IDX[rank] < RANK_IDX[level]:
        return False
    val = info.get(level)
    return val is not None and str(val).strip() != ""


level_counts = {}
for level in TOP_LEVELS:
    visible_taxa = {t for t in taxa_info if taxon_visible_at_level(t, level)}
    visible_edges = [e for e in edges if e["taxon"] in visible_taxa]
    visible_papers = {e["ref_id"] for e in visible_edges}
    level_counts[level] = {
        "taxa": len(visible_taxa),
        "edges": len(visible_edges),
        "papers": len(visible_papers),
    }

# ---------------------------------------------------------------------------
# 6. Hierarchy trees
# ---------------------------------------------------------------------------
EXPECTED = {
    "phylum": {"taxa": 76, "edges": 245, "papers": 118},
    "class":  {"taxa": 73, "edges": 239, "papers": 116},
    "order":  {"taxa": 71, "edges": 224, "papers": 110},
    "family": {"taxa": 70, "edges": 219, "papers": 108},
    "genus":  {"taxa": 60, "edges": 199, "papers": 102},
}


def get_lineage_at_level(taxon, level):
    """Return the value of the taxon's lineage at the given rank level."""
    info = taxa_info.get(taxon)
    if not info:
        return None
    return info.get(level)


def get_lineage_path(taxon, up_to_level):
    """Return ordered list of (rank, value) pairs from domain up to up_to_level."""
    info = taxa_info.get(taxon)
    if not info:
        return []
    path = []
    for r in RANKS:
        val = info.get(r)
        if val:
            path.append((r, val))
        if r == up_to_level:
            break
    return path


def build_subtree_for_level(top_level):
    """Build hierarchy trees for a given top-level grouping."""
    # ranks between top_level (exclusive) and lowest possible rank
    grouping_idx = RANK_IDX[top_level]
    intermediate_ranks = RANKS[grouping_idx + 1:]  # below top_level

    # All claim taxa visible at this level
    visible = [t for t in taxa_info if taxon_visible_at_level(t, top_level)]

    # Group by top-level value
    groups = {}
    for t in visible:
        grp = taxa_info[t][top_level]
        if grp not in groups:
            groups[grp] = []
        groups[grp].append(t)

    def build_tree_node(rank, name, taxa_list, is_claim_taxon=False, taxon_obj=None):
        """Recursively build tree node."""
        if is_claim_taxon:
            # Leaf node
            info = taxa_info[taxon_obj]
            return {
                "id": taxon_obj,
                "rank": info["taxon_rank"],
                "name": taxon_obj,
                "is_claim": True,
                "italic": info["italic"],
                "skipped_ranks": [],
                "taxon_as_cited": info.get("taxon_as_cited", []),
                "children": [],
            }

        # Find the next rank that has variation
        rank_idx = RANK_IDX[rank]
        next_ranks = RANKS[rank_idx + 1:]

        # Group taxa_list by next rank values, descending through ranks
        def group_by_rank(taxa_list, from_rank):
            """Group taxa by their value at from_rank, skipping ranks with no variation."""
            from_idx = RANK_IDX[from_rank]
            remaining_ranks = RANKS[from_idx:]

            for r in remaining_ranks:
                r_idx = RANK_IDX[r]
                # Check if this rank has values for these taxa
                has_values = any(
                    taxa_info[t].get(r) is not None
                    and RANK_IDX.get(taxa_info[t]["taxon_rank"], -1) >= r_idx
                    for t in taxa_list
                )
                if not has_values:
                    continue

                # Group by value at r
                sub = {}
                ungrouped = []
                for t in taxa_list:
                    val = taxa_info[t].get(r)
                    taxon_rank_idx = RANK_IDX.get(taxa_info[t]["taxon_rank"], -1)
                    if val is not None and taxon_rank_idx >= r_idx:
                        sub.setdefault(val, []).append(t)
                    else:
                        ungrouped.append(t)

                # Only group if it creates meaningful structure
                if len(sub) > 1 or ungrouped:
                    return r, sub, ungrouped
                elif len(sub) == 1:
                    # Only one group at this rank - check if we'd be creating
                    # a single-child non-claim node (will be collapsed anyway)
                    return r, sub, ungrouped

            return None, {}, taxa_list

        next_rank, subgroups, ungrouped = group_by_rank(taxa_list, next_ranks[0] if next_ranks else None)

        if next_rank is None:
            # All taxa are leaves at this point
            children = []
            for t in taxa_list:
                children.append(build_tree_node(rank, name, [], is_claim_taxon=True, taxon_obj=t))
            return children  # return list

        children = []
        # Build children for each subgroup
        for val, sub_taxa in subgroups.items():
            if len(sub_taxa) == 1 and taxa_info[sub_taxa[0]]["taxon_rank"] == next_rank:
                # The single taxon IS at this rank — it's a leaf
                children.append(build_tree_node(next_rank, val, [], is_claim_taxon=True, taxon_obj=sub_taxa[0]))
            else:
                # Build sub-node
                sub_children_result = build_tree_node(next_rank, val, sub_taxa)
                if isinstance(sub_children_result, list):
                    # Was a flat list of leaves - wrap in node
                    node = {
                        "id": f"{next_rank}::{val}",
                        "rank": next_rank,
                        "name": val,
                        "is_claim": False,
                        "italic": False,
                        "skipped_ranks": [],
                        "taxon_as_cited": [],
                        "children": sub_children_result,
                    }
                    children.append(node)
                elif isinstance(sub_children_result, dict):
                    children.append(sub_children_result)

        # Handle ungrouped (shouldn't normally happen)
        for t in ungrouped:
            children.append(build_tree_node(rank, name, [], is_claim_taxon=True, taxon_obj=t))

        return children

    def build_group_tree(grp_name, taxa_list):
        """Build tree for a top-level group."""
        children_result = build_tree_node(top_level, grp_name, taxa_list)
        if isinstance(children_result, list):
            children = children_result
        else:
            children = [children_result]

        root = {
            "id": f"{top_level}::{grp_name}",
            "rank": top_level,
            "name": grp_name,
            "is_claim": False,
            "italic": False,
            "skipped_ranks": [],
            "taxon_as_cited": [],
            "children": children,
        }
        return root

    def collapse_uninformative(node, is_root=False):
        """Collapse non-claim nodes with exactly 1 child: remove them,
        put {rank, name} in child's skipped_ranks, recursively.
        Root is NEVER collapsed."""
        if not node.get("children"):
            return node

        # Recurse children first
        node["children"] = [collapse_uninformative(c) for c in node["children"]]

        # Collapse single-child non-claim children (not root)
        if not is_root and not node["is_claim"] and len(node["children"]) == 1:
            child = node["children"][0]
            # Add this node to child's skipped_ranks (prepend)
            child["skipped_ranks"] = [{"rank": node["rank"], "name": node["name"]}] + child.get("skipped_ranks", [])
            return child

        return node

    result = {}
    for grp_name, taxa_list in groups.items():
        tree = build_group_tree(grp_name, taxa_list)
        tree = collapse_uninformative(tree, is_root=True)
        result[grp_name] = tree

    return result


# Build all hierarchies
print("\nBuilding hierarchies...")
hierarchies = {}
for level in TOP_LEVELS:
    hierarchies[level] = build_subtree_for_level(level)
    # Count leaf nodes (claim taxa) to verify
    def count_leaves(node):
        if not node.get("children"):
            return 1 if node.get("is_claim") else 0
        return sum(count_leaves(c) for c in node["children"])
    total = sum(count_leaves(t) for t in hierarchies[level].values())
    print(f"  {level}: {len(hierarchies[level])} groups, {total} claim taxa leaves")

# ---------------------------------------------------------------------------
# 7. Assertions
# ---------------------------------------------------------------------------
print("\n=== ASSERTIONS ===")

# Core counts at phylum level
n_taxa = len(taxa_info)
n_papers = len(papers)
phylum_edges = level_counts["phylum"]["edges"]

status = []
def chk(label, val, expected):
    mark = "✓" if val == expected else f"✗ expected {expected}"
    print(f"  {label}: {val} {mark}")
    return val == expected

ok = True
ok &= chk("Claim taxa", n_taxa, 76)
ok &= chk("Papers", n_papers, 118)
ok &= chk("Phylum-level edges", phylum_edges, 245)

print("\n=== LEVEL COUNTS ===")
print(f"  {'level':<8} {'taxa':>6} {'edges':>7} {'papers':>8}")
print(f"  {'-'*35}")
for level in TOP_LEVELS:
    lc = level_counts[level]
    exp = EXPECTED[level]
    marks = []
    for k in ["taxa", "edges", "papers"]:
        v = lc[k]
        e = exp[k]
        marks.append(f"{v}{'✓' if v == e else f' ✗exp{e}'}")
    print(f"  {level:<8} {marks[0]:>12} {marks[1]:>12} {marks[2]:>12}")

# Check all claim taxa have complete lineage (at least domain+phylum)
print("\n=== LINEAGE COMPLETENESS ===")
missing_lineage = []
for t, info in taxa_info.items():
    if not info.get("domain") or not info.get("phylum"):
        missing_lineage.append(t)
if missing_lineage:
    print(f"  ✗ Missing domain/phylum: {missing_lineage}")
else:
    print(f"  ✓ All {n_taxa} claim taxa have domain and phylum")

# Check all edge targets exist in taxa_info
print("\n=== EDGE TARGET VALIDITY ===")
missing_targets = {e["taxon"] for e in edges if e["taxon"] not in taxa_info}
if missing_targets:
    print(f"  ✗ Edges reference unknown taxa: {missing_targets}")
else:
    print(f"  ✓ All edge targets exist in taxa")

# ---------------------------------------------------------------------------
# 8. Build output JSON
# ---------------------------------------------------------------------------
out = {
    "taxa": taxa_info,
    "papers": papers,
    "edges": edges,
    "level_counts": level_counts,
    "hierarchies": hierarchies,
    "top_levels": TOP_LEVELS,
}

with open(OUT_PATH, "w") as f:
    json.dump(out, f, indent=None, separators=(",", ":"))

size_kb = OUT_PATH.stat().st_size / 1024
print(f"\nWrote {OUT_PATH} ({size_kb:.1f} KB)")
print(f"  taxa: {n_taxa}, papers: {n_papers}, edges: {len(edges)}")
