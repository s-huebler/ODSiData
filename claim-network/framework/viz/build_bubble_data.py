"""
build_bubble_data.py
Reads claims_synthesis_framework.csv and writes bubble_data.json
for the Cytoscape.js mechanism bubble visualization.
"""

import csv
import json
import collections
import os
import sys

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
REPO_ROOT = os.path.abspath(os.path.join(SCRIPT_DIR, "..", "..", ".."))
CSV_PATH = os.path.join(REPO_ROOT, "claim-network", "framework", "claims_synthesis_framework.csv")
OUT_PATH = os.path.join(SCRIPT_DIR, "bubble_data.json")

# ---------------------------------------------------------------------------
# Read CSV
# ---------------------------------------------------------------------------
rows = []
with open(CSV_PATH, newline="", encoding="utf-8") as f:
    reader = csv.DictReader(f)
    for row in reader:
        rows.append(row)

# ---------------------------------------------------------------------------
# Identify paper nodes  (distinct ref_id)
# ---------------------------------------------------------------------------
paper_info = {}   # ref_id -> ref_label
for r in rows:
    paper_info[r["ref_id"]] = r["ref_label"]

paper_ids = sorted(paper_info.keys(), key=lambda rid: paper_info[rid])  # alpha by label

# ---------------------------------------------------------------------------
# Identify taxon nodes  (only rows where target_type == 'taxon')
# ---------------------------------------------------------------------------
taxon_target_type = collections.defaultdict(set)
for r in rows:
    taxon_target_type[r["taxon"]].add(r["target_type"])

taxon_node_set = {t for t, tt in taxon_target_type.items() if "taxon" in tt}
# functional groups: only 'mechanism' target_type — edges point to mechanism_specific bubble

# taxon metadata aggregated from taxon rows
taxon_meta = {}   # taxon -> {rank, taxon_as_cited}
for r in rows:
    if r["target_type"] != "taxon":
        continue
    t = r["taxon"]
    if t not in taxon_meta:
        taxon_meta[t] = {"rank": r["taxon_rank"], "as_cited": set()}
    taxon_meta[t]["as_cited"].add(r["taxon_as_cited"])

# ---------------------------------------------------------------------------
# Broad / Specific bubble definitions (fixed order)
# ---------------------------------------------------------------------------
BROAD_ORDER = [
    "Class 1: Metabolite-mediated",
    "Class 2: Immune cell targeting",
    "Class 3: Barrier and structural",
    "Class 4: Pathobiont expansion",
    "Class 0: Unattributed",
]

SPECIFIC_CHILDREN = {
    "Class 1: Metabolite-mediated": [
        "1a. SCFA / butyrate signaling",
        "1b. Bile acid signaling",
        "1c. Tryptophan / indole signaling",
        "1d. Other metabolites",
    ],
    "Class 2: Immune cell targeting": [
        "2a. Innate immune",
        "2b. T-cell adaptive",
        "2c. Other immune",
    ],
    "Class 3: Barrier and structural": [
        "3a. Epithelial barrier",
        "3b. Colonization resistance / competitive exclusion",
    ],
    "Class 4: Pathobiont expansion": [
        "4b. Pathobiont expansion / mono-dominance",
    ],
    "Class 0: Unattributed": [
        "0. Unattributed",
    ],
}

SPECIFIC_TO_BROAD = {}
for broad, children in SPECIFIC_CHILDREN.items():
    for child in children:
        SPECIFIC_TO_BROAD[child] = broad

# Broad x-positions (left to right)
BROAD_X = {
    "Class 1: Metabolite-mediated": 400,
    "Class 2: Immune cell targeting": 850,
    "Class 3: Barrier and structural": 1200,
    "Class 4: Pathobiont expansion": 1500,
    "Class 0: Unattributed": 1800,
}
BROAD_Y = 300
BROAD_W = 350
BROAD_H = 400

# ---------------------------------------------------------------------------
# Placement logic for taxon nodes
# ---------------------------------------------------------------------------
# Attributed rows = target_type=='taxon' AND mechanism_specific != '0. Unattributed'
taxon_attributed_rows = collections.defaultdict(list)
for r in rows:
    if r["target_type"] == "taxon" and r["mechanism_specific"] != "0. Unattributed":
        taxon_attributed_rows[r["taxon"]].append(r)

