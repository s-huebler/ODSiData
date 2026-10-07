#!/usr/bin/env python3
"""Render claim-network/output/gvhd_claims_network3.html from graph_data3.json.

Reads:   claim-network/data/graph_data3.json
Writes:  claim-network/output/gvhd_claims_network3.html

Leaves render_network_html.py and gvhd_claims_network2_alt.html unchanged.
"""
import json
import re
from pathlib import Path

HERE     = Path(__file__).resolve().parent
TEMPLATE = HERE / "network_html_template_v3.py"
DATA     = HERE.parent / "data" / "graph_data3.json"
OUT      = HERE.parent / "output" / "gvhd_claims_network3.html"

# Extract the r'''...''' HTML template from the template module
src = open(TEMPLATE).read()
m = re.search(r"HTML\s*=\s*r'''(.*?)'''", src, flags=re.S)
if not m:
    raise RuntimeError("HTML template not found in " + str(TEMPLATE))
template = m.group(1)

# Embed graph data
data = json.load(open(DATA))
elements_js = json.dumps(data, separators=(",", ":"))
html = template.replace("__ELEMENTS__", elements_js)

OUT.parent.mkdir(parents=True, exist_ok=True)
OUT.write_text(html)
print(f"written {len(html):,} bytes → {OUT}")
