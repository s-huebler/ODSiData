# July synthesis pipeline and the network pages built from it

**When:** Jul 15 to Oct 8 2026. **Archived:** 2026-11-05.

**What:** the Batch 2 claims pipeline. Quotes were hand-pulled into `data/Claims_15July.xlsx`, parsed
into Claims/Studies, reference-linked, then synthesized into canonical claims
(`data/Claims_Synthesis2.xlsx`, `Claims_Synthesis3.xlsx`) by `scripts/synthesis/` using the
controlled vocabularies in `lookups/`. `scripts/build_graph_json_*.py` and
`scripts/render_network_html*.py` turned those into the Cytoscape pages still in use:
`claim-network/output/gvhd_claims_network2_alt.html` and `gvhd_claims_network3.html`.

**Replaced by:** the paper-by-paper review workflow in `claim-network/` (`reviews/`,
`CODEBOOK.md`), started 2026-11-05.

## Rebuilding the network pages

Data and scripts were archived together so the pages can be rebuilt. The render scripts resolve
paths relative to their own folder, so from this folder:

    python3 scripts/build_graph_json_from_synthesis.py      # data/Claims_Synthesis2.xlsx -> data/graph_data2.json
    python3 scripts/render_network_html.py                  # -> ./output/gvhd_claims_network2_alt.html
    python3 scripts/build_graph_json_v3.py                  # data/Claims_Synthesis3.xlsx -> data/graph_data3.json
    python3 scripts/render_network_html_v3.py               # -> ./output/gvhd_claims_network3.html

The HTML lands in `./output/` inside this archive folder; copy it to `claim-network/output/` if
it should replace the live page.

`scripts/synthesis/common.py` still points at `claim-network/data`, `lookups` and `review`
(paths from the repo root). To rerun the synthesis itself, change `DATA_DIR`, `LOOKUPS_DIR` and
`REVIEW_DIR` there to this folder. `taxonomy_lookup.csv` stayed live in `claim-network/lookups/`.

The external helper `scripts/bash/call_reflink_claims.sh` (repo root) still refers to
`claim-network/data` paths from this era.

| Path | Role |
|---|---|
| `README_claim-network_2026-10.md` | The claim-network README as of Oct 2026 (full pipeline description) |
| `data/` | Master workbooks, reflinked versions, synthesis workbooks, graph JSON |
| `docs/` | `PARSING_INSTRUCTIONS.md`, `SYNTHESIS_PIPELINE_PROMPTS.md` |
| `scripts/` | Graph JSON builders, HTML renderers and templates, `synthesis/` pipeline |
| `lookups/` | Subject, rank, valence, mechanism and canonical-claim lookups for the synthesis |
| `review/` | Synthesis QA outputs (needs-review lists, seed conflicts, GTDB reclassifications, regression vs July) |
