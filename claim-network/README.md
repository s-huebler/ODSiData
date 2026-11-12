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
| weber2026 | 18 (+25 skipped) | 18 | 1.3, auto-accepted |
| godefroy2025 | 54 (+23 skipped) | 54 | 1.3, auto-accepted |
| junior2025 | 16 (+18 skipped) | 16 | 1.3, auto-accepted |
| khuat2021 | 11 (+23 skipped) | 11 | 1.3, auto-accepted; KHU_001 recoded to 4b under 1.4 |
| pinzonleal2025 | 50 (+41 skipped) | 50 | 1.3, auto-accepted |
| samarkhazan2025 | 34 (+39 skipped) | 34 | 1.3, auto-accepted |
| sohouli2025 | 30 (+36 skipped) | 30 | 1.3, auto-accepted |
| yue2024 | 135 (+31 skipped) | 135 | 1.3, auto-accepted |
| ji2024 | 58 (+21 skipped) | 58 | 1.3, auto-accepted; JI_001, JI_003 recoded to 4b under 1.4 |

Auto-accepted (2026-11-12): proposals drafted by Claude under codebook 1.3 and accepted without
manual review (every proposal `approve`, every skip `skip_ok`, `edited` false). Review-reported
claims are treated as a rough draft; the next stage verifies each claim against its primary source.

Citation numbering, Pinzon-Leal 2025: in-text citations from [31] upward point one entry too high
in its printed reference list (see the paper skill's conversion notes). Fixed on the claims side
(2026-11-12): in `reviews/pinzonleal2025/decisions.json`, every printed number of 31 or above in
`ref_string` was lowered by one for PIN_028 to PIN_050 (23 rows), so these rows depart from the
codebook rule that `ref_string` is the citation as printed. Each row's `review_note` records the
printed citation, e.g. `[24,45]` became `[24,44]`; numbers below 31 were left alone. `edited`
stays false, so the rows still count as auto-accepted. Numbers 31 and above must be lowered by
one in any new Pinzon-Leal row. The exceptions in the conversion notes (Tables 2 and 3 Ref [79],
the final [157,158]) are not used by any current claim.

Citation numbering check, all reviews (2026-11-12): a quick pass for systematic shifts, about 12
single-number citations per review read against the title of the reference at that number,
spread from first to last citation. Only Pinzon-Leal shows a run of misses. The others fit
throughout, with isolated miscitations left for the primary-source check (e.g. Guo [55]-[57] and
[38], Ji [130]). Each review's reference list also agrees with the citation dictionary
(`citing_dictionary.csv`) entry for entry: same count, same first author, matching title words.
Dictionary rows without a `ref_id` (Weber 3, 18, 22, 70, 76 with truncated DOIs; Paredes
clinical-trial entries) are a citation-network issue; PAR_049 and PAR_051 link to two of those
trial rows.

Latest build (2026-11-12): all twelve reviews linked — `reviews/claims_linked.csv` 767 rows,
140 cited taxa. Ring: `output/claim_network_2026-11-12.html` (700 rows with a taxon target, linked
reference and GTDB lineage; 101 taxa, 141 papers, 587 phylum-level edges; rebuilt after the Pinzon-Leal citation fix). The EXPECTED counts in
`scripts/ring/build_tree_data.py` still hold an earlier snapshot and print as mismatches.
