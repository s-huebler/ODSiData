#!/usr/bin/env python3
"""
render_tree_html.py
Reads tree_data.json and tree_template.html, injects the JSON into the
__DATA__ placeholder, writes claim-network/output/gvhd_taxonomy_ring.html.
"""

import json
from pathlib import Path

BASE = Path(__file__).resolve().parent
VIZ_DIR = BASE
OUTPUT_DIR = BASE.parent.parent / "output"
DATA_PATH = VIZ_DIR / "tree_data.json"
TEMPLATE_PATH = VIZ_DIR / "tree_template.html"
OUT_PATH = OUTPUT_DIR / "gvhd_taxonomy_ring.html"

# Ensure output dir exists
OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

# Load data
with open(DATA_PATH) as f:
    data = json.load(f)

# Load template
with open(TEMPLATE_PATH) as f:
    template = f.read()

# Serialize JSON compactly
json_str = json.dumps(data, separators=(",", ":"))

# Inject
if "__DATA__" not in template:
    raise ValueError("Template does not contain __DATA__ placeholder")

html = template.replace("__DATA__", json_str, 1)

# Write output
with open(OUT_PATH, "w") as f:
    f.write(html)

print(f"Wrote {OUT_PATH}")
print(f"  File size: {OUT_PATH.stat().st_size / 1024:.1f} KB")
print(f"  Taxa:   {len(data['taxa'])}")
print(f"  Papers: {len(data['papers'])}")
print(f"  Edges:  {len(data['edges'])}")
print(f"  Hierarchies: {list(data['hierarchies'].keys())}")
print()
# Print level counts table
print(f"  {'level':<8} {'taxa':>6} {'edges':>7} {'papers':>8}")
print(f"  {'-'*35}")
for level in data['top_levels']:
    lc = data['level_counts'][level]
    print(f"  {level:<8} {lc['taxa']:>6} {lc['edges']:>7} {lc['papers']:>8}")
