# Mechanism framework from four anchor reviews

**When:** Oct 7 to Nov 5 2026. **Archived:** 2026-11-05.

**What:** defining the mechanism categories top-down. Mechanism statements were extracted
page by page from four anchor reviews (Moses 2026, Paredes 2026, Samarkhazan 2025, Weber 2026;
PDFs in `anchor_reviews/`, page text in `text/`), merged into `mechanisms_raw.csv` (608
statements), and categorized under five candidate schemes (`schemes/`, compared in
`categorization_options.md`). Scheme 3C (two levels, broad class then specific mechanism) was
chosen and applied in `build_scratch/` to produce `claims_synthesis_framework.csv` / `.xlsx`
(329 rows), with references linked through `citation-network/Full_Network/citing_dictionary.csv`
and taxa harmonized to GTDB r232.

`viz/` built the taxonomy ring (`output/gvhd_taxonomy_ring.html`, still live) and the mechanism
bubbles page (`output/gvhd_mechanism_bubbles.html`, not carried forward). To rebuild the ring
from this framework: `python3 viz/build_tree_data.py` then `python3 viz/render_tree_html.py`
(the renderer writes to `../output/`, relative to this archive folder).

**Replaced by:** the rules this work produced now live in `claim-network/CODEBOOK.md`, and claims
are re-extracted paper by paper in `claim-network/reviews/`. The live ring builder is
`claim-network/scripts/ring/`, adapted from `viz/`.

**Note:** `build_scratch/*.py` were run from a scratch directory (`~/work`) and read intermediate
files that were not kept, so they document the method rather than rerun as-is.