taxon_placement = {}   # taxon -> dict with type and parent info
for taxon in taxon_node_set:
    attributed = taxon_attributed_rows.get(taxon, [])
    if len(attributed) == 0:
        taxon_placement[taxon] = {
            "type": "unattributed_only",
            "parent": "0. Unattributed",
            "mechanisms": [],
            "broad_classes": ["Class 0: Unattributed"],
        }
    else:
        specs = sorted(set(r["mechanism_specific"] for r in attributed))
        broads = sorted(set(r["mechanism_broad"] for r in attributed))
        if len(specs) == 1:
            taxon_placement[taxon] = {
                "type": "single_specific",
                "parent": specs[0],
                "mechanisms": specs,
                "broad_classes": broads,
            }
        elif len(broads) == 1:
            taxon_placement[taxon] = {
                "type": "multi_same_broad",
                "parent": broads[0],
                "mechanisms": specs,
                "broad_classes": broads,
            }
        else:
            taxon_placement[taxon] = {
                "type": "multi_broad",
                "parent": None,
                "mechanisms": specs,
                "broad_classes": broads,
            }

# ---------------------------------------------------------------------------
# Layout coordinates
# ---------------------------------------------------------------------------

def specific_positions(broad):
    """Return {specific: (x, y)} relative positions inside broad bubble."""
    children = SPECIFIC_CHILDREN[broad]
    bx = BROAD_X[broad]
    by = BROAD_Y
    n = len(children)
    positions = {}
    if n == 4:
        # 2x2 grid inside parent
        offsets = [(-80, -80), (80, -80), (-80, 80), (80, 80)]
        for i, child in enumerate(children):
            positions[child] = (bx + offsets[i][0], by + offsets[i][1])
    elif n == 3:
        # Horizontal row
        spacing = 100
        start = bx - spacing
        for i, child in enumerate(children):
            positions[child] = (start + i * spacing, by)
    elif n == 2:
        # Horizontal row
        for i, child in enumerate(children):
            positions[child] = (bx + (i - 0.5) * 110, by)
    else:
        # Centered (n==1)
        positions[children[0]] = (bx, by)
    return positions

all_specific_pos = {}
for broad in BROAD_ORDER:
    all_specific_pos.update(specific_positions(broad))

def taxon_position(taxon):
    """Compute (x, y) for a taxon node."""
    pl = taxon_placement[taxon]
    ptype = pl["type"]

    if ptype == "multi_broad":
        # y=50, x=mean x of their broad classes
        broad_xs = [BROAD_X[b] for b in pl["broad_classes"] if b in BROAD_X]
        x = sum(broad_xs) / len(broad_xs) if broad_xs else 1000
        return (x, 50)
    elif ptype == "multi_same_broad":
        broad = pl["broad_classes"][0]
        return (BROAD_X[broad], BROAD_Y)
    elif ptype == "single_specific":
        spec = pl["parent"]
        sx, sy = all_specific_pos.get(spec, (BROAD_X.get(SPECIFIC_TO_BROAD.get(spec, ""), 1000), BROAD_Y))
        return (sx, sy)
    else:  # unattributed_only
        return (BROAD_X["Class 0: Unattributed"], BROAD_Y)


# Taxon nodes per specific bubble for grid packing
taxon_per_specific = collections.defaultdict(list)
taxon_per_broad = collections.defaultdict(list)

for taxon in sorted(taxon_node_set):
    pl = taxon_placement[taxon]
    ptype = pl["type"]
    if ptype == "single_specific":
        taxon_per_specific[pl["parent"]].append(taxon)
    elif ptype == "unattributed_only":
        taxon_per_specific["0. Unattributed"].append(taxon)
    elif ptype == "multi_same_broad":
        taxon_per_broad[pl["broad_classes"][0]].append(taxon)

