# Claims synthesis pipeline: Claude Code prompts

A series of prompts that rebuild the claims synthesis (`Claims_Synthesis2.xlsx`) as a
scripted, reviewable pipeline, then add a GTDB taxonomy and a rank-aware graph layout.

**How to use.** Run one prompt per Claude Code session, from the `ODSiData` folder, in order.
Paste the **Shared context** block first, then the prompt. At the end of each session, read
what it reports, check any `needs_review_*.csv` it wrote, and commit
(`[Claims] <what the step added>`). Each prompt ends with a definition of done; don't move on
until it holds.

**Decisions already made (October 2026).**

- Synthesis is a chain of small steps, each driven by an editable lookup table. Tables are
  seeded from the July synthesis so the current data reproduces it.
- Anything a lookup table doesn't cover is written to a review file and the run stops. Nothing
  is guessed silently.
- Canonical claim IDs are stable: existing claims keep their ID when reviews are added.
- Taxonomy backbone is **GTDB** (current release). The name as cited in the paper is kept for
  display; the GTDB name and lineage drive placement. Reclassifications are reported for the
  manuscript.
- A claim node sits at the rank the paper actually names (strain, species, genus, family,
  order, class, phylum, or a non-taxonomic subject). Edges point to that node.
- In the graph, **higher ranks sit further out**: species closest to the paper ring, phylum
  outermost, with relatives grouped by lineage around the ring.

---

## Shared context (paste at the start of every session)

```
Project: GVHD microbiome claims network, repo ODSiData (folder claim-network/).
Read claim-network/README.md and claim-network/docs/PARSING_INSTRUCTIONS.md first.

Pipeline so far (all working, do not change unless the prompt says so):
  claim-network/data/Claims_Master.xlsx          hand-curated master (Quotes, Claims, Studies)
  scripts/reflink_claims.py                      -> claim-network/data/Claims_Master_reflinked.xlsx
                                                    (one reference per row; adds citing_id, ref_id, ref_label)
  claim-network/data/Claims_Synthesis2.xlsx      July 2026 synthesis, made by hand in a Claude session
                                                    (sheets: README, Canonical_Claims, Atomic_Claims, Nodes,
                                                    Edges, Claims_annotated, Flags). Treat as the reference
                                                    result and the source of seed decisions. Never edit it.
  claim-network/scripts/build_graph_json_from_synthesis.py -> data/graph_data2.json
  claim-network/scripts/render_network_html.py   -> output/gvhd_claims_network2_alt.html
  citation-network/Full_Network/ref_dictionary.csv  reference metadata keyed by ref_id

New work goes in:
  claim-network/scripts/synthesis/   one module per step, plus run_synthesis.py
  claim-network/lookups/             editable lookup tables (CSV, UTF-8, one row per value)
  claim-network/review/              needs_review_*.csv written by the pipeline
  claim-network/data/                outputs (Claims_Synthesis3.xlsx, graph_data3.json)
  claim-network/output/              HTML

Rules:
- Python 3 + openpyxl + pandas, matching the existing scripts. Paths relative to the repo root,
  never hard-coded /Users or /sessions paths.
- Every lookup step: values not in the table go to claim-network/review/needs_review_<step>.csv
  with the source rows that produced them, and the run exits non-zero with a clear message.
  Never invent a mapping.
- Never edit Claims_Synthesis2.xlsx, Claims_Master.xlsx or the citation-network dictionaries.
- Do not change existing scripts unless the prompt says so; old outputs must stay reproducible.
- Keep functions small and documented; each step module has a main() that can run alone.
- End by printing a short summary: files written, counts, anything sent to review.
- Commit message convention: "[Claims] brief description".
```

---

## Prompt 1. Seed the lookup tables and scaffold the pipeline

