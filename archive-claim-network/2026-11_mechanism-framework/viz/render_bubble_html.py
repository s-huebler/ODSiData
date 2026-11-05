"""
render_bubble_html.py
Reads bubble_data.json and bubble_template.html,
replaces __DATA__ with the JSON string,
writes claim-network/output/gvhd_mechanism_bubbles.html
"""

import json
import os

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
REPO_ROOT = os.path.abspath(os.path.join(SCRIPT_DIR, "..", "..", ".."))

DATA_PATH = os.path.join(SCRIPT_DIR, "bubble_data.json")
TEMPLATE_PATH = os.path.join(SCRIPT_DIR, "bubble_template.html")
OUT_PATH = os.path.join(REPO_ROOT, "claim-network", "output", "gvhd_mechanism_bubbles.html")

# Read data
with open(DATA_PATH, "r", encoding="utf-8") as f:
    data = json.load(f)

# Serialize compactly (no extra whitespace) for embedding
json_str = json.dumps(data, ensure_ascii=False)

# Read template
with open(TEMPLATE_PATH, "r", encoding="utf-8") as f:
    template = f.read()

if "__DATA__" not in template:
    raise ValueError("Template does not contain __DATA__ placeholder")

# Replace placeholder
html = template.replace("__DATA__", json_str)

# Write output
os.makedirs(os.path.dirname(OUT_PATH), exist_ok=True)
with open(OUT_PATH, "w", encoding="utf-8") as f:
    f.write(html)

print(f"Wrote {OUT_PATH}")
print(f"  {len(data['nodes'])} nodes, {len(data['edges'])} edges embedded")
print(f"  File size: {os.path.getsize(OUT_PATH):,} bytes")
