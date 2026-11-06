# Claims network

Directional microbe → GVHD claims taken from GVHD-microbiome **review papers**, each linked to
the primary study the review cites for it, and drawn as a taxonomy ring. Claims are drafted by
Claude paper by paper under `CODEBOOK.md` and every row is approved by hand in a local viewer.

Earlier pipelines (the July synthesis network and the anchor-review mechanism framework) are in
`../archive-claim-network/`; see the 2026-11 folders there.

## Layout

| Path | What |
|---|---|
| `CODEBOOK.md` | Rules, controlled values, mechanism classes, worked examples, changelog. Versioned. |
| `reviews/<paper>/proposals.json` | Claude's proposed rows for one review (frozen once reviewed) |
| `reviews/<paper>/decisions.json` | Every decision, including discussion outcomes (source of truth); `decisions.csv` mirrors it |
| `reviews/<paper>/refs.csv` | The review's reference list, cross-checked against the citation dictionary |
| `reviews/claims.csv` | All approved rows from all reviews, one row per cited reference |
| `reviews/claims_linked.csv` | `claims.csv` plus citation-network IDs (`citing_id`, `ref_id`, `ref_label`) and GTDB `taxon`, `taxon_rank` |
| `reviews/taxa.csv` | GTDB lineage for each cited taxon (input to the ring) |
| `scripts/viewer/` | The review viewer (`review_server.py`, `viewer.html`, `marked.min.js`) |
| `scripts/validate_proposals.py` | Checks a proposals file against the codebook and the paper text |
| `scripts/parse_refs.py` | Writes `reviews/<paper>/refs.csv` from the paper skill |
| `scripts/assemble_claims.py`, `link_refs.py`, `harmonize_taxa.py` | decisions → `claims.csv` → `claims_linked.csv` (+ `taxa.csv`); `run_pipeline.py` runs all three |
| `scripts/ring/` | Builds the taxonomy ring from `claims_linked.csv` and `taxa.csv` |
| `lookups/taxonomy_lookup.csv` | Name → GTDB lineage. Curated rows plus every automatic match (`match_method auto_*`); edit a row here to correct a mapping |
| `lookups/taxon_synonyms.csv` | NCBI → GTDB name changes applied before matching (Firmicutes → Bacillota, ...) |
| `lookups/gtdb_cache/` | GTDB r232 taxonomy files (not in git; see `gtdb_release.txt` to re-download) |
| `output/` | Published pages. Untouched by the new scripts unless `--force` is passed |
| `.claude/skills/<paper>-paper/` | Converted text, tables and figures of each review; the viewer and scripts read these |
| `Presentation/` | Lab-update slides |

External input: `../citation-network/Full_Network/citing_dictionary.csv`, keyed by
(`citing_bibtex`, `local_number`). It is read, never written.

## Workflow for one review

All commands run from the ODSiData repo root.

1. **Draft.** Start a fresh Claude session and load the `claim-review` skill for the paper
   (e.g. "claim-review godefroy2025"). Claude reads `CODEBOOK.md` and the paper skill, writes
   `reviews/<paper>/proposals.json`, and runs `python3 claim-network/scripts/validate_proposals.py <paper>`.
2. **Review.** `python3 claim-network/scripts/viewer/review_server.py <paper>` and click through
   the highlights. Every click is saved immediately.
3. **Discuss.** In the same Claude session, go through the Discuss items. Outcomes are written to
   `decisions.json` (`discussion` field). Any new rule goes into `CODEBOOK.md` with a version bump.
4. **Build.**

       python3 claim-network/scripts/parse_refs.py <paper>
       python3 claim-network/scripts/run_pipeline.py

   Check the printed exceptions: unresolved references, `ref_check FALSE`, unmatched taxa.
5. **Ring (when wanted).**

       python3 claim-network/scripts/ring/build_tree_data.py
       python3 claim-network/scripts/ring/render_tree_html.py --force    # replaces output/gvhd_taxonomy_ring.html

Scripts need only Python 3 except the ring builder, which uses pandas.

## Progress

| Review | Proposals | Approved | Codebook |
|---|---|---|---|
| guo2024 | 39 (+13 skipped) | 34 | pre-1.0, resolved to 1.0 |
| moses2026 | 29 (+16 skipped) | 27 | 1.0, resolved to 1.1 |
| paredes2026 | 55 (+16 skipped) | 52 | 1.0, reconciled to 1.3 |

Latest build (2026-11-06): all three reviews linked — `reviews/claims_linked.csv` 133 rows, 46 taxa, 50 papers, 111 edges. Ring: `output/claim_network_2026-11-06.html`.