```
Goal: create the lookup tables, seeded from the July synthesis, and the empty pipeline skeleton.

1. Inspect claim-network/data/Claims_Synthesis2.xlsx: every sheet, its columns, and the README
   sheet (it documents the July rules). Also inspect claim-network/data/Claims_Master_reflinked.xlsx
   (Claims sheet: Citing, Cited, Taxa, Nonspecific Microbes, Suspected Relationship to GVHD,
   Mechanism General/Specific/Detailed, Therapeutic Implication, Evidence, Source, citing_id,
   ref_id, ref_label). Atomic_Claims.src_row refers to the row in the Claims sheet.

2. From Atomic_Claims and Canonical_Claims, write these seed tables to claim-network/lookups/:
   - subject_lookup.csv: token_verbatim (each taxon token as split from the cell, before
     normalization), subject (canonical name), subject_type (taxon | functional_group | metabolite |
     molecular_pattern | other), note. One row per distinct token. Include spelling fixes
     (e.g. Bifidobaterium -> Bifidobacterium) and the Clostridia cluster collapse described in README.
   - rank_lookup.csv: subject, rank_as_cited (strain/species/genus/family/order/class/phylum or the
     non-taxon types), source = "July synthesis". One row per subject.
   - valence_lookup.csv: relationship_verbatim, valence (favourable | unfavourable | context), rule
     (short reason). One row per distinct "Suspected Relationship to GVHD" string (about 17).
   - mechanism_lookup.csv: mechanism_verbatim, categories (semicolon-joined, from the controlled
     vocabulary in README), primary_category. One row per distinct mechanism string (about 74).
   - canonical_claims.csv: claim_id (the July canonical_claim_id), subject, rank_as_cited, valence,
     claim_label (July wording), first_seen = "2026-07-15". This is the stable ID registry.
   Check the seeds are consistent: every Atomic_Claims row must be reproducible from the tables.
   Print any conflict (same verbatim value mapped two ways) and record it in
   claim-network/review/seed_conflicts.csv rather than picking one.

3. Copy the Flags sheet to claim-network/lookups/july_flags.csv for reference.

4. Create claim-network/scripts/synthesis/ with modules 01_atomize.py, 02_subjects.py,
   03_taxonomy.py, 04_valence.py, 05_mechanism.py, 06_canonical.py, 07_write_workbook.py
   (stubs with docstrings describing input, output, lookup used), a shared common.py (paths,
   load/save helpers, the review-and-stop helper), and run_synthesis.py that runs the steps in
   order, passing a pandas DataFrame between them.

5. Write claim-network/lookups/README.md: what each table is, its columns, and how to add rows.

Done when: all five seed tables exist, seed_conflicts.csv is empty or explained, and
run_synthesis.py runs end to end on stubs without error.
```

---

## Prompt 2. Atomize and normalize subjects (steps 01, 02)

```
Goal: implement 01_atomize.py and 02_subjects.py.

01_atomize: read the Claims sheet of claim-network/data/Claims_Master_reflinked.xlsx. One output
row per (source row x taxon token). Split the Taxa cell (and Nonspecific Microbes, if the July
synthesis used it: check Atomic_Claims.taxa_cell_verbatim against both columns to decide) on
the same delimiters the July synthesis used. Keep src_row, Citing, citing_id, ref_id, ref_label,
the verbatim relationship, mechanism and evidence columns, and taxa_cell_verbatim. Assign
atomic_id AT001, AT002, ... in source order. Blank Taxa cells: write them to
needs_review_atomize.csv with their rows (do not drop silently).

02_subjects: map token_verbatim -> subject, subject_type via lookups/subject_lookup.csv
(exact match after trimming whitespace; no fuzzy matching). Unmapped tokens -> 
needs_review_subjects.csv and stop.

Regression check (write as claim-network/scripts/synthesis/check_against_july.py, extended in
later prompts): compare atomic rows to Claims_Synthesis2.xlsx Atomic_Claims on
(src_row, taxon/subject). Report counts matched, missing, extra, and list mismatches. Expected:
330 atomic rows from 222 source rows, all matching.

Done when: both steps run, the regression check reports 330 of 330 matched (or every difference
is listed and explained), and no review file is non-empty.
```

