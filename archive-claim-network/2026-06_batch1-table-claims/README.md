# Batch 1: table-based claims and first network (June 2026)

**When:** Jun 24 – 25 2026.

**What was being attempted:** The first end-to-end claims citation network. Claims were
transcribed from the **tables** of 4 review papers (Weber_2026, Hsu_2026, Paredes_2026,
Samarkhazan_2025) and then collapsed into canonical directional claims
("<subject> reduces / exacerbates GVHD") with a provenance edge list
(claim ← review ← primary paper). Session log:
`AI_assisted_litreview/logs/2026-06-24_brief_citation-network_claim-harmonization-batch1.md`.

**Files, in pipeline order:**

| File | Role |
|---|---|
| `Reviewing_Reviews.xlsx` | Hand-extracted Claims (160 rows) and Studies sheets from the 4 reviews' tables |
| `Claims_Batch1.xlsx` | Cleaned claim rows (96) with DOIs; input to synthesis |
| `Claims_Batch1_duplicate-copy.xlsx` | Same content as above (from the old testing folder; only an empty trailing column differs). Safe to delete. |
| `Claims_Synthesis.xlsx` | First-pass synthesis draft (61 canonical / 72 atomic claims) |
| `Claims_Synthesis_Reference.xlsx` | Revised "reference batch" synthesis (40 canonical claims), meant to fix the canonical vocabulary for later batches |
| `claims_nodes.csv`, `claims_edges.csv` | Node and edge export for the first network |
| `alt_claims_nodes.csv`, `alt_claims_edges.csv` | Alternative model where primaries SUPPORT claims and reviews CITE primaries |
| `gen.py` | CSVs → `graph_data.json` (has hard-coded paths from an old session) |
| `build_html.py` | `graph_data.json` → `gvhd_claims_network.html` (Cytoscape) |
| `gvhd_claims_network.html` | First network render |
| `gvhd_claims_network_alt.html` | Render of the alternative model; its layout became the template for batch 2 |

**Why superseded:** Table-only extraction covered few reviews and missed claims made in the body
text. Batch 2 switched to verbatim quotes from the full text across 10 reviews, with
taxonomic-rank normalization. The HTML template lives on as
`claim-network/scripts/network_html_template.py`.