def packed_grid_positions(n, cx, cy, cell_size=50):
    """Return list of (x, y) for n items in a centered grid."""
    cols = max(1, int(n ** 0.5 + 0.5))
    rows = (n + cols - 1) // cols
    positions = []
    for i in range(n):
        r = i // cols
        c = i % cols
        x = cx + (c - (cols - 1) / 2) * cell_size
        y = cy + (r - (rows - 1) / 2) * cell_size
        positions.append((x, y))
    return positions

# Assign grid positions to taxa inside specific bubbles
taxon_grid_pos = {}

for spec, taxa_list in taxon_per_specific.items():
    taxa_sorted = sorted(taxa_list)
    sx, sy = all_specific_pos.get(spec, (1000, BROAD_Y))
    positions = packed_grid_positions(len(taxa_sorted), sx, sy, cell_size=55)
    for i, taxon in enumerate(taxa_sorted):
        taxon_grid_pos[taxon] = positions[i]

for broad, taxa_list in taxon_per_broad.items():
    taxa_sorted = sorted(taxa_list)
    bx = BROAD_X[broad]
    positions = packed_grid_positions(len(taxa_sorted), bx, BROAD_Y, cell_size=55)
    for i, taxon in enumerate(taxa_sorted):
        taxon_grid_pos[taxon] = positions[i]

# multi_broad taxa get their own position
for taxon in taxon_node_set:
    if taxon not in taxon_grid_pos:
        taxon_grid_pos[taxon] = taxon_position(taxon)

# Paper positions: y=900, evenly spaced, alpha by ref_label
PAPER_Y = 900
paper_x_positions = {}
n_papers = len(paper_ids)
for i, pid in enumerate(paper_ids):
    paper_x_positions[pid] = 100 + i * (max(1900, n_papers * 15) / max(1, n_papers - 1))

# ---------------------------------------------------------------------------
# Build edge list
# ---------------------------------------------------------------------------
# Aggregate rows into one edge per (ref_id, target, direction, evidence)
edge_key_rows = collections.defaultdict(list)
for r in rows:
    if r["target_type"] == "taxon":
        target = r["taxon"]
    else:
        # mechanism row → target is mechanism_specific bubble
        target = r["mechanism_specific"]
    key = (r["ref_id"], target, r["direction"], r["evidence"])
    edge_key_rows[key].append(r)

edges = []
for (ref_id, target, direction, evidence), underlying in edge_key_rows.items():
    edge_id = f"e_{ref_id}_{target}_{direction}_{evidence}".replace(" ", "_").replace("/", "_").replace(".", "_")
    edge_rows = [
        {
            "statement_id": r["statement_id"],
            "citing_label": r["citing_label"],
            "intervention": r.get("intervention", ""),
            "quote": r.get("quote", ""),
            "page": r.get("page", ""),
        }
        for r in underlying
    ]
    edges.append({
        "data": {
            "id": edge_id,
            "source": ref_id,
            "target": target,
            "direction": direction,
            "evidence": evidence,
            "width": len(underlying),
            "rows": edge_rows,
        }
    })

# ---------------------------------------------------------------------------
# Build node list
# ---------------------------------------------------------------------------
nodes = []

# Broad bubble nodes
for broad in BROAD_ORDER:
    bx = BROAD_X[broad]
    nodes.append({
        "data": {
            "id": broad,
            "label": broad,
            "type": "broad",
            "parent": None,
        },
        "position": {"x": bx, "y": BROAD_Y},
    })

# Specific bubble nodes (nested inside broad)
for broad in BROAD_ORDER:
    for spec in SPECIFIC_CHILDREN[broad]:
        sx, sy = all_specific_pos[spec]
        nodes.append({
            "data": {
                "id": spec,
                "label": spec,
                "type": "specific",
                "parent": broad,
            },
            "position": {"x": sx, "y": sy},
        })