---

## Prompt 3. Valence and mechanism (steps 04, 05)

```
Goal: implement 04_valence.py and 05_mechanism.py.

04_valence: map the relationship text to valence via lookups/valence_lookup.csv (exact match
after whitespace/case normalization). Unmapped -> needs_review_valence.csv, stop. Carry the
July flags forward: if a (src_row, field) appears in lookups/july_flags.csv, add a flag column
with the July flag text.

05_mechanism: map mechanism text to categories and primary_category via
lookups/mechanism_lookup.csv. Decide from the July data which column(s) the July synthesis used
(Mechanism General is likely; confirm against Atomic_Claims.mechanism_verbatim). Blank
mechanism -> category "General / unspecified" only if that is what July did; otherwise review.
Unmapped -> needs_review_mechanism.csv, stop.

Extend check_against_july.py to compare valence, mechanism_category and mechanism_primary per
atomic row.

Done when: valence and mechanism match July for every atomic row, or each difference is listed
and explained.
```

---

## Prompt 4. Canonical claims with stable IDs, workbook output, full regression (steps 06, 07)

```
Goal: implement 06_canonical.py and 07_write_workbook.py and reproduce the July synthesis.

06_canonical: a canonical claim = (subject, rank_as_cited, valence). Look each one up in
lookups/canonical_claims.csv. Existing -> reuse claim_id and claim_label. New -> assign the next
free integer ID, build the label with the July wording rule (read it from existing labels and
the README; e.g. "<subject> (<rank>) reduces GVHD" for favourable), append it to
canonical_claims.csv with first_seen = today, and list it in review/new_claims_<date>.csv
(new claims are added, not blocked, but must be visible). IDs are never renumbered or reused.
Aggregate per claim: n_atomic_claims, n_primary_refs, n_reviews, reviews, mechanism_categories
(with counts, as July did).

07_write_workbook: write claim-network/data/Claims_Synthesis3.xlsx with the same sheets and
columns as Claims_Synthesis2.xlsx (README, Canonical_Claims, Atomic_Claims, Nodes, Edges,
Claims_annotated, Flags), plus a Pipeline sheet recording the input file, its modification time,
the lookup table row counts and the run date. Update the README sheet text to describe the
scripted pipeline (keep the July rules text, add how it is now produced).

Full regression: check_against_july.py compares Claims_Synthesis3 to Claims_Synthesis2 sheet by
sheet (Canonical_Claims by claim_id; Atomic_Claims by atomic_id; Edges by
(source_id, target_id, canonical_claim_id)). Write the report to
claim-network/review/regression_vs_july.md. Expected differences only: ref_label / ref ids
changed by the October 2026 dictionary corrections (e.g. Chatila_2018 -> Telesford_2015,
same ref_id). Anything else must be explained in the report.

Then make build_graph_json_from_synthesis.py accept the synthesis path as an argument (default
unchanged), run it on Claims_Synthesis3.xlsx into a scratch file, and confirm the graph JSON
equals data/graph_data2.json apart from those labels.

Done when: regression report shows only expected differences, and the graph built from
Claims_Synthesis3 matches the July graph apart from corrected labels.
```

---

## Prompt 5. GTDB taxonomy (step 03)

