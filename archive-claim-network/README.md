# Archive: claims network development

Superseded attempts, intermediate versions and side experiments from building the GVHD
microbiome claims network. Nothing here is needed for the current workflow in `../claim-network/`, except that two of the
live pages in `claim-network/output/` were built from the 2026-11 folders below (each README
says how to rebuild them). Each subfolder has its own README describing when it was done,
what was being attempted, and what replaced it.

Created 2026-10-06 by merging the old `archive-claim-network-testing/` folder with
claims-related files from the repo root and `claim-network2/`.

| Subfolder | When | What |
|---|---|---|
| `2026-05_ai-screening-run-logs/` | May 19 – Jun 2 2026 | Claude run logs from the second-pass AI full-text screening of the 475 papers (the step before claims extraction) |
| `2026-06_batch1-table-claims/` | Jun 24 – 25 2026 | Batch 1: claims taken from review-paper tables (4 reviews), first synthesis and the first Cytoscape network |
| `2026-06_pdf-table-and-reference-extraction-tests/` | Jun 24 – Jul 9 2026 | Tests of PDF table extraction and of parsing reference lists into DOIs and abbreviations |
| `2026-07_zotero-plugins/` | Jul 9 – 16 2026 | Zotero plugins tried for reference/DOI management |
| `2026-07_microbe-evidence-figure-and-radial/` | Jul 13 – 14 2026 | Evidence-depth table and a translational radial figure (proof of concept) |
| `2026-07_batch2-intermediate-versions/` | Jul 14 – 15 2026 | Batch 2 working versions that the final files replaced |
| `2026-11_july-synthesis-network/` | Jul 15 – Oct 8 2026 | Batch 2 pipeline: workbooks, synthesis scripts, lookups, and the scripts that build `gvhd_claims_network2_alt.html` / `network3.html` |
| `2026-11_mechanism-framework/` | Oct 7 – Nov 5 2026 | Mechanism categories from four anchor reviews, scheme comparison, `claims_synthesis_framework`, ring and bubble builders |
| `2026-11_ring-v1/` | Oct 8 – Nov 5 2026 | First taxonomy ring renderer/template and the Oct 8 ring page, replaced by the current `claim-network/scripts/ring/` version |

Not archived here (separate projects): `citation-network/`, `citation-network-old/`.
Large third-party files (Zotero plugin source, `node_modules`, `.xpi`) and the PDFs here are excluded from git via `.gitignore`.