# Taxon nodes
for taxon in sorted(taxon_node_set):
    pl = taxon_placement[taxon]
    ptype = pl["type"]
    meta = taxon_meta.get(taxon, {"rank": "", "as_cited": set()})
    rank = meta["rank"]
    italic = rank in ("genus", "species")

    if ptype == "single_specific":
        parent = pl["parent"]
    elif ptype == "unattributed_only":
        parent = "0. Unattributed"
    elif ptype == "multi_same_broad":
        parent = pl["broad_classes"][0]
    else:
        parent = None  # multi_broad: free-floating

    x, y = taxon_grid_pos.get(taxon, taxon_position(taxon))

    nodes.append({
        "data": {
            "id": taxon,
            "label": taxon,
            "type": "taxon",
            "parent": parent,
            "taxon_rank": rank,
            "taxon_as_cited": sorted(meta["as_cited"]),
            "placement": ptype,
            "mechanisms": pl["mechanisms"],
            "broad_classes": pl["broad_classes"],
            "italic": italic,
        },
        "position": {"x": x, "y": y},
    })

# Paper nodes
for pid in paper_ids:
    x = paper_x_positions[pid]
    nodes.append({
        "data": {
            "id": pid,
            "label": paper_info[pid],
            "type": "paper",
            "parent": None,
        },
        "position": {"x": x, "y": PAPER_Y},
    })

# ---------------------------------------------------------------------------
# Assertions
# ---------------------------------------------------------------------------
all_node_ids = {n["data"]["id"] for n in nodes}

# Count by type
type_counts = collections.Counter(n["data"]["type"] for n in nodes)
broad_count = type_counts["broad"]
specific_count = type_counts["specific"]
taxon_count = type_counts["taxon"]
paper_count = type_counts["paper"]
edge_count = len(edges)

print(f"Paper nodes:    {paper_count}  (expected 128)")
print(f"Taxon nodes:    {taxon_count}  (expected 76)")
print(f"Broad bubbles:  {broad_count}  (expected 5)")
print(f"Specific bubbles: {specific_count}  (expected 11)")
print(f"Edges:          {edge_count}  (expected 283)")

assert paper_count == 128, f"Expected 128 paper nodes, got {paper_count}"
assert taxon_count == 76, f"Expected 76 taxon nodes, got {taxon_count}"
assert broad_count == 5, f"Expected 5 broad bubbles, got {broad_count}"
assert specific_count == 11, f"Expected 11 specific bubbles, got {specific_count}"
assert edge_count == 283, f"Expected 283 edges, got {edge_count}"

# Placement counts
p_counts = collections.Counter(
    n["data"]["placement"] for n in nodes if n["data"]["type"] == "taxon"
)
print(f"\nPlacement counts:")
print(f"  single_specific:   {p_counts['single_specific']}  (expected 42)")
print(f"  multi_same_broad:  {p_counts['multi_same_broad']}  (expected 4)")
print(f"  multi_broad:       {p_counts['multi_broad']}  (expected 15)")
print(f"  unattributed_only: {p_counts['unattributed_only']}  (expected 15)")

assert p_counts["single_specific"] == 42
assert p_counts["multi_same_broad"] == 4
assert p_counts["multi_broad"] == 15
assert p_counts["unattributed_only"] == 15

# Every edge target exists
missing_targets = set()
for e in edges:
    tgt = e["data"]["target"]
    if tgt not in all_node_ids:
        missing_targets.add(tgt)

if missing_targets:
    print(f"\nMISSING EDGE TARGETS: {sorted(missing_targets)}")
    assert False, f"Edge targets missing from node list: {sorted(missing_targets)}"
else:
    print("\nAll edge targets exist in node list. OK")

# Every target_type=mechanism row points to a specific bubble (not a taxon)
specific_ids = {n["data"]["id"] for n in nodes if n["data"]["type"] == "specific"}
for r in rows:
    if r["target_type"] == "mechanism":
        spec = r["mechanism_specific"]
        assert spec in specific_ids, f"mechanism row target '{spec}' is not a specific bubble"
print("All target_type=mechanism rows point to specific bubbles. OK")

# ---------------------------------------------------------------------------
# Write JSON
# ---------------------------------------------------------------------------
output = {"nodes": nodes, "edges": edges}
os.makedirs(os.path.dirname(OUT_PATH), exist_ok=True)
with open(OUT_PATH, "w", encoding="utf-8") as f:
    json.dump(output, f, ensure_ascii=False, indent=2)

print(f"\nWrote {OUT_PATH}")
print(f"  {len(nodes)} nodes, {len(edges)} edges")