```
Goal: implement 03_taxonomy.py: give every taxon subject a GTDB name and full lineage, keeping
the name as cited.

Background: the July synthesis only stored rank and a phylum-level subject_group mixing NCBI
and GTDB names (e.g. "Firmicutes (Bacillota)"). We now use GTDB (current release) as the
backbone. The manuscript will discuss reclassifications, so they must be recorded, not hidden.

1. Data: download the current GTDB release taxonomy (bac120 and ar53 taxonomy TSVs) and the
   metadata files that carry each genome's ncbi_taxonomy alongside gtdb_taxonomy. Check the
   GTDB website for the current release number and file names; do not assume them. Cache
   downloads in claim-network/lookups/gtdb_cache/ and add that folder to .gitignore (files are
   large). Record the release number and download date in lookups/gtdb_release.txt.

2. Build an NCBI-name -> GTDB mapping per rank from the metadata: for each NCBI taxon name at a
   rank, the GTDB name(s) its genomes fall into, with genome counts. Majority GTDB name = the
   mapping; record the share (e.g. 0.93) so split taxa are visible.

3. For each subject with subject_type == taxon, produce lookups/taxonomy_lookup.csv columns:
   subject (as cited), rank_as_cited, gtdb_name, gtdb_rank, domain, phylum, class, order, family,
   genus, species (GTDB names, blank above/below what applies), match_method
   (exact_gtdb | ncbi_majority | manual), ncbi_to_gtdb_share, reclassified (yes/no),
   gtdb_release, note.
   - Exact GTDB name match first (handle GTDB suffixes such as Clostridium_A, _B: an exact match
     on the unsuffixed name with several suffixed variants is a split; take the lineage they share
     and note the split).
   - Else map via NCBI majority (step 2).
   - Else write to needs_review_taxonomy.csv with candidate matches and stop.
   - Rank-as-cited is kept: a genus cited in the paper stays a genus-rank claim even if GTDB
     splits it; lineage fields above it are filled, below it left blank.
   - Clostridia clusters (IV, XIVa) and similar informal groups: map to the GTDB rank that best
     contains them and mark match_method = manual with a note; list them in the review file the
     first time so Sophie can confirm.

4. Non-bacterial taxa (fungi, viruses) and non-taxon subjects (functional groups, metabolites,
   molecular patterns): GTDB does not cover them. Give them domain = Eukaryota / Virus /
   non-taxonomic, fill lineage from NCBI Taxonomy for fungi and viruses where possible
   (match_method = ncbi_only), and leave lineage blank for non-taxon subjects. They will be
   placed in their own sectors of the graph.

5. Write review/gtdb_reclassifications.csv: every subject whose GTDB name or parent lineage
   differs from the NCBI name used in the paper (e.g. Lactobacillus species moved to
   Limosilactobacillus, Firmicutes -> Bacillota, Eubacterium rectale -> Agathobacter rectalis),
   with the reviews that cite it. This is the manuscript table.

6. Wire 03_taxonomy into run_synthesis.py: join taxonomy_lookup onto the atomic rows and add
   the lineage columns to Atomic_Claims and Canonical_Claims in Claims_Synthesis3.xlsx. Replace
   subject_group with gtdb_phylum (keep the July subject_group column too, renamed
   subject_group_july, for comparison). Canonical claim identity stays
   (subject, rank_as_cited, valence): lineage never merges or splits claims.

Done when: every taxon subject has a lineage or is in a reviewed manual row, the reclassification
table exists, the regression check still passes for all July columns, and the GTDB release is
recorded.
```

---

## Prompt 6. Graph data with taxonomy

```
Goal: a new graph builder that carries rank and lineage, without changing the July builder.

Create claim-network/scripts/build_graph_json_v3.py (start from
build_graph_json_from_synthesis.py; leave that file unchanged) reading Claims_Synthesis3.xlsx
and writing claim-network/data/graph_data3.json.

- Claim nodes get: claim_id, label, rank_as_cited, rank_level (numeric: strain 0, species 1,
  genus 2, family 3, order 4, class 5, phylum 6, domain 7; non-taxon subjects null), the GTDB
  lineage fields, domain/sector (Bacteria, Archaea, Eukaryota, Virus, functional group,
  metabolite, molecular pattern), valence, and the counts.
- Edges are unchanged in meaning: CITES review -> primary, SUPPORTS primary -> claim. A
  SUPPORTS edge points to the claim at the rank the paper named (that is already the claim's
  identity). Do not redirect edges to parent taxa.
- Add a lineage_parent field on each taxon claim: the claim_id of the nearest ancestor that is
  itself a claim node with the same valence, if any (e.g. a Bacteroides fragilis claim ->
  the Bacteroides genus claim). Used only for optional faint "taxonomy" links in the layout.
- Drop the July subjgroup/CLOSTRIDIA clustering hack; grouping now comes from lineage.

Done when: graph_data3.json validates (every edge endpoint exists; every taxon claim has
rank_level and lineage), and node/edge counts equal graph_data2.json plus any new claims.
```

