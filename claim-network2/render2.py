#!/usr/bin/env python3
"""Render gvhd_claims_network2_alt.html by embedding graph_data2.json into the
exact same Cytoscape template used for gvhd_claims_network_alt.html."""
import json, re

BUILD = "/sessions/wonderful-magical-rubin/mnt/ODSiData/claim-network2/build_html.py"
DATA  = "/sessions/wonderful-magical-rubin/mnt/outputs/graph_data2.json"
OUT   = "/sessions/wonderful-magical-rubin/mnt/outputs/gvhd_claims_network2_alt.html"

src = open(BUILD).read()
# extract the r'''...''' HTML template
m = re.search(r"HTML=r'''(.*?)'''", src, flags=re.S)
template = m.group(1)

# ---------------------------------------------------------------------------
# REORGANIZE THE RINGS: reviews (center) -> primaries (middle) -> claims (outer)
# The template's ringLayout already orders papers by the mean angle of their
# claims, so we only need to swap which ring-radius each kind gets (claims get
# the larger/outer radius, primaries the smaller/middle radius) and update the
# concentric fallback + the dropdown label.
# ---------------------------------------------------------------------------
patches = [
    # claims -> outer ring (was 640)
    ("var claimAngle={}, R1=640;", "var claimAngle={}, R1=1550;"),
    # more radial stagger to give the large outer claim labels room (was 95)
    ("var stagger=(i%2===0? -1:1)*95;", "var stagger=(i%2===0? -1:1)*140;"),
    # primary papers -> middle ring, between reviews and claims (was 1180)
    ("var R2=1180;", "var R2=900;"),
    # concentric fallback: review inner(3) > primary middle(2) > claim outer(1)
    ("return n.data('role')==='review'?3:(n.data('ntype')==='claim'?2:1);",
     "return n.data('role')==='review'?3:(n.data('ntype')==='claim'?1:2);"),
    # dropdown label reflects new ring order
    ("Layout: Rings (reviews&rarr;claims&rarr;papers)",
     "Layout: Rings (reviews&rarr;papers&rarr;claims)"),
]
for old, new in patches:
    assert old in template, f"patch target not found: {old!r}"
    template = template.replace(old, new)

# update the header subtitle to reflect the batch-2 model wording (optional, keeps look)
data = json.load(open(DATA))
elements_js = json.dumps(data, separators=(",", ":"))
html = template.replace("__ELEMENTS__", elements_js)
# make the browser tab title batch-specific
html = html.replace("GVHD Microbiome Claims &amp; Evidence Network",
                    "GVHD Microbiome Claims &amp; Evidence Network — Batch 2")
open(OUT, "w").write(html)
print("written", len(html), "bytes ->", OUT)
