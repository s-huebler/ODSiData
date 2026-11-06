# Taxonomy ring, version 1

**When:** Oct 8 to Nov 5 2026. **Archived:** 2026-11-05.

**What:** the first renderer and template for the D3 taxonomy ring.

- `render_tree_html.py` and `tree_template.html` came from `claim-network/scripts/ring/`. They were adapted on 2026-11-05 from `../2026-11_mechanism-framework/viz/` to read the per-review claims.
- `gvhd_taxonomy_ring_2026-10-08.html` was the live `claim-network/output/gvhd_taxonomy_ring.html` until 2026-11-05. It was built from the mechanism-framework data (76 taxa, 118 papers), not from the per-review claims.

**Replaced by:** the current `claim-network/scripts/ring/render_tree_html.py` and `tree_template.html` (developed as "v2", promoted the same day). Changes from v1:

- direction colors: context-dependent purple, unspecified gray, null black
- paper names on hover only; paper size proportional to the number of citing reviews
- larger labels; species rank added to the toggle
- zoom and pan
- groups ordered by GTDB lineage, with arcs for the higher ranks
- mechanism filter
- wider, resizable details panel with click-to-open quotes
- legend moved into the sidebar; footer note removed

**To rerun v1:** it still reads `claim-network/scripts/ring/tree_data.json`. Copy both files back into that folder, then run `render_tree_html.py --out <path>`.