---

## Prompt 7. Rank-aware radial layout

```
Goal: a renderer that places claims by taxonomy, higher ranks further out.

Create claim-network/scripts/render_network_html_v3.py and
claim-network/scripts/network_html_template_v3.py (copies of the current renderer and template;
leave those unchanged) writing claim-network/output/gvhd_claims_network3.html from
data/graph_data3.json.

Layout ("Rings" layout, the default):
- Rings from the centre: reviews, then primary papers, then the claim band.
- Claim band radius by rank: rank_level 0-1 (strain, species) at the inner edge of the band,
  each higher rank further out (genus, family, order, class, phylum, domain outermost). Choose
  radii so labels at adjacent rank levels don't collide; make the per-rank step a single
  constant at the top of the template.
- Angle by lineage: sort taxon claims by (domain, phylum, class, order, family, genus, species,
  valence) and give each lineage group a contiguous arc, so a genus claim sits at the angular
  centre of its own species claims and further out than them. Leave small gaps between phyla.
  Non-taxon subjects (functional groups, metabolites, molecular patterns) and non-bacterial taxa
  get their own labelled sectors after the bacterial phyla.
- Within a lineage group with both valences, keep favourable and unfavourable adjacent so
  disagreement on the same taxon is visible.
- Primary papers: keep the existing rule (mean angle of the claims they support).
- Optional, off by default: a "Show taxonomy links" checkbox drawing faint dashed lines from each
  claim to its lineage_parent.
- Phylum sector labels (GTDB names) on an outer arc; a small legend explaining rank by radius.
- Keep the other layouts in the dropdown working.

Check: render it, open it with Playwright (Chromium is installed), take a full-page
screenshot to claim-network/review/layout_v3.png, and look at it. Confirm: species inside their
genus, higher ranks further out, no label pile-ups at phylum sector borders. Iterate on radii and
gaps until it reads cleanly.

Done when: the HTML renders, the screenshot shows the rank and lineage structure, and the old
gvhd_claims_network2_alt.html still renders unchanged.
```

---

## Prompt 8. One command, documentation, methods notes

```
Goal: make the whole claims pipeline one command and document it.

1. Create claim-network/scripts/run_pipeline.py with steps:
   reflink (scripts/reflink_claims.py on data/Claims_Master.xlsx) -> synthesis
   (run_synthesis.py) -> graph JSON v3 -> HTML v3. Flags: --from <step> to resume,
   --check to run the July regression. Stop at the first step that writes a non-empty review file
   and say which file to fill in.
2. Update claim-network/README.md: the new pipeline diagram (text), the lookup tables, the
   review loop, where outputs go, and that Claims_Synthesis2 / graph v2 / HTML v2 are the frozen
   July reference.
3. Write claim-network/docs/SYNTHESIS_METHODS.md for the manuscript: one short paragraph per
   step stating the rule applied (atomization, subject normalization, rank as cited, GTDB release
   and mapping method, valence and mechanism vocabularies, canonical claim definition, stable IDs,
   layout encoding), plus the counts from the latest run (source rows, atomic claims, canonical
   claims, subjects by rank, reclassified subjects, reviews, primary papers). Plain academic
   prose; no colons, hyphens or em-dashes in the prose itself.
4. Update docs/PARSING_INSTRUCTIONS.md so its "next steps" point to run_pipeline.py.

Done when: `python3 claim-network/scripts/run_pipeline.py --check` runs from a clean checkout of
the data files and reproduces Claims_Synthesis3.xlsx, graph_data3.json and
gvhd_claims_network3.html, with the regression report showing only expected differences.
```
