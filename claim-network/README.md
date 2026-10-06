# Claims network (current)

Directional microbe → GVHD claims extracted from GVHD-microbiome **review papers**, linked to
the **primary studies** each review cites, and rendered as an interactive Cytoscape network.
Current version: **Batch 2** (10 reviews, 109 canonical claims, 118 primary papers; built 2026-07-15).

Earlier attempts and superseded versions are in `../archive-claim-network/` (see its README).

## Pipeline

```
data/Claims_15July.xlsx  (Quotes sheet: verbatim quotes pulled from each review)
   │  1. Parse quotes → Claims / Studies rows          docs/PARSING_INSTRUCTIONS.md (manual + Claude)
   │  2. Reference-link the "Cited" column             ../scripts/bash/call_reflink_claims.sh
   │       (one ref per row; adds citing_id/ref_id)       + ../citation-network/Full_Network/citing_dictionary.csv
   ▼
data/Claims_15July_reflinked.xlsx                    (first 5 reviews reflinked)
   │  3. Remaining reviews parsed + linked; Citing-column autofill error fixed
   ▼
data/parsed2_Claims_15July.xlsx                      (222 claim rows, 70 study rows, 10 reviews)
   │  4. Synthesis: atomize taxa → taxonomic rank → canonical claim (subject@rank + valence),
   │     mechanism → controlled vocabulary. Done in a Claude session following the
   │     claim-synthesis procedure; no standalone script. Method is documented in the
   │     workbook's README sheet.
   ▼
data/Claims_Synthesis2.xlsx                          (README, Canonical_Claims, Atomic_Claims, Nodes, Edges, Claims_annotated, Flags)
   │  5. python3 scripts/build_graph_json_from_synthesis.py
   ▼
data/graph_data2.json                                (237 nodes, 443 edges)
   │  6. python3 scripts/render_network_html.py   (uses scripts/network_html_template.py)
   ▼
output/gvhd_claims_network2_alt.html
```

Steps 5–6 are scripted and verified to reproduce the current HTML byte-for-byte (2026-10-06).
Run them from anywhere; paths are relative to the script folder.

## Files

| Path | Role |
|---|---|
| `data/Claims_15July.xlsx` | Master workbook: Quotes, Claims, Studies sheets (hand-curated) |
| `data/Claims_15July_reflinked.xlsx` | Output of the reflink step for the first 5 reviews |
| `data/parsed2_Claims_15July.xlsx` | Final parsed + linked claims/studies; input to synthesis |
| `data/Claims_Synthesis2.xlsx` | Canonical claim synthesis; input to the graph script |
| `data/graph_data2.json` | Cytoscape elements (nodes/edges) |
| `data/Checking_Claims.xlsx` | Manual QA workbook for spot-checking claims against sources (in progress) |
| `scripts/build_graph_json_from_synthesis.py` | Synthesis workbook → graph JSON (formerly `gen2.py`) |
| `scripts/render_network_html.py` | Graph JSON + template → HTML; puts reviews in the centre, papers in the middle and claims on the outer ring (formerly `render2.py`) |
| `scripts/network_html_template.py` | Cytoscape HTML template (copy of batch-1 `build_html.py`) |
| `output/gvhd_claims_network2_alt.html` | Current network; open in a browser |
| `docs/PARSING_INSTRUCTIONS.md` | Procedure for parsing the Quotes sheet into Claims/Studies |

## Graph model

- Nodes: review papers (centre), primary papers (middle ring), canonical claims (outer ring).
- Edges: `CITES` review → primary; `SUPPORTS` primary → claim; coloured by valence
  (favourable = reduces GVHD, unfavourable = exacerbates GVHD, context).

## Notes

- Shared helpers live outside this folder: `scripts/reflink_claims.py`,
  `scripts/bash/call_reflink_claims.sh`, `citation-network/Full_Network/citing_dictionary.csv`.
- Folder was `claim-network2/` until the 2026-10-06 reorganization.
