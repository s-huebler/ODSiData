#!/usr/bin/env python3
"""
render_tree_html.py
Reads tree_data.json and tree_template.html, injects the JSON into the data
placeholder, writes the taxonomy ring HTML.

    python3 claim-network/scripts/ring/build_tree_data.py
    python3 claim-network/scripts/ring/render_tree_html.py [--out PATH] [--force]

Default output is claim-network/output/gvhd_taxonomy_ring.html. It will not overwrite an
existing file unless --force is given.

Promoted to the main renderer 2026-11-05. The previous version (v1) is in
archive-claim-network/2026-11_ring-v1/. Changes from v1:
  - direction colors: context-dependent purple, unspecified gray, null black; one filter per direction
  - primary-paper labels removed from the ring (name shows on hover)
  - larger taxon and group labels
  - primary-paper circle area proportional to the number of distinct citing reviews
  - structural-node row removed from the legend; footer note removed
  - species added to the rank toggle (needs build_tree_data.py with species in TOP_LEVELS)
  - zoom and pan (mouse wheel, trackpad scroll and pinch, drag; Fit / + / - buttons)
  - groups ordered by full GTDB lineage, with lineage arcs for the higher ranks
  - wider, resizable details panel; group tables include a Taxon column
  - mechanism filter (broad class -> specific mechanism)
  - click a details row to open its quote in a popover left of the panel; click elsewhere closes it
"""

import json
import sys
from pathlib import Path

BASE = Path(__file__).resolve().parent
DATA_PATH = BASE / "tree_data.json"
TEMPLATE_PATH = BASE / "tree_template.html"
DEFAULT_OUT = BASE.parents[1] / "output" / "gvhd_taxonomy_ring.html"
OUT_PATH = Path(sys.argv[sys.argv.index("--out") + 1]).resolve() if "--out" in sys.argv else DEFAULT_OUT
if OUT_PATH.exists() and "--force" not in sys.argv:
    sys.exit(f"{OUT_PATH} exists; pass --force to replace it, or --out to write elsewhere")
OUT_PATH.parent.mkdir(parents=True, exist_ok=True)

data = json.loads(DATA_PATH.read_text())
template = TEMPLATE_PATH.read_text()

PLACEHOLDER = "__DATA__"
if template.count(PLACEHOLDER) != 1:
    raise ValueError(f"Template must contain exactly one {PLACEHOLDER} placeholder")
if "mechanism_specific" not in (data["edges"][0] if data["edges"] else {"mechanism_specific": 1}):
    print("Note: tree_data.json predates the per-edge mechanism field; rerun build_tree_data.py")
if "species" not in data["top_levels"]:
    print("Note: tree_data.json has no species level; rerun build_tree_data.py")

# </ inside JSON strings would end the <script> block early
json_str = json.dumps(data, separators=(",", ":")).replace("</", "<\\/")
html = template.replace(PLACEHOLDER, json_str, 1)
OUT_PATH.write_text(html)

print(f"Wrote {OUT_PATH}")
print(f"  File size: {OUT_PATH.stat().st_size / 1024:.1f} KB")
print(f"  Taxa:   {len(data['taxa'])}")
print(f"  Papers: {len(data['papers'])}")
print(f"  Edges:  {len(data['edges'])}")
print()
print(f"  {'level':<8} {'taxa':>6} {'edges':>7} {'papers':>8}")
print(f"  {'-'*35}")
for level in data["top_levels"]:
    lc = data["level_counts"][level]
    print(f"  {level:<8} {lc['taxa']:>6} {lc['edges']:>7} {lc['papers']:>8}")
